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
    /// Stops the engine before the app exits; it accepts no commands afterwards.
    func shutdown() async
}

extension TorrentEngine {
    nonisolated func resourceBudget() async -> EngineResourceBudget? { nil }
    nonisolated func portMappingStatus() async -> EnginePortMappingStatus? { nil }
    nonisolated func shutdown() async {}
}
