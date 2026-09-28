// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// When a card lights up under the pointer. A list scrolled under a resting
/// pointer passes cards beneath it faster than the delay, so they no longer
/// light up and fade one after another; a card lights up once the pointer
/// rests on it and goes dark at once when the pointer leaves.
enum TorrentCardHoverTiming {
    /// How long the pointer rests on a card before the card lights up.
    static let restDelay: Duration = .milliseconds(80)
}

/// Holds the wait for one hover target in a card. A plain class kept in the
/// card's state, so starting or cancelling a wait does not redraw the card.
final class TorrentCardHoverIntent {
    private var pending: Task<Void, Never>?

    /// Calls `lightUp` once the pointer has rested for the delay.
    func pointerEntered(after delay: Duration = TorrentCardHoverTiming.restDelay, lightUp: @escaping @MainActor () -> Void) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            lightUp()
        }
    }

    func pointerExited() {
        pending?.cancel()
        pending = nil
    }
}
