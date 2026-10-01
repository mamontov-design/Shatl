// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import UserNotifications

@MainActor
final class MacTorrentUserEventNotifier: TorrentUserEventNotifying {
    private static let logger = ShatlLog.ui

    func notify(_ notification: TorrentUserNotification, badgeCount: Int) {
        Task {
            do {
                try await UNUserNotificationCenter.current().add(
                    Self.request(for: notification, badgeCount: badgeCount)
                )
            } catch {
                Self.logger.error("Failed to schedule user notification: \((error as NSError).localizedDescription)")
            }
        }
    }

    private static func request(
        for notification: TorrentUserNotification,
        badgeCount: Int
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.badge = NSNumber(value: badgeCount)
        content.sound = .default

        let identifier: String

        switch notification {
        case .downloadCompleted(let torrentID, let torrentTitle, let localeOverride):
            identifier = "torrent.download-completed.\(torrentID.uuidString)"
            content.title = L10n.string(
                "notification.download_completed.title",
                localeOverride: localeOverride,
                defaultValue: "Download complete"
            )
            // The name alone: a sentence around it would have to agree with
            // a name of any gender and number.
            content.body = torrentTitle

        case .persistentIssue(
            let torrentID,
            let issueKind,
            let torrentTitle,
            let issueTitle,
            let issueMessage,
            _
        ):
            identifier = "torrent.issue.\(torrentID.uuidString).\(issueKind.rawValue)"
            content.title = issueTitle
            content.subtitle = torrentTitle
            content.body = issueMessage
        }

        return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }
}

@MainActor
final class MacTorrentUserEventBadgeDisplay: TorrentUserEventBadgeDisplaying {
    private static let logger = ShatlLog.ui

    func setBadgeCount(_ count: Int) {
        Task {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(count)
            } catch {
                Self.logger.error("Failed to update user notification badge count: \((error as NSError).localizedDescription)")
            }
        }
    }
}
