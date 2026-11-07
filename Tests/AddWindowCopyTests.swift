// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// A magnet link's file list comes from other peers. When the wait runs out
/// with no network at all, the add window says the Mac is offline instead of
/// guessing at slow or missing peers.
@MainActor
final class AddWindowCopyTests: XCTestCase {
    func testFileListWaitWithoutNetworkSaysTheMacIsOffline() async {
        let title = await reviewErrorTitle(afterTimeoutWhileOffline: true)
        XCTAssertEqual(title, ShatlErrorCatalog.offlineMetadataError(localeOverride: .russian).title)
        XCTAssertEqual(title, "Нет подключения к\u{00A0}интернету.")
        // Its own kind, so the window shows it with its own icon.
        XCTAssertEqual(ShatlErrorCatalog.offlineMetadataError().kind, .noConnection)
    }

    func testFileListWaitWithNetworkNamesPeersAndConnection() async {
        let title = await reviewErrorTitle(afterTimeoutWhileOffline: false)
        XCTAssertEqual(title, "Не\u{00A0}удалось получить список файлов.")
    }

    /// Among several, an unreadable link is pasted again into the same
    /// window, which takes it at its end (`DraggedDownloadStoreTests`).
    func testAnUnreadableLinkAmongSeveralIsPastedIntoTheWindow() {
        let error = ShatlErrorCatalog.reviewError(
            for: TorrentEngineError(kind: .invalidMagnet),
            source: AddTorrentSource(kind: .magnet, rawValue: "magnet:?xt=urn:btih:abc"),
            localeOverride: .russian
        )
        let several = plain(error.messageAmongSeveral ?? "")
        XCTAssertTrue(several.hasSuffix("а ссылку скопируйте ещё раз целиком и вставьте в это окно."), several)
    }

    /// Each message of the add window that says to close it has a second
    /// text for a window of several downloads, where "Закрыть окно" gives
    /// way to "Следующая загрузка" and closing would take the others.
    func testMessagesThatCloseTheWindowHaveATextForSeveral() {
        let source = AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/broken.torrent")
        for language in AppLocaleOverride.allCases where language != .system {
            let kinds: [TorrentEngineError.Kind] = [
                .invalidMagnet, .invalidTorrentFile, .draftPreparationLost, .torrentNotFound, .engineFailure,
            ]
            let errors: [TorrentErrorState] = kinds.map { kind in
                ShatlErrorCatalog.reviewError(
                    for: TorrentEngineError(kind: kind),
                    source: source,
                    localeOverride: language
                )
            } + [
                ShatlErrorCatalog.offlineMetadataError(localeOverride: language),
                ShatlErrorCatalog.duplicateDraftError(localeOverride: language),
                ShatlErrorCatalog.duplicateDraftError(torrentName: "Northstar.S01", localeOverride: language),
            ]
            for error in errors {
                let several = error.messageAmongSeveral ?? ""
                XCTAssertFalse(several.isEmpty, "\(language) \(error.kind) has no text for several")
                XCTAssertNotEqual(several, error.message, "\(language) \(error.kind)")
                if language == .russian {
                    XCTAssertTrue(error.message.localizedCaseInsensitiveContains("закройте"), error.message)
                    XCTAssertFalse(several.localizedCaseInsensitiveContains("закройте"), several)
                    XCTAssertTrue(several.contains("другой\u{00A0}загрузке") || several.contains("другой загрузке"), several)
                }
            }
        }
        // Among several, the duplicate's name moves into the title, and the
        // text does not repeat it.
        let named = ShatlErrorCatalog.duplicateDraftError(torrentName: "Northstar.S01", localeOverride: .russian)
        XCTAssertEqual(named.titleAmongSeveral, "Загрузка «Northstar.S01» уже есть.")
        XCTAssertFalse(named.messageAmongSeveral?.contains("Northstar.S01") ?? true)
        let namedInList = ShatlErrorCatalog.duplicateDraftError(
            torrentName: "Northstar.S01",
            showsInList: true,
            localeOverride: .russian
        )
        XCTAssertNotNil(namedInList.titleAmongSeveral)
        XCTAssertFalse(namedInList.messageAmongSeveral?.contains("Northstar.S01") ?? true)
        // With no name, "Показать в списке" serves both, so one text does.
        XCTAssertNil(ShatlErrorCatalog.duplicateDraftError(showsInList: true, localeOverride: .russian).messageAmongSeveral)
        XCTAssertNil(ShatlErrorCatalog.duplicateDraftError(localeOverride: .russian).titleAmongSeveral)
        XCTAssertNil(
            ShatlErrorCatalog.reviewError(
                for: TorrentEngineError(kind: .metadataTimeout),
                source: source,
                localeOverride: .russian
            ).messageAmongSeveral
        )
    }

    /// Among several downloads, a title names the download: a broken file
    /// by its name in Finder, a link by the name it carries.
    func testTitlesAmongSeveralNameTheDownload() {
        let file = ShatlErrorCatalog.reviewError(
            for: TorrentEngineError(kind: .invalidTorrentFile),
            source: AddTorrentSource(kind: .externalOpen, rawValue: "/Users/someone/Downloads/tor164677.torrent"),
            localeOverride: .russian
        )
        XCTAssertEqual(file.titleAmongSeveral, "Не\u{00A0}удалось открыть «tor164677.torrent».")

        let link = ShatlErrorCatalog.reviewError(
            for: TorrentEngineError(kind: .metadataTimeout),
            source: AddTorrentSource(kind: .magnet, rawValue: "magnet:?xt=urn:btih:abc&dn=Northstar+S01"),
            localeOverride: .russian
        )
        XCTAssertTrue(link.titleAmongSeveral?.contains("«Northstar S01»") == true, link.titleAmongSeveral ?? "")

        let bareLink = ShatlErrorCatalog.reviewError(
            for: TorrentEngineError(kind: .invalidMagnet),
            source: AddTorrentSource(kind: .magnet, rawValue: "magnet:?xt=urn:btih:abc"),
            localeOverride: .russian
        )
        XCTAssertNil(bareLink.titleAmongSeveral, "A link without a name keeps the plain title")

        // The network is the trouble, not the download: no name.
        XCTAssertNil(ShatlErrorCatalog.offlineMetadataError(localeOverride: .russian).titleAmongSeveral)

        let long = ShatlErrorCatalog.reviewError(
            for: TorrentEngineError(kind: .engineFailure),
            source: AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/" + String(repeating: "Northstar.S01.", count: 8) + "torrent"),
            localeOverride: .russian
        )
        XCTAssertTrue(long.titleAmongSeveral?.contains("…") == true, "A long name is shortened in the middle")
    }

    private func skipDraft(source: AddTorrentSource) -> AddTorrentDraft {
        AddTorrentDraft(
            source: source,
            originalName: "Northstar.S01",
            suggestedSavePath: "/tmp",
            alias: "",
            stopAfterDownload: false,
            files: [AddTorrentFileOption(name: "Northstar.S01/E01.mkv", sizeBytes: 1_000, fileIndex: 0, isSelected: true)],
            reviewState: .ready,
            errorState: nil
        )
    }

    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// "Не скачивать" names the download, and the file and folder to find it
    /// in again: trackers name files like "tor164677.torrent".
    func testSkipQuestionNamesTheFileAndItsFolder() {
        let file = skipDraft(source: AddTorrentSource(kind: .externalOpen, rawValue: "/tmp/Probe Folder/tor164677.torrent"))
        let question = ShatlErrorCatalog.skipDownloadQuestion(for: file, canSave: true, localeOverride: .russian)
        XCTAssertEqual(plain(question.title), "Не скачивать «Northstar.S01»?")
        XCTAssertTrue(question.message.contains("«tor164677.torrent»"), question.message)
        XCTAssertTrue(question.message.contains("«Probe Folder»"), question.message)
        XCTAssertTrue(plain(question.message).hasSuffix("Если сохранить её в список загрузок, она подождёт там, пока вы её не запустите."))

        let unsavable = ShatlErrorCatalog.skipDownloadQuestion(for: file, canSave: false, localeOverride: .russian)
        XCTAssertFalse(plain(unsavable.message).contains("сохранить"), unsavable.message)

        let link = skipDraft(source: AddTorrentSource(kind: .magnet, rawValue: "magnet:?xt=urn:btih:abc"))
        let linkQuestion = ShatlErrorCatalog.skipDownloadQuestion(for: link, canSave: true, localeOverride: .russian)
        XCTAssertTrue(plain(linkQuestion.message).contains("снова открыть ссылку"), linkQuestion.message)

        // Japanese runs its sentences on without a space.
        let japanese = ShatlErrorCatalog.skipDownloadQuestion(for: link, canSave: true, localeOverride: .japanese)
        XCTAssertFalse(japanese.message.contains("。 "), japanese.message)
    }

    /// Return goes back to the add window, and the button that keeps the
    /// download is there only when there is something to keep. The window's
    /// own button stays "Сохранить в список": there the download is in view.
    func testSkipQuestionGoesBackOnReturnAndOffersToKeepTheDownload() {
        let draft = skipDraft(source: AddTorrentSource(kind: .externalOpen, rawValue: "/tmp/tor164677.torrent"))
        let alert = AddTorrentSkipQuestion.makeAlert(about: draft, canSave: true, localeOverride: .russian)
        XCTAssertEqual(alert.buttons.map { plain($0.title) }, ["Вернуться в окно добавления", "Сохранить загрузку в список", "Не скачивать"])
        XCTAssertEqual(alert.buttons.first?.keyEquivalent, "\r")
        XCTAssertEqual(AddTorrentSkipQuestion.answer(for: .alertFirstButtonReturn, canSave: true), .goBack)
        XCTAssertEqual(AddTorrentSkipQuestion.answer(for: .alertSecondButtonReturn, canSave: true), .saveToList)
        XCTAssertEqual(AddTorrentSkipQuestion.answer(for: .alertThirdButtonReturn, canSave: true), .skip)

        let unsavable = AddTorrentSkipQuestion.makeAlert(about: draft, canSave: false, localeOverride: .russian)
        XCTAssertEqual(unsavable.buttons.map { plain($0.title) }, ["Вернуться в окно добавления", "Не скачивать"])
        XCTAssertEqual(AddTorrentSkipQuestion.answer(for: .alertSecondButtonReturn, canSave: false), .skip)
    }

    /// Closing with work in one download names it, and the file and folder
    /// to open it from again; with several, it counts them.
    func testCloseQuestionNamesOneDownloadAndCountsSeveral() {
        let file = skipDraft(source: AddTorrentSource(kind: .externalOpen, rawValue: "/tmp/Probe Folder/tor164677.torrent"))
        let one = ShatlErrorCatalog.closeWindowQuestion(
            losing: [file],
            savableCount: 1,
            includesWaitingLinks: false,
            localeOverride: .russian
        )
        XCTAssertEqual(plain(one.title), "Загрузка «Northstar.S01» не добавлена")
        XCTAssertTrue(plain(one.message).contains("выбор файлов и настройки пропадут"), one.message)
        XCTAssertTrue(one.message.contains("«tor164677.torrent»") && one.message.contains("«Probe Folder»"), one.message)
        XCTAssertTrue(plain(one.message).hasSuffix("Если сохранить её в список загрузок, она подождёт там, пока вы её не запустите."))

        let link = skipDraft(source: AddTorrentSource(kind: .magnet, rawValue: "magnet:?xt=urn:btih:abc"))
        let two = ShatlErrorCatalog.closeWindowQuestion(
            losing: [file, link],
            savableCount: 2,
            includesWaitingLinks: false,
            localeOverride: .russian
        )
        XCTAssertEqual(plain(two.title), "2 загрузки не добавлены")
        XCTAssertTrue(plain(two.message).hasSuffix("Если сохранить их в список загрузок, они подождут там, пока вы их не запустите."))
        let five = ShatlErrorCatalog.closeWindowQuestion(
            losing: Array(repeating: file, count: 5),
            savableCount: 5,
            includesWaitingLinks: false,
            localeOverride: .russian
        )
        XCTAssertEqual(plain(five.title), "5 загрузок не добавлены")

        let waiting = ShatlErrorCatalog.closeWindowQuestion(
            losing: [file, link],
            savableCount: 1,
            includesWaitingLinks: true,
            localeOverride: .russian
        )
        XCTAssertTrue(plain(waiting.message).hasSuffix("Ссылки, для которых ещё нет списка файлов, сохранить нельзя."))

        let unsavable = ShatlErrorCatalog.closeWindowQuestion(
            losing: [file, link],
            savableCount: 0,
            includesWaitingLinks: true,
            localeOverride: .russian
        )
        XCTAssertFalse(plain(unsavable.message).contains("сохранить"), unsavable.message)
    }

    func testCloseQuestionGoesBackOnReturnAndOffersToKeepWhatWaits() {
        let draft = skipDraft(source: AddTorrentSource(kind: .externalOpen, rawValue: "/tmp/tor164677.torrent"))
        let loss = AddTorrentReviewModel.ClosingLoss(drafts: [draft, draft], savableDrafts: [draft, draft], includesWaitingLinks: false)
        let alert = AddTorrentCloseQuestion.makeAlert(about: loss, localeOverride: .russian)
        XCTAssertEqual(
            alert.buttons.map { plain($0.title) },
            ["Вернуться в окно добавления", "Сохранить загрузки в список", "Закрыть окно добавления"]
        )
        XCTAssertEqual(alert.buttons.first?.keyEquivalent, "\r")
        XCTAssertEqual(AddTorrentCloseQuestion.answer(for: .alertSecondButtonReturn, canSave: true), .saveToList)
        XCTAssertEqual(AddTorrentCloseQuestion.answer(for: .alertThirdButtonReturn, canSave: true), .close)

        // Of two waiting, one has its files: the button saves one.
        let oneSavable = AddTorrentReviewModel.ClosingLoss(drafts: [draft, draft], savableDrafts: [draft], includesWaitingLinks: true)
        XCTAssertEqual(
            AddTorrentCloseQuestion.makeAlert(about: oneSavable, localeOverride: .russian).buttons.map { plain($0.title) },
            ["Вернуться в окно добавления", "Сохранить загрузку в список", "Закрыть окно добавления"]
        )

        let unsavable = AddTorrentReviewModel.ClosingLoss(drafts: [draft, draft], savableDrafts: [], includesWaitingLinks: true)
        let shortAlert = AddTorrentCloseQuestion.makeAlert(about: unsavable, localeOverride: .russian)
        XCTAssertEqual(shortAlert.buttons.map { plain($0.title) }, ["Вернуться в окно добавления", "Закрыть окно добавления"])
        XCTAssertEqual(AddTorrentCloseQuestion.answer(for: .alertSecondButtonReturn, canSave: false), .close)
    }

    /// ⌘Q asks the same question, about leaving Shatl rather than the window:
    /// over the add window "Выйти" alone could mean the window.
    func testQuitQuestionSpeaksOfLeavingShatl() {
        let file = skipDraft(source: AddTorrentSource(kind: .externalOpen, rawValue: "/tmp/Probe Folder/tor164677.torrent"))
        let link = skipDraft(source: AddTorrentSource(kind: .magnet, rawValue: "magnet:?xt=urn:btih:abc"))

        let one = ShatlErrorCatalog.closeWindowQuestion(
            losing: [file],
            savableCount: 1,
            includesWaitingLinks: false,
            whenQuitting: true,
            localeOverride: .russian
        )
        XCTAssertEqual(plain(one.title), "Загрузка «Northstar.S01» не добавлена")
        XCTAssertTrue(plain(one.message).hasPrefix("Если выйти из Shatl, она не появится в списке загрузок"), one.message)
        XCTAssertTrue(one.message.contains("«tor164677.torrent»") && one.message.contains("«Probe Folder»"), one.message)

        let several = ShatlErrorCatalog.closeWindowQuestion(
            losing: [file, link],
            savableCount: 2,
            includesWaitingLinks: false,
            whenQuitting: true,
            localeOverride: .russian
        )
        XCTAssertEqual(plain(several.title), "2 загрузки не добавлены")
        XCTAssertTrue(plain(several.message).hasPrefix("Если выйти из Shatl, они не появятся"), several.message)

        let loss = AddTorrentReviewModel.ClosingLoss(drafts: [file, link], savableDrafts: [file, link], includesWaitingLinks: false)
        let alert = AddTorrentCloseQuestion.makeAlert(about: loss, whenQuitting: true, localeOverride: .russian)
        XCTAssertEqual(
            alert.buttons.map { plain($0.title) },
            ["Вернуться в окно добавления", "Сохранить загрузки в список", "Выйти из Shatl"]
        )
        XCTAssertEqual(alert.buttons.first?.keyEquivalent, "\r")
        XCTAssertEqual(AddTorrentCloseQuestion.answer(for: .alertThirdButtonReturn, canSave: true), .close)
    }

    private func reviewErrorTitle(afterTimeoutWhileOffline isOffline: Bool) async -> String? {
        let engine = FakeTorrentEngine()
        await engine.setPrepareError(TorrentEngineError(kind: .metadataTimeout))
        var preferences = AppPreferences.defaultValue
        preferences.localeOverride = .russian
        let bundle = makeTestStoreBundle(engine: engine, preferences: preferences)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        bundle.store.networkIsOffline = { isOffline }

        bundle.store.continueFromEntry(with: "magnet:?xt=urn:btih:file-list-wait")
        let shown = await waitForCondition {
            bundle.store.currentAddTorrentDraft?.errorState != nil
        }
        XCTAssertTrue(shown)
        return bundle.store.currentAddTorrentDraft?.errorState?.title
    }
}
