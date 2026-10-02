// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Canonical torrent card states.
nonisolated enum TorrentStatus: String, CaseIterable, Codable, Sendable {
    case downloading
    case stopped
    case seeding
    case completed
    case error
    case checking

    nonisolated var title: String {
        localizedTitle(localeOverride: .russian)
    }

    nonisolated func localizedTitle(localeOverride: AppLocaleOverride) -> String {
        switch self {
        case .downloading:
            L10n.string("torrent.status.downloading", localeOverride: localeOverride)
        case .stopped:
            L10n.string("torrent.status.stopped", localeOverride: localeOverride)
        case .seeding:
            L10n.string("torrent.status.seeding", localeOverride: localeOverride)
        case .completed:
            L10n.string("torrent.status.completed", localeOverride: localeOverride)
        case .error:
            L10n.string("torrent.status.error", localeOverride: localeOverride)
        case .checking:
            L10n.string("torrent.status.checking", localeOverride: localeOverride)
        }
    }

    /// Active torrents receive regular batches from the engine.
    nonisolated var isActive: Bool {
        switch self {
        case .downloading, .seeding, .checking:
            true
        case .stopped, .completed, .error:
            false
        }
    }

    /// Sleeping torrents do not require continuous engine polling.
    nonisolated var isSleeping: Bool {
        switch self {
        case .stopped, .completed:
            true
        case .downloading, .seeding, .error, .checking:
            false
        }
    }
}
