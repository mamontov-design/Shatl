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
