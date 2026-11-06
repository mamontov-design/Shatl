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
