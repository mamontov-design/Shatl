// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// Several cards are selected as in Finder: a click takes one, Shift a run,
/// ⌘ single ones. A card with an error never shares a selection.
final class TorrentListMultiSelectionTests: XCTestCase {
    /// A card still being added, at the top of the list.
    private let adding = UUID()
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()
    private let e = UUID()
    /// A card with an error, in the middle of the list.
    private let failed = UUID()

    private var visible: [UUID] { [adding, a, b, failed, c, d, e] }
    private var joinable: Set<UUID> { [a, b, c, d, e] }
    private var alone: Set<UUID> { [adding] }

    private func click(
        _ selection: inout TorrentListSelection,
        _ id: UUID,
        _ kind: TorrentListSelectionClick = .plain
    ) -> Bool {
        selection.click(id, kind, visible: visible, joinable: joinable, alone: alone)
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
        XCTAssertEqual(selection.order, [b])
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
    func testShiftClickAddsTheRunFromTheAnchorWithoutFailedCards() {
        var selection = TorrentListSelection(only: b)

        XCTAssertTrue(click(&selection, d, .range))
        XCTAssertEqual(selection.ids, [b, c, d])

        // The anchor stays: a second Shift click adds the run on its other
        // side.
        XCTAssertTrue(click(&selection, a, .range))
        XCTAssertEqual(selection.ids, [a, b, c, d])
    }

    /// Cards selected apart from the run stay selected.
    func testShiftClickKeepsCardsSelectedWithCommand() {
        var selection = TorrentListSelection(only: a)
        _ = click(&selection, c, .toggle)

        XCTAssertTrue(click(&selection, e, .range))
        XCTAssertEqual(selection.ids, [a, c, d, e])
    }

    /// As in Finder: Shift takes a selected card out, the others stay.
    func testShiftClickOnASelectedCardTakesItOut() {
        var selection = TorrentListSelection(only: a)
        _ = click(&selection, d, .range)
        XCTAssertEqual(selection.ids, [a, b, c, d])

        XCTAssertTrue(click(&selection, c, .range))
        XCTAssertEqual(selection.ids, [a, b, d])

        // Clicked again, it comes back and nothing else changes.
        XCTAssertTrue(click(&selection, c, .range))
        XCTAssertEqual(selection.ids, [a, b, c, d])

        // The card the run started from can be taken out too; the next run
        // then starts from the card selected last.
        XCTAssertTrue(click(&selection, a, .range))
        XCTAssertEqual(selection.ids, [b, c, d])
        XCTAssertTrue(click(&selection, e, .range))
        XCTAssertEqual(selection.ids, [b, c, d, e])
    }

    func testShiftClickOnTheOnlySelectedCardClearsTheSelection() {
        var selection = TorrentListSelection(only: b)
        XCTAssertTrue(click(&selection, b, .range))
        XCTAssertTrue(selection.isEmpty)

        _ = click(&selection, adding)
        XCTAssertTrue(click(&selection, adding, .range))
        XCTAssertTrue(selection.isEmpty)
    }

    /// The numbers on the cards follow this order: the card clicked last
    /// comes last, wherever it is in the list.
    func testOrderFollowsTheClicksAndNotTheList() {
        var selection = TorrentListSelection(only: e)
        _ = click(&selection, a, .toggle)
        _ = click(&selection, b, .toggle)
        XCTAssertEqual(selection.order, [e, a, b])

        // A card taken out closes the gap.
        _ = click(&selection, a, .toggle)
        XCTAssertEqual(selection.order, [e, b])

        // A run is counted from its start, so the clicked card comes last.
        var run = TorrentListSelection(only: d)
        _ = click(&run, a, .range)
        XCTAssertEqual(run.order, [d, c, b, a])

        var all = TorrentListSelection(only: d)
        all.selectAll(visible: visible, joinable: joinable)
        XCTAssertEqual(all.order, [a, b, c, d, e])
    }

    func testShiftAndCommandWithNothingSelectedActLikeAPlainClick() {
        var selection = TorrentListSelection()
        XCTAssertTrue(click(&selection, c, .range))
        XCTAssertEqual(selection.ids, [c])

        selection.clear()
        XCTAssertTrue(click(&selection, d, .toggle))
        XCTAssertEqual(selection.ids, [d])
    }

    /// A card with an error acts through its own buttons, so a click on it
    /// selects nothing and leaves the selection as it was.
    func testCardWithAnErrorIsNeverSelected() {
        var selection = TorrentListSelection()
        XCTAssertTrue(click(&selection, failed))
        XCTAssertTrue(selection.isEmpty)
        XCTAssertTrue(click(&selection, failed, .toggle))
        XCTAssertTrue(click(&selection, failed, .range))
        XCTAssertTrue(selection.isEmpty)

        _ = click(&selection, a)
        _ = click(&selection, c, .toggle)
        XCTAssertTrue(click(&selection, failed))
        XCTAssertEqual(selection.ids, [a, c])
    }

    /// One click on it is silent; the second of a quick pair is answered, so
    /// the first is not taken for a broken selection.
    func testCardWithAnErrorAnswersASecondClick() {
        var selection = TorrentListSelection()
        XCTAssertTrue(
            selection.click(failed, .plain, isRepeated: false, visible: visible, joinable: joinable, alone: alone)
        )
        XCTAssertFalse(
            selection.click(failed, .plain, isRepeated: true, visible: visible, joinable: joinable, alone: alone)
        )
        XCTAssertTrue(selection.isEmpty)

        // The selection stays as it was, and other cards take a second
        // click as any other.
        _ = click(&selection, a)
        XCTAssertFalse(
            selection.click(failed, .plain, isRepeated: true, visible: visible, joinable: joinable, alone: alone)
        )
        XCTAssertEqual(selection.ids, [a])
        XCTAssertTrue(
            selection.click(a, .plain, isRepeated: true, visible: visible, joinable: joinable, alone: alone)
        )
        XCTAssertTrue(selection.isEmpty)
    }

    /// Clicked with ⌘ or Shift while others are selected, it refuses aloud.
    func testCardWithAnErrorRefusesToJoinAndLeavesTheSelectionAsItWas() {
        var selection = TorrentListSelection(only: a)

        XCTAssertFalse(click(&selection, failed, .toggle))
        XCTAssertEqual(selection.ids, [a])
        XCTAssertFalse(click(&selection, failed, .range))
        XCTAssertEqual(selection.ids, [a])

        // A card being added is nothing to join, so there is no refusal.
        _ = click(&selection, adding)
        XCTAssertTrue(click(&selection, failed, .toggle))
        XCTAssertEqual(selection.ids, [adding])
    }

    /// Its cancelling lives in the toolbar, so it is selected, but takes no
    /// company.
    func testCardBeingAddedIsSelectedOnlyAlone() {
        var selection = TorrentListSelection()
        XCTAssertTrue(click(&selection, adding))
        XCTAssertEqual(selection.ids, [adding])

        XCTAssertTrue(click(&selection, b, .toggle))
        XCTAssertEqual(selection.ids, [b])

        XCTAssertFalse(click(&selection, adding, .toggle))
        XCTAssertFalse(click(&selection, adding, .range))
        XCTAssertEqual(selection.ids, [b])

        _ = click(&selection, adding)
        XCTAssertTrue(click(&selection, d, .range))
        XCTAssertEqual(selection.ids, [d])
    }

    func testSelectAllTakesEveryCardThatCanShareASelection() {
        var selection = TorrentListSelection(only: adding)

        selection.selectAll(visible: visible, joinable: joinable)

        XCTAssertEqual(selection.ids, joinable)
        XCTAssertFalse(selection.contains(adding))
        XCTAssertFalse(selection.contains(failed))
    }

    func testCardsHiddenByTheSearchLeaveTheSelection() {
        var selection = TorrentListSelection()
        selection.selectAll(visible: visible, joinable: joinable)

        selection.prune(visible: [a, c, failed], joinable: joinable, alone: alone)

        XCTAssertEqual(selection.ids, [a, c])
    }

    /// A download that fails while selected drops out quietly, alone or
    /// among others.
    func testCardThatFailsWhileSelectedLeavesTheSelection() {
        var several = TorrentListSelection(only: a)
        _ = click(&several, c, .range)
        XCTAssertEqual(several.ids, [a, b, c])

        several.prune(visible: Set(visible), joinable: [a, c, d, e], alone: alone)
        XCTAssertEqual(several.ids, [a, c])

        var single = TorrentListSelection(only: b)
        single.prune(visible: Set(visible), joinable: [a, c, d, e], alone: alone)
        XCTAssertTrue(single.isEmpty)

        var beingAdded = TorrentListSelection(only: adding)
        beingAdded.prune(visible: Set(visible), joinable: joinable, alone: alone)
        XCTAssertEqual(beingAdded.ids, [adding])
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
