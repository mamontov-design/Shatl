// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated struct SessionTorrentRecord: Codable, Equatable, Sendable {
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
    /// The download's size, so a stopped card shows it after relaunch: the
    /// engine has such a download only after Start. Optional and with no new
    /// schema version, so an older Shatl skips it and a list without it reads
    /// as before. Written only when known.
    var totalBytes: Int64? = nil
    var selectedBytes: Int64? = nil
}

/// Versions the session format from the start to support future migrations.
nonisolated struct SessionSnapshot: Codable, Sendable {
    static let oldestSupportedSchemaVersion = 3
    static let currentSchemaVersion = 5

    var schemaVersion: Int
    var savedAt: Date
    var torrents: [SessionTorrentRecord]
}
