// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
@testable import Shatl

struct RemovedTorrentCall: Sendable, Equatable {
    var id: UUID
    var deleteData: Bool
}

actor FakeTorrentEngine: TorrentEngine {
    private var bootCallCountValue = 0
    private var addCallCountValue = 0
    private var addError: TorrentEngineError?
    private var suspendsAdd = false
    private var addContinuation: CheckedContinuation<Void, Never>?
    private var prepareSources: [AddTorrentSource] = []
    private var removeCallsValue: [RemovedTorrentCall] = []
    private var removeError: TorrentEngineError?
    private var removeDelayNanoseconds: UInt64 = 0
    private var recheckCallIDsValue: [UUID] = []
    private var inspectContentsValue: [TorrentContentFileDescriptor] = [
        TorrentContentFileDescriptor(relativePath: "test-file.bin", sizeBytes: 1_024, fileIndex: 0),
    ]
    private var restoreSessionCallCountValue = 0
    private var restoreSessionEntriesValue: [SessionRestoreEntry] = []
    private var restoreSnapshotsByTorrentID: [UUID: EngineTorrentSnapshot] = [:]
    private var materializedSelectionsByTorrentID: [UUID: Set<Int>] = [:]
    private var restoreSessionErrors: [TorrentEngineError] = []
    private var activeTorrentIDs: Set<UUID> = []
    private var queuedActiveSnapshots: [[EngineTorrentSnapshot]] = []
    private var appliedPerformanceSettingsValue: [EnginePerformanceSettings] = []
    private var checkpointedTorrentIDsValue: [UUID] = []
    private var checkpointResultsByTorrentID: [UUID: EngineResumeCheckpointStatus] = [:]

    func boot() async throws {
        bootCallCountValue += 1
    }

    func applyPerformanceSettings(_ settings: EnginePerformanceSettings) async throws {
        appliedPerformanceSettingsValue.append(settings)
    }

    func prepareDraft(
        from source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool
    ) async throws -> AddTorrentDraft {
        prepareSources.append(source)

        return AddTorrentDraft(
            source: source,
            originalName: "Test Torrent",
            infoHash: "test-info-hash",
            suggestedSavePath: suggestedSavePath,
            alias: "",
            stopAfterDownload: stopAfterDownload,
            files: [
                AddTorrentFileOption(
                    name: "test-file.bin",
                    sizeBytes: 1_024,
                    fileIndex: 0,
                    isSelected: true
                ),
            ],
            reviewState: .ready,
            errorState: nil
        )
    }

    func inspectTorrentContents(at torrentFilePath: String) async throws -> [TorrentContentFileDescriptor] {
        _ = torrentFilePath
        return inspectContentsValue
    }

    func exportPreparedTorrent(from source: AddTorrentSource, to destinationPath: String) async throws {
        let data = Data("dummy torrent".utf8)
        try data.write(to: URL(fileURLWithPath: destinationPath), options: .atomic)
        _ = source
    }

    func addTorrent(
        using draft: AddTorrentDraft,
        recordID: UUID,
        attemptID: UUID
    ) async throws -> TorrentRecord {
        addCallCountValue += 1

        if suspendsAdd {
            await withCheckedContinuation { continuation in
                addContinuation = continuation
            }
        }

        if let addError {
            throw addError
        }

        activeTorrentIDs.insert(recordID)
        var record = makeTestRecord(
            id: recordID,
            attemptID: attemptID,
            infoHash: draft.infoHash,
            originalName: draft.originalName,
            savePath: draft.suggestedSavePath,
            selectedFileIndices: draft.selectedFileIndices,
            selectedFileCount: draft.selectedFileIndices.count,
            totalFileCount: draft.files.count,
            status: .downloading,
            progress: 0
        )
        record.alias = draft.alias.isEmpty ? nil : draft.alias
        return record
    }

    func restoreSession(_ entries: [SessionRestoreEntry]) async throws -> [EngineTorrentSnapshot] {
        restoreSessionCallCountValue += 1
        restoreSessionEntriesValue.append(contentsOf: entries)
        if !restoreSessionErrors.isEmpty {
            throw restoreSessionErrors.removeFirst()
        }

        for entry in entries {
            activeTorrentIDs.insert(entry.torrentID)
        }

        return entries.map {
            if let snapshot = restoreSnapshotsByTorrentID[$0.torrentID] {
                return snapshot
            }

            return EngineTorrentSnapshot(
                id: $0.torrentID,
                status: $0.shouldStart ? .downloading : .stopped,
                progress: 0,
                metrics: TorrentMetrics(),
                errorState: nil
            )
        }
    }

    func fetchMaterializedSelectedFileIndices(
        for id: UUID,
        selectedFileIndices: [Int]
    ) async throws -> Set<Int> {
        let materialized = materializedSelectionsByTorrentID[id] ?? []
        return materialized.intersection(Set(selectedFileIndices))
    }

    func startTorrent(id: UUID) async throws {
        guard activeTorrentIDs.contains(id) else {
            throw TorrentEngineError(kind: .torrentNotFound, debugReason: "Handle not present in fake engine")
        }
    }

    func stopTorrent(id: UUID) async throws {
        activeTorrentIDs.insert(id)
    }

    func forceRecheck(id: UUID) async throws {
        guard activeTorrentIDs.contains(id) else {
            throw TorrentEngineError(kind: .torrentNotFound, debugReason: "Handle not restored in fake engine")
        }
        recheckCallIDsValue.append(id)
    }

    func checkpointTorrents(ids: [UUID]) async -> [EngineResumeCheckpointResult] {
        checkpointedTorrentIDsValue.append(contentsOf: ids)
        return ids.map {
            EngineResumeCheckpointResult(
                id: $0,
                status: checkpointResultsByTorrentID[$0] ?? (activeTorrentIDs.contains($0) ? .saved : .notFound)
            )
        }
    }

    func removeTorrent(id: UUID, deleteData: Bool) async throws {
        removeCallsValue.append(RemovedTorrentCall(id: id, deleteData: deleteData))
        activeTorrentIDs.remove(id)

        if removeDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: removeDelayNanoseconds)
        }

        if let removeError {
            throw removeError
        }
    }

    func fetchActiveSnapshots() async throws -> [EngineTorrentSnapshot] {
        guard !queuedActiveSnapshots.isEmpty else {
            return []
        }

        let activeIDs = activeTorrentIDs
        var nextSnapshots: [EngineTorrentSnapshot] = []
        for snapshot in queuedActiveSnapshots[0] where activeIDs.contains(snapshot.id) {
            nextSnapshots.append(snapshot)
        }

        guard !nextSnapshots.isEmpty else {
            return []
        }

        queuedActiveSnapshots.removeFirst()
        return nextSnapshots
    }

    func reconcileSleepingTorrents(_ records: [TorrentRecord]) async throws -> [EngineTorrentSnapshot] {
        _ = records
        return []
    }

    func addCallCount() async -> Int {
        addCallCountValue
    }

    func bootCallCount() async -> Int {
        bootCallCountValue
    }

    func recordedPrepareSources() async -> [AddTorrentSource] {
        prepareSources
    }

    func recordedPerformanceSettings() async -> [EnginePerformanceSettings] {
        appliedPerformanceSettingsValue
    }

    func setAddError(_ error: TorrentEngineError?) async {
        addError = error
    }

    func setAddSuspended(_ isSuspended: Bool) async {
        suspendsAdd = isSuspended
        if !isSuspended {
            let continuation = addContinuation
            addContinuation = nil
            continuation?.resume()
        }
    }

    func recordedRecheckCallIDs() async -> [UUID] {
        recheckCallIDsValue
    }

    func recordedCheckpointedTorrentIDs() async -> [UUID] {
        checkpointedTorrentIDsValue
    }

    func setCheckpointStatus(_ status: EngineResumeCheckpointStatus, for torrentID: UUID) async {
        checkpointResultsByTorrentID[torrentID] = status
    }

    func recordedRemoveCalls() async -> [RemovedTorrentCall] {
        removeCallsValue
    }

    func setRemoveError(_ error: TorrentEngineError?) async {
        removeError = error
    }

    func setRemoveDelay(nanoseconds: UInt64) async {
        removeDelayNanoseconds = nanoseconds
    }

    func setInspectContents(_ contents: [TorrentContentFileDescriptor]) async {
        inspectContentsValue = contents
    }

    func restoreSessionCallCount() async -> Int {
        restoreSessionCallCountValue
    }

    func recordedRestoreSessionEntries() async -> [SessionRestoreEntry] {
        restoreSessionEntriesValue
    }

    func setRestoreSnapshot(_ snapshot: EngineTorrentSnapshot, for torrentID: UUID) async {
        restoreSnapshotsByTorrentID[torrentID] = snapshot
    }

    func setMaterializedFileIndices(_ indices: Set<Int>, for torrentID: UUID) async {
        materializedSelectionsByTorrentID[torrentID] = indices
    }

    func setRestoreSessionErrors(_ errors: [TorrentEngineError]) async {
        restoreSessionErrors = errors
    }

    func enqueueActiveSnapshots(_ snapshots: [EngineTorrentSnapshot]) async {
        queuedActiveSnapshots.append(snapshots)
    }

    func setHandleActive(_ isActive: Bool, for torrentID: UUID) async {
        if isActive {
            activeTorrentIDs.insert(torrentID)
        } else {
            activeTorrentIDs.remove(torrentID)
        }
    }
}

actor SuspendedSessionReader {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didStartValue = false
    private var isReleased = false

    func read(_ url: URL) async throws -> Data {
        didStartValue = true
        if !isReleased {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        return try Data(contentsOf: url)
    }

    func didStart() -> Bool {
        didStartValue
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class SpyTorrentUserEventNotifier: TorrentUserEventNotifying {
    private(set) var notifications: [TorrentUserNotification] = []
    private(set) var badgeCounts: [Int] = []

    func notify(_ notification: TorrentUserNotification, badgeCount: Int) {
        notifications.append(notification)
        badgeCounts.append(badgeCount)
    }
}

@MainActor
final class SpyTorrentUserEventBadgeDisplay: TorrentUserEventBadgeDisplaying {
    private(set) var badgeCounts: [Int] = []

    func setBadgeCount(_ count: Int) {
        badgeCounts.append(count)
    }
}

struct TestStoreBundle {
    var rootURL: URL
    var directories: ShatlDirectories
    var store: AppStore
    var sessionStore: SessionStore
    var archiveStore: TorrentArchiveStore
    var bookmarkStore: BookmarkStore
    var resumeDataStore: ResumeDataStore
    var payloadLocator: TorrentPayloadLocator
    var payloadDeletionService: TorrentPayloadDeletionService
    var router: ExternalOpenRouter
}

@MainActor
func makeTestStoreBundle(
    engine: FakeTorrentEngine,
    router: ExternalOpenRouter,
    torrents: [TorrentRecord] = [],
    preferences: AppPreferences? = nil,
    userEventNotifier: (any TorrentUserEventNotifying)? = nil,
    userEventBadgeDisplay: (any TorrentUserEventBadgeDisplaying)? = nil,
    usageTelemetryCoordinator: UsageTelemetryLocalCoordinator? = nil,
    usageTelemetrySender: (any UsageTelemetrySending)? = nil,
    sessionStoreStartupMode: SessionStoreStartupMode = .alreadyInitialized,
    sessionReadData: @escaping @Sendable (URL) async throws -> Data = { url in
        try Data(contentsOf: url)
    }
) -> TestStoreBundle {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ShatlTests-\(UUID().uuidString)", isDirectory: true)
    let directories = ShatlDirectories(
        applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
        cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
    )
    let archiveStore = TorrentArchiveStore(directories: directories)
    let bookmarkStore = BookmarkStore(directories: directories)
    let resumeDataStore = ResumeDataStore(directories: directories)
    let sessionStore = SessionStore(
        directories: directories,
        archiveStore: archiveStore,
        bookmarkStore: bookmarkStore,
        resumeDataStore: resumeDataStore,
        startupMode: sessionStoreStartupMode,
        initialRecords: torrents,
        readSessionData: sessionReadData
    )
    let coordinator = SessionRestoreCoordinator(
        engine: engine,
        archiveStore: archiveStore,
        bookmarkStore: bookmarkStore
    )
    let payloadLocator = TorrentPayloadLocator(
        engine: engine,
        archiveStore: archiveStore,
        bookmarkStore: bookmarkStore
    )
    let payloadDeletionService = TorrentPayloadDeletionService(
        payloadLocator: payloadLocator
    )
    let diskIssueDetector = DiskIssueDetector(
        engine: engine,
        archiveStore: archiveStore,
        bookmarkStore: bookmarkStore
    )
    let store = AppStore(
        engine: engine,
        sessionStore: sessionStore,
        torrentArchiveStore: archiveStore,
        bookmarkStore: bookmarkStore,
        sessionRestoreCoordinator: coordinator,
        diskIssueDetector: diskIssueDetector,
        torrentPayloadLocator: payloadLocator,
        torrentPayloadDeletionService: payloadDeletionService,
        externalOpenRouter: router,
        userEventNotifier: userEventNotifier,
        userEventBadgeDisplay: userEventBadgeDisplay,
        usageTelemetryCoordinator: usageTelemetryCoordinator,
        usageTelemetrySender: usageTelemetrySender,
        torrents: torrents,
        preferences: preferences,
        hasLoadedInitialSession: sessionStoreStartupMode == .alreadyInitialized
    )

    return TestStoreBundle(
        rootURL: rootURL,
        directories: directories,
        store: store,
        sessionStore: sessionStore,
        archiveStore: archiveStore,
        bookmarkStore: bookmarkStore,
        resumeDataStore: resumeDataStore,
        payloadLocator: payloadLocator,
        payloadDeletionService: payloadDeletionService,
        router: router
    )
}

@MainActor
func makeTestStoreBundle(
    engine: FakeTorrentEngine,
    torrents: [TorrentRecord] = [],
    preferences: AppPreferences? = nil,
    userEventNotifier: (any TorrentUserEventNotifying)? = nil,
    userEventBadgeDisplay: (any TorrentUserEventBadgeDisplaying)? = nil,
    usageTelemetryCoordinator: UsageTelemetryLocalCoordinator? = nil,
    usageTelemetrySender: (any UsageTelemetrySending)? = nil,
    sessionStoreStartupMode: SessionStoreStartupMode = .alreadyInitialized,
    sessionReadData: @escaping @Sendable (URL) async throws -> Data = { url in
        try Data(contentsOf: url)
    }
) -> TestStoreBundle {
    makeTestStoreBundle(
        engine: engine,
        router: ExternalOpenRouter(),
        torrents: torrents,
        preferences: preferences,
        userEventNotifier: userEventNotifier,
        userEventBadgeDisplay: userEventBadgeDisplay,
        usageTelemetryCoordinator: usageTelemetryCoordinator,
        usageTelemetrySender: usageTelemetrySender,
        sessionStoreStartupMode: sessionStoreStartupMode,
        sessionReadData: sessionReadData
    )
}

@MainActor
func waitForCondition(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    pollNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() {
            return true
        }

        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }

    return condition()
}

func waitForAsyncCondition(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    pollNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() {
            return true
        }

        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }

    return await condition()
}

nonisolated func makeTestRecord(
    id: UUID = UUID(),
    attemptID: UUID = UUID(),
    infoHash: String? = "test-info-hash",
    originalName: String = "Test Torrent",
    savePath: String = "/tmp/Test Torrent",
    selectedFileIndices: [Int] = [0],
    selectedFileRelativePaths: [String] = [],
    selectedFileCount: Int = 1,
    totalFileCount: Int = 1,
    status: TorrentStatus = .downloading,
    progress: Double = 0.4,
    stopAfterDownload: Bool = false,
    materializedSelectionFootprint: MaterializedSelectionFootprint? = nil,
    persistentIssue: TorrentPersistentIssue? = nil,
    runtimeErrorState: TorrentErrorState? = nil
) -> TorrentRecord {
    TorrentRecord(
        id: id,
        attemptID: attemptID,
        infoHash: infoHash,
        originalName: originalName,
        alias: nil,
        progress: progress,
        status: status,
        metrics: TorrentMetrics(
            downloadSpeedBytesPerSecond: 0,
            uploadSpeedBytesPerSecond: 0,
            etaSeconds: nil,
            seeds: nil,
            peers: nil,
            uploadedBytes: 0,
            totalBytes: 10_000,
            selectedBytes: 10_000
        ),
        canonicalSavePath: savePath,
        selectedFileIndices: selectedFileIndices,
        selectedFileRelativePaths: selectedFileRelativePaths,
        selectedFileCount: selectedFileCount,
        totalFileCount: totalFileCount,
        materializedSelectionFootprint: materializedSelectionFootprint,
        persistentIssue: persistentIssue,
        runtimeErrorState: runtimeErrorState,
        lastKnownProgress: progress,
        resumeCheckpointedAt: nil,
        resumeCheckpointProgress: nil,
        stopAfterDownload: stopAfterDownload
    )
}
