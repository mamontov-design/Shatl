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

/// The single entry point into the Objective-C++ layer.
/// All implementation details of `libtorrent` remain inside it.
@interface LibtorrentSessionBridge : NSObject

- (BOOL)boot:(NSError * _Nullable * _Nullable)error;

- (BOOL)applyPerformanceProfile:(LTPerformanceProfile)profile
                           error:(NSError * _Nullable * _Nullable)error;

- (nullable LTPreparedDraft *)prepareDraftWithSourceKind:(NSString *)sourceKind
                                                rawValue:(NSString *)rawValue
                                       suggestedSavePath:(NSString *)suggestedSavePath
                                                  error:(NSError * _Nullable * _Nullable)error;

- (nullable NSArray<LTPreparedFile *> *)inspectTorrentContentsAtPath:(NSString *)torrentFilePath
                                                               error:(NSError * _Nullable * _Nullable)error;

- (nullable LTAddedTorrent *)addTorrentWithSourceKind:(NSString *)sourceKind
                                             rawValue:(NSString *)rawValue
                                    suggestedSavePath:(NSString *)suggestedSavePath
                                     stopAfterDownload:(BOOL)stopAfterDownload
                                    selectedFileIndices:(NSArray<NSNumber *> *)selectedFileIndices
                                       recordIdentifier:(NSString *)recordIdentifier
                                      attemptIdentifier:(NSString *)attemptIdentifier
                                                  error:(NSError * _Nullable * _Nullable)error;

- (BOOL)exportPreparedTorrentWithSourceKind:(NSString *)sourceKind
                                   rawValue:(NSString *)rawValue
                            destinationPath:(NSString *)destinationPath
                                      error:(NSError * _Nullable * _Nullable)error;

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
