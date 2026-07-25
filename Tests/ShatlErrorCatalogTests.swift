// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

final class ShatlErrorCatalogTests: XCTestCase {
    func testTorrentActionErrorOffersRemoveFromListForGenericRuntimeFailure() {
        let state = ShatlErrorCatalog.torrentActionError(
            for: TorrentEngineError(kind: .engineFailure, debugReason: "synthetic")
        )

        XCTAssertEqual(state.kind, .engineFailure)
        XCTAssertTrue(state.recoveryOptions.contains(.removeFromList))
    }

    func testTorrentActionErrorOffersRemoveFromListForTorrentNotFound() {
        let state = ShatlErrorCatalog.torrentActionError(
            for: TorrentEngineError(kind: .torrentNotFound, debugReason: "missing handle")
        )

        XCTAssertEqual(state.kind, .torrentNotFound)
        XCTAssertTrue(state.recoveryOptions.contains(.removeFromList))
    }

    func testRuntimeSnapshotErrorOffersRemoveFromList() {
        let state = ShatlErrorCatalog.runtimeSnapshotError(debugReason: "snapshot failed")

        XCTAssertEqual(state.kind, .engineFailure)
        XCTAssertTrue(state.recoveryOptions.contains(.removeFromList))
    }
}
