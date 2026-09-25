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

    init(kind: Kind, debugReason: String? = nil) {
        self.kind = kind
        self.debugReason = debugReason
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
    func fetchMaterializedSelectedFileIndices(
        for id: UUID,
        selectedFileIndices: [Int]
    ) async throws -> Set<Int>
    func startTorrent(id: UUID) async throws
    func stopTorrent(id: UUID) async throws
    func forceRecheck(id: UUID) async throws
    func checkpointTorrents(ids: [UUID]) async -> [EngineResumeCheckpointResult]
    func removeTorrent(id: UUID, deleteData: Bool) async throws
    func fetchActiveSnapshots() async throws -> [EngineTorrentSnapshot]
    func reconcileSleepingTorrents(_ records: [TorrentRecord]) async throws -> [EngineTorrentSnapshot]
    /// The open-file budget of the running engine; `nil` before boot.
    func resourceBudget() async -> EngineResourceBudget?
}

extension TorrentEngine {
    nonisolated func resourceBudget() async -> EngineResourceBudget? { nil }
}
