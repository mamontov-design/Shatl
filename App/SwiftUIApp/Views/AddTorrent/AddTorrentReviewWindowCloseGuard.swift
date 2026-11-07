// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation

/// Stands in as the add window's delegate to answer the one question AppKit
/// asks before the close button or ⌘W closes a window — may it close? — and
/// hands every other call to the delegate SwiftUI set, unchanged.
///
/// SwiftUI can only forbid closing a window (`windowDismissBehavior`, which
/// greys the close button out), not ask first; so the add window answers this
/// question itself (the owner's choice, November 2026). A window closed by
/// the app itself (`dismissWindow`) is not asked. If SwiftUI sets a delegate
/// of its own again, the window wraps the new one the next time it is laid
/// out; `AddTorrentReviewWindowCloseGuardTests` checks the handing over.
final class AddTorrentReviewWindowCloseGuard: NSObject, NSWindowDelegate {
    /// SwiftUI's own delegate, which keeps every call but this one. Weak, as
    /// the window holds its delegate: SwiftUI owns it.
    nonisolated(unsafe) private(set) weak var wrappedDelegate: (any NSWindowDelegate)?
    /// `false` keeps the window open: the add window asks first.
    var shouldClose: (NSWindow) -> Bool

    init(wrapping delegate: (any NSWindowDelegate)?, shouldClose: @escaping (NSWindow) -> Bool) {
        wrappedDelegate = delegate
        self.shouldClose = shouldClose
        super.init()
    }

    /// Puts a guard in as `window`'s delegate, around the one it has, or
    /// gives the guard already there its new answer. The window keeps the
    /// guard alive: a window holds its delegate weakly, and a guard gone
    /// with the view that made it would leave the window with no delegate,
    /// not even SwiftUI's.
    static func install(on window: NSWindow, shouldClose: @escaping (NSWindow) -> Bool) {
        if let existing = window.delegate as? AddTorrentReviewWindowCloseGuard {
            existing.shouldClose = shouldClose
            return
        }
        let closeGuard = AddTorrentReviewWindowCloseGuard(wrapping: window.delegate, shouldClose: shouldClose)
        objc_setAssociatedObject(window, &associationKey, closeGuard, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        window.delegate = closeGuard
    }

    nonisolated(unsafe) private static var associationKey: UInt8 = 0

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) {
            return true
        }
        return wrappedDelegate?.responds(to: aSelector) ?? false
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let wrappedDelegate, wrappedDelegate.responds(to: aSelector) {
            return wrappedDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard shouldClose(sender) else { return false }
        return wrappedDelegate?.windowShouldClose?(sender) ?? true
    }
}
