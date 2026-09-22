// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

#import "LibtorrentSessionBridge.h"

#include <atomic>
#include <chrono>
#include <fstream>
#include <map>
#include <memory>
#include <string>
#include <thread>
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

static NSString *LTSourceKey(NSString *sourceKind, NSString *rawValue) {
    return [NSString stringWithFormat:@"%@::%@", sourceKind, rawValue];
}

static void LTApplyNetworkDiscoverySettings(lt::settings_pack& pack, bool enableLSD) {
    pack.set_bool(lt::settings_pack::enable_dht, true);
    pack.set_bool(lt::settings_pack::enable_lsd, enableLSD);
    pack.set_bool(lt::settings_pack::enable_upnp, false);
    pack.set_bool(lt::settings_pack::enable_natpmp, false);
}

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

static BOOL LTDiagnosticsLoggingEnabled(void) {
    Class bridgeClass = NSClassFromString(@"ShatlDiagnosticsBridge");
    SEL selector = NSSelectorFromString(@"loggingEnabled");
    if (bridgeClass == Nil || ![bridgeClass respondsToSelector:selector]) {
        return NO;
    }

    BOOL (*messageSend)(id, SEL) = reinterpret_cast<BOOL (*)(id, SEL)>([bridgeClass methodForSelector:selector]);
    return messageSend(bridgeClass, selector);
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
    Class bridgeClass = NSClassFromString(@"ShatlSnapshotDiagnosticsBridge");
    SEL selector = NSSelectorFromString(@"loggingEnabled");
    if (bridgeClass == Nil || ![bridgeClass respondsToSelector:selector]) {
        return NO;
    }

    BOOL (*messageSend)(id, SEL) = reinterpret_cast<BOOL (*)(id, SEL)>([bridgeClass methodForSelector:selector]);
    return messageSend(bridgeClass, selector);
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
    LTSnapshotDiagnosticsLog(@"snapshot.status.begin", fields, YES);

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
        LTSnapshotDiagnosticsLog(event, watchdogFields, YES);
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
    LTSnapshotDiagnosticsLog(@"snapshot.status.end", endFields, NO);

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

@interface LibtorrentSessionBridge () {
    NSURL *_resumeDataDirectoryURL;
    std::unique_ptr<lt::session> _session;
    std::map<std::string, lt::torrent_handle> _handlesByRecordID;
    // libtorrent provides magnet metadata through a weak/shared pointer to const
    // torrent_info. Cache it as-is to avoid copying the heavy structure.
    std::unordered_map<std::string, std::shared_ptr<const lt::torrent_info>> _cachedTorrentInfoBySource;
    std::unordered_map<std::string, bool> _stopAfterDownloadByRecordID;
    std::unordered_map<std::string, NSInteger> _lastSnapshotStatusByRecordID;
    LTPerformanceProfile _performanceProfile;
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
        LTDiagnosticsBridgeLog(
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
        LTDiagnosticsBridgeLog(
            @"resume.requested",
            recordIdentifier,
            @{ @"resumeMode": @"only_if_modified" },
            YES
        );
    } catch (...) {
        LTDiagnosticsBridgeLog(
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
                    LTDiagnosticsBridgeLog(
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
                LTDiagnosticsBridgeLog(
                    @"resume.alert.received",
                    recordIdentifier,
                    @{ @"resumeWaitMs": LTMillisecondsString(startedAt) },
                    YES
                );
                return;
            }

            if (auto *failedAlert = lt::alert_cast<lt::save_resume_data_failed_alert>(alert)) {
                if (failedAlert->handle == handle) {
                    LTDiagnosticsBridgeLog(
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

    LTDiagnosticsBridgeLog(
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

    lt::settings_pack pack = LTMakePerformanceSettingsPack(_performanceProfile);

    try {
        _session = std::make_unique<lt::session>(pack);
    } catch (std::exception const& exception) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeEngineFailure, LTToNSString(exception.what()));
        }
        return NO;
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
        _session->apply_settings(LTMakePerformanceSettingsPack(profile));
    } catch (std::exception const& exception) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeEngineFailure, LTToNSString(exception.what()));
        }
        return NO;
    }

    return YES;
}

- (LTPreparedDraft *)prepareDraftWithSourceKind:(NSString *)sourceKind
                                       rawValue:(NSString *)rawValue
                              suggestedSavePath:(NSString *)suggestedSavePath
                                         error:(NSError * _Nullable __autoreleasing *)error {
    if (![self boot:error]) {
        return nil;
    }

    NSString *normalizedSavePath = [suggestedSavePath stringByStandardizingPath];
    NSString *sourceKey = LTSourceKey(sourceKind, rawValue);

    if ([sourceKind isEqualToString:@"magnet"]) {
        return [self prepareMagnetDraftWithRawValue:rawValue
                                          sourceKey:sourceKey
                                  suggestedSavePath:normalizedSavePath
                                              error:error];
    }

    if ([sourceKind isEqualToString:@"torrentFile"] || [sourceKind isEqualToString:@"externalOpen"]) {
        return [self prepareTorrentFileDraftWithPath:rawValue
                                           sourceKey:sourceKey
                                   suggestedSavePath:normalizedSavePath
                                               error:error];
    }

    if (error != nullptr) {
        *error = LTMakeError(ShatlLibtorrentErrorCodeEngineFailure, @"Неизвестный тип источника торрента.");
    }
    return nil;
}

- (LTPreparedDraft *)prepareMagnetDraftWithRawValue:(NSString *)rawValue
                                          sourceKey:(NSString *)sourceKey
                                  suggestedSavePath:(NSString *)suggestedSavePath
                                              error:(NSError * _Nullable __autoreleasing *)error {
    lt::error_code ec;
    lt::add_torrent_params params = lt::parse_magnet_uri(LTToStdString(rawValue), ec);
    if (ec) {
        if (error != nullptr) {
            *error = LTMakeErrorFromCode(ShatlLibtorrentErrorCodeInvalidMagnet, ec, @"Magnet-ссылка не прошла валидацию.");
        }
        return nil;
    }

    if (self->_session->find_torrent(params.info_hashes.get_best()).is_valid()) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeDuplicateTorrent, @"Такая загрузка уже есть.");
        }
        return nil;
    }

    params.save_path = LTToStdString(suggestedSavePath);
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

    LTPreparedDraft *preparedDraft = nil;

    for (NSInteger attempt = 0; attempt < 160; ++attempt) {
        lt::torrent_status status = handle.status(LTMinimalStatusQueryFlags());

        if (status.errc) {
            self->_session->remove_torrent(handle);
            if (error != nullptr) {
                *error = LTMakeErrorFromCode(ShatlLibtorrentErrorCodeEngineFailure, status.errc, @"Получение метаданных завершилось с ошибкой.");
            }
            return nil;
        }

        auto torrentInfo = status.torrent_file.lock();
        if (status.has_metadata && torrentInfo) {
            self->_cachedTorrentInfoBySource[LTToStdString(sourceKey)] = torrentInfo;

            preparedDraft = [self makePreparedDraftFromTorrentInfo:torrentInfo
                                                  suggestedSavePath:suggestedSavePath];

            self->_session->remove_torrent(handle);
            auto infoHash = torrentInfo->info_hashes().get_best();
            for (NSInteger waitIteration = 0; waitIteration < 80; ++waitIteration) {
                if (!self->_session->find_torrent(infoHash).is_valid()) {
                    break;
                }
                std::this_thread::sleep_for(std::chrono::milliseconds(25));
            }

            return preparedDraft;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(250));
    }

    self->_session->remove_torrent(handle);
    if (error != nullptr) {
        *error = LTMakeError(ShatlLibtorrentErrorCodeMetadataTimeout, @"Не удалось получить метаданные magnet-ссылки вовремя.");
    }
    return nil;
}

- (LTPreparedDraft *)prepareTorrentFileDraftWithPath:(NSString *)path
                                           sourceKey:(NSString *)sourceKey
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

    if (self->_session->find_torrent(torrentInfo->info_hashes().get_best()).is_valid()) {
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeDuplicateTorrent, @"Такая загрузка уже есть.");
        }
        return nil;
    }

    self->_cachedTorrentInfoBySource[LTToStdString(sourceKey)] = torrentInfo;
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
                                    rawValue:(NSString *)rawValue
                           suggestedSavePath:(NSString *)suggestedSavePath
                            stopAfterDownload:(BOOL)stopAfterDownload
                           selectedFileIndices:(NSArray<NSNumber *> *)selectedFileIndices
                              recordIdentifier:(NSString *)recordIdentifier
                             attemptIdentifier:(NSString *)attemptIdentifier
                                         error:(NSError * _Nullable __autoreleasing *)error {
    auto addStartedAt = std::chrono::steady_clock::now();
    if (![self boot:error]) {
        LTDiagnosticsBridgeLog(@"add.boot.failed", recordIdentifier, nil, YES);
        return nil;
    }

    NSString *normalizedSavePath = [suggestedSavePath stringByStandardizingPath];
    LTDiagnosticsBridgeLog(
        @"add.begin",
        recordIdentifier,
        @{
            @"sourceKind": sourceKind ?: @"unknown",
            @"savePath": normalizedSavePath ?: @"",
            @"selectedCount": [NSString stringWithFormat:@"%lu", static_cast<unsigned long>(selectedFileIndices.count)]
        },
        YES
    );

    NSString *sourceKey = LTSourceKey(sourceKind, rawValue);
    auto cachedInfoIterator = self->_cachedTorrentInfoBySource.find(LTToStdString(sourceKey));
    if (cachedInfoIterator == self->_cachedTorrentInfoBySource.end()) {
        LTDiagnosticsBridgeLog(@"add.draft-missing", recordIdentifier, nil, YES);
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
    if (self->_session->find_torrent(bestHash).is_valid()) {
        LTDiagnosticsBridgeLog(@"add.duplicate", recordIdentifier, nil, YES);
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
        LTDiagnosticsBridgeLog(@"add.invalid-selection", recordIdentifier, nil, YES);
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
        LTDiagnosticsBridgeLog(
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
    LTDiagnosticsBridgeLog(
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

- (BOOL)exportPreparedTorrentWithSourceKind:(NSString *)sourceKind
                                   rawValue:(NSString *)rawValue
                            destinationPath:(NSString *)destinationPath
                                      error:(NSError * _Nullable __autoreleasing *)error {
    NSString *sourceKey = LTSourceKey(sourceKind, rawValue);
    auto cachedInfoIterator = self->_cachedTorrentInfoBySource.find(LTToStdString(sourceKey));
    if (cachedInfoIterator == self->_cachedTorrentInfoBySource.end()) {
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

- (LTTorrentSnapshot *)restoreTorrentWithTorrentFilePath:(NSString *)torrentFilePath
                                       suggestedSavePath:(NSString *)suggestedSavePath
                                        stopAfterDownload:(BOOL)stopAfterDownload
                                       selectedFileIndices:(NSArray<NSNumber *> *)selectedFileIndices
                                          recordIdentifier:(NSString *)recordIdentifier
                                               shouldStart:(BOOL)shouldStart
                                                     error:(NSError * _Nullable __autoreleasing *)error {
    auto restoreStartedAt = std::chrono::steady_clock::now();
    LTDiagnosticsBridgeLog(
        @"restore.begin",
        recordIdentifier,
        @{
            @"shouldStart": shouldStart ? @"1" : @"0",
            @"selectedCount": [NSString stringWithFormat:@"%lu", static_cast<unsigned long>(selectedFileIndices.count)]
        },
        YES
    );

    if (![self boot:error]) {
        LTDiagnosticsBridgeLog(@"restore.boot.failed", recordIdentifier, nil, YES);
        return nil;
    }

    lt::error_code ec;
    auto torrentInfo = std::make_shared<lt::torrent_info>(LTToStdString(torrentFilePath), ec);
    if (ec) {
        LTDiagnosticsBridgeLog(
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
                LTDiagnosticsBridgeLog(@"restore.resume.loaded", recordIdentifier, nil, YES);
            } else {
                resumeDataStatus = @"invalid";
                LTDiagnosticsBridgeLog(
                    @"restore.resume.invalid",
                    recordIdentifier,
                    @{ @"reason": LTToNSString(resumeError.message()) },
                    YES
                );
            }
        } else {
            LTDiagnosticsBridgeLog(@"restore.resume.missing", recordIdentifier, nil, YES);
        }
    }

    if (shouldStart) {
        params.flags &= ~lt::torrent_flags::paused;
    } else {
        params.flags |= lt::torrent_flags::paused;
    }

    lt::file_storage const& fileStorage = torrentInfo->files();

    if (selectedFileIndices.count == 0) {
        LTDiagnosticsBridgeLog(@"restore.invalid-selection", recordIdentifier, nil, YES);
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

    lt::torrent_handle handle = self->_session->add_torrent(params, ec);
    if (ec || !handle.is_valid()) {
        LTDiagnosticsBridgeLog(
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
    LTDiagnosticsBridgeLog(
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
    LTDiagnosticsBridgeLog(@"start.begin", recordIdentifier, nil, YES);
    auto iterator = self->_handlesByRecordID.find(LTToStdString(recordIdentifier));
    if (iterator == self->_handlesByRecordID.end() || !iterator->second.is_valid()) {
        LTDiagnosticsBridgeLog(@"start.not-found", recordIdentifier, nil, YES);
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeTorrentNotFound, @"Торрент не найден в активной сессии.");
        }
        return NO;
    }

    iterator->second.unset_flags(lt::torrent_flags::paused);
    iterator->second.resume();
    LTDiagnosticsBridgeLog(
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
    LTDiagnosticsBridgeLog(@"stop.begin", recordIdentifier, nil, YES);
    auto iterator = self->_handlesByRecordID.find(LTToStdString(recordIdentifier));
    if (iterator == self->_handlesByRecordID.end() || !iterator->second.is_valid()) {
        LTDiagnosticsBridgeLog(@"stop.not-found", recordIdentifier, nil, YES);
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeTorrentNotFound, @"Торрент не найден в активной сессии.");
        }
        return NO;
    }

    iterator->second.pause();
    iterator->second.set_flags(lt::torrent_flags::paused);
    LTDiagnosticsBridgeLog(
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
    LTDiagnosticsBridgeLog(@"recheck.begin", recordIdentifier, nil, YES);
    auto iterator = self->_handlesByRecordID.find(LTToStdString(recordIdentifier));
    if (iterator == self->_handlesByRecordID.end() || !iterator->second.is_valid()) {
        LTDiagnosticsBridgeLog(@"recheck.not-found", recordIdentifier, nil, YES);
        if (error != nullptr) {
            *error = LTMakeError(ShatlLibtorrentErrorCodeTorrentNotFound, @"Торрент не найден в активной сессии.");
        }
        return NO;
    }

    iterator->second.force_recheck();
    LTDiagnosticsBridgeLog(
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
    LTDiagnosticsBridgeLog(
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
            LTDiagnosticsBridgeLog(@"resume.skip", recordIdentifier, @{ @"reason": @"not-found" }, YES);
            [results addObject:[self checkpointResultForRecordIdentifier:recordIdentifier
                                                                  status:@"not-found"
                                                            errorMessage:nil]];
            continue;
        }

        try {
            iterator->second.save_resume_data();
            pending[key] = iterator->second;
            LTDiagnosticsBridgeLog(
                @"resume.requested",
                recordIdentifier,
                @{ @"resumeMode": @"checkpoint" },
                YES
            );
        } catch (std::exception const& exception) {
            LTDiagnosticsBridgeLog(
                @"resume.request.failed",
                recordIdentifier,
                @{ @"reason": LTToNSString(exception.what()) },
                YES
            );
            [results addObject:[self checkpointResultForRecordIdentifier:recordIdentifier
                                                                  status:@"failed"
                                                            errorMessage:LTToNSString(exception.what())]];
        } catch (...) {
            LTDiagnosticsBridgeLog(
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
                        LTDiagnosticsBridgeLog(
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
                    LTDiagnosticsBridgeLog(
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
                    LTDiagnosticsBridgeLog(
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
        LTDiagnosticsBridgeLog(
            @"resume.timeout",
            recordIdentifier,
            @{ @"resumeWaitMs": LTMillisecondsString(startedAt) },
            YES
        );
    }

    LTDiagnosticsBridgeLog(
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
    LTDiagnosticsBridgeLog(
        @"remove.begin",
        recordIdentifier,
        @{ @"deleteData": deleteData ? @"1" : @"0" },
        YES
    );
    auto key = LTToStdString(recordIdentifier);
    auto iterator = self->_handlesByRecordID.find(key);
    if (iterator == self->_handlesByRecordID.end() || !iterator->second.is_valid()) {
        LTDiagnosticsBridgeLog(@"remove.not-found", recordIdentifier, nil, YES);
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

    LTDiagnosticsBridgeLog(
        @"remove.session-call",
        recordIdentifier,
        @{ @"deleteData": deleteData ? @"1" : @"0" },
        YES
    );
    self->_session->remove_torrent(iterator->second, flags);
    self->_handlesByRecordID.erase(iterator);
    self->_stopAfterDownloadByRecordID.erase(key);
    self->_lastSnapshotStatusByRecordID.erase(key);
    LTDiagnosticsBridgeLog(
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
    LTSnapshotDiagnosticsLog(
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

    LTSnapshotDiagnosticsLog(
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
        LTDiagnosticsBridgeLog(
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
