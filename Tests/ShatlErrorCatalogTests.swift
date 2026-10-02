// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

final class ShatlErrorCatalogTests: XCTestCase {
    func testTorrentActionErrorOffersRetryAndRemoveFromListForGenericFailure() {
        let state = ShatlErrorCatalog.torrentActionError(
            for: TorrentEngineError(kind: .engineFailure, debugReason: "synthetic")
        )

        XCTAssertEqual(state.kind, .engineFailure)
        XCTAssertTrue(state.recoveryOptions.contains(.removeFromList))
    }

    /// A handle the engine lost is restored from the saved torrent by
    /// "Повторить"; only a lost saved torrent is a dead end.
    func testTorrentActionErrorOffersRetryForAHandleTheEngineLost() {
        let state = ShatlErrorCatalog.torrentActionError(
            for: TorrentEngineError(kind: .torrentNotFound, debugReason: "missing handle")
        )

        XCTAssertEqual(state.kind, .engineFailure)
        XCTAssertEqual(state.recoveryOptions, [.retry, .removeFromList])
    }

    func testMissingSavedTorrentOffersOnlyRemoveFromList() {
        let state = ShatlErrorCatalog.missingTorrentError()

        XCTAssertEqual(state.kind, .torrentNotFound)
        XCTAssertEqual(state.recoveryOptions, [.removeFromList])
    }

    func testRuntimeSnapshotErrorOffersRetryAndRemoveFromList() {
        let state = ShatlErrorCatalog.runtimeSnapshotError(debugReason: "snapshot failed")

        XCTAssertEqual(state.kind, .engineFailure)
        XCTAssertEqual(state.recoveryOptions, [.retry, .removeFromList])
    }
}
