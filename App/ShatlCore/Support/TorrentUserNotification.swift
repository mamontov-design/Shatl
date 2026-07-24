import Foundation

nonisolated enum TorrentUserNotification: Equatable, Sendable {
    case downloadCompleted(
        torrentID: UUID,
        torrentTitle: String,
        localeOverride: AppLocaleOverride
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
