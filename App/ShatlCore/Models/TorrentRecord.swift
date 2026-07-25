// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// The primary torrent domain record stored by AppStore.
nonisolated struct TorrentRecord: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var attemptID: UUID
    var infoHash: String?
    var originalName: String
    var alias: String?
    var progress: Double
    var status: TorrentStatus
    var metrics: TorrentMetrics
    var canonicalSavePath: String
    var selectedFileIndices: [Int]
    var selectedFileRelativePaths: [String]
    var selectedFileCount: Int
    var totalFileCount: Int
    var materializedSelectionFootprint: MaterializedSelectionFootprint?
    var persistentIssue: TorrentPersistentIssue?
    var runtimeErrorState: TorrentErrorState?
    var lastKnownProgress: Double
    var resumeCheckpointedAt: Date?
    var resumeCheckpointProgress: Double?
    var stopAfterDownload: Bool

    /// The UI prioritizes a persistent card issue over a transient runtime error.
    var errorState: TorrentErrorState? {
        persistentIssue.flatMap(ShatlErrorCatalog.persistentIssueState(for:))
            ?? runtimeErrorState
    }

    /// The UI prefers a user-defined alias when one exists.
    var displayName: String {
        alias?.isEmpty == false ? alias! : originalName
    }

    /// Hides percentage until the first meaningful progress is reported.
    var visibleProgressPercent: Int? {
        let percent = Int((progress * 100).rounded(.down))
        return percent >= 1 ? percent : nil
    }

    /// Open is available only for a completed single-file payload.
    var isFinishedForOpening: Bool {
        status == .completed
            || status == .seeding
            || progress >= 1.0
    }
}

extension TorrentRecord {
    /// A small sample record used only by SwiftUI previews.
    static let previewData: [TorrentRecord] = [
        TorrentRecord(
            id: UUID(),
            attemptID: UUID(),
            infoHash: "preview-ios",
            originalName: "iOS 26.3 (iPhone 17).ipsw",
            alias: nil,
            progress: 0.50,
            status: .downloading,
            metrics: TorrentMetrics(
                downloadSpeedBytesPerSecond: 10_000_000,
                uploadSpeedBytesPerSecond: 0,
                etaSeconds: 3600,
                seeds: 10,
                peers: 1,
                uploadedBytes: 1_000_000_000,
                totalBytes: 12_000_000_000,
                selectedBytes: 12_000_000_000
            ),
            canonicalSavePath: "/Users/example/Downloads",
            selectedFileIndices: [0],
            selectedFileRelativePaths: ["iOS 26.3 (iPhone 17).ipsw"],
            selectedFileCount: 1,
            totalFileCount: 1,
            materializedSelectionFootprint: nil,
            persistentIssue: nil,
            runtimeErrorState: nil,
            lastKnownProgress: 0.50,
            resumeCheckpointedAt: nil,
            resumeCheckpointProgress: nil,
            stopAfterDownload: false
        ),
        TorrentRecord(
            id: UUID(),
            attemptID: UUID(),
            infoHash: "preview-macos",
            originalName: "macOS 14.5 (Ventura).dmg",
            alias: nil,
            progress: 0.01,
            status: .stopped,
            metrics: TorrentMetrics(
                downloadSpeedBytesPerSecond: 0,
                uploadSpeedBytesPerSecond: 0,
                etaSeconds: nil,
                seeds: nil,
                peers: nil,
                uploadedBytes: 0,
                totalBytes: 2_000_000_000,
                selectedBytes: 2_000_000_000
            ),
            canonicalSavePath: "/Users/example/Downloads",
            selectedFileIndices: [0],
            selectedFileRelativePaths: ["macOS 14.5 (Ventura).dmg"],
            selectedFileCount: 1,
            totalFileCount: 1,
            materializedSelectionFootprint: nil,
            persistentIssue: nil,
            runtimeErrorState: nil,
            lastKnownProgress: 0.01,
            resumeCheckpointedAt: nil,
            resumeCheckpointProgress: nil,
            stopAfterDownload: false
        ),
        TorrentRecord(
            id: UUID(),
            attemptID: UUID(),
            infoHash: "preview-completed",
            originalName: "iPadOS 17.0.ipsw",
            alias: nil,
            progress: 1.0,
            status: .completed,
            metrics: TorrentMetrics(
                downloadSpeedBytesPerSecond: 0,
                uploadSpeedBytesPerSecond: 0,
                etaSeconds: nil,
                seeds: nil,
                peers: nil,
                uploadedBytes: 0,
                totalBytes: 4_000_000_000,
                selectedBytes: 4_000_000_000
            ),
            canonicalSavePath: "/Users/example/Downloads",
            selectedFileIndices: [0],
            selectedFileRelativePaths: ["iPadOS 17.0.ipsw"],
            selectedFileCount: 1,
            totalFileCount: 1,
            materializedSelectionFootprint: nil,
            persistentIssue: nil,
            runtimeErrorState: nil,
            lastKnownProgress: 1.0,
            resumeCheckpointedAt: nil,
            resumeCheckpointProgress: nil,
            stopAfterDownload: true
        )
    ]
}
