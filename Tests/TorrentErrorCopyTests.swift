// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// A card with an error says what happened, why it may have happened and
/// what to do; its notification says where to fix it, since a notification
/// has no buttons.
final class TorrentErrorCopyTests: XCTestCase {
    private let nbsp = "\u{00A0}"

    private func issue(_ kind: TorrentPersistentIssue.Kind) -> TorrentPersistentIssue {
        TorrentPersistentIssue(kind: kind, detectedAt: Date(), statusBeforeIssue: .downloading, debugReason: nil)
    }

    func testMissingFilesCardNamesTheFolder() throws {
        let folder = "/ShatlMissingFolder-\(UUID().uuidString)/Сериалы"
        let row = try XCTUnwrap(TorrentRowErrorState(
            ShatlErrorCatalog.persistentIssueState(for: issue(.missingContent), localeOverride: .russian),
            saveFolderPath: folder,
            localeOverride: .russian
        ))

        XCTAssertEqual(
            row.message,
            "В\(nbsp)папке «Сериалы» нет файлов этой загрузки\(nbsp)— возможно, их\(nbsp)переместили, "
                + "переименовали или\(nbsp)удалили. Скачайте их\(nbsp)заново или\(nbsp)удалите загрузку из\(nbsp)списка."
        )
        XCTAssertEqual(row.recoveryOptions, [.redownload, .removeFromList])
    }

    func testMissingFilesCardWithoutAFolderStillGivesCauseAndAction() throws {
        let row = try XCTUnwrap(TorrentRowErrorState(
            ShatlErrorCatalog.persistentIssueState(for: issue(.missingContent), localeOverride: .russian),
            localeOverride: .russian
        ))

        XCTAssertTrue(row.message.hasPrefix("Файлы не\(nbsp)найдены в\(nbsp)папке загрузки"), row.message)
        XCTAssertFalse(row.message.contains("Shatl"))
    }

    func testFolderNameIsLookedUpOnce() {
        let path = "/ShatlMissingFolder-\(UUID().uuidString)/Фильмы"
        XCTAssertEqual(ShatlErrorCatalog.folderDisplayName(forPath: path), "Фильмы")
        XCTAssertEqual(ShatlErrorCatalog.folderDisplayName(forPath: path), "Фильмы")
    }

    /// The notification names the event and says where to fix it; the card
    /// text would point at buttons a notification does not have.
    func testIssueNotificationsHaveTheirOwnText() {
        let missing = ShatlErrorCatalog.persistentIssueNotification(for: .missingContent, localeOverride: .russian)
        XCTAssertEqual(missing.title, "Файлы загрузки не\(nbsp)найдены")
        XCTAssertEqual(
            missing.body,
            "Возможно, их\(nbsp)переместили, переименовали или\(nbsp)удалили. Скачать их\(nbsp)заново можно в\(nbsp)списке загрузок."
        )

        for language in AppLocaleOverride.allCases where language != .system {
            for kind in [TorrentPersistentIssue.Kind.missingContent, .savePathUnavailable] {
                let notification = ShatlErrorCatalog.persistentIssueNotification(for: kind, localeOverride: language)
                let card = TorrentRowErrorState(
                    ShatlErrorCatalog.persistentIssueState(for: issue(kind), localeOverride: language),
                    localeOverride: language
                )
                XCTAssertFalse(notification.title.isEmpty, "\(language) \(kind)")
                XCTAssertFalse(notification.body.isEmpty, "\(language) \(kind)")
                XCTAssertNotEqual(notification.body, card?.message, "\(language) \(kind)")
                XCTAssertFalse(notification.body.contains("Shatl"), "\(language) \(kind)")
            }
        }
    }
}
