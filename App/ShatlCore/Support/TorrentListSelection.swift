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
    /// Shift: adds every card from the anchor to this one; a selected card
    /// is taken out, as in Finder.
    case range
}

/// The cards selected in the list, as Finder selects: one by a click, a run
/// by Shift, single ones by ⌘.
///
/// What is selected is what the toolbar acts on. A card with an error acts
/// through its own buttons, so it is never selected. A card still being
/// added has only its cancelling in the toolbar, so it is selected alone and
/// never with others. `joinable` names the cards that can share a selection
/// and `alone` those selected only alone; a card in neither has an error.
nonisolated struct TorrentListSelection: Equatable, Sendable {
    private(set) var ids: Set<UUID> = []
    /// The selected cards in the order they were selected: the one clicked
    /// last comes last, and of a run, the far end. The cards' numbers follow
    /// it.
    private(set) var order: [UUID] = []
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
        order = []
        anchor = nil
        lead = nil
    }

    mutating func selectOnly(_ id: UUID) {
        ids = [id]
        order = [id]
        anchor = id
        lead = id
    }

    /// A card that left the list leaves the selection.
    mutating func remove(_ id: UUID) {
        guard ids.contains(id) else { return }
        drop([id])
    }

    /// Answers a click. `false` when the card refuses and should say so: it
    /// was clicked with ⌘ or Shift while something it cannot join is
    /// selected. The selection then stays as it was.
    ///
    /// A plain click on a card with an error changes nothing and is not a
    /// refusal. Clicked again at once (`isRepeated`), the card does answer,
    /// so the first click is not taken for a broken selection.
    @discardableResult
    mutating func click(
        _ id: UUID,
        _ click: TorrentListSelectionClick,
        isRepeated: Bool = false,
        visible visibleIDs: [UUID],
        joinable: Set<UUID>,
        alone: Set<UUID>
    ) -> Bool {
        guard joinable.contains(id) || alone.contains(id) else {
            if isRepeated {
                return false
            }
            return click == .plain || !hasJoinableSelection(joinable)
        }

        switch click {
        case .plain:
            if ids == [id] {
                clear()
            } else {
                selectOnly(id)
            }
            return true

        case .toggle:
            if ids.contains(id) {
                drop([id])
                return true
            }
            // With nothing to join, ⌘ selects like a plain click.
            guard hasJoinableSelection(joinable) else {
                selectOnly(id)
                return true
            }
            guard joinable.contains(id) else { return false }

            add(id)
            anchor = id
            lead = id
            return true

        case .range:
            if ids.contains(id) {
                drop([id])
                return true
            }
            guard hasJoinableSelection(joinable),
                  let start = resolvedAnchor(in: visibleIDs) else {
                selectOnly(id)
                return true
            }
            guard joinable.contains(id) else { return false }

            run(from: start, to: id, visible: visibleIDs, joinable: joinable).forEach { add($0) }
            anchor = start
            lead = id
            return true
        }
    }

    /// ↑ and ↓. Without Shift the selection moves to the next card that can
    /// be selected, stepping over the cards with an error. With Shift the run
    /// from the anchor grows or shrinks by a card, stepping over the cards
    /// that cannot join; cards selected apart from the run stay. Returns the
    /// card to scroll to, or `nil` when nothing changed.
    @discardableResult
    mutating func move(
        _ step: TorrentListSelectionStep,
        extending: Bool,
        visible visibleIDs: [UUID],
        joinable: Set<UUID>,
        alone: Set<UUID>
    ) -> UUID? {
        guard extending, hasJoinableSelection(joinable),
              let start = resolvedAnchor(in: visibleIDs) else {
            let selectableIDs = visibleIDs.filter { joinable.contains($0) || alone.contains($0) }
            let current = lead.flatMap { ids.contains($0) ? $0 : nil } ?? single
            guard let target = step.target(from: current, in: selectableIDs),
                  ids != [target] else {
                return nil
            }
            selectOnly(target)
            return target
        }

        let end = lead.flatMap { visibleIDs.contains($0) ? $0 : nil } ?? start
        guard let endIndex = visibleIDs.firstIndex(of: end) else { return nil }

        let candidates: [UUID]
        switch step {
        case .previous:
            candidates = Array(visibleIDs[..<endIndex].reversed())
        case .next:
            candidates = Array(visibleIDs[(endIndex + 1)...])
        }
        guard let target = candidates.first(where: joinable.contains) else { return nil }

        let previousRun = run(from: start, to: end, visible: visibleIDs, joinable: joinable)
        let newRun = run(from: start, to: target, visible: visibleIDs, joinable: joinable)
        drop(Set(previousRun).subtracting(newRun))
        newRun.forEach { add($0) }
        anchor = start
        lead = target
        return target
    }

    /// ⌘A: every card that can share a selection.
    mutating func selectAll(visible visibleIDs: [UUID], joinable: Set<UUID>) {
        let all = visibleIDs.filter(joinable.contains)
        guard let first = all.first, let last = all.last else { return }
        ids = Set(all)
        order = all
        anchor = first
        lead = last
    }

    /// Drops the cards the search has hidden and those that can no longer
    /// be selected: a download that failed while selected.
    mutating func prune(visible visibleIDs: Set<UUID>, joinable: Set<UUID>, alone: Set<UUID>) {
        var kept = ids.intersection(visibleIDs).filter { joinable.contains($0) || alone.contains($0) }
        if kept.count > 1 {
            kept = kept.intersection(joinable)
        }
        drop(ids.subtracting(kept))
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

    /// The anchor, or, once it has left the selection, the card selected
    /// last.
    private func resolvedAnchor(in visibleIDs: [UUID]) -> UUID? {
        if let anchor, ids.contains(anchor), visibleIDs.contains(anchor) {
            return anchor
        }
        return order.last(where: visibleIDs.contains)
    }

    /// The cards from `start` to `end` that can share a selection, counted
    /// from `start`.
    private func run(
        from start: UUID,
        to end: UUID,
        visible visibleIDs: [UUID],
        joinable: Set<UUID>
    ) -> [UUID] {
        guard let startIndex = visibleIDs.firstIndex(of: start),
              let endIndex = visibleIDs.firstIndex(of: end) else {
            return []
        }
        let run = visibleIDs[min(startIndex, endIndex)...max(startIndex, endIndex)]
            .filter(joinable.contains)
        return startIndex <= endIndex ? run : run.reversed()
    }

    private mutating func add(_ id: UUID) {
        guard ids.insert(id).inserted else { return }
        order.append(id)
    }

    /// Takes cards out. An end of the Shift range that went with them moves
    /// to the card selected last.
    private mutating func drop(_ dropped: Set<UUID>) {
        guard !dropped.isEmpty else { return }
        ids.subtract(dropped)
        order.removeAll(where: dropped.contains)

        if let anchor, !ids.contains(anchor) {
            self.anchor = order.last
        }
        if let lead, !ids.contains(lead) {
            self.lead = anchor
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
