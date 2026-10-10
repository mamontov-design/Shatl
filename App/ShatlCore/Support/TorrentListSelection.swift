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

/// How a card was clicked.
nonisolated enum TorrentListSelectionClick: Sendable {
    /// Selects the card alone; a click on the only selected card clears it.
    case plain
    /// ⌘: adds the card to the selection or takes it out.
    case toggle
    /// Shift: selects every card from the anchor to this one.
    case range
}

/// The cards selected in the list, as Finder selects: one by a click, a run
/// by Shift, single ones by ⌘.
///
/// A card with an error, or one still being added, acts through its own
/// buttons and not through the toolbar. It can be selected alone and never
/// with others: `joinable` names the cards that can share a selection.
nonisolated struct TorrentListSelection: Equatable, Sendable {
    private(set) var ids: Set<UUID> = []
    /// Where a Shift range starts: the card selected last without Shift.
    private(set) var anchor: UUID?
    /// The far end of a Shift range, which Shift+arrows move.
    private(set) var lead: UUID?

    init() {}

    init(only id: UUID) {
        selectOnly(id)
    }

    var isEmpty: Bool { ids.isEmpty }
    var count: Int { ids.count }

    /// The selected card when there is exactly one: what "Open" and the other
    /// single-download actions work on.
    var single: UUID? {
        ids.count == 1 ? ids.first : nil
    }

    func contains(_ id: UUID) -> Bool {
        ids.contains(id)
    }

    /// The selected cards in the order of the list.
    func ordered(in visibleIDs: [UUID]) -> [UUID] {
        visibleIDs.filter(ids.contains)
    }

    mutating func clear() {
        ids = []
        anchor = nil
        lead = nil
    }

    mutating func selectOnly(_ id: UUID) {
        ids = [id]
        anchor = id
        lead = id
    }

    /// A card that left the list leaves the selection.
    mutating func remove(_ id: UUID) {
        guard ids.remove(id) != nil else { return }
        repairEnds()
    }

    /// Answers a click. `false` when the card refuses to join the others: a
    /// card with an error clicked with ⌘ or Shift while something else is
    /// selected. The selection then stays as it was.
    @discardableResult
    mutating func click(
        _ id: UUID,
        _ click: TorrentListSelectionClick,
        visible visibleIDs: [UUID],
        joinable: Set<UUID>
    ) -> Bool {
        switch click {
        case .plain:
            if ids == [id] {
                clear()
            } else {
                selectOnly(id)
            }
            return true

        case .toggle:
            // With nothing to join, ⌘ selects like a plain click.
            guard hasJoinableSelection(joinable) else {
                if ids == [id] {
                    clear()
                } else {
                    selectOnly(id)
                }
                return true
            }
            guard joinable.contains(id) else { return false }

            if ids.contains(id) {
                ids.remove(id)
                repairEnds()
            } else {
                ids.insert(id)
                anchor = id
                lead = id
            }
            return true

        case .range:
            guard hasJoinableSelection(joinable),
                  let anchor, visibleIDs.contains(anchor) else {
                selectOnly(id)
                return true
            }
            guard joinable.contains(id) else { return false }

            selectRange(from: anchor, to: id, visible: visibleIDs, joinable: joinable)
            return true
        }
    }

    /// ↑ and ↓. Without Shift the selection moves to the neighbouring card,
    /// whatever it is. With Shift it grows or shrinks by a card from the
    /// anchor and steps over the cards that cannot join. Returns the card to
    /// scroll to, or `nil` when nothing changed.
    @discardableResult
    mutating func move(
        _ step: TorrentListSelectionStep,
        extending: Bool,
        visible visibleIDs: [UUID],
        joinable: Set<UUID>
    ) -> UUID? {
        guard extending, hasJoinableSelection(joinable),
              let anchor, visibleIDs.contains(anchor) else {
            let current = lead.flatMap { ids.contains($0) ? $0 : nil } ?? single
            guard let target = step.target(from: current, in: visibleIDs),
                  ids != [target] else {
                return nil
            }
            selectOnly(target)
            return target
        }

        let start = lead.flatMap { visibleIDs.contains($0) ? $0 : nil } ?? anchor
        guard let startIndex = visibleIDs.firstIndex(of: start) else { return nil }

        let candidates: [UUID]
        switch step {
        case .previous:
            candidates = Array(visibleIDs[..<startIndex].reversed())
        case .next:
            candidates = Array(visibleIDs[(startIndex + 1)...])
        }
        guard let target = candidates.first(where: joinable.contains) else { return nil }

        selectRange(from: anchor, to: target, visible: visibleIDs, joinable: joinable)
        return target
    }

    /// ⌘A: every card that can share a selection.
    mutating func selectAll(visible visibleIDs: [UUID], joinable: Set<UUID>) {
        let all = visibleIDs.filter(joinable.contains)
        guard let first = all.first, let last = all.last else { return }
        ids = Set(all)
        anchor = first
        lead = last
    }

    /// Drops the cards the search has hidden and, from a selection of
    /// several, those that can no longer share it: a download that failed
    /// while selected.
    mutating func prune(visible visibleIDs: Set<UUID>, joinable: Set<UUID>) {
        var kept = ids.intersection(visibleIDs)
        if kept.count > 1 {
            kept = kept.intersection(joinable)
        }
        guard kept != ids else { return }
        ids = kept
        repairEnds()
    }

    /// Whether the selection is something a card could join: not empty and
    /// not a lone card that takes no company itself.
    private func hasJoinableSelection(_ joinable: Set<UUID>) -> Bool {
        guard !ids.isEmpty else { return false }
        if let single {
            return joinable.contains(single)
        }
        return true
    }

    private mutating func selectRange(
        from anchor: UUID,
        to end: UUID,
        visible visibleIDs: [UUID],
        joinable: Set<UUID>
    ) {
        guard let anchorIndex = visibleIDs.firstIndex(of: anchor),
              let endIndex = visibleIDs.firstIndex(of: end) else {
            return
        }
        let range = visibleIDs[min(anchorIndex, endIndex)...max(anchorIndex, endIndex)]
        ids = Set(range.filter(joinable.contains))
        self.anchor = anchor
        lead = end
    }

    private mutating func repairEnds() {
        if let anchor, !ids.contains(anchor) {
            self.anchor = ids.count == 1 ? ids.first : nil
        }
        if let lead, !ids.contains(lead) {
            self.lead = ids.count == 1 ? ids.first : anchor
        }
        if ids.isEmpty {
            anchor = nil
            lead = nil
        }
    }
}

/// What the toolbar's one Start/Stop button does for the selected downloads.
nonisolated enum TorrentListRunAction: Equatable, Sendable {
    case start
    case stop

    /// Start while any of them is stopped: it starts those and leaves the
    /// running ones alone, so a wrong guess costs nothing. Stop only when all
    /// of them run.
    static func action(for statuses: [TorrentStatus]) -> TorrentListRunAction {
        statuses.contains(where: \.isSleeping) ? .start : .stop
    }
}

/// Where the count of the selected downloads is shown.
nonisolated enum TorrentSelectionCount {
    /// From this many the bar under the toolbar names the count.
    static let smallestSeveral = 2
    /// The largest number a card can wear: `9.circle.fill` is the last of
    /// the one-digit symbols that read at the size of the check mark.
    static let largestCardNumber = 9
}
