// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated enum TorrentUserNotification: Equatable, Sendable {
    case downloadCompleted(
        torrentID: UUID,
        torrentTitle: String,
        localeOverride: AppLocaleOverride
    )
    /// The engine stopped a running download with an error.
    case downloadStopped(
        torrentID: UUID,
        torrentTitle: String,
        title: String,
        body: String
    )
    case persistentIssue(
        torrentID: UUID,
        issueKind: TorrentPersistentIssue.Kind,
        torrentTitle: String,
        issueTitle: String,
        issueMessage: String,
        localeOverride: AppLocaleOverride
    )
}

@MainActor
protocol TorrentUserEventNotifying: AnyObject {
    func notify(_ notification: TorrentUserNotification, badgeCount: Int)
}

@MainActor
protocol TorrentUserEventBadgeDisplaying: AnyObject {
    func setBadgeCount(_ count: Int)
}
