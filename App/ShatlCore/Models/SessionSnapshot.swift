// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated struct SessionTorrentRecord: Codable, Sendable {
    var torrentID: UUID
    var attemptID: UUID
    var infoHash: String?
    var originalName: String
    var alias: String?
    var status: TorrentStatus
    var progress: Double
    var canonicalSavePath: String
    var stopAfterDownload: Bool
    var selectedFileIndices: [Int]
    var selectedFileRelativePaths: [String]? = nil
    var selectedFileCount: Int
    var totalFileCount: Int
    var archivedTorrentRelativePath: String
    var materializedSelectionFootprint: MaterializedSelectionFootprint?
    var persistentIssue: TorrentPersistentIssue?
    var resumeCheckpointedAt: Date? = nil
    var resumeCheckpointProgress: Double? = nil
}

/// Versions the session format from the start to support future migrations.
nonisolated struct SessionSnapshot: Codable, Sendable {
    var schemaVersion: Int
    var savedAt: Date
    var torrents: [SessionTorrentRecord]
}
