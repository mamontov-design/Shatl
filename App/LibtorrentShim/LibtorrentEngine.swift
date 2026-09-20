// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Keeps the Swift domain model separate from the Objective-C++ bridge.
/// This allows the store and UI to evolve without spreading C++ across the project.
actor LibtorrentEngine: TorrentEngine {
    private let bridge = LibtorrentSessionBridge()
    private let bridgeErrorDomain = "mamontov.design.shatl.libtorrent"

    private enum BridgeErrorCode: Int {
        case sessionNotBooted = 1
        case invalidMagnet = 2
        case invalidTorrentFile = 3
        case duplicateTorrent = 4
        case metadataTimeout = 5
        case torrentNotFound = 6
        case engineFailure = 7
        case draftPreparationLost = 8
    }

    func boot() async throws {
        do {
            try bridge.boot()
        } catch {
            throw mapBridgeError(error)
        }
    }

    func applyPerformanceSettings(_ settings: EnginePerformanceSettings) async throws {
        do {
            try bridge.apply(mapPerformanceProfile(settings.mode))
        } catch {
            throw mapBridgeError(error)
        }
    }

    func prepareDraft(
        from source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool
    ) async throws -> AddTorrentDraft {
        _ = stopAfterDownload

        let preparedDraft: LTPreparedDraft
        do {
            preparedDraft = try bridge.prepareDraft(
                withSourceKind: source.kind.rawValue,
                rawValue: source.rawValue,
                suggestedSavePath: suggestedSavePath
            )
        } catch {
            throw mapBridgeError(error)
        }

        return AddTorrentDraft(
            source: source,
            originalName: preparedDraft.originalName,
            infoHash: preparedDraft.infoHash,
            suggestedSavePath: preparedDraft.suggestedSavePath,
            alias: "",
            stopAfterDownload: stopAfterDownload,
            files: preparedDraft.files.map {
                AddTorrentFileOption(
                    name: $0.name,
                    sizeBytes: $0.sizeBytes,
                    fileIndex: $0.fileIndex,
                    isSelected: true
                )
            },
            reviewState: mapDraftState(preparedDraft.reviewState, message: preparedDraft.invalidMessage),
            errorState: nil
        )
    }

    func inspectTorrentContents(at torrentFilePath: String) async throws -> [TorrentContentFileDescriptor] {
        do {
            return try bridge.inspectTorrentContents(atPath: torrentFilePath).map {
                TorrentContentFileDescriptor(
                    relativePath: $0.name,
                    sizeBytes: $0.sizeBytes,
                    fileIndex: $0.fileIndex
                )
            }
        } catch {
            throw mapBridgeError(error)
        }
    }

    func exportPreparedTorrent(from source: AddTorrentSource, to destinationPath: String) async throws {
        do {
            try bridge.exportPreparedTorrent(
                withSourceKind: source.kind.rawValue,
                rawValue: source.rawValue,
                destinationPath: destinationPath
            )
        } catch {
            throw mapBridgeError(error)
        }
    }

    func addTorrent(
        using draft: AddTorrentDraft,
        recordID: UUID,
        attemptID: UUID
    ) async throws -> TorrentRecord {
        let selectedIndices = draft.files
            .compactMap { $0.isSelected ? NSNumber(value: $0.fileIndex) : nil }
        let selectedFileIndices = draft.selectedFileIndices
        let selectedFileRelativePaths = draft.files
            .filter(\.isSelected)
            .sorted { $0.fileIndex < $1.fileIndex }
            .compactMap { TorrentPathSafety.normalizedRelativePath($0.name) }

        let addedTorrent: LTAddedTorrent
        do {
            addedTorrent = try bridge.addTorrent(
                withSourceKind: draft.source.kind.rawValue,
                rawValue: draft.source.rawValue,
                suggestedSavePath: draft.suggestedSavePath,
                stopAfterDownload: draft.stopAfterDownload,
                selectedFileIndices: selectedIndices,
                recordIdentifier: recordID.uuidString,
                attemptIdentifier: attemptID.uuidString
            )
        } catch {
            throw mapBridgeError(error)
        }

        return TorrentRecord(
            id: recordID,
            attemptID: attemptID,
            infoHash: addedTorrent.infoHash,
            originalName: addedTorrent.originalName,
            alias: draft.alias.isEmpty ? nil : draft.alias,
            progress: 0,
            status: .downloading,
            metrics: TorrentMetrics(
                downloadSpeedBytesPerSecond: 0,
                uploadSpeedBytesPerSecond: 0,
                etaSeconds: nil,
                seeds: nil,
                peers: nil,
                uploadedBytes: 0,
                totalBytes: addedTorrent.totalBytes,
                selectedBytes: addedTorrent.selectedBytes
            ),
            canonicalSavePath: draft.suggestedSavePath,
            selectedFileIndices: selectedFileIndices,
            selectedFileRelativePaths: selectedFileRelativePaths,
            selectedFileCount: addedTorrent.selectedFileCount,
            totalFileCount: addedTorrent.totalFileCount,
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
        var snapshots: [EngineTorrentSnapshot] = []

        for entry in entries {
            do {
                let bridgeSnapshot = try bridge.restoreTorrent(
                    withTorrentFilePath: entry.archivedTorrentPath,
                    suggestedSavePath: entry.suggestedSavePath,
                    stopAfterDownload: entry.stopAfterDownload,
                    selectedFileIndices: entry.selectedFileIndices.map { NSNumber(value: $0) },
                    recordIdentifier: entry.torrentID.uuidString,
                    shouldStart: entry.shouldStart
                )

                if let mapped = mapSnapshot(bridgeSnapshot) {
                    snapshots.append(mapped)
                }
            } catch {
                throw mapBridgeError(error)
            }
        }

        return snapshots
    }

    func fetchMaterializedSelectedFileIndices(
        for id: UUID,
        selectedFileIndices: [Int]
    ) async throws -> Set<Int> {
        do {
            let values = try bridge.materializedFileIndices(
                recordIdentifier: id.uuidString,
                selectedFileIndices: selectedFileIndices.map { NSNumber(value: $0) }
            )

            return Set(values.map { $0.intValue })
        } catch {
            throw mapBridgeError(error)
        }
    }

    func startTorrent(id: UUID) async throws {
        do {
            try bridge.startTorrent(withIdentifier: id.uuidString)
        } catch {
            throw mapBridgeError(error)
        }
    }

    func stopTorrent(id: UUID) async throws {
        do {
            try bridge.stopTorrent(withIdentifier: id.uuidString)
        } catch {
            throw mapBridgeError(error)
        }
    }

    func forceRecheck(id: UUID) async throws {
        do {
            try bridge.forceRecheckTorrent(withIdentifier: id.uuidString)
        } catch {
            throw mapBridgeError(error)
        }
    }

    func checkpointTorrents(ids: [UUID]) async -> [EngineResumeCheckpointResult] {
        guard !ids.isEmpty else { return [] }

        do {
            let checkpoints = try bridge.checkpointTorrents(withIdentifiers: ids.map(\.uuidString))
            return checkpoints.compactMap { checkpoint in
                guard let id = UUID(uuidString: checkpoint.recordIdentifier) else {
                    return nil
                }

                return EngineResumeCheckpointResult(
                    id: id,
                    status: mapResumeCheckpointStatus(checkpoint)
                )
            }
        } catch {
            let mappedError = TorrentEngineError.normalized(from: mapBridgeError(error))
            return ids.map {
                EngineResumeCheckpointResult(
                    id: $0,
                    status: .failed(mappedError.debugReason)
                )
            }
        }
    }

    func removeTorrent(id: UUID, deleteData: Bool) async throws {
        ShatlDiskDiagnosticsLog.event(
            "engine.remove.begin",
            fields: [
                "torrent": id.uuidString,
                "deleteData": deleteData ? "1" : "0"
            ]
        )
        do {
            try bridge.removeTorrent(withIdentifier: id.uuidString, deleteData: deleteData)
            ShatlDiskDiagnosticsLog.event(
                "engine.remove.end",
                fields: [
                    "torrent": id.uuidString,
                    "deleteData": deleteData ? "1" : "0",
                    "outcome": "success"
                ]
            )
        } catch {
            let mappedError = mapBridgeError(error)
            let engineError = TorrentEngineError.normalized(from: mappedError)
            ShatlDiskDiagnosticsLog.event(
                "engine.remove.end",
                fields: [
                    "torrent": id.uuidString,
                    "deleteData": deleteData ? "1" : "0",
                    "outcome": "failed",
                    "kind": engineError.kind.rawValue,
                    "reason": engineError.debugReason ?? "-"
                ]
            )
            throw mappedError
        }
    }

    func fetchActiveSnapshots() async throws -> [EngineTorrentSnapshot] {
        let bridgeSnapshots: [LTTorrentSnapshot]
        do {
            bridgeSnapshots = try bridge.fetchActiveSnapshots()
        } catch {
            throw mapBridgeError(error)
        }

        return bridgeSnapshots.compactMap(mapSnapshot)
    }

    func reconcileSleepingTorrents(_ records: [TorrentRecord]) async throws -> [EngineTorrentSnapshot] {
        let identifiers = records.map(\.id.uuidString)
        let bridgeSnapshots: [LTTorrentSnapshot]
        do {
            bridgeSnapshots = try bridge.reconcileTorrentIdentifiers(identifiers)
        } catch {
            throw mapBridgeError(error)
        }

        return bridgeSnapshots.compactMap(mapSnapshot)
    }

    private func mapDraftState(_ state: LTTorrentDraftState, message: String?) -> AddTorrentReviewState {
        switch state {
        case .loadingMetadata:
            return .loadingMetadata
        case .ready:
            return .ready
        case .invalid:
            return .invalid(message: message ?? "Не удалось подготовить торрент.")
        @unknown default:
            return .invalid(message: "Неизвестное состояние подготовки торрента.")
        }
    }

    private func mapPerformanceProfile(_ mode: EnginePerformanceMode) -> LTPerformanceProfile {
        switch mode {
        case .economical:
            return .economical
        case .balanced:
            return .balanced
        case .maximum:
            return .maximum
        }
    }

    private func mapSnapshot(_ snapshot: LTTorrentSnapshot) -> EngineTorrentSnapshot? {
        guard let identifier = UUID(uuidString: snapshot.recordIdentifier) else {
            return nil
        }

        let status = mapStatus(snapshot.status)
        let metrics: TorrentMetrics

        switch status {
        case .downloading, .seeding:
            metrics = TorrentMetrics(
                downloadSpeedBytesPerSecond: snapshot.downloadSpeedBytesPerSecond,
                uploadSpeedBytesPerSecond: snapshot.uploadSpeedBytesPerSecond,
                etaSeconds: snapshot.etaSeconds?.intValue,
                seeds: snapshot.seeds?.intValue,
                peers: snapshot.peers?.intValue,
                uploadedBytes: snapshot.uploadedBytes,
                totalBytes: snapshot.totalBytes,
                selectedBytes: snapshot.selectedBytes
            )

        case .stopped, .completed, .checking, .error:
            metrics = TorrentMetrics(
                downloadSpeedBytesPerSecond: 0,
                uploadSpeedBytesPerSecond: 0,
                etaSeconds: nil,
                seeds: nil,
                peers: nil,
                uploadedBytes: snapshot.uploadedBytes,
                totalBytes: snapshot.totalBytes,
                selectedBytes: snapshot.selectedBytes
            )
        }

        let engineSnapshot = EngineTorrentSnapshot(
            id: identifier,
            status: status,
            progress: snapshot.progress,
            metrics: metrics,
            errorState: snapshot.errorMessage.map { ShatlErrorCatalog.runtimeSnapshotError(debugReason: $0) },
            resumeDataStatus: mapResumeDataStatus(snapshot.resumeDataStatus)
        )

        logUploadCounterDiagnostics(
            bridgeSnapshot: snapshot,
            engineSnapshot: engineSnapshot
        )

        return engineSnapshot
    }

    private func logUploadCounterDiagnostics(
        bridgeSnapshot: LTTorrentSnapshot,
        engineSnapshot: EngineTorrentSnapshot
    ) {
        let metrics = engineSnapshot.metrics
        guard bridgeSnapshot.uploadSpeedBytesPerSecond > 0
            || bridgeSnapshot.uploadedBytes > 0
            || metrics.uploadSpeedBytesPerSecond > 0
            || metrics.uploadedBytes > 0 else {
            return
        }

        let suspicious = bridgeSnapshot.uploadSpeedBytesPerSecond > 0 && bridgeSnapshot.uploadedBytes == 0
        let fields: [(String, String)] = [
            ("torrent", engineSnapshot.id.uuidString),
            ("phase", "snapshot.upload-counters.engine"),
            ("bridgeStatus", "\(bridgeSnapshot.status.rawValue)"),
            ("engineStatus", engineSnapshot.status.rawValue),
            ("progress", String(format: "%.3f", engineSnapshot.progress)),
            ("bridgeUploadSpeed", "\(bridgeSnapshot.uploadSpeedBytesPerSecond)"),
            ("bridgeUploaded", "\(bridgeSnapshot.uploadedBytes)"),
            ("engineUploadSpeed", "\(metrics.uploadSpeedBytesPerSecond)"),
            ("engineUploaded", "\(metrics.uploadedBytes)"),
            ("uploadedCounterSuspicious", suspicious ? "1" : "0")
        ]

        let message = fields
            .map { Self.formatDiagnosticField(key: $0.0, value: $0.1) }
            .joined(separator: " ")

        if suspicious {
            ShatlLog.bridge.criticalDebug(message)
        } else {
            ShatlLog.bridge.debug(message)
        }
    }

    private nonisolated static func formatDiagnosticField(key: String, value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let needsQuotes = escaped.contains(where: { $0.isWhitespace || $0 == "=" || $0 == "\"" })
        return needsQuotes ? "\(key)=\"\(escaped)\"" : "\(key)=\(escaped)"
    }

    private func mapResumeDataStatus(_ status: String?) -> EngineResumeDataStatus? {
        guard let status else { return nil }
        return EngineResumeDataStatus(rawValue: status)
    }

    private func mapResumeCheckpointStatus(_ checkpoint: LTResumeCheckpoint) -> EngineResumeCheckpointStatus {
        switch checkpoint.status {
        case "saved":
            return .saved
        case "not-found":
            return .notFound
        case "timed-out":
            return .timedOut
        default:
            return .failed(checkpoint.errorMessage)
        }
    }

    private func mapStatus(_ status: LTTorrentRuntimeStatus) -> TorrentStatus {
        switch status {
        case .downloading:
            return .downloading
        case .stopped:
            return .stopped
        case .seeding:
            return .seeding
        case .completed:
            return .completed
        case .error:
            return .error
        case .checking:
            return .checking
        @unknown default:
            return .error
        }
    }

    private func mapBridgeError(_ error: Error) -> TorrentEngineError {
        let nsError = error as NSError

        guard nsError.domain == bridgeErrorDomain,
              let code = BridgeErrorCode(rawValue: nsError.code) else {
            return TorrentEngineError(
                kind: .engineFailure,
                debugReason: nsError.localizedDescription
            )
        }

        switch code {
        case .sessionNotBooted:
            return TorrentEngineError(kind: .engineFailure, debugReason: nsError.localizedDescription)
        case .invalidMagnet:
            return TorrentEngineError(kind: .invalidMagnet, debugReason: nsError.localizedDescription)
        case .invalidTorrentFile:
            return TorrentEngineError(kind: .invalidTorrentFile, debugReason: nsError.localizedDescription)
        case .duplicateTorrent:
            return TorrentEngineError(kind: .duplicateTorrent, debugReason: nsError.localizedDescription)
        case .metadataTimeout:
            return TorrentEngineError(kind: .metadataTimeout, debugReason: nsError.localizedDescription)
        case .torrentNotFound:
            return TorrentEngineError(kind: .torrentNotFound, debugReason: nsError.localizedDescription)
        case .engineFailure:
            return TorrentEngineError(kind: .engineFailure, debugReason: nsError.localizedDescription)
        case .draftPreparationLost:
            return TorrentEngineError(kind: .draftPreparationLost, debugReason: nsError.localizedDescription)
        }
    }
}
