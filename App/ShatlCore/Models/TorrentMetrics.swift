// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Raw torrent metrics received from the engine.
nonisolated struct TorrentMetrics: Equatable, Codable, Sendable {
    var downloadSpeedBytesPerSecond: Int64 = 0
    var uploadSpeedBytesPerSecond: Int64 = 0
    var etaSeconds: Int?
    var seeds: Int?
    var peers: Int?
    var uploadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var selectedBytes: Int64 = 0

    var hasVisibleDownloadSpeed: Bool {
        downloadSpeedBytesPerSecond > 0
    }

    var hasVisibleUploadSpeed: Bool {
        uploadSpeedBytesPerSecond > 0
    }

    var hasVisiblePeerStats: Bool {
        (seeds ?? 0) > 0 || (peers ?? 0) > 0
    }
}
