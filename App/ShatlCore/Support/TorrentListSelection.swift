// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Where ↑ and ↓ move the selection among the cards on screen.
nonisolated enum TorrentListSelectionStep: Sendable {
    case previous
    case next

    /// With no selection, or one hidden by the search, ↓ takes the first card
    /// and ↑ the last. At either end the selection stays where it is.
    func target(from selectedID: UUID?, in visibleIDs: [UUID]) -> UUID? {
        guard !visibleIDs.isEmpty else { return nil }
        guard let selectedID, let index = visibleIDs.firstIndex(of: selectedID) else {
            return self == .next ? visibleIDs.first : visibleIDs.last
        }

        switch self {
        case .previous:
            return visibleIDs[max(index - 1, visibleIDs.startIndex)]
        case .next:
            return visibleIDs[min(index + 1, visibleIDs.endIndex - 1)]
        }
    }
}
