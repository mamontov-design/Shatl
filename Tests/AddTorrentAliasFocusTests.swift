// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import XCTest
@testable import Shatl

/// macOS focuses the first text field in a window as the window is shown. A
/// `.torrent` file is read at once, so its files, and the alias field among
/// them, are in the add window before the window is on screen: the field
/// came up focused by itself. The window keeps the focus now.
@MainActor
final class AddTorrentAliasFocusTests: XCTestCase {
    private func makeDraft(isReady: Bool, id: UUID = UUID()) -> AddTorrentDraft {
        AddTorrentDraft(
            id: id,
            source: AddTorrentSource(kind: .externalOpen, rawValue: "/tmp/Northstar.torrent"),
            originalName: "Northstar",
            infoHash: isReady ? "northstar" : nil,
            suggestedSavePath: NSTemporaryDirectory(),
            alias: "",
            stopAfterDownload: false,
            files: isReady
                ? [AddTorrentFileOption(name: "Northstar/E01.mkv", sizeBytes: 300_000_000, fileIndex: 0, isSelected: true)]
                : [],
            reviewState: isReady ? .ready : .loadingMetadata,
            errorState: nil
        )
    }

    private func allViews(in root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap { allViews(in: $0) }
    }

    /// Whether a text field of the window holds the keyboard.
    private func isFieldFocused(in window: NSWindow) -> Bool {
        guard let contentView = window.contentView else { return false }
        let editsField = allViews(in: contentView)
            .compactMap { $0 as? NSTextField }
            .contains { $0.currentEditor() != nil }
        return editsField || window.firstResponder is NSText
    }

    private func makeWindow(store: AppStore) -> NSWindow {
        let size = NSSize(width: 780, height: 570)
        let hosting = NSHostingView(
            rootView: AddTorrentReviewView()
                .environmentObject(store)
                .frame(width: size.width, height: size.height)
        )
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        return window
    }

    func testFilesAlreadyInTheWindowDoNotFocusTheAliasFieldAsItIsShown() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        bundle.store.currentAddTorrentDraft = makeDraft(isReady: true)

        let window = makeWindow(store: bundle.store)
        defer { window.orderOut(nil) }
        // The files are put into the window before it is shown, as with a
        // file read at once.
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let hasAliasField = allViews(in: try XCTUnwrap(window.contentView))
            .contains { ($0 as? NSTextField)?.isEditable == true }
        XCTAssertTrue(hasAliasField, "The alias field must be in the window for this to test anything")

        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertFalse(isFieldFocused(in: window))
    }

    /// The field still takes the keyboard when asked, and gives it up before
    /// the window closes: its focus ring is drawn apart from the window's
    /// content and outlived the window for a moment.
    func testAliasFieldTakesTheFocusWhenAskedAndGivesItUpAsTheWindowCloses() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        bundle.store.currentAddTorrentDraft = makeDraft(isReady: true)

        let window = makeWindow(store: bundle.store)
        defer { window.orderOut(nil) }
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(600))

        let aliasField = try XCTUnwrap(
            allViews(in: try XCTUnwrap(window.contentView))
                .compactMap { $0 as? NSTextField }
                .first(where: \.isEditable)
        )
        XCTAssertTrue(window.makeFirstResponder(aliasField))
        XCTAssertTrue(isFieldFocused(in: window))

        window.close()

        // Closing does not take the focus from a field by itself.
        XCTAssertFalse(window.firstResponder is NSText)
    }

    func testFilesArrivingInAnOpenWindowDoNotFocusTheAliasField() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        let id = UUID()
        bundle.store.currentAddTorrentDraft = makeDraft(isReady: false, id: id)

        let window = makeWindow(store: bundle.store)
        defer { window.orderOut(nil) }
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(300))

        bundle.store.currentAddTorrentDraft = makeDraft(isReady: true, id: id)
        try await Task.sleep(for: .milliseconds(700))

        XCTAssertFalse(isFieldFocused(in: window))
    }
}
