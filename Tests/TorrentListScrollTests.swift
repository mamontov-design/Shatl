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
            bottomMargin: 8
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

    private func makeList() async throws -> HostedList {
        let records = (0..<8).map { index in
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
        XCTAssertGreaterThan(list.end, 200, "The list must be taller than its window for this to test anything")
        return list
    }

    private func scrollToEnd(_ list: HostedList) async throws {
        list.scroll.contentView.scroll(to: NSPoint(x: 0, y: list.end))
        list.scroll.reflectScrolledClipView(list.scroll.contentView)
        try await Task.sleep(for: .milliseconds(300))
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
