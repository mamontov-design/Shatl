// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// A duplicate names the torrent that is already in the list, shortened in
/// the middle so a long name stays readable in the message.
final class ShatlMessageTextTests: XCTestCase {
    func testShortNamesStayWhole() {
        XCTAssertEqual(ShatlErrorCatalog.shortenedTorrentName("Northstar.S01"), "Northstar.S01")
        let forty = String(repeating: "a", count: 40)
        XCTAssertEqual(ShatlErrorCatalog.shortenedTorrentName(forty), forty)
    }

    func testLongNamesKeepTheirStartAndEnd() {
        let name = "Northstar.S01.1080p.WEB-DL.DDP5.1.H.264-GROUP"
        let shortened = ShatlErrorCatalog.shortenedTorrentName(name)

        XCTAssertEqual(shortened, "Northstar.S01.1080p.WEB-DL…1.H.264-GROUP")
        XCTAssertEqual(shortened.count, 40)
    }

    /// Every error of the add window titles its message block with a full
    /// stop, in every language.
    func testAddWindowErrorTitlesEndWithAFullStop() {
        let source = AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/test.torrent")
        let kinds: [TorrentEngineError.Kind] = [
            .notImplemented, .invalidMagnet, .invalidTorrentFile, .duplicateTorrent,
            .metadataTimeout, .draftPreparationLost, .torrentNotFound, .engineFailure,
        ]
        for locale in AppLocaleOverride.allCases where locale != .system {
            for kind in kinds {
                let title = ShatlErrorCatalog.reviewError(
                    for: TorrentEngineError(kind: kind),
                    source: source,
                    localeOverride: locale
                ).title
                XCTAssertTrue(title.hasSuffix(".") || title.hasSuffix("。"), "\(locale) \(kind): \(title)")
            }
        }
    }

    /// A torrent already running is caught by the engine while the add window
    /// prepares it; the engine's error carries the name to the message.
    func testDuplicateFoundByTheEngineNamesTheTorrent() {
        let source = AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/test.torrent")
        let named = ShatlErrorCatalog.reviewError(
            for: TorrentEngineError(kind: .duplicateTorrent, torrentName: "Northstar.S01"),
            source: source,
            localeOverride: .russian
        )
        XCTAssertEqual(named.message, "Торрент «Northstar.S01» уже добавлен в\u{00A0}список загрузок.")

        let unnamed = ShatlErrorCatalog.reviewError(
            for: TorrentEngineError(kind: .duplicateTorrent),
            source: source,
            localeOverride: .russian
        )
        XCTAssertEqual(unnamed.message, "Этот торрент уже добавлен в\u{00A0}список загрузок.")
    }

    func testDuplicateMessageNamesTheTorrent() {
        let named = ShatlErrorCatalog.duplicateDraftError(torrentName: "Northstar.S01", localeOverride: .russian)
        XCTAssertEqual(named.message, "Торрент «Northstar.S01» уже добавлен в\u{00A0}список загрузок.")
        XCTAssertEqual(named.title, "Такая загрузка уже есть.")

        for name in [nil, "", "  "] as [String?] {
            let unnamed = ShatlErrorCatalog.duplicateDraftError(torrentName: name, localeOverride: .russian)
            XCTAssertEqual(unnamed.message, "Этот торрент уже добавлен в\u{00A0}список загрузок.", "\(String(describing: name))")
        }
    }
}
