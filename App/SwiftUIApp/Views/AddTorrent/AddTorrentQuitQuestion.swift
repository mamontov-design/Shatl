// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation

/// ⌘Q with work waiting in the add window asks what closing the window asks
/// (`AddTorrentCloseQuestion`), by the same rule (`ClosingLoss`): two
/// downloads waiting or more, or a choice made in the one left. The question
/// stands over the add window, brought forward, and comes before the quit
/// saves anything, so downloads saved to the list reach the session the
/// quit writes; see `ShatlTerminationFlow`. Logout and restart do not ask.
@MainActor
enum AddTorrentQuitQuestion {
    /// `false` keeps Shatl open: the user went back to the add window.
    static func confirm(for store: AppStore) async -> Bool {
        guard store.isAddTorrentReviewWindowActive, let loss = store.addTorrentReview.closingLoss else {
            return true
        }
        // Found by its guard; without it the question is asked on its own.
        let window = AddTorrentReviewWindowCloseGuard.guardedWindow(among: NSApp.windows)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // A question already over the window, or the folder panel, is
        // answered first: the quit waits for the next ⌘Q.
        guard window?.attachedSheet == nil else { return false }

        let answer = await AddTorrentCloseQuestion.ask(
            about: loss,
            whenQuitting: true,
            localeOverride: store.preferences.localeOverride,
            window: window
        )
        switch answer {
        case .goBack:
            return false
        case .saveToList:
            // The focus leaves before the window does; see
            // `AddTorrentReviewWindowFocus`.
            window?.makeFirstResponder(nil)
            store.saveWaitingDraftsToList()
            return true
        case .close:
            return true
        }
    }
}
