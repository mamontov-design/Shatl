// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import XCTest
@testable import Shatl

/// The main window changes its stage one step at a time, with one transition,
/// under a toolbar that stays the same: transitions used to pick a different
/// direction each time, because the whole window was rebuilt under them.
@MainActor
final class MainWindowStageTests: XCTestCase {
    func testStageFollowsSessionLoadAndRows() {
        XCTAssertEqual(
            MainWindowStage.current(hasLoadedInitialSession: false, sessionLoadIssue: nil, hasRows: true),
            .loadingSession
        )
        XCTAssertEqual(
            MainWindowStage.current(hasLoadedInitialSession: true, sessionLoadIssue: .unreadable, hasRows: true),
            .sessionLoadFailure(.unreadable)
        )
        XCTAssertEqual(
            MainWindowStage.current(hasLoadedInitialSession: true, sessionLoadIssue: nil, hasRows: false),
            .empty
        )
        XCTAssertEqual(
            MainWindowStage.current(hasLoadedInitialSession: true, sessionLoadIssue: nil, hasRows: true),
            .list
        )
    }

    func testLastCardLeavesTheListBeforeTheEmptyStateComes() {
        XCTAssertEqual(
            MainWindowStageStep.step(from: .list, to: .empty),
            .switchAfterCardRemoval(.empty)
        )
    }

    /// A download added while the last card leaves cancels the waiting change
    /// and finds the list already shown.
    func testDownloadAddedWhileTheLastCardLeavesKeepsTheList() {
        XCTAssertEqual(MainWindowStageStep.step(from: .list, to: .list), .stay)
    }

    func testFirstDownloadReplacesTheEmptyStateAtOnce() {
        XCTAssertEqual(MainWindowStageStep.step(from: .empty, to: .list), .switchNow(.list))
    }

    func testSessionStagesChangeAtOnce() {
        XCTAssertEqual(MainWindowStageStep.step(from: .loadingSession, to: .list), .switchNow(.list))
        XCTAssertEqual(MainWindowStageStep.step(from: .loadingSession, to: .empty), .switchNow(.empty))
        XCTAssertEqual(
            MainWindowStageStep.step(from: .loadingSession, to: .sessionLoadFailure(.unreadable)),
            .switchNow(.sessionLoadFailure(.unreadable))
        )
        XCTAssertEqual(
            MainWindowStageStep.step(from: .sessionLoadFailure(.unreadable), to: .empty),
            .switchNow(.empty)
        )
    }

    func testToolbarAddAndSearchBelongToTheListOnly() {
        XCTAssertTrue(MainWindowStage.list.allowsListActions)
        XCTAssertFalse(MainWindowStage.empty.allowsListActions)
        XCTAssertFalse(MainWindowStage.loadingSession.allowsListActions)
        XCTAssertFalse(MainWindowStage.sessionLoadFailure(.unreadable).allowsListActions)
    }

    /// The disabled search must not disable the window under it: the empty
    /// state's add field lives there.
    func testDisabledSearchKeepsTheWindowContentEnabled() {
        let control = EnabledProbe()
        _ = NSHostingView(rootView: control.disabled(true)).fittingSize
        XCTAssertEqual(control.recorder.value, false, "The probe must see a plain disabled parent")

        let probe = EnabledProbe()
        let view = probe.modifier(
            MainWindowSearchModifier(isEnabled: false, searchText: .constant(""), prompt: "Search")
        )
        _ = NSHostingView(rootView: view).fittingSize
        XCTAssertEqual(probe.recorder.value, true)
    }

    /// In a narrow window the search field folds into its toolbar item's
    /// button, which `.disabled` does not reach; the item itself is disabled
    /// and stays so through SwiftUI updates.
    func testSearchToolbarItemIsDisabledOutsideTheList() throws {
        let model = SearchWindowModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: SearchWindowContent(model: model))
        host.sceneBridgingOptions = [.toolbars]
        window.contentView = host
        pumpRunLoop()

        let item = try XCTUnwrap(
            window.toolbar?.items.compactMap { $0 as? NSSearchToolbarItem }.first
        )
        XCTAssertFalse(item.searchField.isEnabled)

        MainWindowSearchToolbarItem.setEnabled(false, in: window)
        model.revision += 1
        pumpRunLoop()
        XCTAssertFalse(item.isEnabled)

        model.isSearchEnabled = true
        MainWindowSearchToolbarItem.setEnabled(true, in: window)
        pumpRunLoop()
        XCTAssertTrue(item.isEnabled)
        XCTAssertTrue(item.searchField.isEnabled)
    }

    private func pumpRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }
}

@MainActor
private final class SearchWindowModel: ObservableObject {
    @Published var revision = 0
    @Published var isSearchEnabled = false
}

private struct SearchWindowContent: View {
    @ObservedObject var model: SearchWindowModel

    var body: some View {
        Text("\(model.revision)")
            .frame(width: 440, height: 400)
            .modifier(
                MainWindowSearchModifier(
                    isEnabled: model.isSearchEnabled,
                    searchText: .constant(""),
                    prompt: "Search"
                )
            )
    }
}

private final class EnabledRecorder {
    var value: Bool?
}

private struct EnabledProbe: View {
    @Environment(\.isEnabled) private var isEnabled
    let recorder = EnabledRecorder()

    var body: some View {
        recorder.value = isEnabled
        return Color.clear.frame(width: 1, height: 1)
    }
}
