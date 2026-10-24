// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// A card with an error says what happened, why it may have happened and
/// what to do; its notification says where to fix it, since a notification
/// has no buttons.
@MainActor
final class TorrentErrorCopyTests: XCTestCase {
    private let nbsp = "\u{00A0}"

    private func issue(_ kind: TorrentPersistentIssue.Kind) -> TorrentPersistentIssue {
        TorrentPersistentIssue(kind: kind, detectedAt: Date(), statusBeforeIssue: .downloading, debugReason: nil)
    }

    /// The text as a reader sees it, without the typograph's no-break spaces.
    private func plain(_ text: String?) -> String? {
        text?.replacingOccurrences(of: nbsp, with: " ")
    }

    private func missingFilesCard(hasOneFile: Bool, folder: String? = nil) throws -> TorrentRowErrorState {
        try XCTUnwrap(TorrentRowErrorState(
            ShatlErrorCatalog.persistentIssueState(for: issue(.missingContent), localeOverride: .russian),
            saveFolderPath: folder,
            hasOneFile: hasOneFile,
            localeOverride: .russian
        ))
    }

    /// One missing file is enough for the error, so a download of several
    /// is told that one or more are gone, not all of them.
    func testMissingFilesCardNamesTheFolder() throws {
        let folder = "/ShatlMissingFolder-\(UUID().uuidString)/Сериалы"
        let row = try missingFilesCard(hasOneFile: false, folder: folder)

        XCTAssertEqual(
            plain(row.message),
            "В папке «Сериалы» нет одного или нескольких файлов этой загрузки — возможно, их переместили, "
                + "переименовали или удалили. Скачайте их заново или удалите загрузку из списка."
        )
        XCTAssertEqual(row.recoveryOptions, [.redownload, .removeFromList])
    }

    /// A download of one file is told about that file.
    func testMissingFileCardOfADownloadOfOneFileSpeaksOfThatFile() throws {
        let folder = "/ShatlMissingFolder-\(UUID().uuidString)/Книги"
        let row = try missingFilesCard(hasOneFile: true, folder: folder)

        XCTAssertEqual(
            plain(row.message),
            "В папке «Книги» нет файла этой загрузки — возможно, его переместили, "
                + "переименовали или удалили. Скачайте его заново или удалите загрузку из списка."
        )
        XCTAssertEqual(plain(row.title), "Файл загрузки не найден")
    }

    func testMissingFilesCardWithoutAFolderStillGivesCauseAndAction() throws {
        let several = try missingFilesCard(hasOneFile: false)
        XCTAssertTrue(
            plain(several.message)?.hasPrefix("В папке загрузки нет одного или нескольких её файлов") == true,
            several.message
        )
        XCTAssertFalse(several.message.contains("Shatl"))

        let one = try missingFilesCard(hasOneFile: true)
        XCTAssertTrue(plain(one.message)?.hasPrefix("В папке загрузки нет её файла") == true, one.message)
    }

    /// The engine stopped a download because a file went missing: the same
    /// distinction between one file and several.
    func testFilesMissingWhileRunningAreToldApartForOneFile() throws {
        let error = ShatlErrorCatalog.runtimeSnapshotError(debugReason: nil, posixCode: Int(ENOENT))
        let folder = "/Volumes/Metis/Фильмы"
        let several = try XCTUnwrap(TorrentRowErrorState(error, saveFolderPath: folder, localeOverride: .russian))
        let one = try XCTUnwrap(TorrentRowErrorState(error, saveFolderPath: folder, hasOneFile: true, localeOverride: .russian))

        XCTAssertTrue(
            plain(several.message)?.hasPrefix("Из папки «Фильмы» пропали один или несколько файлов загрузки, и загрузка остановилась.") == true,
            several.message
        )
        XCTAssertTrue(
            plain(one.message)?.hasPrefix("Файл загрузки пропал из папки «Фильмы», и она остановилась.") == true,
            one.message
        )
        XCTAssertEqual(
            plain(ShatlErrorCatalog.runtimeErrorNotification(for: .filesMissing, localeOverride: .russian).body),
            "Из папки пропали один или несколько файлов загрузки. Повторить запуск можно в списке загрузок."
        )
        XCTAssertEqual(
            plain(ShatlErrorCatalog.runtimeErrorNotification(for: .filesMissing, hasOneFile: true, localeOverride: .russian).body),
            "Файл загрузки пропал из папки. Повторить запуск можно в списке загрузок."
        )
        // Other causes have one wording whatever the number of files.
        XCTAssertEqual(
            ShatlErrorCatalog.runtimeErrorKey(.diskFull, hasOneFile: true),
            ShatlErrorCatalog.runtimeErrorKey(.diskFull, hasOneFile: false)
        )
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
        XCTAssertEqual(plain(missing.title), "Не хватает файлов загрузки")
        XCTAssertEqual(
            plain(missing.body),
            "Возможно, их переместили, переименовали или удалили. Скачать их заново можно в списке загрузок."
        )
        let missingOne = ShatlErrorCatalog.persistentIssueNotification(
            for: .missingContent,
            hasOneFile: true,
            localeOverride: .russian
        )
        XCTAssertEqual(plain(missingOne.title), "Файл загрузки не найден")
        XCTAssertEqual(
            plain(missingOne.body),
            "Возможно, его переместили, переименовали или удалили. Скачать его заново можно в списке загрузок."
        )

        for language in AppLocaleOverride.allCases where language != .system {
            for kind in [TorrentPersistentIssue.Kind.missingContent, .savePathUnavailable] {
                for hasOneFile in [false, true] {
                    let notification = ShatlErrorCatalog.persistentIssueNotification(
                        for: kind,
                        hasOneFile: hasOneFile,
                        localeOverride: language
                    )
                    let card = TorrentRowErrorState(
                        ShatlErrorCatalog.persistentIssueState(for: issue(kind), localeOverride: language),
                        hasOneFile: hasOneFile,
                        localeOverride: language
                    )
                    let label = "\(language) \(kind) one file: \(hasOneFile)"
                    XCTAssertFalse(notification.title.isEmpty, label)
                    XCTAssertFalse(notification.title.hasPrefix("torrent."), label)
                    XCTAssertFalse(notification.body.hasPrefix("torrent."), label)
                    XCTAssertFalse(card?.message.hasPrefix("torrent.") ?? true, label)
                    XCTAssertNotEqual(notification.body, card?.message, label)
                    XCTAssertFalse(notification.body.contains("Shatl"), label)
                }
            }
        }
    }
}
