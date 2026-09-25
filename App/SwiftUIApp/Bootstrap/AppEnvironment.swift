// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// How this process was started. Unit tests are hosted in `Shatl.app`, so a
/// test run also runs `ShatlApp`; only `.live` may touch the user's session,
/// preferences, telemetry and Sparkle.
nonisolated enum ShatlLaunchMode: Equatable, Sendable {
    case live
    case xcodePreview
    case unitTestHost

    static let current = resolve(environment: ProcessInfo.processInfo.environment)

    static func resolve(environment: [String: String]) -> ShatlLaunchMode {
        #if DEBUG
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1" {
            return .xcodePreview
        }
        if environment["XCTestConfigurationFilePath"] != nil {
            return .unitTestHost
        }
        #endif
        return .live
    }
}

/// Assembles the application's live dependencies in one place.
struct AppEnvironment {
    var engine: any TorrentEngine
    var preferencesStore: AppPreferencesStore
    var sessionStore: SessionStore
    var torrentArchiveStore: TorrentArchiveStore
    var bookmarkStore: BookmarkStore
    var sessionRestoreCoordinator: SessionRestoreCoordinator
    var diskIssueDetector: DiskIssueDetector
    var torrentPayloadLocator: TorrentPayloadLocator
    var torrentPayloadDeletionService: TorrentPayloadDeletionService
    var externalOpenRouter: ExternalOpenRouter
    var userEventNotifier: (any TorrentUserEventNotifying)?
    var userEventBadgeDisplay: (any TorrentUserEventBadgeDisplaying)?
    var usageTelemetryCoordinator: UsageTelemetryLocalCoordinator
    var usageTelemetrySender: (any UsageTelemetrySending)?

    static func live() -> AppEnvironment {
        let directories = liveDirectories
        let archiveStore = TorrentArchiveStore(directories: directories)
        let bookmarkStore = BookmarkStore(directories: directories)
        let resumeDataStore = ResumeDataStore(directories: directories)
        let preferencesStore = livePreferencesStore
        let engine = LibtorrentEngine(directories: directories)
        let payloadLocator = TorrentPayloadLocator(
            engine: engine,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore
        )
        let usageTelemetryCoordinator = UsageTelemetryLocalCoordinator(
            store: UsageTelemetryStore(directories: directories)
        )
        let usageTelemetrySender = UsageTelemetryHTTPSender()
        let externalOpenRouter = ExternalOpenRouter.shared

        return AppEnvironment(
            engine: engine,
            preferencesStore: preferencesStore,
            sessionStore: SessionStore(
                directories: directories,
                archiveStore: archiveStore,
                bookmarkStore: bookmarkStore,
                resumeDataStore: resumeDataStore
            ),
            torrentArchiveStore: archiveStore,
            bookmarkStore: bookmarkStore,
            sessionRestoreCoordinator: SessionRestoreCoordinator(
                engine: engine,
                archiveStore: archiveStore,
                bookmarkStore: bookmarkStore
            ),
            diskIssueDetector: DiskIssueDetector(
                engine: engine,
                archiveStore: archiveStore,
                bookmarkStore: bookmarkStore
            ),
            torrentPayloadLocator: payloadLocator,
            torrentPayloadDeletionService: TorrentPayloadDeletionService(
                payloadLocator: payloadLocator
            ),
            externalOpenRouter: externalOpenRouter,
            userEventNotifier: MacTorrentUserEventNotifier(),
            userEventBadgeDisplay: MacTorrentUserEventBadgeDisplay(),
            usageTelemetryCoordinator: usageTelemetryCoordinator,
            usageTelemetrySender: usageTelemetrySender
        )
    }

    static var liveDirectories: ShatlDirectories {
        #if DEBUG
        if let rootPath = ProcessInfo.processInfo.environment["SHATL_TEST_STORAGE_ROOT"],
           !rootPath.isEmpty {
            let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            return ShatlDirectories(
                applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
                cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
            )
        }
        #endif
        return ShatlDirectories()
    }

    static var livePreferencesStore: AppPreferencesStore {
        #if DEBUG
        if let suiteName = ProcessInfo.processInfo.environment["SHATL_TEST_USER_DEFAULTS_SUITE"],
           !suiteName.isEmpty,
           let userDefaults = UserDefaults(suiteName: suiteName) {
            return AppPreferencesStore(userDefaults: userDefaults)
        }
        #endif
        return AppPreferencesStore()
    }
}

#if DEBUG
extension AppEnvironment {
    @MainActor
    static func previewStore(torrents: [TorrentRecord] = []) -> AppStore {
        let directories = ShatlDirectories.preview
        let archiveStore = TorrentArchiveStore(directories: directories)
        let bookmarkStore = BookmarkStore(directories: directories)
        let resumeDataStore = ResumeDataStore(directories: directories)
        let engine = PreviewTorrentEngine()
        let payloadLocator = TorrentPayloadLocator(
            engine: engine,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore
        )
        let usageTelemetryCoordinator = UsageTelemetryLocalCoordinator(
            store: UsageTelemetryStore(directories: directories)
        )

        return AppStore(
            engine: engine,
            sessionStore: SessionStore(
                directories: directories,
                archiveStore: archiveStore,
                bookmarkStore: bookmarkStore,
                resumeDataStore: resumeDataStore,
                startupMode: .alreadyInitialized,
                initialRecords: torrents
            ),
            torrentArchiveStore: archiveStore,
            bookmarkStore: bookmarkStore,
            sessionRestoreCoordinator: SessionRestoreCoordinator(
                engine: engine,
                archiveStore: archiveStore,
                bookmarkStore: bookmarkStore
            ),
            diskIssueDetector: DiskIssueDetector(
                engine: engine,
                archiveStore: archiveStore,
                bookmarkStore: bookmarkStore
            ),
            torrentPayloadLocator: payloadLocator,
            torrentPayloadDeletionService: TorrentPayloadDeletionService(
                payloadLocator: payloadLocator
            ),
            externalOpenRouter: ExternalOpenRouter(),
            userEventNotifier: nil,
            userEventBadgeDisplay: nil,
            usageTelemetryCoordinator: usageTelemetryCoordinator,
            usageTelemetrySender: nil,
            torrents: torrents,
            preferences: .defaultValue,
            hasLoadedInitialSession: true
        )
    }
}

private extension ShatlDirectories {
    static var preview: ShatlDirectories {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShatlPreview", isDirectory: true)

        return ShatlDirectories(
            applicationSupportURL: baseURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: baseURL.appendingPathComponent("Caches", isDirectory: true)
        )
    }
}

private actor PreviewTorrentEngine: TorrentEngine {
    func boot() async throws {}

    func applyPerformanceSettings(_ settings: EnginePerformanceSettings) async throws {}

    func prepareDraft(
        from source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool
    ) async throws -> AddTorrentDraft {
        AddTorrentDraft(
            source: source,
            originalName: "Preview Download",
            infoHash: "preview-info-hash",
            suggestedSavePath: suggestedSavePath,
            alias: "",
            stopAfterDownload: stopAfterDownload,
            files: [
                AddTorrentFileOption(
                    name: "Preview Download.mp4",
                    sizeBytes: 734_003_200,
                    fileIndex: 0,
                    isSelected: true
                )
            ],
            reviewState: .ready,
            errorState: nil
        )
    }

    func inspectTorrentContents(at torrentFilePath: String) async throws -> [TorrentContentFileDescriptor] {
        []
    }

    func exportPreparedTorrent(draftID: UUID, to destinationPath: String) async throws {}

    func releasePreparedDraft(id draftID: UUID) async {}

    func addTorrent(
        using draft: AddTorrentDraft,
        recordID: UUID,
        attemptID: UUID
    ) async throws -> TorrentRecord {
        let selectedFiles = draft.files.filter(\.isSelected)

        return TorrentRecord(
            id: recordID,
            attemptID: attemptID,
            infoHash: draft.infoHash,
            originalName: draft.originalName,
            alias: draft.alias.isEmpty ? nil : draft.alias,
            progress: 0,
            status: draft.stopAfterDownload ? .stopped : .downloading,
            metrics: TorrentMetrics(
                downloadSpeedBytesPerSecond: 0,
                uploadSpeedBytesPerSecond: 0,
                etaSeconds: nil,
                seeds: nil,
                peers: nil,
                uploadedBytes: 0,
                totalBytes: draft.totalBytes,
                selectedBytes: draft.selectedBytes
            ),
            canonicalSavePath: draft.suggestedSavePath,
            selectedFileIndices: draft.selectedFileIndices,
            selectedFileRelativePaths: selectedFiles.map(\.name),
            selectedFileCount: selectedFiles.count,
            totalFileCount: draft.files.count,
            materializedSelectionFootprint: nil,
            persistentIssue: nil,
            runtimeErrorState: nil,
            lastKnownProgress: 0,
            resumeCheckpointedAt: nil,
            resumeCheckpointProgress: nil,
            stopAfterDownload: draft.stopAfterDownload
        )
    }

    func restoreSession(_ entries: [SessionRestoreEntry]) async throws -> [EngineTorrentSnapshot] {
        []
    }

    func startTorrent(id: UUID) async throws {}

    func forceRecheck(id: UUID) async throws {}

    func checkpointTorrents(ids: [UUID]) async -> [EngineResumeCheckpointResult] {
        ids.map { EngineResumeCheckpointResult(id: $0, status: .notFound) }
    }

    func removeTorrent(id: UUID) async throws {}

    func fetchActiveSnapshots() async throws -> [EngineTorrentSnapshot] {
        []
    }

    func reconcileSleepingTorrents(_ records: [TorrentRecord]) async throws -> [EngineTorrentSnapshot] {
        []
    }
}
#endif
