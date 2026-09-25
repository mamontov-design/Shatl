// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LTTorrentDraftState) {
    LTTorrentDraftStateLoadingMetadata = 0,
    LTTorrentDraftStateReady = 1,
    LTTorrentDraftStateInvalid = 2,
};

typedef NS_ENUM(NSInteger, LTTorrentRuntimeStatus) {
    LTTorrentRuntimeStatusDownloading = 0,
    LTTorrentRuntimeStatusStopped = 1,
    LTTorrentRuntimeStatusSeeding = 2,
    LTTorrentRuntimeStatusCompleted = 3,
    LTTorrentRuntimeStatusError = 4,
    LTTorrentRuntimeStatusChecking = 5,
};

typedef NS_ENUM(NSInteger, LTPerformanceProfile) {
    LTPerformanceProfileEconomical = 0,
    LTPerformanceProfileBalanced = 1,
    LTPerformanceProfileMaximum = 2,
};

/// A file entry used by the add flow.
/// Kept separate so Swift does not depend on libtorrent C++ types.
@interface LTPreparedFile : NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) long long sizeBytes;
@property (nonatomic, readonly) NSInteger fileIndex;

- (instancetype)initWithName:(NSString *)name
                   sizeBytes:(long long)sizeBytes
                   fileIndex:(NSInteger)fileIndex NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

/// The result of preparing the add-flow review window.
@interface LTPreparedDraft : NSObject

@property (nonatomic, readonly) NSString *originalName;
@property (nonatomic, readonly, nullable) NSString *infoHash;
@property (nonatomic, readonly) NSString *suggestedSavePath;
@property (nonatomic, readonly) NSArray<LTPreparedFile *> *files;
@property (nonatomic, readonly) LTTorrentDraftState reviewState;
@property (nonatomic, readonly, nullable) NSString *invalidMessage;

- (instancetype)initWithOriginalName:(NSString *)originalName
                            infoHash:(nullable NSString *)infoHash
                   suggestedSavePath:(NSString *)suggestedSavePath
                               files:(NSArray<LTPreparedFile *> *)files
                         reviewState:(LTTorrentDraftState)reviewState
                      invalidMessage:(nullable NSString *)invalidMessage NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

/// The result of adding a torrent to the live session.
@interface LTAddedTorrent : NSObject

@property (nonatomic, readonly) NSString *recordIdentifier;
@property (nonatomic, readonly) NSString *attemptIdentifier;
@property (nonatomic, readonly, nullable) NSString *infoHash;
@property (nonatomic, readonly) NSString *originalName;
@property (nonatomic, readonly) long long totalBytes;
@property (nonatomic, readonly) long long selectedBytes;
@property (nonatomic, readonly) NSInteger selectedFileCount;
@property (nonatomic, readonly) NSInteger totalFileCount;

- (instancetype)initWithRecordIdentifier:(NSString *)recordIdentifier
                       attemptIdentifier:(NSString *)attemptIdentifier
                                infoHash:(nullable NSString *)infoHash
                            originalName:(NSString *)originalName
                              totalBytes:(long long)totalBytes
                           selectedBytes:(long long)selectedBytes
                       selectedFileCount:(NSInteger)selectedFileCount
                          totalFileCount:(NSInteger)totalFileCount NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

/// A snapshot of torrent runtime state.
@interface LTTorrentSnapshot : NSObject

@property (nonatomic, readonly) NSString *recordIdentifier;
@property (nonatomic, readonly) LTTorrentRuntimeStatus status;
@property (nonatomic, readonly) double progress;
@property (nonatomic, readonly) long long downloadSpeedBytesPerSecond;
@property (nonatomic, readonly) long long uploadSpeedBytesPerSecond;
@property (nonatomic, readonly, nullable) NSNumber *etaSeconds;
@property (nonatomic, readonly, nullable) NSNumber *seeds;
@property (nonatomic, readonly, nullable) NSNumber *peers;
@property (nonatomic, readonly) long long uploadedBytes;
@property (nonatomic, readonly) long long totalBytes;
@property (nonatomic, readonly) long long selectedBytes;
@property (nonatomic, readonly, nullable) NSString *errorMessage;
@property (nonatomic, readonly, nullable) NSString *resumeDataStatus;

- (instancetype)initWithRecordIdentifier:(NSString *)recordIdentifier
                                  status:(LTTorrentRuntimeStatus)status
                                progress:(double)progress
              downloadSpeedBytesPerSecond:(long long)downloadSpeedBytesPerSecond
                uploadSpeedBytesPerSecond:(long long)uploadSpeedBytesPerSecond
                               etaSeconds:(nullable NSNumber *)etaSeconds
                                    seeds:(nullable NSNumber *)seeds
                                    peers:(nullable NSNumber *)peers
                            uploadedBytes:(long long)uploadedBytes
                               totalBytes:(long long)totalBytes
                            selectedBytes:(long long)selectedBytes
                             errorMessage:(nullable NSString *)errorMessage
                         resumeDataStatus:(nullable NSString *)resumeDataStatus NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface LTResumeCheckpoint : NSObject

@property (nonatomic, readonly) NSString *recordIdentifier;
@property (nonatomic, readonly) NSString *status;
@property (nonatomic, readonly, nullable) NSString *errorMessage;

- (instancetype)initWithRecordIdentifier:(NSString *)recordIdentifier
                                  status:(NSString *)status
                            errorMessage:(nullable NSString *)errorMessage NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

/// How many descriptors the session may use. macOS starts apps with a soft
/// limit of 256 open files, while every TCP peer and every open payload file
/// takes one of them.
@interface LTResourceBudget : NSObject

/// The soft open-file limit before the bridge raised it.
@property (nonatomic, readonly) NSInteger initialOpenFileLimit;
/// The soft open-file limit the session runs within.
@property (nonatomic, readonly) NSInteger openFileLimit;
/// What the performance profile asks for.
@property (nonatomic, readonly) NSInteger requestedConnectionsLimit;
@property (nonatomic, readonly) NSInteger requestedFilePoolSize;
/// What the session gets.
@property (nonatomic, readonly) NSInteger connectionsLimit;
@property (nonatomic, readonly) NSInteger filePoolSize;

- (instancetype)initWithInitialOpenFileLimit:(NSInteger)initialOpenFileLimit
                               openFileLimit:(NSInteger)openFileLimit
                   requestedConnectionsLimit:(NSInteger)requestedConnectionsLimit
                       requestedFilePoolSize:(NSInteger)requestedFilePoolSize
                            connectionsLimit:(NSInteger)connectionsLimit
                                filePoolSize:(NSInteger)filePoolSize NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

/// The single entry point into the Objective-C++ layer.
/// All implementation details of `libtorrent` remain inside it.
@interface LibtorrentSessionBridge : NSObject

/// The resume directory comes from `ShatlDirectories` so the bridge never
/// derives durable storage paths on its own.
- (instancetype)initWithResumeDataDirectoryURL:(NSURL *)resumeDataDirectoryURL NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/// Replaces a fast-resume file only after the new bytes are fully written,
/// so a failed write keeps the previous checkpoint intact.
+ (BOOL)writeResumeData:(NSData *)data
              toFileURL:(NSURL *)fileURL
                  error:(NSError * _Nullable * _Nullable)error;

- (BOOL)boot:(NSError * _Nullable * _Nullable)error;

- (BOOL)applyPerformanceProfile:(LTPerformanceProfile)profile
                           error:(NSError * _Nullable * _Nullable)error;

/// What a profile gets under a limit. Boot raises the soft limit towards
/// 10 240, and boot and every profile switch fit connections and the file
/// pool into it.
+ (LTResourceBudget *)resourceBudgetForProfile:(LTPerformanceProfile)profile
                                 openFileLimit:(NSInteger)openFileLimit;

/// The budget of the running session, read back from libtorrent. Nil before boot.
- (nullable LTResourceBudget *)currentResourceBudget;

/// Descriptors the process has open right now.
+ (NSInteger)openFileDescriptorCount;

/// Prepares `.torrent` sources. Magnet links use the metadata fetch below,
/// because their metadata arrives from the network over seconds.
/// The metadata is kept under `draftIdentifier` until the draft is released.
- (nullable LTPreparedDraft *)prepareDraftWithSourceKind:(NSString *)sourceKind
                                                rawValue:(NSString *)rawValue
                                         draftIdentifier:(NSString *)draftIdentifier
                                       suggestedSavePath:(NSString *)suggestedSavePath
                                                  error:(NSError * _Nullable * _Nullable)error;

/// Adds a temporary torrent that only receives metadata and returns a token
/// for it. Every call of the fetch is short, so the caller can suspend between
/// polls and other commands are served while the metadata is on its way.
- (nullable NSString *)beginMagnetMetadataFetchWithRawValue:(NSString *)rawValue
                                            draftIdentifier:(NSString *)draftIdentifier
                                          suggestedSavePath:(NSString *)suggestedSavePath
                                                      error:(NSError * _Nullable * _Nullable)error;

/// Returns a `LoadingMetadata` draft while the metadata is missing and a ready
/// draft once it arrived. A ready or failed fetch is finished: its temporary
/// torrent is already removed from the session, and a ready draft keeps the
/// metadata under its draft identifier.
- (nullable LTPreparedDraft *)pollMagnetMetadataFetchWithToken:(NSString *)token
                                                         error:(NSError * _Nullable * _Nullable)error;

/// Removes the temporary torrent of an unfinished fetch. Unknown tokens are ignored.
- (void)cancelMagnetMetadataFetchWithToken:(NSString *)token;

/// Torrents in the session that belong to no record, i.e. magnet metadata
/// fetches. Tests use it to prove that a fetch leaves nothing behind.
- (NSInteger)temporaryTorrentCount;

- (nullable NSArray<LTPreparedFile *> *)inspectTorrentContentsAtPath:(NSString *)torrentFilePath
                                                               error:(NSError * _Nullable * _Nullable)error;

- (nullable LTAddedTorrent *)addTorrentWithSourceKind:(NSString *)sourceKind
                                      draftIdentifier:(NSString *)draftIdentifier
                                    suggestedSavePath:(NSString *)suggestedSavePath
                                     stopAfterDownload:(BOOL)stopAfterDownload
                                    selectedFileIndices:(NSArray<NSNumber *> *)selectedFileIndices
                                       recordIdentifier:(NSString *)recordIdentifier
                                      attemptIdentifier:(NSString *)attemptIdentifier
                                                  error:(NSError * _Nullable * _Nullable)error;

- (BOOL)exportPreparedTorrentWithDraftIdentifier:(NSString *)draftIdentifier
                                 destinationPath:(NSString *)destinationPath
                                           error:(NSError * _Nullable * _Nullable)error;

/// Drops the metadata of a draft that was closed or finished adding.
/// Unknown identifiers are ignored.
- (void)releasePreparedDraftWithIdentifier:(NSString *)draftIdentifier;

/// Drafts whose metadata is still held. Tests use it to prove release.
- (NSInteger)preparedDraftCount;

- (nullable LTTorrentSnapshot *)restoreTorrentWithTorrentFilePath:(NSString *)torrentFilePath
                                                suggestedSavePath:(NSString *)suggestedSavePath
                                                 stopAfterDownload:(BOOL)stopAfterDownload
                                                selectedFileIndices:(NSArray<NSNumber *> *)selectedFileIndices
                                                   recordIdentifier:(NSString *)recordIdentifier
                                                        shouldStart:(BOOL)shouldStart
                                                              error:(NSError * _Nullable * _Nullable)error;

- (nullable NSArray<NSNumber *> *)materializedFileIndicesForTorrentWithIdentifier:(NSString *)recordIdentifier
                                                               selectedFileIndices:(NSArray<NSNumber *> *)selectedFileIndices
                                                                             error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(materializedFileIndices(recordIdentifier:selectedFileIndices:));

- (BOOL)startTorrentWithIdentifier:(NSString *)recordIdentifier
                             error:(NSError * _Nullable * _Nullable)error;

- (BOOL)stopTorrentWithIdentifier:(NSString *)recordIdentifier
                            error:(NSError * _Nullable * _Nullable)error;

- (BOOL)forceRecheckTorrentWithIdentifier:(NSString *)recordIdentifier
                                    error:(NSError * _Nullable * _Nullable)error;

- (nullable NSArray<LTResumeCheckpoint *> *)checkpointTorrentsWithIdentifiers:(NSArray<NSString *> *)recordIdentifiers
                                                                        error:(NSError * _Nullable * _Nullable)error;

- (BOOL)removeTorrentWithIdentifier:(NSString *)recordIdentifier
                         deleteData:(BOOL)deleteData
                              error:(NSError * _Nullable * _Nullable)error;

- (nullable NSArray<LTTorrentSnapshot *> *)fetchActiveSnapshots:(NSError * _Nullable * _Nullable)error;

- (nullable NSArray<LTTorrentSnapshot *> *)reconcileTorrentIdentifiers:(NSArray<NSString *> *)recordIdentifiers
                                                                 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
