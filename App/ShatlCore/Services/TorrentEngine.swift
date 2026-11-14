// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated struct EngineTorrentSnapshot: Identifiable, Equatable, Sendable {
    var id: UUID
    var status: TorrentStatus
    var progress: Double
    var metrics: TorrentMetrics
    var errorState: TorrentErrorState?
    var resumeDataStatus: EngineResumeDataStatus? = nil
}

nonisolated enum EngineResumeDataStatus: String, Equatable, Sendable {
    case missing
    case loaded
    case invalid
}

nonisolated enum EngineResumeCheckpointStatus: Equatable, Sendable {
    case saved
    case notFound
    case failed(String?)
    case timedOut
}

nonisolated struct EngineResumeCheckpointResult: Equatable, Sendable {
    var id: UUID
    var status: EngineResumeCheckpointStatus
}

/// How many open files the engine may use. An app gets a soft limit of 256
/// (2560 once AppKit starts from Finder or the Dock), while every TCP peer and
/// every open payload file takes one.
nonisolated struct EngineResourceBudget: Equatable, Sendable {
    /// The soft limit the process started with.
    var initialOpenFileLimit: Int
    /// The soft limit the engine runs within.
    var openFileLimit: Int
    var connectionsLimit: Int
    var requestedConnectionsLimit: Int
    var filePoolSize: Int
    var requestedFilePoolSize: Int
    /// Descriptors the process has open right now.
    var openFileCount: Int

    /// The profile got less than it asks for because the limit is too small.
    var isReduced: Bool {
        connectionsLimit < requestedConnectionsLimit || filePoolSize < requestedFilePoolSize
    }
}

/// Whether the router opened a port for incoming connections.
nonisolated enum EnginePortMappingStatus: Equatable, Sendable {
    case off
    /// The router has not opened the port yet. `waiting` counts from the
    /// moment the running engine asked it and is `nil` before boot;
    /// `lastError` is the router's last refusal, if any.
    case searching(waiting: Duration?, lastError: EnginePortMappingError?)
    case mapped(externalPort: Int, transport: String)
}

nonisolated struct EnginePortMappingError: Equatable, Sendable {
    /// `UPnP` or `NAT-PMP`.
    var transport: String
    var reason: String
}

nonisolated struct TorrentContentFileDescriptor: Equatable, Sendable {
    var relativePath: String
    var sizeBytes: Int64
    var fileIndex: Int
}

/// Keeps engine errors machine-readable.
/// The UI must not expose raw libtorrent messages to users.
nonisolated struct TorrentEngineError: Error, Equatable, Sendable {
    nonisolated enum Kind: String, Sendable {
        case notImplemented
        case invalidMagnet
        case invalidTorrentFile
        case duplicateTorrent
        case metadataTimeout
        case draftPreparationLost
        case torrentNotFound
        case engineFailure
    }

    var kind: Kind
    var debugReason: String?
    /// The torrent a duplicate already is, when the engine knows its name.
    var torrentName: String?
    /// And its info hash, which finds that download in the list.
    var infoHash: String?

    init(kind: Kind, debugReason: String? = nil, torrentName: String? = nil, infoHash: String? = nil) {
        self.kind = kind
        self.debugReason = debugReason
        self.torrentName = torrentName
        self.infoHash = infoHash
    }

    static func normalized(from error: Error) -> TorrentEngineError {
        if let engineError = error as? TorrentEngineError {
            return engineError
        }

        return TorrentEngineError(
            kind: .engineFailure,
            debugReason: (error as NSError).localizedDescription
        )
    }
}

/// A single engine contract allows moving it into a helper process later
/// without rewriting the UI or store.
nonisolated protocol TorrentEngine: Sendable {
    func boot() async throws
    func applyPerformanceSettings(_ settings: EnginePerformanceSettings) async throws
    func prepareDraft(
        from source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool
    ) async throws -> AddTorrentDraft
    func prepareDraft(
        from source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool,
        onMetadataProgress: @escaping @Sendable (Double) async -> Void
    ) async throws -> AddTorrentDraft
    func inspectTorrentContents(at torrentFilePath: String) async throws -> [TorrentContentFileDescriptor]
    /// `prepareDraft` keeps the metadata of each draft under the draft `id`;
    /// `addTorrent` and this export read it until `releasePreparedDraft` drops it.
    func exportPreparedTorrent(draftID: UUID, to destinationPath: String) async throws
    func releasePreparedDraft(id draftID: UUID) async
    func addTorrent(
        using draft: AddTorrentDraft,
        recordID: UUID,
        attemptID: UUID
    ) async throws -> TorrentRecord
    func restoreSession(_ entries: [SessionRestoreEntry]) async throws -> [EngineTorrentSnapshot]
    func startTorrent(id: UUID) async throws
    func forceRecheck(id: UUID) async throws
    func checkpointTorrents(ids: [UUID]) async -> [EngineResumeCheckpointResult]
    /// Detaches the torrent and keeps its files: payload deletion belongs to
    /// `TorrentPayloadDeletionService`, never to the engine.
    func removeTorrent(id: UUID) async throws
    func fetchActiveSnapshots() async throws -> [EngineTorrentSnapshot]
    func reconcileSleepingTorrents(_ records: [TorrentRecord]) async throws -> [EngineTorrentSnapshot]
    /// The open-file budget of the running engine; `nil` before boot.
    func resourceBudget() async -> EngineResourceBudget?
    /// What the router answered to port forwarding; `nil` for engines without it.
    func portMappingStatus() async -> EnginePortMappingStatus?
    /// Forgets the router's answer and asks again, for a Mac that moved to
    /// another network. Nothing happens while port forwarding is off.
    func restartPortMappingCheck() async
    /// Stops the engine before the app exits; it accepts no commands afterwards.
    func shutdown() async
    #if DEBUG
    /// Asks every tracker of the download for its seeds and leechers; false
    /// for a download the engine does not hold. See `EngineTrackerScrape`.
    func scrapeTrackers(id: UUID) async -> Bool
    /// What the trackers answered since `scrapeTrackers`.
    func trackerScrape(id: UUID) async -> EngineTrackerScrape?
    #endif
}

extension TorrentEngine {
    nonisolated func resourceBudget() async -> EngineResourceBudget? { nil }
    nonisolated func portMappingStatus() async -> EnginePortMappingStatus? { nil }
    nonisolated func restartPortMappingCheck() async {}
    nonisolated func shutdown() async {}
    #if DEBUG
    nonisolated func scrapeTrackers(id: UUID) async -> Bool { false }
    nonisolated func trackerScrape(id: UUID) async -> EngineTrackerScrape? { nil }
    #endif
}

#if DEBUG
/// What a download's trackers answered when asked how many seeds and
/// leechers it has, without it downloading anything. Debug only: the first
/// step of a queue that would rank downloads by their swarms, tried on the
/// owner's real trackers (2026-11-13).
nonisolated struct EngineTrackerScrape: Equatable, Sendable {
    nonisolated struct Answer: Equatable, Sendable {
        /// Scheme and host only.
        var tracker: String
        var milliseconds: Int
        /// `nil` when the tracker failed.
        var seeds: Int?
        var leechers: Int?
        var errorMessage: String?
    }

    var trackerCount: Int
    var elapsedMilliseconds: Int
    var answers: [Answer]

    /// The answers with numbers, the most seeds first.
    var replies: [Answer] {
        answers.filter { $0.seeds != nil }.sorted { ($0.seeds ?? 0) > ($1.seeds ?? 0) }
    }

    var firstReplyMilliseconds: Int? {
        answers.filter { $0.seeds != nil }.map(\.milliseconds).min()
    }
}
#endif

extension TorrentEngine {
    func prepareDraft(
        from source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool,
        onMetadataProgress: @escaping @Sendable (Double) async -> Void
    ) async throws -> AddTorrentDraft {
        try await prepareDraft(from: source, suggestedSavePath: suggestedSavePath, stopAfterDownload: stopAfterDownload)
    }
}
