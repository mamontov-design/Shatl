// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// What the middle of the main window shows. The toolbar and the title stay
/// the same in every stage; only what they allow follows it, and the title
/// turns transparent over the empty list with the wordmark
/// (`MainWindowTitle`).
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

    /// In light the list stands on a grey ground under its white cards; the
    /// empty list and the session stages keep the window's own background.
    var standsOnListGround: Bool {
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

/// Over the empty list with the wordmark the window's name is already
/// written large in its middle, so the title turns transparent. It keeps its
/// place, so nothing in the toolbar moves, and the window keeps its title for
/// VoiceOver and the Window menu. macOS has no setting for this: the title's
/// own label is looked up in the title bar, and should a later macOS build
/// the bar otherwise, the title simply stays.
enum MainWindowTitle {
    /// False while the title bar has no label yet.
    @discardableResult
    static func setTransparent(_ isTransparent: Bool, in window: NSWindow, animated: Bool) -> Bool {
        guard let titleBar = window.standardWindowButton(.closeButton)?.superview,
              let label = label(in: titleBar, title: window.title) else {
            return false
        }
        // An animated change sets the value at once and moves only the
        // layer, so a repeated call does not start the fade over.
        let alpha: CGFloat = isTransparent ? 0 : 1
        guard label.alphaValue != alpha else { return true }
        guard animated else {
            label.alphaValue = alpha
            return true
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ShatlMotion.brandMarkChangeDuration
            context.timingFunction = CAMediaTimingFunction(name: .default)
            label.animator().alphaValue = alpha
        }
        return true
    }

    private static func label(in view: NSView, title: String) -> NSTextField? {
        if let field = view as? NSTextField,
           !(field is NSSearchField),
           !field.isEditable,
           field.stringValue == title {
            return field
        }
        for subview in view.subviews {
            if let label = label(in: subview, title: title) {
                return label
            }
        }
        return nil
    }
}
