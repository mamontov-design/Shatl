// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

#if DEBUG
import Foundation

/// Debug builds only: plays the made-up downloads of a demo list the way the
/// real engine reports its own. Every poll, speeds waver around each
/// download's level, crossing speed-level thresholds now and then, progress
/// grows and the ETA follows. Nothing finishes, so the number of active
/// downloads holds through a test. It adds no torrents and touches no files.
actor DemoTorrentEngine: TorrentEngine {
    private struct Transfer {
        var plan: DemoTransferPlan
        var status: TorrentStatus
        var progress: Double
        var uploadedBytes: Double
        var seeds: Int
        var peers: Int
        /// How far the speed sits from its level, as a slow random walk.
        var downloadDrift: Double = 0
        var uploadDrift: Double = 0
        var downloadSpeed: Double = 0
        var uploadSpeed: Double = 0
    }

    /// A download stays short of the end, so it never becomes seeding.
    static let progressCeiling = 0.985

    private var transfers: [UUID: Transfer] = [:]
    private var order: [UUID] = []
    private var generator: DemoRandom
    private var lastPoll: ContinuousClock.Instant?

    init(plans: [DemoTransferPlan], seed: UInt64) {
        generator = DemoRandom(seed: seed ^ 0xD3A0)
        for plan in plans {
            order.append(plan.id)
            transfers[plan.id] = Transfer(
                plan: plan,
                status: plan.status,
                progress: plan.progress,
                uploadedBytes: Double(plan.uploadedBytes),
                seeds: plan.seeds,
                peers: plan.peers
            )
        }
    }

    // MARK: - Polling

    func fetchActiveSnapshots() async throws -> [EngineTorrentSnapshot] {
        let now = ContinuousClock.now
        let seconds = lastPoll.map { Self.seconds(now - $0) } ?? 1
        lastPoll = now
        return advance(bySeconds: min(max(seconds, 0.2), 3))
    }

    /// Moves every active download on by `seconds` and reports them.
    func advance(bySeconds seconds: Double) -> [EngineTorrentSnapshot] {
        var snapshots: [EngineTorrentSnapshot] = []
        for id in order {
            guard var transfer = transfers[id], transfer.status == .downloading || transfer.status == .seeding else {
                continue
            }
            step(&transfer, seconds: seconds)
            transfers[id] = transfer
            snapshots.append(snapshot(of: transfer))
        }
        return snapshots
    }

    func reconcileSleepingTorrents(_ records: [TorrentRecord]) async throws -> [EngineTorrentSnapshot] {
        records.compactMap { transfers[$0.id].map(snapshot(of:)) }
    }

    func restoreSession(_ entries: [SessionRestoreEntry]) async throws -> [EngineTorrentSnapshot] {
        []
    }

    private func step(_ transfer: inout Transfer, seconds: Double) {
        transfer.downloadDrift = 0.75 * transfer.downloadDrift + 0.25 * 0.35 * generator.nextGaussian()
        transfer.uploadDrift = 0.75 * transfer.uploadDrift + 0.25 * 0.35 * generator.nextGaussian()
        let downloadFactor = max(0.05, 1 + transfer.downloadDrift)
        let uploadFactor = max(0, 1 + transfer.uploadDrift)

        if transfer.status == .downloading {
            transfer.downloadSpeed = transfer.plan.baseDownloadSpeed * downloadFactor
            let added = transfer.downloadSpeed * seconds / Double(max(transfer.plan.totalBytes, 1))
            transfer.progress = min(Self.progressCeiling, transfer.progress + added)
        } else {
            transfer.downloadSpeed = 0
        }
        transfer.uploadSpeed = transfer.plan.baseUploadSpeed * uploadFactor
        transfer.uploadedBytes += transfer.uploadSpeed * seconds

        // Now and then a peer comes or goes.
        if generator.nextUnit() < 0.2 {
            transfer.peers = max(0, transfer.peers + (generator.nextUnit() < 0.5 ? -1 : 1))
        }
        if generator.nextUnit() < 0.1 {
            transfer.seeds = max(0, transfer.seeds + (generator.nextUnit() < 0.5 ? -1 : 1))
        }
    }

    private func snapshot(of transfer: Transfer) -> EngineTorrentSnapshot {
        let totalBytes = transfer.plan.totalBytes
        let remainingBytes = Double(totalBytes) * (1 - transfer.progress)
        let isDownloading = transfer.status == .downloading
        let isActive = isDownloading || transfer.status == .seeding
        return EngineTorrentSnapshot(
            id: transfer.plan.id,
            status: transfer.status,
            progress: transfer.progress,
            metrics: TorrentMetrics(
                downloadSpeedBytesPerSecond: isDownloading ? Int64(transfer.downloadSpeed) : 0,
                uploadSpeedBytesPerSecond: isActive ? Int64(transfer.uploadSpeed) : 0,
                etaSeconds: isDownloading && transfer.downloadSpeed > 0
                    ? Int(remainingBytes / transfer.downloadSpeed)
                    : nil,
                seeds: isActive ? transfer.seeds : nil,
                peers: isActive ? transfer.peers : nil,
                uploadedBytes: Int64(transfer.uploadedBytes),
                totalBytes: totalBytes,
                selectedBytes: totalBytes
            ),
            errorState: nil
        )
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    // MARK: - Commands

    func boot() async throws {}

    func applyPerformanceSettings(_ settings: EnginePerformanceSettings) async throws {}

    func startTorrent(id: UUID) async throws {
        guard var transfer = transfers[id] else { throw Self.unavailable }
        transfer.status = transfer.progress >= Self.progressCeiling ? .seeding : .downloading
        transfers[id] = transfer
    }

    func forceRecheck(id: UUID) async throws {}

    func checkpointTorrents(ids: [UUID]) async -> [EngineResumeCheckpointResult] {
        []
    }

    /// Detaches the download: it stops moving until started again.
    func removeTorrent(id: UUID) async throws {
        guard var transfer = transfers[id] else { return }
        if transfer.status == .downloading || transfer.status == .seeding {
            transfer.status = transfer.progress >= 1 ? .completed : .stopped
        }
        transfers[id] = transfer
    }

    func prepareDraft(
        from source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool
    ) async throws -> AddTorrentDraft {
        throw Self.unavailable
    }

    func inspectTorrentContents(at torrentFilePath: String) async throws -> [TorrentContentFileDescriptor] {
        []
    }

    func exportPreparedTorrent(draftID: UUID, to destinationPath: String) async throws {
        throw Self.unavailable
    }

    func releasePreparedDraft(id draftID: UUID) async {}

    func addTorrent(
        using draft: AddTorrentDraft,
        recordID: UUID,
        attemptID: UUID
    ) async throws -> TorrentRecord {
        throw Self.unavailable
    }

    private static let unavailable = TorrentEngineError(
        kind: .engineFailure,
        debugReason: "The demo list adds no torrents."
    )
}
#endif
