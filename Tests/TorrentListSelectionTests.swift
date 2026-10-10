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

/// Several cards are selected as in Finder: a click takes one, Shift a run,
/// ⌘ single ones. A card with an error never shares a selection.
final class TorrentListMultiSelectionTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()
    private let e = UUID()
    /// A card with an error, in the middle of the list.
    private let failed = UUID()

    private var visible: [UUID] { [a, b, failed, c, d, e] }
    private var joinable: Set<UUID> { [a, b, c, d, e] }

    private func click(
        _ selection: inout TorrentListSelection,
        _ id: UUID,
        _ kind: TorrentListSelectionClick = .plain
    ) -> Bool {
        selection.click(id, kind, visible: visible, joinable: joinable)
    }

    func testPlainClickSelectsOneAndASecondClickClearsIt() {
        var selection = TorrentListSelection()

        XCTAssertTrue(click(&selection, a))
        XCTAssertEqual(selection.ids, [a])
        XCTAssertEqual(selection.single, a)

        XCTAssertTrue(click(&selection, b))
        XCTAssertEqual(selection.ids, [b])

        XCTAssertTrue(click(&selection, b))
        XCTAssertTrue(selection.isEmpty)
        XCTAssertNil(selection.single)
    }

    func testPlainClickOnOneOfSeveralKeepsOnlyIt() {
        var selection = TorrentListSelection(only: a)
        _ = click(&selection, c, .range)
        XCTAssertEqual(selection.count, 3)

        XCTAssertTrue(click(&selection, b))
        XCTAssertEqual(selection.ids, [b])
    }

    func testCommandClickAddsAndTakesOutSingleCards() {
        var selection = TorrentListSelection(only: a)

        XCTAssertTrue(click(&selection, c, .toggle))
        XCTAssertTrue(click(&selection, e, .toggle))
        XCTAssertEqual(selection.ids, [a, c, e])
        XCTAssertNil(selection.single)
        XCTAssertEqual(selection.ordered(in: visible), [a, c, e])

        XCTAssertTrue(click(&selection, c, .toggle))
        XCTAssertEqual(selection.ids, [a, e])
    }

    /// The run goes from the card clicked last without Shift, in the order
    /// of the list, and leaves out the card with an error inside it.
    func testShiftClickSelectsTheRunFromTheAnchorWithoutFailedCards() {
        var selection = TorrentListSelection(only: b)

        XCTAssertTrue(click(&selection, d, .range))
        XCTAssertEqual(selection.ids, [b, c, d])

        // The anchor stays: a second Shift click turns the run the other way.
        XCTAssertTrue(click(&selection, a, .range))
        XCTAssertEqual(selection.ids, [a, b])
    }

    func testShiftAndCommandWithNothingSelectedActLikeAPlainClick() {
        var selection = TorrentListSelection()
        XCTAssertTrue(click(&selection, c, .range))
        XCTAssertEqual(selection.ids, [c])

        selection.clear()
        XCTAssertTrue(click(&selection, d, .toggle))
        XCTAssertEqual(selection.ids, [d])
    }

    func testFailedCardRefusesToJoinAndLeavesTheSelectionAsItWas() {
        var selection = TorrentListSelection(only: a)

        XCTAssertFalse(click(&selection, failed, .toggle))
        XCTAssertEqual(selection.ids, [a])
        XCTAssertFalse(click(&selection, failed, .range))
        XCTAssertEqual(selection.ids, [a])
    }

    /// Alone it is selected as before, and takes no company.
    func testFailedCardIsSelectedOnlyAlone() {
        var selection = TorrentListSelection()
        XCTAssertTrue(click(&selection, failed))
        XCTAssertEqual(selection.ids, [failed])

        XCTAssertTrue(click(&selection, b, .toggle))
        XCTAssertEqual(selection.ids, [b])

        _ = click(&selection, failed)
        XCTAssertTrue(click(&selection, d, .range))
        XCTAssertEqual(selection.ids, [d])
    }

    func testArrowsWithoutShiftMoveToTheNeighbouringCardWhateverItIs() {
        var selection = TorrentListSelection(only: b)

        XCTAssertEqual(selection.move(.next, extending: false, visible: visible, joinable: joinable), failed)
        XCTAssertEqual(selection.ids, [failed])
        XCTAssertEqual(selection.move(.next, extending: false, visible: visible, joinable: joinable), c)
        XCTAssertEqual(selection.ids, [c])
    }

    func testShiftArrowsGrowTheRunOverFailedCardsAndShrinkItBack() {
        var selection = TorrentListSelection(only: b)

        XCTAssertEqual(selection.move(.next, extending: true, visible: visible, joinable: joinable), c)
        XCTAssertEqual(selection.ids, [b, c])
        XCTAssertEqual(selection.move(.next, extending: true, visible: visible, joinable: joinable), d)
        XCTAssertEqual(selection.ids, [b, c, d])

        XCTAssertEqual(selection.move(.previous, extending: true, visible: visible, joinable: joinable), c)
        XCTAssertEqual(selection.ids, [b, c])
        XCTAssertEqual(selection.move(.previous, extending: true, visible: visible, joinable: joinable), b)
        XCTAssertEqual(selection.ids, [b])

        // Past the anchor the run grows the other way.
        XCTAssertEqual(selection.move(.previous, extending: true, visible: visible, joinable: joinable), a)
        XCTAssertEqual(selection.ids, [a, b])
        XCTAssertNil(selection.move(.previous, extending: true, visible: visible, joinable: joinable))
        XCTAssertEqual(selection.ids, [a, b])
    }

    func testPlainArrowAfterSeveralSelectsOneFromTheMovingEnd() {
        var selection = TorrentListSelection(only: b)
        _ = selection.move(.next, extending: true, visible: visible, joinable: joinable)
        XCTAssertEqual(selection.ids, [b, c])

        XCTAssertEqual(selection.move(.next, extending: false, visible: visible, joinable: joinable), d)
        XCTAssertEqual(selection.ids, [d])
    }

    func testSelectAllTakesEveryCardThatCanShareASelection() {
        var selection = TorrentListSelection(only: failed)

        selection.selectAll(visible: visible, joinable: joinable)

        XCTAssertEqual(selection.ids, joinable)
        XCTAssertFalse(selection.contains(failed))
    }

    func testCardsHiddenByTheSearchLeaveTheSelection() {
        var selection = TorrentListSelection()
        selection.selectAll(visible: visible, joinable: joinable)

        selection.prune(visible: [a, c, failed], joinable: joinable)

        XCTAssertEqual(selection.ids, [a, c])
    }

    /// A download that fails while selected with others drops out quietly;
    /// selected alone, it stays selected.
    func testCardThatFailsWhileSelectedLeavesASelectionOfSeveral() {
        var several = TorrentListSelection(only: a)
        _ = click(&several, c, .range)
        XCTAssertEqual(several.ids, [a, b, c])

        several.prune(visible: Set(visible), joinable: [a, c, d, e])
        XCTAssertEqual(several.ids, [a, c])

        var alone = TorrentListSelection(only: b)
        alone.prune(visible: Set(visible), joinable: [a, c, d, e])
        XCTAssertEqual(alone.ids, [b])
    }

    func testRemovedCardLeavesTheSelection() {
        var selection = TorrentListSelection(only: a)
        _ = click(&selection, b, .toggle)

        selection.remove(b)
        XCTAssertEqual(selection.ids, [a])
        XCTAssertEqual(selection.single, a)

        selection.remove(a)
        XCTAssertTrue(selection.isEmpty)
    }

    /// One button for several: Start while any is stopped, Stop only when
    /// all of them run.
    func testRunActionStartsWhileAnySelectedDownloadIsStopped() {
        XCTAssertEqual(TorrentListRunAction.action(for: [.downloading, .stopped]), .start)
        XCTAssertEqual(TorrentListRunAction.action(for: [.completed, .seeding]), .start)
        XCTAssertEqual(TorrentListRunAction.action(for: [.downloading, .seeding, .checking]), .stop)
        XCTAssertEqual(TorrentListRunAction.action(for: [.stopped]), .start)
        XCTAssertEqual(TorrentListRunAction.action(for: [.downloading]), .stop)
    }
}
