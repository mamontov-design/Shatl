// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

final class TorrentListSelectionTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()
    private let third = UUID()

    private var visible: [UUID] { [first, second, third] }

    func testArrowsMoveToTheNeighbouringCard() {
        XCTAssertEqual(TorrentListSelectionStep.next.target(from: second, in: visible), third)
        XCTAssertEqual(TorrentListSelectionStep.previous.target(from: second, in: visible), first)
    }

    func testWithoutSelectionDownTakesTheFirstCardAndUpTheLast() {
        XCTAssertEqual(TorrentListSelectionStep.next.target(from: nil, in: visible), first)
        XCTAssertEqual(TorrentListSelectionStep.previous.target(from: nil, in: visible), third)
    }

    /// A card hidden by the search counts as no selection.
    func testHiddenSelectionCountsAsNone() {
        XCTAssertEqual(TorrentListSelectionStep.next.target(from: UUID(), in: visible), first)
        XCTAssertEqual(TorrentListSelectionStep.previous.target(from: UUID(), in: visible), third)
    }

    func testSelectionStaysAtEitherEnd() {
        XCTAssertEqual(TorrentListSelectionStep.previous.target(from: first, in: visible), first)
        XCTAssertEqual(TorrentListSelectionStep.next.target(from: third, in: visible), third)
    }

    func testEmptyListSelectsNothing() {
        XCTAssertNil(TorrentListSelectionStep.next.target(from: nil, in: []))
        XCTAssertNil(TorrentListSelectionStep.previous.target(from: first, in: []))
    }
}
