// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// What the middle of the main window shows. The toolbar and the title stay
/// the same in every stage; only what they allow follows it.
enum MainWindowStage: Equatable {
    case loadingSession
    case sessionLoadFailure(SessionLoadIssue)
    case empty
    case list

    static func current(
        hasLoadedInitialSession: Bool,
        sessionLoadIssue: SessionLoadIssue?,
        hasRows: Bool
    ) -> MainWindowStage {
        guard hasLoadedInitialSession else { return .loadingSession }
        if let sessionLoadIssue {
            return .sessionLoadFailure(sessionLoadIssue)
        }
        return hasRows ? .list : .empty
    }

    /// Adding from the toolbar and searching belong to the list: the empty
    /// state has its own add field, and the session stages allow neither.
    var allowsListActions: Bool {
        self == .list
    }
}

/// How the window goes from the stage it shows to the one the store asks for.
/// One stage change at a time, always with the same transition.
enum MainWindowStageStep: Equatable {
    case stay
    case switchNow(MainWindowStage)
    /// The last card leaves the list like any other card first; the empty
    /// state comes once it has gone, so the two never move at once.
    case switchAfterCardRemoval(MainWindowStage)

    static func step(from displayed: MainWindowStage, to target: MainWindowStage) -> MainWindowStageStep {
        guard displayed != target else { return .stay }
        if displayed == .list, target == .empty {
            return .switchAfterCardRemoval(target)
        }
        return .switchNow(target)
    }
}

/// The toolbar search field stays in the window in every stage, so it never
/// rebuilds the content under it; outside the list it is only disabled, as
/// the file search of Add Torrent Review is.
struct MainWindowSearchModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var searchText: String
    let prompt: String

    func body(content: Content) -> some View {
        content
            // `.disabled` below reaches the toolbar field; the window's own
            // content, the add field of the empty state among it, stays enabled.
            .environment(\.isEnabled, true)
            .searchable(
                text: $searchText,
                placement: .toolbar,
                prompt: Text(prompt)
            )
            .searchToolbarBehavior(.automatic)
            .disabled(!isEnabled)
    }
}

/// `.disabled` reaches the search field but not its toolbar item, and a
/// narrow window folds the field into the item's button, which stayed
/// clickable. SwiftUI leaves the item's own `isEnabled` alone, so the window
/// sets it.
enum MainWindowSearchToolbarItem {
    static func setEnabled(_ isEnabled: Bool, in window: NSWindow) {
        for case let item as NSSearchToolbarItem in window.toolbar?.items ?? []
        where item.isEnabled != isEnabled {
            item.isEnabled = isEnabled
        }
    }
}
