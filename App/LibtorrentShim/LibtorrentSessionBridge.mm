// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

#import "LibtorrentSessionBridge.h"

#include <libproc.h>
#include <sys/resource.h>
#include <sys/syslimits.h>
#include <sys/sysctl.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <fstream>
#include <map>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include "libtorrent/add_torrent_params.hpp"
#include "libtorrent/alert_types.hpp"
#include "libtorrent/bencode.hpp"
#include "libtorrent/create_torrent.hpp"
#include "libtorrent/download_priority.hpp"
#include "libtorrent/entry.hpp"
#include "libtorrent/file_storage.hpp"
#include "libtorrent/hex.hpp"
#include "libtorrent/magnet_uri.hpp"
#include "libtorrent/read_resume_data.hpp"
#include "libtorrent/session.hpp"
#include "libtorrent/settings_pack.hpp"
#include "libtorrent/torrent_flags.hpp"
#include "libtorrent/torrent_handle.hpp"
#include "libtorrent/torrent_info.hpp"
#include "libtorrent/torrent_status.hpp"
#include "libtorrent/write_resume_data.hpp"

namespace lt = libtorrent;

static NSString * const ShatlLibtorrentErrorDomain = @"mamontov.design.shatl.libtorrent";

typedef NS_ENUM(NSInteger, ShatlLibtorrentErrorCode) {
    ShatlLibtorrentErrorCodeSessionNotBooted = 1,
    ShatlLibtorrentErrorCodeInvalidMagnet = 2,
    ShatlLibtorrentErrorCodeInvalidTorrentFile = 3,
    ShatlLibtorrentErrorCodeDuplicateTorrent = 4,
    ShatlLibtorrentErrorCodeMetadataTimeout = 5,
    ShatlLibtorrentErrorCodeTorrentNotFound = 6,
    ShatlLibtorrentErrorCodeEngineFailure = 7,
    ShatlLibtorrentErrorCodeDraftPreparationLost = 8,
};

static lt::status_flags_t LTMinimalStatusQueryFlags();
static LTTorrentRuntimeStatus LTRuntimeStatusFromTorrentStatus(lt::torrent_status const& status);

static std::string LTToStdString(NSString *value) {
    return value == nil ? std::string() : std::string(value.UTF8String);
}

static NSString *LTToNSString(std::string const& value) {
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *LTInfoHashString(lt::info_hash_t const& infoHash) {
    lt::sha1_hash bestHash = infoHash.get_best();
    auto bytes = bestHash.data();
    return LTToNSString(lt::aux::to_hex({reinterpret_cast<char const*>(bytes), int(bestHash.size())}));
}

static NSError *LTMakeError(ShatlLibtorrentErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ShatlLibtorrentErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSError *LTMakeErrorFromCode(ShatlLibtorrentErrorCode code, lt::error_code const& ec, NSString *fallback) {
    NSString *message = ec ? LTToNSString(ec.message()) : fallback;
    return LTMakeError(code, message);
}

static void LTApplyNetworkDiscoverySettings(lt::settings_pack& pack, bool enableLSD) {
    pack.set_bool(lt::settings_pack::enable_dht, true);
    pack.set_bool(lt::settings_pack::enable_lsd, enableLSD);
    pack.set_bool(lt::settings_pack::enable_upnp, false);
    pack.set_bool(lt::settings_pack::enable_natpmp, false);
}

/// What a profile asks for. The session gets it only through
/// `LTMakeSessionSettingsPack`, which fits it into the open-file limit.
static lt::settings_pack LTMakePerformanceSettingsPack(LTPerformanceProfile profile) {
    switch (profile) {
    case LTPerformanceProfileEconomical: {
        lt::settings_pack pack = lt::min_memory_usage();
        pack.set_int(lt::settings_pack::connections_limit, 24);
        pack.set_int(lt::settings_pack::max_peerlist_size, 100);
        pack.set_int(lt::settings_pack::max_paused_peerlist_size, 20);
        pack.set_int(lt::settings_pack::download_rate_limit, 5 * 1024 * 1024);
        pack.set_int(lt::settings_pack::upload_rate_limit, 2560 * 1024);
        pack.set_int(lt::settings_pack::dht_upload_rate_limit, 2048);
        pack.set_int(lt::settings_pack::connection_speed, 3);
        pack.set_int(lt::settings_pack::torrent_connect_boost, 4);
        pack.set_int(lt::settings_pack::tick_interval, 1000);
        pack.set_int(lt::settings_pack::unchoke_slots_limit, 2);
        pack.set_int(lt::settings_pack::send_buffer_watermark, 16 * 1024);
        pack.set_int(lt::settings_pack::max_queued_disk_bytes, 256 * 1024);
        pack.set_int(lt::settings_pack::aio_threads, 1);
        pack.set_int(lt::settings_pack::hashing_threads, 1);
        pack.set_int(lt::settings_pack::checking_mem_usage, 2);
        LTApplyNetworkDiscoverySettings(pack, false);
        return pack;
    }
    case LTPerformanceProfileMaximum: {
        lt::settings_pack pack = lt::high_performance_seed();
        pack.set_int(lt::settings_pack::connections_limit, 5000);
        pack.set_int(lt::settings_pack::max_peerlist_size, 0);
        pack.set_int(lt::settings_pack::max_paused_peerlist_size, 0);
        pack.set_int(lt::settings_pack::download_rate_limit, 0);
        pack.set_int(lt::settings_pack::upload_rate_limit, 0);
        pack.set_int(lt::settings_pack::dht_upload_rate_limit, 0);
        pack.set_int(lt::settings_pack::send_buffer_watermark, 4 * 1024 * 1024);
        pack.set_int(lt::settings_pack::send_buffer_watermark_factor, 200);
        pack.set_int(lt::settings_pack::max_queued_disk_bytes, 64 * 1024 * 1024);
        pack.set_int(lt::settings_pack::connection_speed, 200);
        pack.set_int(lt::settings_pack::torrent_connect_boost, 100);
        pack.set_int(lt::settings_pack::file_pool_size, 400);
        pack.set_int(lt::settings_pack::aio_threads, 16);
        pack.set_int(lt::settings_pack::hashing_threads, 8);
        pack.set_int(lt::settings_pack::checking_mem_usage, 512);
        pack.set_int(lt::settings_pack::unchoke_slots_limit, -1);
        LTApplyNetworkDiscoverySettings(pack, true);
        return pack;
    }
    case LTPerformanceProfileBalanced:
    default: {
        lt::settings_pack pack = lt::default_settings();
        pack.set_int(lt::settings_pack::connections_limit, 1000);
        pack.set_int(lt::settings_pack::max_peerlist_size, 3000);
        pack.set_int(lt::settings_pack::max_paused_peerlist_size, 1000);
        pack.set_int(lt::settings_pack::download_rate_limit, 0);
        pack.set_int(lt::settings_pack::upload_rate_limit, 0);
        pack.set_int(lt::settings_pack::dht_upload_rate_limit, 16 * 1024);
        pack.set_int(lt::settings_pack::send_buffer_watermark, 1024 * 1024);
        pack.set_int(lt::settings_pack::send_buffer_watermark_factor, 150);
        pack.set_int(lt::settings_pack::max_queued_disk_bytes, 16 * 1024 * 1024);
        pack.set_int(lt::settings_pack::connection_speed, 100);
        pack.set_int(lt::settings_pack::file_pool_size, 200);
        pack.set_int(lt::settings_pack::aio_threads, 8);
        pack.set_int(lt::settings_pack::hashing_threads, 4);
        pack.set_int(lt::settings_pack::checking_mem_usage, 256);
        LTApplyNetworkDiscoverySettings(pack, true);
        return pack;
    }
    }
}

/// The Swift switch that says whether a diagnostics log is on, looked up once:
/// the 1 Hz tick asks it for every torrent.
struct LTLoggingSwitch {
    Class bridgeClass = Nil;
    SEL selector = nullptr;
    BOOL (*isEnabled)(id, SEL) = nullptr;

    explicit LTLoggingSwitch(NSString *className) {
        bridgeClass = NSClassFromString(className);
        selector = NSSelectorFromString(@"loggingEnabled");
        if (bridgeClass != Nil && [bridgeClass respondsToSelector:selector]) {
            isEnabled = reinterpret_cast<BOOL (*)(id, SEL)>([bridgeClass methodForSelector:selector]);
        }
    }

    BOOL value() const {
        return isEnabled != nullptr && isEnabled(bridgeClass, selector);
    }
};

static BOOL LTDiagnosticsLoggingEnabled(void) {
    static LTLoggingSwitch const loggingSwitch(@"ShatlDiagnosticsBridge");
    return loggingSwitch.value();
}

static void LTDiagnosticsLog(NSString *category, NSString *level, NSString *message, BOOL flush) {
    if (!LTDiagnosticsLoggingEnabled()) {
        return;
    }

    Class bridgeClass = NSClassFromString(@"ShatlDiagnosticsBridge");
    SEL selector = NSSelectorFromString(@"logWithCategory:level:message:flush:");
    if (bridgeClass == Nil || ![bridgeClass respondsToSelector:selector]) {
        return;
    }

    void (*messageSend)(id, SEL, NSString *, NSString *, NSString *, BOOL) =
        reinterpret_cast<void (*)(id, SEL, NSString *, NSString *, NSString *, BOOL)>([bridgeClass methodForSelector:selector]);
    messageSend(bridgeClass, selector, category, level, message, flush);
}

static NSString *LTDiagnosticsField(NSString *key, NSString *value) {
    NSString *escaped = [[value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
        stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSCharacterSet *quoteTriggers = [NSCharacterSet characterSetWithCharactersInString:@" =\""];
    BOOL needsQuotes = [escaped rangeOfCharacterFromSet:quoteTriggers].location != NSNotFound;
    return needsQuotes
        ? [NSString stringWithFormat:@"%@=\"%@\"", key, escaped]
        : [NSString stringWithFormat:@"%@=%@", key, escaped];
}

static NSString *LTMillisecondsString(std::chrono::steady_clock::time_point startedAt) {
    auto now = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(now - startedAt);
    return [NSString stringWithFormat:@"%lld", static_cast<long long>(duration.count())];
}

static void LTDiagnosticsBridgeLog(NSString *phase,
                                   NSString *recordIdentifier,
                                   NSDictionary<NSString *, NSString *> * _Nullable extra,
                                   BOOL flush) {
    if (!LTDiagnosticsLoggingEnabled()) {
        return;
    }

    NSMutableArray<NSString *> *fields = [[NSMutableArray alloc] initWithObjects:
        LTDiagnosticsField(@"torrent", recordIdentifier),
        LTDiagnosticsField(@"phase", phase),
        nil];

    NSArray<NSString *> *sortedKeys = [[extra allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in sortedKeys) {
        NSString *value = extra[key];
        if (value == nil) {
            continue;
        }
        [fields addObject:LTDiagnosticsField(key, value)];
    }

    LTDiagnosticsLog(@"Bridge", @"DEBUG", [fields componentsJoinedByString:@" "], flush);
}

static BOOL LTSnapshotDiagnosticsLoggingEnabled(void) {
    static LTLoggingSwitch const loggingSwitch(@"ShatlSnapshotDiagnosticsBridge");
    return loggingSwitch.value();
}

static void LTSnapshotDiagnosticsLog(NSString *event,
                                     NSDictionary<NSString *, NSString *> *fields,
                                     BOOL flush) {
    if (!LTSnapshotDiagnosticsLoggingEnabled()) {
        return;
    }

    Class bridgeClass = NSClassFromString(@"ShatlSnapshotDiagnosticsBridge");
    SEL selector = NSSelectorFromString(@"logWithEvent:fields:flush:");
    if (bridgeClass == Nil || ![bridgeClass respondsToSelector:selector]) {
        return;
    }

    void (*messageSend)(id, SEL, NSString *, NSDictionary<NSString *, NSString *> *, BOOL) =
        reinterpret_cast<void (*)(id, SEL, NSString *, NSDictionary<NSString *, NSString *> *, BOOL)>([bridgeClass methodForSelector:selector]);
    messageSend(bridgeClass, selector, event, fields ?: @{}, flush);
}

// Every diagnostics call goes through these: the arguments, often dictionaries
// of formatted strings, are built only while the log is on. Diagnostics are
// always off in Release, and the 1 Hz tick logs for every torrent.
#define LT_BRIDGE_LOG(...) \
    do { \
        if (LTDiagnosticsLoggingEnabled()) { \
            LTDiagnosticsBridgeLog(__VA_ARGS__); \
        } \
    } while (0)
#define LT_SNAPSHOT_LOG(...) \
    do { \
        if (LTSnapshotDiagnosticsLoggingEnabled()) { \
            LTSnapshotDiagnosticsLog(__VA_ARGS__); \
        } \
    } while (0)

static NSString *LTStatusQueryFlagsDescription(void) {
    return @"query_name,query_torrent_file,query_accurate_download_counters";
}

static NSMutableDictionary<NSString *, NSString *> *LTSnapshotBaseFields(NSString *source,
                                                                         NSString *recordIdentifier,
                                                                         uint64_t tickID,
                                                                         NSUInteger handleIndex,
                                                                         NSString *phase) {
    NSMutableDictionary<NSString *, NSString *> *fields = [[NSMutableDictionary alloc] init];
    fields[@"source"] = source ?: @"unknown";
    fields[@"torrent"] = recordIdentifier ?: @"-";
    fields[@"tickID"] = [NSString stringWithFormat:@"%llu", static_cast<unsigned long long>(tickID)];
    fields[@"handleIndex"] = handleIndex == NSNotFound
        ? @"-"
        : [NSString stringWithFormat:@"%lu", static_cast<unsigned long>(handleIndex)];
    fields[@"phase"] = phase ?: @"status";
    fields[@"queryFlags"] = LTStatusQueryFlagsDescription();
    return fields;
}

static lt::torrent_status LTStatusWithSnapshotDiagnostics(lt::torrent_handle const& handle,
                                                          NSString *source,
                                                          NSString *recordIdentifier,
                                                          uint64_t tickID,
                                                          NSUInteger handleIndex,
                                                          NSString *phase,
                                                          BOOL stopAfterDownloadPending) {
    if (!LTSnapshotDiagnosticsLoggingEnabled()) {
        return handle.status(LTMinimalStatusQueryFlags());
    }

    auto startedAt = std::chrono::steady_clock::now();
    lt::torrent_handle watchdogHandle = handle;
    std::shared_ptr<std::atomic_bool> completed = std::make_shared<std::atomic_bool>(false);
    NSMutableDictionary<NSString *, NSString *> *fields = LTSnapshotBaseFields(
        source,
        recordIdentifier,
        tickID,
        handleIndex,
        phase
    );
    fields[@"handleValid"] = handle.is_valid() ? @"1" : @"0";
    fields[@"stopAfterDownloadPending"] = stopAfterDownloadPending ? @"1" : @"0";
    LT_SNAPSHOT_LOG(@"snapshot.status.begin", fields, YES);

    auto logWatchdog = ^(NSString *event, NSString *thresholdMs) {
        if (completed->load()) {
            return;
        }

        NSMutableDictionary<NSString *, NSString *> *watchdogFields = LTSnapshotBaseFields(
            source,
            recordIdentifier,
            tickID,
            handleIndex,
            phase
        );
        watchdogFields[@"durationMs"] = LTMillisecondsString(startedAt);
        watchdogFields[@"thresholdMs"] = thresholdMs;
        watchdogFields[@"handleValid"] = watchdogHandle.is_valid() ? @"1" : @"0";
        watchdogFields[@"stopAfterDownloadPending"] = stopAfterDownloadPending ? @"1" : @"0";
        LT_SNAPSHOT_LOG(event, watchdogFields, YES);
    };

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(500 * NSEC_PER_MSEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        logWatchdog(@"snapshot.status.slow", @"500");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(2000 * NSEC_PER_MSEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        logWatchdog(@"snapshot.status.stalled", @"2000");
    });

    lt::torrent_status status = handle.status(LTMinimalStatusQueryFlags());
    completed->store(true);

    NSMutableDictionary<NSString *, NSString *> *endFields = LTSnapshotBaseFields(
        source,
        recordIdentifier,
        tickID,
        handleIndex,
        phase
    );
    endFields[@"durationMs"] = LTMillisecondsString(startedAt);
    endFields[@"runtimeStatus"] = [NSString stringWithFormat:@"%d", static_cast<int>(LTRuntimeStatusFromTorrentStatus(status))];
    endFields[@"state"] = [NSString stringWithFormat:@"%d", static_cast<int>(status.state)];
    endFields[@"progress"] = [NSString stringWithFormat:@"%.3f", status.progress];
    endFields[@"downloadRate"] = [NSString stringWithFormat:@"%lld", static_cast<long long>(status.download_rate)];
    endFields[@"uploadPayloadRate"] = [NSString stringWithFormat:@"%lld", static_cast<long long>(status.upload_payload_rate)];
    endFields[@"errc"] = status.errc ? LTToNSString(status.errc.message()) : @"none";
    LT_SNAPSHOT_LOG(@"snapshot.status.end", endFields, NO);

    return status;
}

static lt::status_flags_t LTMinimalStatusQueryFlags() {
    return lt::torrent_handle::query_name
        | lt::torrent_handle::query_torrent_file
        | lt::torrent_handle::query_accurate_download_counters;
}

static bool LTFlagEnabled(lt::torrent_flags_t const flags, lt::torrent_flags_t const flag) {
    return (flags & flag) != lt::torrent_flags_t{};
}

static NSNumber * _Nullable LTBoxedIntIfPositive(int value) {
    return value > 0 ? @(value) : nil;
}

static NSNumber * _Nullable LTBoxedETA(lt::torrent_status const& status) {
    if (status.download_rate <= 0 || status.total_wanted <= status.total_wanted_done) {
        return nil;
    }

    auto remainingBytes = status.total_wanted - status.total_wanted_done;
    auto etaSeconds = int(remainingBytes / std::max(status.download_rate, 1));
    return etaSeconds > 0 ? @(etaSeconds) : nil;
}

static LTTorrentRuntimeStatus LTRuntimeStatusFromTorrentStatus(lt::torrent_status const& status) {
    if (status.errc) {
        return LTTorrentRuntimeStatusError;
    }

    if (status.state == lt::torrent_status::checking_files
        || status.state == lt::torrent_status::checking_resume_data) {
        return LTTorrentRuntimeStatusChecking;
    }

    if (LTFlagEnabled(status.flags, lt::torrent_flags::paused)) {
        return status.is_finished ? LTTorrentRuntimeStatusCompleted : LTTorrentRuntimeStatusStopped;
    }

    if (status.is_seeding || status.state == lt::torrent_status::seeding) {
        return LTTorrentRuntimeStatusSeeding;
    }

    // libtorrent can keep a partially selected multi-file torrent in `finished`
    // while it remains an active peer. Shatl treats this as seeding rather than
    // completed; otherwise the card appears sleeping and the toolbar attempts
    // lazy restoration over a live handle.
    if (status.is_finished || status.state == lt::torrent_status::finished) {
        return LTTorrentRuntimeStatusSeeding;
    }

    return LTTorrentRuntimeStatusDownloading;
}

@implementation LTPreparedFile

- (instancetype)initWithName:(NSString *)name
                   sizeBytes:(long long)sizeBytes
                   fileIndex:(NSInteger)fileIndex {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _name = [name copy];
    _sizeBytes = sizeBytes;
    _fileIndex = fileIndex;
    return self;
}

@end

@implementation LTPreparedDraft

- (instancetype)initWithOriginalName:(NSString *)originalName
                            infoHash:(NSString *)infoHash
                   suggestedSavePath:(NSString *)suggestedSavePath
                               files:(NSArray<LTPreparedFile *> *)files
                         reviewState:(LTTorrentDraftState)reviewState
                      invalidMessage:(NSString *)invalidMessage {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _originalName = [originalName copy];
    _infoHash = [infoHash copy];
    _suggestedSavePath = [suggestedSavePath copy];
    _files = [files copy];
    _reviewState = reviewState;
    _invalidMessage = [invalidMessage copy];
    return self;
}

@end

@implementation LTAddedTorrent

- (instancetype)initWithRecordIdentifier:(NSString *)recordIdentifier
                       attemptIdentifier:(NSString *)attemptIdentifier
                                infoHash:(NSString *)infoHash
                            originalName:(NSString *)originalName
                              totalBytes:(long long)totalBytes
                           selectedBytes:(long long)selectedBytes
                       selectedFileCount:(NSInteger)selectedFileCount
                          totalFileCount:(NSInteger)totalFileCount {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _recordIdentifier = [recordIdentifier copy];
    _attemptIdentifier = [attemptIdentifier copy];
    _infoHash = [infoHash copy];
    _originalName = [originalName copy];
    _totalBytes = totalBytes;
    _selectedBytes = selectedBytes;
    _selectedFileCount = selectedFileCount;
    _totalFileCount = totalFileCount;
    return self;
}

@end

@implementation LTTorrentSnapshot

- (instancetype)initWithRecordIdentifier:(NSString *)recordIdentifier
                                  status:(LTTorrentRuntimeStatus)status
                                progress:(double)progress
              downloadSpeedBytesPerSecond:(long long)downloadSpeedBytesPerSecond
                uploadSpeedBytesPerSecond:(long long)uploadSpeedBytesPerSecond
                               etaSeconds:(NSNumber *)etaSeconds
                                    seeds:(NSNumber *)seeds
                                    peers:(NSNumber *)peers
                            uploadedBytes:(long long)uploadedBytes
                               totalBytes:(long long)totalBytes
                            selectedBytes:(long long)selectedBytes
                             errorMessage:(NSString *)errorMessage
                         resumeDataStatus:(NSString *)resumeDataStatus {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _recordIdentifier = [recordIdentifier copy];
    _status = status;
    _progress = progress;
    _downloadSpeedBytesPerSecond = downloadSpeedBytesPerSecond;
    _uploadSpeedBytesPerSecond = uploadSpeedBytesPerSecond;
    _etaSeconds = etaSeconds;
    _seeds = seeds;
    _peers = peers;
    _uploadedBytes = uploadedBytes;
    _totalBytes = totalBytes;
    _selectedBytes = selectedBytes;
    _errorMessage = [errorMessage copy];
    _resumeDataStatus = [resumeDataStatus copy];
    return self;
}

@end

@implementation LTResumeCheckpoint

- (instancetype)initWithRecordIdentifier:(NSString *)recordIdentifier
                                  status:(NSString *)status
                            errorMessage:(NSString *)errorMessage {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _recordIdentifier = [recordIdentifier copy];
    _status = [status copy];
    _errorMessage = [errorMessage copy];
    return self;
}

@end

@implementation LTResourceBudget

- (instancetype)initWithInitialOpenFileLimit:(NSInteger)initialOpenFileLimit
                               openFileLimit:(NSInteger)openFileLimit
                   requestedConnectionsLimit:(NSInteger)requestedConnectionsLimit
                       requestedFilePoolSize:(NSInteger)requestedFilePoolSize
                            connectionsLimit:(NSInteger)connectionsLimit
                                filePoolSize:(NSInteger)filePoolSize {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _initialOpenFileLimit = initialOpenFileLimit;
    _openFileLimit = openFileLimit;
    _requestedConnectionsLimit = requestedConnectionsLimit;
    _requestedFilePoolSize = requestedFilePoolSize;
    _connectionsLimit = connectionsLimit;
    _filePoolSize = filePoolSize;
    return self;
}

@end

/// The soft open-file limit, capped like libtorrent's own `max_open_files()`.
static int LTCurrentOpenFileLimit() {
    int const unlimited = 10000000;
    struct rlimit limit {};
    if (getrlimit(RLIMIT_NOFILE, &limit) != 0) {
        return 1024;
    }
    return limit.rlim_cur >= static_cast<rlim_t>(unlimited) ? unlimited : static_cast<int>(limit.rlim_cur);
}

/// launchd starts processes with a soft limit of 256 open files, and AppKit
/// raises it to 2560 for an app opened from Finder or the Dock. A busy Nova
/// session needs more. Apple's setrlimit(2) asks for at most `OPEN_MAX`
/// (10 240); the hard limit and `kern.maxfilesperproc` may be lower.
static void LTRaiseOpenFileLimit() {
    struct rlimit limit {};
    if (getrlimit(RLIMIT_NOFILE, &limit) != 0) {
        return;
    }

    rlim_t target = std::min<rlim_t>(OPEN_MAX, limit.rlim_max);
    int perProcessLimit = 0;
    std::size_t size = sizeof(perProcessLimit);
    if (sysctlbyname("kern.maxfilesperproc", &perProcessLimit, &size, nullptr, 0) == 0 && perProcessLimit > 0) {
        target = std::min<rlim_t>(target, static_cast<rlim_t>(perProcessLimit));
    }
    // Never lower a limit that is already higher, e.g. after a launch from Terminal.
    if (limit.rlim_cur >= target) {
        return;
    }

    limit.rlim_cur = target;
    // On failure the budget fits the session into the limit it has.
    setrlimit(RLIMIT_NOFILE, &limit);
}

/// Descriptors kept outside peer connections and the file pool: Shatl itself,
/// the three sockets libtorrent opens per local address (75 on a Mac with VPN
/// interfaces), up to 50 concurrent tracker announces and short writes such as
/// `session.json`.
static int LTReservedDescriptorCount(int openFileLimit) {
    return std::clamp(openFileLimit / 4, 160, 1024);
}

struct LTDescriptorBudget {
    int connectionsLimit;
    int filePoolSize;
};

/// Under the raised limit every profile keeps its values; a smaller limit cuts
/// them, with libtorrent's own split of 80% to connections and 20% to files.
static LTDescriptorBudget LTFitProfileIntoOpenFileLimit(lt::settings_pack const& profilePack, int openFileLimit) {
    int const available = std::max(0, openFileLimit - LTReservedDescriptorCount(openFileLimit));
    int const filePoolSize = std::min(
        profilePack.get_int(lt::settings_pack::file_pool_size),
        std::max(4, available / 5)
    );
    int const connectionsLimit = std::min(
        profilePack.get_int(lt::settings_pack::connections_limit),
        std::max(10, available - filePoolSize)
    );
    return {connectionsLimit, filePoolSize};
}

/// The only settings the session gets, at boot and on every profile switch.
/// libtorrent caps connections to the limit only when the session is created,
/// and never caps the file pool.
static lt::settings_pack LTMakeSessionSettingsPack(LTPerformanceProfile profile, int openFileLimit) {
    lt::settings_pack pack = LTMakePerformanceSettingsPack(profile);
    LTDescriptorBudget const budget = LTFitProfileIntoOpenFileLimit(pack, openFileLimit);
    pack.set_int(lt::settings_pack::connections_limit, budget.connectionsLimit);
    pack.set_int(lt::settings_pack::file_pool_size, budget.filePoolSize);
    return pack;
}

/// A temporary upload-mode torrent that exists only to receive magnet metadata.
struct LTMagnetMetadataFetch {
    lt::torrent_handle handle;
    lt::info_hash_t infoHashes;
    std::string draftIdentifier;
    std::string suggestedSavePath;
    // Set when a record or a newer add took the same torrent: the temporary
    // torrent is already gone and the next poll reports a duplicate.
    bool isSuperseded = false;
};

static bool LTInfoHashesOverlap(lt::info_hash_t const& lhs, lt::info_hash_t const& rhs) {
    return (lhs.has_v1() && rhs.has_v1() && lhs.v1 == rhs.v1)
        || (lhs.has_v2() && rhs.has_v2() && lhs.v2 == rhs.v2);
}

@interface LibtorrentSessionBridge () {
    NSURL *_resumeDataDirectoryURL;
    std::unique_ptr<lt::session> _session;
    std::map<std::string, lt::torrent_handle> _handlesByRecordID;
    std::unordered_map<std::string, LTMagnetMetadataFetch> _magnetMetadataFetchesByToken;
    // Metadata of prepared drafts, kept until Swift releases the draft after
    // closing Review or finishing the add. Each draft owns its entry, so a
    // Review and an add of the same source never drop each other's metadata.
    // libtorrent provides magnet metadata through a weak/shared pointer to const
    // torrent_info. Keep it as-is to avoid copying the heavy structure.
    std::unordered_map<std::string, std::shared_ptr<const lt::torrent_info>> _preparedTorrentInfoByDraftID;
    std::unordered_map<std::string, bool> _stopAfterDownloadByRecordID;
    std::unordered_map<std::string, NSInteger> _lastSnapshotStatusByRecordID;
    LTPerformanceProfile _performanceProfile;
    int _initialOpenFileLimit;
    uint64_t _snapshotTickCounter;
}
@end

@implementation LibtorrentSessionBridge

- (instancetype)initWithResumeDataDirectoryURL:(NSURL *)resumeDataDirectoryURL {
    self = [super init];
    if (self != nil) {
        _resumeDataDirectoryURL = [resumeDataDirectoryURL copy];
        _performanceProfile = LTPerformanceProfileBalanced;
        _snapshotTickCounter = 0;
    }
    return self;
}

+ (BOOL)writeResumeData:(NSData *)data
              toFileURL:(NSURL *)fileURL
                  error:(NSError * _Nullable __autoreleasing *)error {
    NSError *writeError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:[fileURL URLByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&writeError]) {
        if (error != nullptr) {
            *error = writeError ?: LTMakeError(
                ShatlLibtorrentErrorCodeEngineFailure,
                @"Не удалось подготовить папку для fastresume-файла."
            );
        }
        return NO;
    }

    // An atomic write goes through a temporary file and a rename, so the
    // previous fast-resume file survives a failed or interrupted write.
    if (![data writeToURL:fileURL options:NSDataWritingAtomic error:&writeError]) {
        if (error != nullptr) {
            *error = writeError ?: LTMakeError(
                ShatlLibtorrentErrorCodeEngineFailure,
                @"Не удалось сохранить fastresume-файл."
            );
        }
        return NO;
    }

    return YES;
}

- (NSURL *)resumeDataFileURLForRecordIdentifier:(NSString *)recordIdentifier {
    NSString *fileName = [recordIdentifier stringByAppendingPathExtension:@"fastresume"];
    return [_resumeDataDirectoryURL URLByAppendingPathComponent:fileName isDirectory:NO];
}

- (BOOL)persistResumeDataFromParams:(lt::add_torrent_params const&)params
                forRecordIdentifier:(NSString *)recordIdentifier
                              error:(NSError * _Nullable __autoreleasing *)error {
    NSData *data = nil;
    try {
        std::vector<char> buffer = lt::write_resume_data_buf(params);
        data = [NSData dataWithBytes:buffer.data() length:buffer.size()];
    } catch (std::exception const& exception) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeEngineFailure, LTToNSString(exception.what()));
        }
        return NO;
    } catch (...) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeEngineFailure, @"write_resume_data_buf-throw");
        }
        return NO;
    }

    return [LibtorrentSessionBridge writeResumeData:data
                                          toFileURL:[self resumeDataFileURLForRecordIdentifier:recordIdentifier]
                                              error:error];
}

- (LTResumeCheckpoint *)checkpointResultForRecordIdentifier:(NSString *)recordIdentifier
                                                     status:(NSString *)status
                                               errorMessage:(NSString *)errorMessage {
    return [[LTResumeCheckpoint alloc] initWithRecordIdentifier:recordIdentifier
                                                         status:status
                                                   errorMessage:errorMessage];
}

- (void)saveResumeDataForHandle:(lt::torrent_handle const&)handle
               recordIdentifier:(NSString *)recordIdentifier {
    if (_session == nullptr || !handle.is_valid()) {
        LT_BRIDGE_LOG(
            @"resume.skip",
            recordIdentifier,
            @{ @"reason": @"invalid-session-or-handle" },
            YES
        );
        return;
    }

    auto startedAt = std::chrono::steady_clock::now();
    try {
        handle.save_resume_data(lt::torrent_handle::only_if_modified);
        LT_BRIDGE_LOG(
            @"resume.requested",
            recordIdentifier,
            @{ @"resumeMode": @"only_if_modified" },
            YES
        );
    } catch (...) {
        LT_BRIDGE_LOG(
            @"resume.request.failed",
            recordIdentifier,
            @{ @"reason": @"save_resume_data-throw" },
            YES
        );
        return;
    }

    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (std::chrono::steady_clock::now() < deadline) {
        _session->wait_for_alert(std::chrono::milliseconds(100));

        std::vector<lt::alert *> alerts;
        _session->pop_alerts(&alerts);

        for (lt::alert *alert : alerts) {
            if (auto *resumeAlert = lt::alert_cast<lt::save_resume_data_alert>(alert)) {
                if (resumeAlert->handle != handle) {
                    continue;
                }

                // Detach still proceeds: the atomic write keeps the previous
                // fast-resume file, so a failure costs a recheck, not data.
                NSError *persistError = nil;
                if (![self persistResumeDataFromParams:resumeAlert->params
                                   forRecordIdentifier:recordIdentifier
                                                 error:&persistError]) {
                    LT_BRIDGE_LOG(
                        @"resume.persist.failed",
                        recordIdentifier,
                        @{
                            @"resumeWaitMs": LTMillisecondsString(startedAt),
                            @"reason": persistError.localizedDescription ?: @"unknown"
                        },
                        YES
                    );
                    return;
                }
                LT_BRIDGE_LOG(
                    @"resume.alert.received",
                    recordIdentifier,
                    @{ @"resumeWaitMs": LTMillisecondsString(startedAt) },
                    YES
                );
                return;
            }

            if (auto *failedAlert = lt::alert_cast<lt::save_resume_data_failed_alert>(alert)) {
                if (failedAlert->handle == handle) {
                    LT_BRIDGE_LOG(
                        @"resume.alert.failed",
                        recordIdentifier,
                        @{
                            @"resumeWaitMs": LTMillisecondsString(startedAt),
                            @"reason": LTToNSString(failedAlert->error.message())
                        },
                        YES
                    );
                    return;
                }
            }
        }
    }

    LT_BRIDGE_LOG(
        @"resume.timeout",
        recordIdentifier,
        @{ @"resumeWaitMs": LTMillisecondsString(startedAt) },
        YES
    );
}

- (BOOL)boot:(NSError * _Nullable __autoreleasing *)error {
    if (_session != nullptr) {
        return YES;
    }

    _initialOpenFileLimit = LTCurrentOpenFileLimit();
    LTRaiseOpenFileLimit();
    int const openFileLimit = LTCurrentOpenFileLimit();
    lt::settings_pack pack = LTMakeSessionSettingsPack(_performanceProfile, openFileLimit);

    try {
        _session = std::make_unique<lt::session>(pack);
    } catch (std::exception const& exception) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeEngineFailure, LTToNSString(exception.what()));
        }
        return NO;
    }

    if (LTDiagnosticsLoggingEnabled()) {
        LTDiagnosticsLog(
            @"Bridge",
            @"INFO",
            [NSString stringWithFormat:@"phase=boot.open-file-limit initial=%d limit=%d connections=%d filePool=%d",
                _initialOpenFileLimit,
                openFileLimit,
                pack.get_int(lt::settings_pack::connections_limit),
                pack.get_int(lt::settings_pack::file_pool_size)],
            YES
        );
    }
    return YES;
}

- (BOOL)applyPerformanceProfile:(LTPerformanceProfile)profile
                           error:(NSError * _Nullable __autoreleasing *)error {
    _performanceProfile = profile;

    if (_session == nullptr) {
        return YES;
    }

    try {
        _session->apply_settings(LTMakeSessionSettingsPack(profile, LTCurrentOpenFileLimit()));
    } catch (std::exception const& exception) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeEngineFailure, LTToNSString(exception.what()));
        }
        return NO;
    }

    return YES;
}

+ (LTResourceBudget *)resourceBudgetForProfile:(LTPerformanceProfile)profile
                                 openFileLimit:(NSInteger)openFileLimit {
    int const limit = static_cast<int>(std::clamp<NSInteger>(openFileLimit, 0, 10000000));
    lt::settings_pack const requested = LTMakePerformanceSettingsPack(profile);
    LTDescriptorBudget const budget = LTFitProfileIntoOpenFileLimit(requested, limit);
    return [[LTResourceBudget alloc]
        initWithInitialOpenFileLimit:limit
                       openFileLimit:limit
           requestedConnectionsLimit:requested.get_int(lt::settings_pack::connections_limit)
               requestedFilePoolSize:requested.get_int(lt::settings_pack::file_pool_size)
                    connectionsLimit:budget.connectionsLimit
                        filePoolSize:budget.filePoolSize];
}

- (LTResourceBudget *)currentResourceBudget {
    if (_session == nullptr) {
        return nil;
    }

    lt::settings_pack const requested = LTMakePerformanceSettingsPack(_performanceProfile);
    lt::settings_pack const applied = _session->get_settings();
    return [[LTResourceBudget alloc]
        initWithInitialOpenFileLimit:_initialOpenFileLimit
                       openFileLimit:LTCurrentOpenFileLimit()
           requestedConnectionsLimit:requested.get_int(lt::settings_pack::connections_limit)
               requestedFilePoolSize:requested.get_int(lt::settings_pack::file_pool_size)
                    connectionsLimit:applied.get_int(lt::settings_pack::connections_limit)
                        filePoolSize:applied.get_int(lt::settings_pack::file_pool_size)];
}

+ (NSInteger)openFileDescriptorCount {
    pid_t const pid = getpid();
    int const estimatedBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nullptr, 0);
    if (estimatedBytes <= 0) {
        return 0;
    }

    // Room for descriptors opened between the two calls.
    std::vector<proc_fdinfo> descriptors(static_cast<std::size_t>(estimatedBytes) / sizeof(proc_fdinfo) + 64);
    int const filledBytes = proc_pidinfo(
        pid,
        PROC_PIDLISTFDS,
        0,
        descriptors.data(),
        static_cast<int>(descriptors.size() * sizeof(proc_fdinfo))
    );
    return filledBytes <= 0 ? 0 : filledBytes / static_cast<int>(sizeof(proc_fdinfo));
}

- (LTPreparedDraft *)prepareDraftWithSourceKind:(NSString *)sourceKind
                                       rawValue:(NSString *)rawValue
                                draftIdentifier:(NSString *)draftIdentifier
                              suggestedSavePath:(NSString *)suggestedSavePath
                                         error:(NSError * _Nullable __autoreleasing *)error {
    if (![self boot:error]) {
        return nil;
    }

    NSString *normalizedSavePath = [suggestedSavePath stringByStandardizingPath];

    if ([sourceKind isEqualToString:@"torrentFile"] || [sourceKind isEqualToString:@"externalOpen"]) {
        return [self prepareTorrentFileDraftWithPath:rawValue
                                     draftIdentifier:draftIdentifier
                                   suggestedSavePath:normalizedSavePath
                                               error:error];
    }

    if (error != nullptr) {
        *error = LTMakeError(ShatlLibtorrentErrorCodeEngineFailure, @"Неизвестный тип источника торрента.");
    }
    return nil;
}

- (NSString *)beginMagnetMetadataFetchWithRawValue:(NSString *)rawValue
                                   draftIdentifier:(NSString *)draftIdentifier
                                 suggestedSavePath:(NSString *)suggestedSavePath
                                             error:(NSError * _Nullable __autoreleasing *)error {
    if (![self boot:error]) {
        return nil;
    }

    lt::error_code ec;
    lt::add_torrent_params params = lt::parse_magnet_uri(LTToStdString(rawValue), ec);
    if (ec) {
        if (error != nullptr) {
            *error = LTMakeErrorFromCode(ShatlLibtorrentErrorCodeInvalidMagnet, ec, @"Magnet-ссылка не прошла валидацию.");
        }
        return nil;
    }

    // A fetch left behind by a just-closed Review window must not turn the
    // same magnet into a duplicate of itself when the window is reopened.
    [self supersedeMagnetMetadataFetchesForInfoHashes:params.info_hashes];

    if (self->_session->find_torrent(params.info_hashes.get_best()).is_valid()) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeDuplicateTorrent, @"Такая загрузка уже есть.");
        }
        return nil;
    }

    NSString *normalizedSavePath = [suggestedSavePath stringByStandardizingPath];
    params.save_path = LTToStdString(normalizedSavePath);
    params.flags &= ~lt::torrent_flags::paused;
    params.flags &= ~lt::torrent_flags::auto_managed;
    params.flags |= lt::torrent_flags::upload_mode;
    params.flags |= lt::torrent_flags::duplicate_is_error;
    params.flags |= lt::torrent_flags::default_dont_download;

    lt::torrent_handle handle = self->_session->add_torrent(params, ec);
    if (ec || !handle.is_valid()) {
        if (error != nullptr) {
            *error = LTMakeErrorFromCode(ShatlLibtorrentErrorCodeEngineFailure, ec, @"Не удалось начать получение метаданных.");
        }
        return nil;
    }

    NSString *token = [NSUUID UUID].UUIDString;
    LTMagnetMetadataFetch fetch;
    fetch.handle = handle;
    fetch.infoHashes = params.info_hashes;
    fetch.draftIdentifier = LTToStdString(draftIdentifier);
    fetch.suggestedSavePath = LTToStdString(normalizedSavePath);
    self->_magnetMetadataFetchesByToken[LTToStdString(token)] = fetch;
    return token;
}

- (LTPreparedDraft *)pollMagnetMetadataFetchWithToken:(NSString *)token
                                                error:(NSError * _Nullable __autoreleasing *)error {
    std::string key = LTToStdString(token);
    auto iterator = self->_magnetMetadataFetchesByToken.find(key);
    if (iterator == self->_magnetMetadataFetchesByToken.end()) {
        if (error != nullptr) {
            *error = LTMakeError(
                ShatlLibtorrentErrorCodeDraftPreparationLost,
                @"Получение метаданных уже завершено или отменено."
            );
        }
        return nil;
    }

    LTMagnetMetadataFetch fetch = iterator->second;
    if (fetch.isSuperseded) {
        self->_magnetMetadataFetchesByToken.erase(iterator);
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeDuplicateTorrent, @"Такая загрузка уже есть.");
        }
        return nil;
    }

    lt::torrent_status status;
    try {
        status = fetch.handle.status(LTMinimalStatusQueryFlags());
    } catch (std::exception const& exception) {
        [self removeMagnetMetadataFetchWithKey:key];
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeEngineFailure, LTToNSString(exception.what()));
        }
        return nil;
    }

    if (status.errc) {
        [self removeMagnetMetadataFetchWithKey:key];
        if (error != nullptr) {
            *error = LTMakeErrorFromCode(ShatlLibtorrentErrorCodeEngineFailure, status.errc, @"Получение метаданных завершилось с ошибкой.");
        }
        return nil;
    }

    NSString *suggestedSavePath = LTToNSString(fetch.suggestedSavePath);
    auto torrentInfo = status.torrent_file.lock();
    if (!status.has_metadata || !torrentInfo) {
        return [[LTPreparedDraft alloc] initWithOriginalName:@""
                                                    infoHash:nil
                                           suggestedSavePath:suggestedSavePath
                                                       files:@[]
                                                 reviewState:LTTorrentDraftStateLoadingMetadata
                                              invalidMessage:nil];
    }

    self->_preparedTorrentInfoByDraftID[fetch.draftIdentifier] = torrentInfo;
    LTPreparedDraft *preparedDraft = [self makePreparedDraftFromTorrentInfo:torrentInfo
                                                          suggestedSavePath:suggestedSavePath];

    // Session calls run in order on libtorrent's network thread, so the
    // temporary torrent is gone before a later Confirm adds the real one.
    [self removeMagnetMetadataFetchWithKey:key];
    return preparedDraft;
}

- (void)cancelMagnetMetadataFetchWithToken:(NSString *)token {
    [self removeMagnetMetadataFetchWithKey:LTToStdString(token)];
}

- (void)removeMagnetMetadataFetchWithKey:(std::string const&)key {
    auto iterator = self->_magnetMetadataFetchesByToken.find(key);
    if (iterator == self->_magnetMetadataFetchesByToken.end()) {
        return;
    }

    if (self->_session != nullptr && iterator->second.handle.is_valid()) {
        self->_session->remove_torrent(iterator->second.handle);
    }
    self->_magnetMetadataFetchesByToken.erase(iterator);
}

/// A record or a newer add always wins over a pending magnet fetch of the same
/// torrent, so Start or Confirm never fails because a Review is still loading.
- (void)supersedeMagnetMetadataFetchesForInfoHashes:(lt::info_hash_t const&)infoHashes {
    for (auto& entry : self->_magnetMetadataFetchesByToken) {
        LTMagnetMetadataFetch& fetch = entry.second;
        if (fetch.isSuperseded || !LTInfoHashesOverlap(fetch.infoHashes, infoHashes)) {
            continue;
        }

        if (self->_session != nullptr && fetch.handle.is_valid()) {
            self->_session->remove_torrent(fetch.handle);
        }
        fetch.handle = lt::torrent_handle();
        fetch.isSuperseded = true;
    }
}

- (NSInteger)temporaryTorrentCount {
    if (_session == nullptr) {
        return 0;
    }

    NSInteger count = 0;
    for (lt::torrent_handle const& handle : _session->get_torrents()) {
        bool belongsToRecord = false;
        for (auto const& entry : self->_handlesByRecordID) {
            if (entry.second == handle) {
                belongsToRecord = true;
                break;
            }
        }
        if (!belongsToRecord) {
            count += 1;
        }
    }
    return count;
}

- (LTPreparedDraft *)prepareTorrentFileDraftWithPath:(NSString *)path
                                     draftIdentifier:(NSString *)draftIdentifier
                                   suggestedSavePath:(NSString *)suggestedSavePath
                                               error:(NSError * _Nullable __autoreleasing *)error {
    lt::error_code ec;
    auto torrentInfo = std::make_shared<lt::torrent_info>(LTToStdString(path), ec);
    if (ec) {
        if (error != nullptr) {
            *error = LTMakeErrorFromCode(ShatlLibtorrentErrorCodeInvalidTorrentFile, ec, @"Torrent-файл не прошёл валидацию.");
        }
        return nil;
    }

    [self supersedeMagnetMetadataFetchesForInfoHashes:torrentInfo->info_hashes()];
    if (self->_session->find_torrent(torrentInfo->info_hashes().get_best()).is_valid()) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeDuplicateTorrent, @"Такая загрузка уже есть.");
        }
        return nil;
    }

    self->_preparedTorrentInfoByDraftID[LTToStdString(draftIdentifier)] = torrentInfo;
    return [self makePreparedDraftFromTorrentInfo:torrentInfo suggestedSavePath:suggestedSavePath];
}

- (NSArray<LTPreparedFile *> *)inspectTorrentContentsAtPath:(NSString *)torrentFilePath
                                                      error:(NSError * _Nullable __autoreleasing *)error {
    lt::error_code ec;
    auto torrentInfo = std::make_shared<lt::torrent_info>(LTToStdString(torrentFilePath), ec);
    if (ec) {
        if (error != nullptr) {
            *error = LTMakeErrorFromCode(
                ShatlLibtorrentErrorCodeInvalidTorrentFile,
                ec,
                @"Не удалось прочитать torrent-файл."
            );
        }
        return nil;
    }

    lt::file_storage const& fileStorage = torrentInfo->files();
    NSMutableArray<LTPreparedFile *> *files = [[NSMutableArray alloc] init];

    for (int index = 0; index < fileStorage.num_files(); ++index) {
        lt::file_index_t fileIndex{index};
        NSString *filePath = LTToNSString(fileStorage.file_path(fileIndex));
        long long fileSize = fileStorage.file_size(fileIndex);

        [files addObject:[[LTPreparedFile alloc] initWithName:filePath
                                                    sizeBytes:fileSize
                                                    fileIndex:index]];
    }

    return files;
}

- (LTPreparedDraft *)makePreparedDraftFromTorrentInfo:(std::shared_ptr<const lt::torrent_info>)torrentInfo
                                    suggestedSavePath:(NSString *)suggestedSavePath {
    NSMutableArray<LTPreparedFile *> *files = [[NSMutableArray alloc] init];
    lt::file_storage const& fileStorage = torrentInfo->files();

    for (int index = 0; index < fileStorage.num_files(); ++index) {
        lt::file_index_t fileIndex{index};
        NSString *filePath = LTToNSString(fileStorage.file_path(fileIndex));
        long long fileSize = fileStorage.file_size(fileIndex);

        [files addObject:[[LTPreparedFile alloc] initWithName:filePath
                                                    sizeBytes:fileSize
                                                    fileIndex:index]];
    }

    return [[LTPreparedDraft alloc] initWithOriginalName:LTToNSString(torrentInfo->name())
                                                infoHash:LTInfoHashString(torrentInfo->info_hashes())
                                       suggestedSavePath:suggestedSavePath
                                                   files:files
                                             reviewState:LTTorrentDraftStateReady
                                          invalidMessage:nil];
}

- (LTAddedTorrent *)addTorrentWithSourceKind:(NSString *)sourceKind
                             draftIdentifier:(NSString *)draftIdentifier
                           suggestedSavePath:(NSString *)suggestedSavePath
                            stopAfterDownload:(BOOL)stopAfterDownload
                           selectedFileIndices:(NSArray<NSNumber *> *)selectedFileIndices
                              recordIdentifier:(NSString *)recordIdentifier
                             attemptIdentifier:(NSString *)attemptIdentifier
                                         error:(NSError * _Nullable __autoreleasing *)error {
    auto addStartedAt = std::chrono::steady_clock::now();
    if (![self boot:error]) {
        LT_BRIDGE_LOG(@"add.boot.failed", recordIdentifier, nil, YES);
        return nil;
    }

    NSString *normalizedSavePath = [suggestedSavePath stringByStandardizingPath];
    LT_BRIDGE_LOG(
        @"add.begin",
        recordIdentifier,
        @{
            @"sourceKind": sourceKind ?: @"unknown",
            @"savePath": normalizedSavePath ?: @"",
            @"selectedCount": [NSString stringWithFormat:@"%lu", static_cast<unsigned long>(selectedFileIndices.count)]
        },
        YES
    );

    auto cachedInfoIterator = self->_preparedTorrentInfoByDraftID.find(LTToStdString(draftIdentifier));
    if (cachedInfoIterator == self->_preparedTorrentInfoByDraftID.end()) {
        LT_BRIDGE_LOG(@"add.draft-missing", recordIdentifier, nil, YES);
        if (error != nullptr) {
            *error = LTMakeError(
                ShatlLibtorrentErrorCodeDraftPreparationLost,
                @"Черновик торрента потерян и требует повторной подготовки."
            );
        }
        return nil;
    }

    std::shared_ptr<const lt::torrent_info> torrentInfo = cachedInfoIterator->second;
    lt::sha1_hash bestHash = torrentInfo->info_hashes().get_best();
    [self supersedeMagnetMetadataFetchesForInfoHashes:torrentInfo->info_hashes()];
    if (self->_session->find_torrent(bestHash).is_valid()) {
        LT_BRIDGE_LOG(@"add.duplicate", recordIdentifier, nil, YES);
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeDuplicateTorrent, @"Такая загрузка уже есть.");
        }
        return nil;
    }

    lt::add_torrent_params params;
    // add_torrent_params expects a non-const shared_ptr, while this torrent_info is
    // already treated as immutable. Remove const only at the libtorrent boundary.
    params.ti = std::const_pointer_cast<lt::torrent_info>(torrentInfo);
    params.save_path = LTToStdString(normalizedSavePath);
    params.storage_mode = lt::storage_mode_sparse;
    params.flags &= ~lt::torrent_flags::paused;
    params.flags &= ~lt::torrent_flags::auto_managed;
    params.flags |= lt::torrent_flags::duplicate_is_error;

    lt::file_storage const& fileStorage = torrentInfo->files();
    params.file_priorities.reserve(fileStorage.num_files());

    if (selectedFileIndices.count == 0) {
        LT_BRIDGE_LOG(@"add.invalid-selection", recordIdentifier, nil, YES);
        if (error != nullptr) {
            *error = LTMakeError(
                ShatlLibtorrentErrorCodeEngineFailure,
                @"Для загрузки должен быть выбран хотя бы один файл."
            );
        }
        return nil;
    }

    std::unordered_map<int, bool> selectedIndices;
    for (NSNumber *index in selectedFileIndices) {
        selectedIndices[index.intValue] = true;
    }

    long long selectedBytes = 0;
    NSInteger selectedFileCount = 0;

    for (int index = 0; index < fileStorage.num_files(); ++index) {
        bool isSelected = selectedIndices.count(index) > 0;
        params.file_priorities.push_back(isSelected ? lt::default_priority : lt::dont_download);
        if (isSelected) {
            selectedBytes += fileStorage.file_size(lt::file_index_t{index});
            selectedFileCount += 1;
        }
    }

    lt::error_code ec;
    lt::torrent_handle handle = self->_session->add_torrent(params, ec);
    if (ec || !handle.is_valid()) {
        LT_BRIDGE_LOG(
            @"add.failed",
            recordIdentifier,
            @{ @"reason": ec ? LTToNSString(ec.message()) : @"invalid-handle" },
            YES
        );
        if (error != nullptr) {
            ShatlLibtorrentErrorCode code = ec == lt::errors::duplicate_torrent
                ? ShatlLibtorrentErrorCodeDuplicateTorrent
                : ShatlLibtorrentErrorCodeEngineFailure;
            *error = LTMakeErrorFromCode(code, ec, @"Не удалось добавить торрент в сессию.");
        }
        return nil;
    }

    self->_handlesByRecordID[LTToStdString(recordIdentifier)] = handle;
    self->_stopAfterDownloadByRecordID[LTToStdString(recordIdentifier)] = stopAfterDownload;

    // A fresh add needs the same explicit start kick as restore and start.
    // On external drives, clearing the paused flag in add_torrent_params is not
    // reliable enough: the handle can report downloading without writing data
    // until the user performs a manual stop and start.
    handle.resume();
    handle.unset_flags(lt::torrent_flags::paused);

    lt::torrent_status status = handle.status(LTMinimalStatusQueryFlags());
    LT_BRIDGE_LOG(
        @"add.end",
        recordIdentifier,
        @{
            @"status": [NSString stringWithFormat:@"%d", static_cast<int>(LTRuntimeStatusFromTorrentStatus(status))],
            @"progress": [NSString stringWithFormat:@"%.3f", status.progress],
            @"paused": LTFlagEnabled(status.flags, lt::torrent_flags::paused) ? @"1" : @"0",
            @"errc": status.errc ? LTToNSString(status.errc.message()) : @"none",
            @"totalMs": LTMillisecondsString(addStartedAt)
        },
        YES
    );

    return [[LTAddedTorrent alloc] initWithRecordIdentifier:recordIdentifier
                                          attemptIdentifier:attemptIdentifier
                                                   infoHash:LTInfoHashString(torrentInfo->info_hashes())
                                               originalName:LTToNSString(torrentInfo->name())
                                                 totalBytes:torrentInfo->total_size()
                                              selectedBytes:selectedBytes
                                          selectedFileCount:selectedFileCount
                                             totalFileCount:fileStorage.num_files()];
}

- (BOOL)exportPreparedTorrentWithDraftIdentifier:(NSString *)draftIdentifier
                                 destinationPath:(NSString *)destinationPath
                                           error:(NSError * _Nullable __autoreleasing *)error {
    auto cachedInfoIterator = self->_preparedTorrentInfoByDraftID.find(LTToStdString(draftIdentifier));
    if (cachedInfoIterator == self->_preparedTorrentInfoByDraftID.end()) {
        if (error != nullptr) {
            *error = LTMakeError(
                ShatlLibtorrentErrorCodeDraftPreparationLost,
                @"Черновик торрента потерян и требует повторной подготовки."
            );
        }
        return NO;
    }

    std::shared_ptr<const lt::torrent_info> torrentInfo = cachedInfoIterator->second;
    lt::create_torrent creator(*torrentInfo);
    lt::entry torrentEntry = creator.generate();
    std::vector<char> encodedData;
    lt::bencode(std::back_inserter(encodedData), torrentEntry);

    NSString *normalizedDestinationPath = [destinationPath stringByStandardizingPath];
    NSURL *destinationURL = [NSURL fileURLWithPath:normalizedDestinationPath];
    NSURL *parentDirectoryURL = [destinationURL URLByDeletingLastPathComponent];

    NSError *directoryError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:parentDirectoryURL
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&directoryError]) {
        if (error != nullptr) {
            *error = directoryError ?: LTMakeError(
                ShatlLibtorrentErrorCodeEngineFailure,
                @"Не удалось подготовить папку для архивного torrent-файла."
            );
        }
        return NO;
    }

    NSData *data = [NSData dataWithBytes:encodedData.data() length:encodedData.size()];
    if (![data writeToURL:destinationURL options:NSDataWritingAtomic error:&directoryError]) {
        if (error != nullptr) {
            *error = directoryError ?: LTMakeError(
                ShatlLibtorrentErrorCodeEngineFailure,
                @"Не удалось сохранить архивный torrent-файл."
            );
        }
        return NO;
    }

    return YES;
}

- (void)releasePreparedDraftWithIdentifier:(NSString *)draftIdentifier {
    self->_preparedTorrentInfoByDraftID.erase(LTToStdString(draftIdentifier));
}

- (NSInteger)preparedDraftCount {
    return static_cast<NSInteger>(self->_preparedTorrentInfoByDraftID.size());
}

- (LTTorrentSnapshot *)restoreTorrentWithTorrentFilePath:(NSString *)torrentFilePath
                                       suggestedSavePath:(NSString *)suggestedSavePath
                                        stopAfterDownload:(BOOL)stopAfterDownload
                                       selectedFileIndices:(NSArray<NSNumber *> *)selectedFileIndices
                                          recordIdentifier:(NSString *)recordIdentifier
                                               shouldStart:(BOOL)shouldStart
                                                     error:(NSError * _Nullable __autoreleasing *)error {
    auto restoreStartedAt = std::chrono::steady_clock::now();
    LT_BRIDGE_LOG(
        @"restore.begin",
        recordIdentifier,
        @{
            @"shouldStart": shouldStart ? @"1" : @"0",
            @"selectedCount": [NSString stringWithFormat:@"%lu", static_cast<unsigned long>(selectedFileIndices.count)]
        },
        YES
    );

    if (![self boot:error]) {
        LT_BRIDGE_LOG(@"restore.boot.failed", recordIdentifier, nil, YES);
        return nil;
    }

    lt::error_code ec;
    auto torrentInfo = std::make_shared<lt::torrent_info>(LTToStdString(torrentFilePath), ec);
    if (ec) {
        LT_BRIDGE_LOG(
            @"restore.archive-invalid",
            recordIdentifier,
            @{ @"reason": LTToNSString(ec.message()) },
            YES
        );
        if (error != nullptr) {
            *error = LTMakeErrorFromCode(
                ShatlLibtorrentErrorCodeInvalidTorrentFile,
                ec,
                @"Не удалось прочитать архивный torrent-файл."
            );
        }
        return nil;
    }

    NSString *normalizedSavePath = [suggestedSavePath stringByStandardizingPath];
    lt::add_torrent_params params;
    params.ti = torrentInfo;
    params.save_path = LTToStdString(normalizedSavePath);
    params.storage_mode = lt::storage_mode_sparse;
    params.flags &= ~lt::torrent_flags::auto_managed;
    params.flags |= lt::torrent_flags::duplicate_is_error;
    NSString *resumeDataStatus = @"missing";

    {
        std::ifstream in(
            LTToStdString([self resumeDataFileURLForRecordIdentifier:recordIdentifier].path),
            std::ios::binary
        );
        if (in.good()) {
            std::vector<char> data((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
            lt::error_code resumeError;
            lt::add_torrent_params resumed = lt::read_resume_data(data, resumeError);
            if (!resumeError) {
                resumed.ti = torrentInfo;
                resumed.save_path = LTToStdString(normalizedSavePath);
                resumed.storage_mode = lt::storage_mode_sparse;
                resumed.flags &= ~lt::torrent_flags::auto_managed;
                resumed.flags |= lt::torrent_flags::duplicate_is_error;
                params = std::move(resumed);
                resumeDataStatus = @"loaded";
                LT_BRIDGE_LOG(@"restore.resume.loaded", recordIdentifier, nil, YES);
            } else {
                resumeDataStatus = @"invalid";
                LT_BRIDGE_LOG(
                    @"restore.resume.invalid",
                    recordIdentifier,
                    @{ @"reason": LTToNSString(resumeError.message()) },
                    YES
                );
            }
        } else {
            LT_BRIDGE_LOG(@"restore.resume.missing", recordIdentifier, nil, YES);
        }
    }

    if (shouldStart) {
        params.flags &= ~lt::torrent_flags::paused;
    } else {
        params.flags |= lt::torrent_flags::paused;
    }

    lt::file_storage const& fileStorage = torrentInfo->files();

    if (selectedFileIndices.count == 0) {
        LT_BRIDGE_LOG(@"restore.invalid-selection", recordIdentifier, nil, YES);
        if (error != nullptr) {
            *error = LTMakeError(
                ShatlLibtorrentErrorCodeEngineFailure,
                @"Для восстановления должен быть выбран хотя бы один файл."
            );
        }
        return nil;
    }

    std::unordered_map<int, bool> selectedIndices;
    for (NSNumber *index in selectedFileIndices) {
        selectedIndices[index.intValue] = true;
    }

    params.file_priorities.assign(
        static_cast<std::size_t>(fileStorage.num_files()),
        lt::dont_download
    );
    for (int index = 0; index < fileStorage.num_files(); ++index) {
        bool isSelected = selectedIndices.count(index) > 0;
        params.file_priorities[static_cast<std::size_t>(index)] =
            isSelected ? lt::default_priority : lt::dont_download;
    }

    [self supersedeMagnetMetadataFetchesForInfoHashes:torrentInfo->info_hashes()];
    lt::torrent_handle handle = self->_session->add_torrent(params, ec);
    if (ec || !handle.is_valid()) {
        LT_BRIDGE_LOG(
            @"restore.add.failed",
            recordIdentifier,
            @{ @"reason": ec ? LTToNSString(ec.message()) : @"invalid-handle" },
            YES
        );
        if (error != nullptr) {
            ShatlLibtorrentErrorCode code = ec == lt::errors::duplicate_torrent
                ? ShatlLibtorrentErrorCodeDuplicateTorrent
                : ShatlLibtorrentErrorCodeEngineFailure;
            *error = LTMakeErrorFromCode(code, ec, @"Не удалось восстановить торрент в сессии.");
        }
        return nil;
    }

    auto key = LTToStdString(recordIdentifier);
    self->_handlesByRecordID[key] = handle;
    self->_stopAfterDownloadByRecordID[key] = stopAfterDownload;

    if (shouldStart) {
        handle.resume();
        handle.unset_flags(lt::torrent_flags::paused);
    } else {
        handle.pause();
        handle.set_flags(lt::torrent_flags::paused);
    }

    LTTorrentSnapshot *snapshot = [self snapshotFromHandle:handle
                                          recordIdentifier:recordIdentifier
                                          resumeDataStatus:resumeDataStatus];
    self->_lastSnapshotStatusByRecordID[key] = snapshot.status;
    LT_BRIDGE_LOG(
        @"restore.end",
        recordIdentifier,
        @{
            @"status": [NSString stringWithFormat:@"%ld", static_cast<long>(snapshot.status)],
            @"progress": [NSString stringWithFormat:@"%.3f", snapshot.progress],
            @"resumeDataStatus": resumeDataStatus,
            @"totalMs": LTMillisecondsString(restoreStartedAt)
        },
        YES
    );
    return snapshot;
}

- (NSArray<NSNumber *> *)materializedFileIndicesForTorrentWithIdentifier:(NSString *)recordIdentifier
                                                     selectedFileIndices:(NSArray<NSNumber *> *)selectedFileIndices
                                                                   error:(NSError * _Nullable __autoreleasing *)error {
    auto iterator = self->_handlesByRecordID.find(LTToStdString(recordIdentifier));
    if (iterator == self->_handlesByRecordID.end() || !iterator->second.is_valid()) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeTorrentNotFound, @"Торрент не найден в активной сессии.");
        }
        return nil;
    }

    std::unordered_map<int, bool> selectedIndices;
    for (NSNumber *index in selectedFileIndices) {
        selectedIndices[index.intValue] = true;
    }

    std::vector<std::int64_t> progress = iterator->second.file_progress();
    NSMutableArray<NSNumber *> *materializedIndices = [[NSMutableArray alloc] init];

    for (int index = 0; index < int(progress.size()); ++index) {
        if (selectedIndices.count(index) == 0) {
            continue;
        }

        if (progress[std::size_t(index)] > 0) {
            [materializedIndices addObject:@(index)];
        }
    }

    return materializedIndices;
}

- (BOOL)startTorrentWithIdentifier:(NSString *)recordIdentifier
                             error:(NSError * _Nullable __autoreleasing *)error {
    auto startedAt = std::chrono::steady_clock::now();
    LT_BRIDGE_LOG(@"start.begin", recordIdentifier, nil, YES);
    auto iterator = self->_handlesByRecordID.find(LTToStdString(recordIdentifier));
    if (iterator == self->_handlesByRecordID.end() || !iterator->second.is_valid()) {
        LT_BRIDGE_LOG(@"start.not-found", recordIdentifier, nil, YES);
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeTorrentNotFound, @"Торрент не найден в активной сессии.");
        }
        return NO;
    }

    iterator->second.unset_flags(lt::torrent_flags::paused);
    iterator->second.resume();
    LT_BRIDGE_LOG(
        @"start.end",
        recordIdentifier,
        @{ @"totalMs": LTMillisecondsString(startedAt) },
        YES
    );
    return YES;
}

- (BOOL)stopTorrentWithIdentifier:(NSString *)recordIdentifier
                            error:(NSError * _Nullable __autoreleasing *)error {
    auto startedAt = std::chrono::steady_clock::now();
    LT_BRIDGE_LOG(@"stop.begin", recordIdentifier, nil, YES);
    auto iterator = self->_handlesByRecordID.find(LTToStdString(recordIdentifier));
    if (iterator == self->_handlesByRecordID.end() || !iterator->second.is_valid()) {
        LT_BRIDGE_LOG(@"stop.not-found", recordIdentifier, nil, YES);
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeTorrentNotFound, @"Торрент не найден в активной сессии.");
        }
        return NO;
    }

    iterator->second.pause();
    iterator->second.set_flags(lt::torrent_flags::paused);
    LT_BRIDGE_LOG(
        @"stop.end",
        recordIdentifier,
        @{ @"totalMs": LTMillisecondsString(startedAt) },
        YES
    );
    return YES;
}

- (BOOL)forceRecheckTorrentWithIdentifier:(NSString *)recordIdentifier
                                    error:(NSError * _Nullable __autoreleasing *)error {
    auto startedAt = std::chrono::steady_clock::now();
    LT_BRIDGE_LOG(@"recheck.begin", recordIdentifier, nil, YES);
    auto iterator = self->_handlesByRecordID.find(LTToStdString(recordIdentifier));
    if (iterator == self->_handlesByRecordID.end() || !iterator->second.is_valid()) {
        LT_BRIDGE_LOG(@"recheck.not-found", recordIdentifier, nil, YES);
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeTorrentNotFound, @"Торрент не найден в активной сессии.");
        }
        return NO;
    }

    iterator->second.force_recheck();
    LT_BRIDGE_LOG(
        @"recheck.end",
        recordIdentifier,
        @{ @"totalMs": LTMillisecondsString(startedAt) },
        YES
    );
    return YES;
}

- (NSArray<LTResumeCheckpoint *> *)checkpointTorrentsWithIdentifiers:(NSArray<NSString *> *)recordIdentifiers
                                                               error:(NSError * _Nullable __autoreleasing *)error {
    if (_session == nullptr) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeSessionNotBooted, @"Сессия libtorrent ещё не запущена.");
        }
        return nil;
    }

    auto startedAt = std::chrono::steady_clock::now();
    LT_BRIDGE_LOG(
        @"resume.batch.begin",
        @"-",
        @{ @"count": [NSString stringWithFormat:@"%lu", static_cast<unsigned long>(recordIdentifiers.count)] },
        YES
    );

    NSMutableArray<LTResumeCheckpoint *> *results = [[NSMutableArray alloc] init];
    std::map<std::string, lt::torrent_handle> pending;

    for (NSString *recordIdentifier in recordIdentifiers) {
        auto key = LTToStdString(recordIdentifier);
        auto iterator = self->_handlesByRecordID.find(key);
        if (iterator == self->_handlesByRecordID.end() || !iterator->second.is_valid()) {
            LT_BRIDGE_LOG(@"resume.skip", recordIdentifier, @{ @"reason": @"not-found" }, YES);
            [results addObject:[self checkpointResultForRecordIdentifier:recordIdentifier
                                                                  status:@"not-found"
                                                            errorMessage:nil]];
            continue;
        }

        try {
            iterator->second.save_resume_data();
            pending[key] = iterator->second;
            LT_BRIDGE_LOG(
                @"resume.requested",
                recordIdentifier,
                @{ @"resumeMode": @"checkpoint" },
                YES
            );
        } catch (std::exception const& exception) {
            LT_BRIDGE_LOG(
                @"resume.request.failed",
                recordIdentifier,
                @{ @"reason": LTToNSString(exception.what()) },
                YES
            );
            [results addObject:[self checkpointResultForRecordIdentifier:recordIdentifier
                                                                  status:@"failed"
                                                            errorMessage:LTToNSString(exception.what())]];
        } catch (...) {
            LT_BRIDGE_LOG(
                @"resume.request.failed",
                recordIdentifier,
                @{ @"reason": @"save_resume_data-throw" },
                YES
            );
            [results addObject:[self checkpointResultForRecordIdentifier:recordIdentifier
                                                                  status:@"failed"
                                                            errorMessage:@"save_resume_data-throw"]];
        }
    }

    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (!pending.empty() && std::chrono::steady_clock::now() < deadline) {
        _session->wait_for_alert(std::chrono::milliseconds(100));

        std::vector<lt::alert *> alerts;
        _session->pop_alerts(&alerts);

        for (lt::alert *alert : alerts) {
            if (auto *resumeAlert = lt::alert_cast<lt::save_resume_data_alert>(alert)) {
                for (auto iterator = pending.begin(); iterator != pending.end(); ++iterator) {
                    if (iterator->second != resumeAlert->handle) {
                        continue;
                    }

                    NSString *recordIdentifier = LTToNSString(iterator->first);
                    NSError *persistError = nil;
                    if (![self persistResumeDataFromParams:resumeAlert->params
                                       forRecordIdentifier:recordIdentifier
                                                     error:&persistError]) {
                        // A checkpoint is `saved` only after the file write is
                        // confirmed; one failure must not abort the whole batch.
                        [results addObject:[self checkpointResultForRecordIdentifier:recordIdentifier
                                                                              status:@"failed"
                                                                        errorMessage:@"resume-persist-failed"]];
                        LT_BRIDGE_LOG(
                            @"resume.persist.failed",
                            recordIdentifier,
                            @{
                                @"resumeWaitMs": LTMillisecondsString(startedAt),
                                @"reason": persistError.localizedDescription ?: @"unknown"
                            },
                            YES
                        );
                        pending.erase(iterator);
                        break;
                    }

                    [results addObject:[self checkpointResultForRecordIdentifier:recordIdentifier
                                                                          status:@"saved"
                                                                    errorMessage:nil]];
                    LT_BRIDGE_LOG(
                        @"resume.alert.received",
                        recordIdentifier,
                        @{ @"resumeWaitMs": LTMillisecondsString(startedAt) },
                        YES
                    );
                    pending.erase(iterator);
                    break;
                }
                continue;
            }

            if (auto *failedAlert = lt::alert_cast<lt::save_resume_data_failed_alert>(alert)) {
                for (auto iterator = pending.begin(); iterator != pending.end(); ++iterator) {
                    if (iterator->second != failedAlert->handle) {
                        continue;
                    }

                    NSString *recordIdentifier = LTToNSString(iterator->first);
                    NSString *reason = LTToNSString(failedAlert->error.message());
                    [results addObject:[self checkpointResultForRecordIdentifier:recordIdentifier
                                                                          status:@"failed"
                                                                    errorMessage:reason]];
                    LT_BRIDGE_LOG(
                        @"resume.alert.failed",
                        recordIdentifier,
                        @{
                            @"resumeWaitMs": LTMillisecondsString(startedAt),
                            @"reason": reason
                        },
                        YES
                    );
                    pending.erase(iterator);
                    break;
                }
            }
        }
    }

    for (auto const& entry : pending) {
        NSString *recordIdentifier = LTToNSString(entry.first);
        [results addObject:[self checkpointResultForRecordIdentifier:recordIdentifier
                                                              status:@"timed-out"
                                                        errorMessage:nil]];
        LT_BRIDGE_LOG(
            @"resume.timeout",
            recordIdentifier,
            @{ @"resumeWaitMs": LTMillisecondsString(startedAt) },
            YES
        );
    }

    LT_BRIDGE_LOG(
        @"resume.batch.end",
        @"-",
        @{
            @"resultCount": [NSString stringWithFormat:@"%lu", static_cast<unsigned long>(results.count)],
            @"totalMs": LTMillisecondsString(startedAt)
        },
        YES
    );

    return results;
}

- (BOOL)removeTorrentWithIdentifier:(NSString *)recordIdentifier
                         deleteData:(BOOL)deleteData
                              error:(NSError * _Nullable __autoreleasing *)error {
    auto startedAt = std::chrono::steady_clock::now();
    LT_BRIDGE_LOG(
        @"remove.begin",
        recordIdentifier,
        @{ @"deleteData": deleteData ? @"1" : @"0" },
        YES
    );
    auto key = LTToStdString(recordIdentifier);
    auto iterator = self->_handlesByRecordID.find(key);
    if (iterator == self->_handlesByRecordID.end() || !iterator->second.is_valid()) {
        LT_BRIDGE_LOG(@"remove.not-found", recordIdentifier, nil, YES);
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeTorrentNotFound, @"Торрент не найден в активной сессии.");
        }
        return NO;
    }

    lt::remove_flags_t flags{};
    if (deleteData) {
        flags |= lt::session_handle::delete_files;
    } else {
        [self saveResumeDataForHandle:iterator->second recordIdentifier:recordIdentifier];
    }

    LT_BRIDGE_LOG(
        @"remove.session-call",
        recordIdentifier,
        @{ @"deleteData": deleteData ? @"1" : @"0" },
        YES
    );
    self->_session->remove_torrent(iterator->second, flags);
    self->_handlesByRecordID.erase(iterator);
    self->_stopAfterDownloadByRecordID.erase(key);
    self->_lastSnapshotStatusByRecordID.erase(key);
    LT_BRIDGE_LOG(
        @"remove.end",
        recordIdentifier,
        @{
            @"deleteData": deleteData ? @"1" : @"0",
            @"totalMs": LTMillisecondsString(startedAt)
        },
        YES
    );
    return YES;
}

- (NSArray<LTTorrentSnapshot *> *)fetchActiveSnapshots:(NSError * _Nullable __autoreleasing *)error {
    if (_session == nullptr) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeSessionNotBooted, @"Сессия libtorrent ещё не запущена.");
        }
        return nil;
    }

    uint64_t tickID = ++self->_snapshotTickCounter;
    auto tickStartedAt = std::chrono::steady_clock::now();
    LT_SNAPSHOT_LOG(
        @"snapshot.tick.begin",
        @{
            @"source": @"active",
            @"tickID": [NSString stringWithFormat:@"%llu", static_cast<unsigned long long>(tickID)],
            @"handleCount": [NSString stringWithFormat:@"%lu", static_cast<unsigned long>(self->_handlesByRecordID.size())]
        },
        YES
    );

    NSMutableArray<LTTorrentSnapshot *> *snapshots = [[NSMutableArray alloc] init];
    NSUInteger handleIndex = 0;

    for (auto const& entry : self->_handlesByRecordID) {
        if (!entry.second.is_valid()) {
            handleIndex += 1;
            continue;
        }

        NSString *recordIdentifier = LTToNSString(entry.first);
        LTTorrentSnapshot *snapshot = [self snapshotFromHandle:entry.second
                                              recordIdentifier:recordIdentifier
                                              resumeDataStatus:nil
                                                        source:@"active"
                                                        tickID:tickID
                                                   handleIndex:handleIndex];
        auto runtimeStatus = snapshot.status;
        bool isSleeping = runtimeStatus == LTTorrentRuntimeStatusCompleted
            || runtimeStatus == LTTorrentRuntimeStatusStopped;

        auto previousStatusIterator = self->_lastSnapshotStatusByRecordID.find(entry.first);
        bool didTransitionToNewState = previousStatusIterator == self->_lastSnapshotStatusByRecordID.end()
            || previousStatusIterator->second != runtimeStatus;
        self->_lastSnapshotStatusByRecordID[entry.first] = runtimeStatus;

        // Sleeping torrents emit one final snapshot during the transition,
        // then leave active polling.
        if (isSleeping && !didTransitionToNewState) {
            handleIndex += 1;
            continue;
        }

        [snapshots addObject:snapshot];
        handleIndex += 1;
    }

    LT_SNAPSHOT_LOG(
        @"snapshot.tick.end",
        @{
            @"source": @"active",
            @"tickID": [NSString stringWithFormat:@"%llu", static_cast<unsigned long long>(tickID)],
            @"durationMs": LTMillisecondsString(tickStartedAt),
            @"snapshotCount": [NSString stringWithFormat:@"%lu", static_cast<unsigned long>(snapshots.count)]
        },
        NO
    );

    return snapshots;
}

- (NSArray<LTTorrentSnapshot *> *)reconcileTorrentIdentifiers:(NSArray<NSString *> *)recordIdentifiers
                                                        error:(NSError * _Nullable __autoreleasing *)error {
    if (_session == nullptr) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeSessionNotBooted, @"Сессия libtorrent ещё не запущена.");
        }
        return nil;
    }

    NSMutableArray<LTTorrentSnapshot *> *snapshots = [[NSMutableArray alloc] init];
    uint64_t tickID = ++self->_snapshotTickCounter;
    NSUInteger handleIndex = 0;

    for (NSString *recordIdentifier in recordIdentifiers) {
        auto iterator = self->_handlesByRecordID.find(LTToStdString(recordIdentifier));
        if (iterator == self->_handlesByRecordID.end() || !iterator->second.is_valid()) {
            handleIndex += 1;
            continue;
        }

        LTTorrentSnapshot *snapshot = [self snapshotFromHandle:iterator->second
                                              recordIdentifier:recordIdentifier
                                              resumeDataStatus:nil
                                                        source:@"reconcile"
                                                        tickID:tickID
                                                   handleIndex:handleIndex];
        self->_lastSnapshotStatusByRecordID[LTToStdString(recordIdentifier)] = snapshot.status;
        [snapshots addObject:snapshot];
        handleIndex += 1;
    }

    return snapshots;
}

- (LTTorrentSnapshot *)snapshotFromHandle:(lt::torrent_handle const&)handle
                         recordIdentifier:(NSString *)recordIdentifier {
    return [self snapshotFromHandle:handle recordIdentifier:recordIdentifier resumeDataStatus:nil];
}

- (LTTorrentSnapshot *)snapshotFromHandle:(lt::torrent_handle const&)handle
                         recordIdentifier:(NSString *)recordIdentifier
                         resumeDataStatus:(NSString *)resumeDataStatus {
    return [self snapshotFromHandle:handle
                    recordIdentifier:recordIdentifier
                    resumeDataStatus:resumeDataStatus
                              source:@"direct"
                              tickID:0
                         handleIndex:NSNotFound];
}

- (LTTorrentSnapshot *)snapshotFromHandle:(lt::torrent_handle const&)handle
                         recordIdentifier:(NSString *)recordIdentifier
                         resumeDataStatus:(NSString *)resumeDataStatus
                                   source:(NSString *)source
                                   tickID:(uint64_t)tickID
                              handleIndex:(NSUInteger)handleIndex {
    auto recordKey = LTToStdString(recordIdentifier);
    BOOL stopAfterDownloadPending = self->_stopAfterDownloadByRecordID[recordKey];
    lt::torrent_status status = LTStatusWithSnapshotDiagnostics(
        handle,
        source,
        recordIdentifier,
        tickID,
        handleIndex,
        @"initial-status",
        stopAfterDownloadPending
    );
    auto handleIterator = self->_handlesByRecordID.find(recordKey);
    if (handleIterator != self->_handlesByRecordID.end()
        && status.is_finished
        && self->_stopAfterDownloadByRecordID[recordKey]
        && !LTFlagEnabled(status.flags, lt::torrent_flags::paused)) {
        handleIterator->second.pause();
        handleIterator->second.set_flags(lt::torrent_flags::paused);
        // Auto-stop is a one-shot rule applied when a download completes.
        // After it fires, the user can manually start the finished torrent
        // for seeding without triggering another immediate pause.
        self->_stopAfterDownloadByRecordID[recordKey] = false;
        status = LTStatusWithSnapshotDiagnostics(
            handle,
            source,
            recordIdentifier,
            tickID,
            handleIndex,
            @"autostop-status",
            NO
        );
    }

    // For partial selections, compute progress from wanted bytes instead of relying
    // on `status.progress`, whose calculation base can change between launches.
    double visibleProgress = status.progress;
    if (status.total_wanted > 0) {
        visibleProgress = double(status.total_wanted_done) / double(status.total_wanted);
    }

    if (status.upload_rate > 0 || status.upload_payload_rate > 0 || status.all_time_upload > 0) {
        LT_BRIDGE_LOG(
            @"snapshot.upload-counters.bridge",
            recordIdentifier,
            @{
                @"downloadRate": [NSString stringWithFormat:@"%lld", static_cast<long long>(status.download_rate)],
                @"progress": [NSString stringWithFormat:@"%.3f", visibleProgress],
                @"runtimeStatus": [NSString stringWithFormat:@"%d", static_cast<int>(LTRuntimeStatusFromTorrentStatus(status))],
                @"state": [NSString stringWithFormat:@"%d", static_cast<int>(status.state)],
                @"totalWanted": [NSString stringWithFormat:@"%lld", static_cast<long long>(status.total_wanted)],
                @"totalWantedDone": [NSString stringWithFormat:@"%lld", static_cast<long long>(status.total_wanted_done)],
                @"uploadRate": [NSString stringWithFormat:@"%lld", static_cast<long long>(status.upload_rate)],
                @"uploadPayloadRate": [NSString stringWithFormat:@"%lld", static_cast<long long>(status.upload_payload_rate)],
                @"uploadedBytes": [NSString stringWithFormat:@"%lld", static_cast<long long>(status.all_time_upload)],
                @"uploadedCounterSuspicious": status.upload_payload_rate > 0 && status.all_time_upload == 0 ? @"1" : @"0"
            },
            status.upload_payload_rate > 0 && status.all_time_upload == 0
        );
    }

    return [[LTTorrentSnapshot alloc] initWithRecordIdentifier:recordIdentifier
                                                        status:LTRuntimeStatusFromTorrentStatus(status)
                                                      progress:visibleProgress
                                    downloadSpeedBytesPerSecond:status.download_rate
                                      uploadSpeedBytesPerSecond:status.upload_payload_rate
                                                     etaSeconds:LTBoxedETA(status)
                                                          seeds:LTBoxedIntIfPositive(status.num_seeds)
                                                          peers:LTBoxedIntIfPositive(status.num_peers)
                                                  uploadedBytes:status.all_time_upload
                                                     totalBytes:status.total
                                                  selectedBytes:status.total_wanted > 0 ? status.total_wanted : status.total
                                                   errorMessage:status.errc ? LTToNSString(status.errc.message()) : nil
                                               resumeDataStatus:resumeDataStatus];
	}

@end
