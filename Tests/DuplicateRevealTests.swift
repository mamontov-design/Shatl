// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// A duplicate in the add window offers to show the download it repeats:
/// the window closes, and the list selects that download and scrolls to it.
@MainActor
final class DuplicateRevealTests: XCTestCase {
    private var preferences: AppPreferences {
        var preferences = AppPreferences.defaultValue
        preferences.localeOverride = .russian
        return preferences
    }

    func testDuplicateDraftShowsTheDownloadInTheList() async throws {
        let engine = FakeTorrentEngine()
        let record = makeTestRecord(infoHash: "test-info-hash")
        let other = makeTestRecord(infoHash: "other-hash", originalName: "Other")
        let bundle = makeTestStoreBundle(engine: engine, torrents: [other, record], preferences: preferences)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        bundle.store.continueFromEntry(with: "magnet:?xt=urn:btih:duplicate")
        let shown = await waitForCondition {
            bundle.store.currentAddTorrentDraft?.errorState?.kind == .duplicateTorrent
        }
        XCTAssertTrue(shown)
        XCTAssertEqual(bundle.store.addTorrentDuplicateID, record.id)
        let message = try XCTUnwrap(bundle.store.currentAddTorrentDraft?.errorState?.message)
        XCTAssertTrue(message.contains("«Показать в\u{00A0}списке»"), message)

        bundle.store.showAddTorrentDuplicateInList()

        XCTAssertNil(bundle.store.presentedModal)
        XCTAssertNil(bundle.store.addTorrentDuplicateID)
        XCTAssertEqual(bundle.store.selectedTorrentID, record.id)
        XCTAssertEqual(bundle.store.listRevealRequest?.torrentID, record.id)
    }

    /// The engine catches a torrent already running and names its info hash.
    func testDuplicateFoundByTheEngineIsFoundByInfoHash() async {
        let engine = FakeTorrentEngine()
        let record = makeTestRecord(infoHash: "running-hash")
        await engine.setPrepareError(
            TorrentEngineError(kind: .duplicateTorrent, torrentName: "Northstar.S01", infoHash: "RUNNING-HASH")
        )
        let other = makeTestRecord(infoHash: "other-hash", originalName: "Other")
        let bundle = makeTestStoreBundle(engine: engine, torrents: [other, record], preferences: preferences)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        bundle.store.continueFromEntry(with: "magnet:?xt=urn:btih:running")
        let shown = await waitForCondition {
            bundle.store.currentAddTorrentDraft?.errorState?.kind == .duplicateTorrent
        }
        XCTAssertTrue(shown)
        XCTAssertEqual(bundle.store.addTorrentDuplicateID, record.id)
    }

    /// With nothing to show, the window keeps Close alone and the message
    /// asks to find the download by hand.
    func testUnknownDuplicateKeepsTheMessageWithoutTheButton() async throws {
        let engine = FakeTorrentEngine()
        await engine.setPrepareError(
            TorrentEngineError(kind: .duplicateTorrent, torrentName: "Northstar.S01", infoHash: "unknown-hash")
        )
        let bundle = makeTestStoreBundle(engine: engine, preferences: preferences)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        bundle.store.continueFromEntry(with: "magnet:?xt=urn:btih:unknown")
        let shown = await waitForCondition {
            bundle.store.currentAddTorrentDraft?.errorState?.kind == .duplicateTorrent
        }
        XCTAssertTrue(shown)
        XCTAssertNil(bundle.store.addTorrentDuplicateID)
        let message = try XCTUnwrap(bundle.store.currentAddTorrentDraft?.errorState?.message)
        XCTAssertTrue(message.contains("закройте окно"), message)
    }

    /// A list of one shows its only download as soon as the window closes;
    /// there is nothing to show, so Close stays alone.
    func testSingleDownloadNeedsNoShowing() async throws {
        let engine = FakeTorrentEngine()
        let record = makeTestRecord(infoHash: "test-info-hash")
        let bundle = makeTestStoreBundle(engine: engine, torrents: [record], preferences: preferences)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        bundle.store.continueFromEntry(with: "magnet:?xt=urn:btih:single")
        let shown = await waitForCondition {
            bundle.store.currentAddTorrentDraft?.errorState?.kind == .duplicateTorrent
        }
        XCTAssertTrue(shown)
        XCTAssertNil(bundle.store.addTorrentDuplicateID)
        let message = try XCTUnwrap(bundle.store.currentAddTorrentDraft?.errorState?.message)
        XCTAssertTrue(message.contains("закройте окно"), message)
    }

    func testInListMessagesExistInEveryLanguage() {
        for language in AppLocaleOverride.allCases where language != .system {
            for key in ["add_torrent.error.duplicate.in_list.message", "add_torrent.error.duplicate.in_list.named_message"] {
                let message = L10n.string(key, localeOverride: language)
                XCTAssertNotEqual(message, key, "\(language) \(key)")
                // The message names the button exactly as it is labelled.
                let button = L10n.string("add_torrent.review.show_in_list", localeOverride: language)
                XCTAssertTrue(message.contains(button), "\(language) \(key): \(message)")
            }
        }
    }
}
