// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import XCTest
@testable import Shatl

/// Where the list has to stand to show a card: the arithmetic of
/// `TorrentListScrollDriver`, apart from AppKit.
final class TorrentListSightTests: XCTestCase {
    /// Eight cards of 91 pt, 8 pt apart and 8 pt from the edges, in a list
    /// 440 pt tall.
    private func sight(origin: CGFloat, contentHeight: CGFloat = 800) -> TorrentListSight {
        TorrentListSight(
            origin: origin,
            viewportHeight: 440,
            contentHeight: contentHeight,
            topMargin: 8,
            bottomMargin: 8
        )
    }

    private func card(_ number: Int, height: CGFloat = 91) -> CGRect {
        CGRect(x: 8, y: 8 + CGFloat(number - 1) * 99, width: 424, height: height)
    }

    func testCardInSightMovesNothing() {
        XCTAssertNil(sight(origin: 0).origin(showing: card(1)))
        XCTAssertNil(sight(origin: 0).origin(showing: card(4)))
        XCTAssertNil(sight(origin: 360).origin(showing: card(8)))
    }

    func testCardBelowIsShownAtTheBottomWithItsMargin() {
        // The fifth card ends at 495: its margin has to fit above 440.
        XCTAssertEqual(sight(origin: 0).origin(showing: card(5)), 63)
        XCTAssertEqual(sight(origin: 63).origin(showing: card(6)), 162)
        XCTAssertEqual(sight(origin: 0).origin(showing: card(8)), 360)
    }

    func testCardAboveIsShownAtTheTopWithItsMargin() {
        XCTAssertEqual(sight(origin: 360).origin(showing: card(4)), 297)
        XCTAssertEqual(sight(origin: 360).origin(showing: card(1)), 0)
    }

    /// The list scrolls under the toolbar: a card there is not in sight.
    func testToolbarCoversTheTopOfTheList() {
        var underToolbar = TorrentListSight(
            origin: 0,
            viewportHeight: 500,
            contentHeight: 800,
            coveredTop: 52,
            topMargin: 8,
            bottomMargin: 8,
            lowestOrigin: -52
        )
        XCTAssertEqual(underToolbar.lowestOrigin, -52)
        XCTAssertEqual(underToolbar.highestOrigin, 300)
        // The first card lies under the toolbar while the list stands at 0.
        XCTAssertEqual(underToolbar.origin(showing: card(1)), -52)

        underToolbar.origin = -52
        XCTAssertNil(underToolbar.origin(showing: card(1)))
        XCTAssertNil(underToolbar.origin(showing: card(4)))
        XCTAssertEqual(underToolbar.origin(showing: card(5)), 3)
    }

    func testCardTallerThanTheListShowsItsTop() {
        let tall = card(3, height: 600)
        XCTAssertEqual(sight(origin: 0, contentHeight: 1400).origin(showing: tall), 198)
    }

    func testListNeverLeavesItsEnds() {
        XCTAssertEqual(sight(origin: 100).clamped(-40), 0)
        XCTAssertEqual(sight(origin: 100).clamped(900), 360)
        // A list shorter than the window stays at its top.
        XCTAssertEqual(sight(origin: 0, contentHeight: 305).highestOrigin, 0)
    }

    /// A card that expands: the list goes down with the content, a step at a
    /// time, and never past the card's own top.
    func testListFollowsAGrowingCardAsFarAsTheContentReaches() {
        let expanded = card(8, height: 152)

        // The content has grown by 20 pt of the card's 61 so far.
        XCTAssertEqual(sight(origin: 360, contentHeight: 820).origin(following: expanded), 380)
        // All of it: the card's lower edge and its margin are in sight.
        XCTAssertEqual(sight(origin: 380, contentHeight: 861).origin(following: expanded), 421)
        XCTAssertNil(sight(origin: 421, contentHeight: 861).origin(following: expanded))

        // In the middle of the window nothing has to move.
        XCTAssertNil(sight(origin: 0, contentHeight: 861).origin(following: card(2, height: 152)))

        // A card taller than the list keeps its top in sight.
        let tall = card(2, height: 700)
        XCTAssertEqual(sight(origin: 0, contentHeight: 1500).origin(following: tall), 99)
    }

    /// A card partly out of sight when it began to grow: that part is not
    /// taken in one step, the list is held back by what is left of it.
    func testListCoversWhatWasOutOfSightAStepAtATime() {
        // The last card is cut by 40 pt, and its margin is 8 more.
        let last = card(8)
        let cut = sight(origin: 312)
        XCTAssertEqual(cut.origin(following: last), 360)
        // Nothing of the way covered yet: the list stays where it is.
        XCTAssertNil(cut.origin(following: last, heldBackBy: 48))
        // Half of it.
        XCTAssertEqual(cut.origin(following: last, heldBackBy: 24), 336)

        // A card in the middle is laid out at its full height at once:
        // held back, the list does not take that in one step either.
        let expanded = card(5, height: 152)
        let middle = sight(origin: 63, contentHeight: 861)
        XCTAssertEqual(middle.origin(following: expanded), 124)
        XCTAssertEqual(middle.origin(following: expanded, heldBackBy: 50), 74)
        // Held back never means going up.
        XCTAssertNil(middle.origin(following: expanded, heldBackBy: 80))
    }

    /// Cards have left and room under the content held the list in place:
    /// where the list belongs once the room is gone.
    func testListGlidesToTheEndItHasWithoutTheRoom() {
        // The last of eight cards left: 701 pt of content plus 800 of room.
        XCTAssertEqual(sight(origin: 360, contentHeight: 1501).origin(afterTakingAway: 800), 261)
        // The list was not past its new end.
        XCTAssertNil(sight(origin: 100, contentHeight: 1501).origin(afterTakingAway: 800))
        // What is left is shorter than the window: back to the top.
        XCTAssertEqual(sight(origin: 60, contentHeight: 305 + 500).origin(afterTakingAway: 500), 0)
    }
}

/// The list in a window: the cases the owner reported in October 2026.
@MainActor
final class TorrentListScrollFollowTests: XCTestCase {
    private struct HostedList {
        let store: AppStore
        let records: [TorrentRecord]
        let window: NSWindow
        let scroll: NSScrollView

        var offset: CGFloat { scroll.contentView.bounds.origin.y }
        var end: CGFloat {
            max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
        }
    }

    private func allViews(in root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap { allViews(in: $0) }
    }

    private func makeList(cards: Int = 8) async throws -> HostedList {
        let records = (0..<cards).map { index in
            makeTestRecord(originalName: "Download \(index + 1)", status: .stopped, progress: 0.3)
        }
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: records)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        await bundle.sessionStore.replaceAllRecordsForTesting(from: records)

        let size = NSSize(width: 440, height: 440)
        let hosting = NSHostingView(
            rootView: TorrentListView(searchText: "", bottomContentPadding: 8, onRemoveSelected: {})
                .environmentObject(bundle.store)
                .frame(width: size.width, height: size.height)
        )
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        window.makeKey()
        try await Task.sleep(for: .milliseconds(900))

        let scroll = try XCTUnwrap(allViews(in: hosting).compactMap { $0 as? NSScrollView }.first)
        let list = HostedList(store: bundle.store, records: records, window: window, scroll: scroll)
        XCTAssertGreaterThan(list.end, 40, "The list must be taller than its window for this to test anything")
        return list
    }

    private func scrollToEnd(_ list: HostedList, short: CGFloat = 0) async throws {
        list.scroll.contentView.scroll(to: NSPoint(x: 0, y: list.end - short))
        list.scroll.reflectScrolledClipView(list.scroll.contentView)
        try await Task.sleep(for: .milliseconds(300))
    }

    /// Where the list stands, read as often as the main thread lets go, for
    /// `duration`.
    private func offsets(of list: HostedList, for duration: TimeInterval) async throws -> [(time: TimeInterval, offset: CGFloat)] {
        var samples: [(time: TimeInterval, offset: CGFloat)] = []
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < duration {
            samples.append((CACurrentMediaTime() - start, list.offset))
            try await Task.sleep(for: .milliseconds(4))
        }
        return samples
    }

    /// Every move of the list, with the content's height at the time.
    @MainActor
    private final class Moves {
        private(set) var all: [(offset: CGFloat, contentHeight: CGFloat)] = []
        private var observation: NSObjectProtocol?

        init(of scroll: NSScrollView) {
            let clip = scroll.contentView
            clip.postsBoundsChangedNotifications = true
            observation = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clip,
                queue: nil
            ) { [weak self, weak scroll] _ in
                MainActor.assumeIsolated {
                    guard let self, let scroll else { return }
                    self.all.append((scroll.contentView.bounds.origin.y, scroll.documentView?.frame.height ?? 0))
                }
            }
        }

        func stop() {
            if let observation {
                NotificationCenter.default.removeObserver(observation)
            }
            observation = nil
        }

        /// How far the list went from `offset` while the content was still
        /// `contentHeight` tall: before the card began to grow on screen.
        func farthest(from offset: CGFloat, whileContentIs contentHeight: CGFloat) -> CGFloat {
            all.filter { abs($0.contentHeight - contentHeight) < 0.01 }
                .map { abs($0.offset - offset) }
                .max() ?? 0
        }
    }

    /// The longest way the list went between two readings beyond what a
    /// glide covers in that time. A glide here is at its fastest under
    /// 1500 pt a second; a jump takes tens of points in no time at all.
    private func longestJump(in samples: [(time: TimeInterval, offset: CGFloat)]) -> CGFloat {
        zip(samples, samples.dropFirst())
            .map { before, after in
                abs(after.offset - before.offset) - 1500 * CGFloat(after.time - before.time)
            }
            .max() ?? 0
    }

    private func pressArrow(down: Bool, in window: NSWindow) throws {
        let characters = down ? "\u{F701}" : "\u{F700}"
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.numericPad, .function],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: down ? 125 : 126
        ))
        window.sendEvent(event)
    }

    /// Arrows pressed as fast as a held key repeats, over a list that is
    /// drawn anew all the while, as running downloads draw it. An animated
    /// `scrollTo` lost most of these: the selection went on and the list
    /// stayed behind.
    func testArrowsPressedFastOverAChangingListKeepTheSelectedCardInSight() async throws {
        let list = try await makeList()
        defer { list.window.orderOut(nil) }
        let store = list.store

        let redrawing = Task { @MainActor in
            var step = 0
            while !Task.isCancelled {
                step += 1
                var changed = store.torrents
                for index in changed.indices {
                    changed[index].progress = min(0.99, 0.3 + Double(step) * 0.001)
                }
                store.torrents = changed
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
        defer { redrawing.cancel() }

        for _ in 0..<8 {
            try pressArrow(down: true, in: list.window)
            try await Task.sleep(for: .milliseconds(40))
        }
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(store.selectedTorrentID, list.records[7].id)
        XCTAssertEqual(list.offset, list.end, accuracy: 1, "The last card is selected: the list stands at its end")

        for _ in 0..<8 {
            try pressArrow(down: false, in: list.window)
            try await Task.sleep(for: .milliseconds(40))
        }
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(store.selectedTorrentID, list.records[0].id)
        XCTAssertEqual(list.offset, 0, accuracy: 1, "The first card is selected: the list stands at its top")
    }

    /// The content loses a leaving card's height in one frame, and the list
    /// was pushed to its new end in that frame. It glides there now.
    func testRemovingTheLastCardGlidesTheListToItsNewEnd() async throws {
        let list = try await makeList()
        defer { list.window.orderOut(nil) }
        try await scrollToEnd(list)
        let before = list.offset

        await list.store.removeTorrent(id: list.records[7].id, policy: .removeFromListOnly)
        try await Task.sleep(for: .milliseconds(60))
        // A whole card is 99 pt; a jump would have covered it by now.
        XCTAssertGreaterThan(list.offset, before - 40, "The list has barely set off")

        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(list.store.torrents.count, 7)
        XCTAssertEqual(list.offset, list.end, accuracy: 1)
        XCTAssertLessThan(list.offset, before - 60, "The list has come down by the card that left")
    }

    /// A list barely taller than its window, at its end, and a card leaves
    /// its middle: what is left fits the window. The list went to its top
    /// in one frame in the owner's window; it glides there.
    func testRemovingAMiddleCardFromABarelyScrolledListGlidesItToItsTop() async throws {
        let list = try await makeList(cards: 5)
        defer { list.window.orderOut(nil) }
        try await scrollToEnd(list)
        let before = list.offset
        XCTAssertGreaterThan(before, 40)

        await list.store.removeTorrent(id: list.records[3].id, policy: .removeFromListOnly)
        let samples = try await offsets(of: list, for: 0.9)

        XCTAssertEqual(list.store.torrents.count, 4)
        XCTAssertEqual(list.offset, 0, accuracy: 1, "Four cards fit the window: the list stands at its top")
        XCTAssertLessThan(longestJump(in: samples), 15, "The list came to its top in a glide")
        let early = try XCTUnwrap(samples.last { $0.time < 0.08 })
        XCTAssertGreaterThan(early.offset, before - 25, "The list has barely set off")
    }

    /// A card cut by the window's lower edge, then expanded: the list went
    /// down to show all of it in one step, and only then did the card grow.
    func testExpandingACardCutByTheWindowBringsItIntoSightWithoutAJump() async throws {
        let list = try await makeList()
        defer { list.window.orderOut(nil) }
        // The last card shows its top 21 pt of 91.
        try await scrollToEnd(list, short: 78)
        let before = list.offset
        let contentBefore = try XCTUnwrap(list.scroll.documentView).frame.height
        let moves = Moves(of: list.scroll)
        defer { moves.stop() }

        withAnimation(ShatlMotion.cardLayout) {
            list.store.toggleExpanded(for: list.records[7].id)
        }
        let samples = try await offsets(of: list, for: 0.9)

        XCTAssertGreaterThan(list.end, before + 78 + 20, "The card has grown, and the content with it")
        XCTAssertEqual(list.offset, list.end, accuracy: 1, "All of the card is in sight")
        XCTAssertLessThan(
            moves.farthest(from: before, whileContentIs: contentBefore), 1,
            "The list does not set off before the card begins to grow"
        )
        XCTAssertGreaterThan(moves.all.count, 8, "The list went down a step at a time")
        XCTAssertLessThan(longestJump(in: samples), 15, "The list went down in one move with the card")
    }

    /// A card in the middle of the list, cut by the window's lower edge.
    func testExpandingAMiddleCardCutByTheWindowBringsItIntoSightWithoutAJump() async throws {
        let list = try await makeList()
        defer { list.window.orderOut(nil) }
        // The fifth card of eight ends at 495; the window shows down to 440.
        list.scroll.contentView.scroll(to: .zero)
        list.scroll.reflectScrolledClipView(list.scroll.contentView)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(list.offset, 0)
        let contentBefore = try XCTUnwrap(list.scroll.documentView).frame.height
        let moves = Moves(of: list.scroll)
        defer { moves.stop() }

        withAnimation(ShatlMotion.cardLayout) {
            list.store.toggleExpanded(for: list.records[4].id)
        }
        let samples = try await offsets(of: list, for: 0.9)

        XCTAssertGreaterThan(list.offset, 63 + 20, "The card is in sight, grown")
        XCTAssertLessThan(list.offset, list.end - 100, "And the list has not gone to its end")
        XCTAssertLessThan(
            moves.farthest(from: 0, whileContentIs: contentBefore), 1,
            "The list does not set off before the card begins to grow"
        )
        XCTAssertGreaterThan(moves.all.count, 8, "The list went down a step at a time")
        XCTAssertLessThan(longestJump(in: samples), 15, "The list went down in one move with the card")
    }

    /// The last card is expanded, and the card above it expands in its
    /// place. The card that collapses still told where it was on its way
    /// out, and the list went after it, to its end.
    func testExpandingACardAboveAnExpandedOneFollowsTheCardThatExpands() async throws {
        let list = try await makeList()
        defer { list.window.orderOut(nil) }
        withAnimation(ShatlMotion.cardLayout) {
            list.store.toggleExpanded(for: list.records[7].id)
        }
        try await Task.sleep(for: .milliseconds(900))
        // The seventh card will end at 754, 21 pt under the window's edge
        // with its margin; the list's end is 99 pt farther.
        try await scrollToEnd(list, short: 120)
        let before = list.offset
        let moves = Moves(of: list.scroll)
        defer { moves.stop() }

        withAnimation(ShatlMotion.cardLayout) {
            list.store.toggleExpanded(for: list.records[6].id)
        }
        try await Task.sleep(for: .milliseconds(900))

        XCTAssertEqual(list.store.expandedTorrentID, list.records[6].id)
        XCTAssertEqual(list.offset, before + 21, accuracy: 1.5, "The card that expanded is in sight")
        XCTAssertLessThan(moves.all.map(\.offset).max() ?? 0, before + 30, "The list never went after the card that collapsed")
    }

    /// A card expanded at the bottom of the list grew out of the window.
    func testExpandingTheLastCardKeepsItInSight() async throws {
        let list = try await makeList()
        defer { list.window.orderOut(nil) }
        try await scrollToEnd(list)
        let before = list.offset

        withAnimation(ShatlMotion.cardLayout) {
            list.store.toggleExpanded(for: list.records[7].id)
        }
        try await Task.sleep(for: .milliseconds(900))

        XCTAssertGreaterThan(list.end, before + 20, "The card has grown, and the content with it")
        XCTAssertEqual(list.offset, list.end, accuracy: 1, "The list has followed the card down")
    }
}
