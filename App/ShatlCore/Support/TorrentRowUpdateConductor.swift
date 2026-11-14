// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// When each card shows its new numbers.
///
/// The engine reports once a second, and every card used to take its new
/// numbers in the same frame: their digits rolled all at once, and while
/// the list scrolled the rolls fought its movement for the same frames.
/// Now the cards take their newest numbers on five beats a second, each
/// card on its own beat: the cards are dealt to the beats evenly, in an
/// order that does not follow the list (it would run down it like a wave).
/// With five cards or fewer each has a beat of its own, spread over the
/// second. Every card still changes once a second, with numbers no older
/// than a second; the changes come a few at a time instead of in one
/// volley. Not one card at a time with many cards: every separate update
/// costs SwiftUI a pass over the whole window, and 46 of them a second
/// fought a scroll that had just begun (the owner's check, 2026-11-13).
///
/// While the list rushes (`TorrentListScrollPace`), no card starts a new
/// change. The changes under way play to their end; the cards keep only
/// their newest numbers and, once the list has calmed down, each takes
/// them on its beat of the next second, rolling from what it showed to
/// what is now true. Nothing stops halfway and nothing changes in one
/// volley, so the pause is not seen, as the brand marks go on from where
/// they stood.
///
/// Only numbers wait: the speed set, the expanded groups and the progress.
/// Anything else (a status, an error, the finish, "Простаивает", the
/// selection) shows at once, with the newest numbers in it. The engine and
/// the store do not wait at all; the speed chips under the list do not
/// either: they stand still and their pause would be seen.
///
/// It conducts only on the second level of simplification, from 25 active
/// downloads (`CardSimplificationLevel.lightest`; the owner's decision,
/// 2026-11-13). With fewer, every card takes its new numbers at once, as
/// before the conductor.
///
/// Ships in 1.0.6 as a first step, to be reworked (the owner, 2026-11-14):
/// with 46-57 downloads the list still scrolled uncomfortably, held
/// numbers or not (the owner's checks of 2026-11-13). Open for 1.0.7: what
/// the remaining load is (engine against interface, never measured at that
/// count), whether cards out of sight should take numbers at all, and how
/// it fits the download queue planned for 1.0.7 (`Shatl Features.ru.md`,
/// item 22), with which no more than five downloads work at once.
@MainActor
final class TorrentRowUpdateConductor {
    /// Off, a card shows a new state at once, as it did before the
    /// conductor; the tests of the store work that way.
    let spreadsNumbers: Bool
    /// Set by the store from the level of simplification.
    private(set) var isConducting = true
    private(set) var listMovesFast = false
    /// The Debug readout of the list.
    var onWaitingCountChange: (@MainActor (Int) -> Void)?

    private struct Waiting {
        weak var model: TorrentRowPresentationModel?
        var state: TorrentRowState
        var due: ContinuousClock.Instant
    }

    private var waiting: [UUID: Waiting] = [:]
    private var phases: [UUID: Double] = [:]
    private var arrangedIDs: Set<UUID> = []
    private let start: ContinuousClock.Instant
    private let now: () -> ContinuousClock.Instant
    private let schedulesWakes: Bool
    private var wake: Task<Void, Never>?
    private var wakeAt: ContinuousClock.Instant?

    /// `now` and `schedulesWakes` let tests drive the clock themselves.
    init(
        spreadsNumbers: Bool = true,
        now: @escaping () -> ContinuousClock.Instant = { .now },
        schedulesWakes: Bool = true
    ) {
        self.spreadsNumbers = spreadsNumbers
        self.now = now
        self.schedulesWakes = schedulesWakes
        start = now()
    }

    var waitingCount: Int { waiting.count }

    /// Beats a second the cards take their numbers on.
    static let beatsPerSecond = 5

    /// The cards of the list, so each has its beat.
    func arrange(_ ids: [UUID]) {
        let idSet = Set(ids)
        guard idSet != arrangedIDs else { return }
        arrangedIDs = idSet
        let order = ids.sorted { Self.shuffleKey(of: $0) < Self.shuffleKey(of: $1) }
        let beats = max(1, min(order.count, Self.beatsPerSecond))
        phases = Dictionary(uniqueKeysWithValues: order.enumerated().map { index, id in
            (id, Double(index % beats) / Double(beats))
        })

        let before = waiting.count
        waiting = waiting.filter { idSet.contains($0.key) }
        let time = now()
        for id in waiting.keys {
            waiting[id]?.due = nextSlot(for: id, after: time)
        }
        if waiting.count != before {
            onWaitingCountChange?(waiting.count)
        }
        scheduleWake()
    }

    /// The newest state of a card: shown at once, or on the card's beat
    /// when only its numbers have changed.
    func offer(_ state: TorrentRowState, to model: TorrentRowPresentationModel) {
        guard spreadsNumbers, isConducting else {
            model.update(state: state)
            return
        }
        let id = model.id
        guard state != model.state else {
            // Back to what the card shows: nothing to wait for.
            drop(id)
            return
        }
        guard state.differsOnlyInNumbers(from: model.state) else {
            drop(id)
            model.update(state: state)
            return
        }
        if var entry = waiting[id] {
            entry.state = state
            entry.model = model
            waiting[id] = entry
        } else {
            waiting[id] = Waiting(model: model, state: state, due: nextSlot(for: id, after: now()))
            onWaitingCountChange?(waiting.count)
        }
        scheduleWake()
    }

    /// Off, the cards that wait take their numbers at once, in one update,
    /// and every new state shows at once.
    func setConducting(_ conducts: Bool) {
        guard conducts != isConducting else { return }
        isConducting = conducts
        guard !conducts else { return }
        cancelWake()
        let held = waiting
        waiting = [:]
        for entry in held.values {
            entry.model?.update(state: entry.state)
        }
        if !held.isEmpty {
            onWaitingCountChange?(0)
        }
    }

    /// Told by the list as its pace changes.
    func setListMovesFast(_ fast: Bool) {
        guard fast != listMovesFast else { return }
        listMovesFast = fast
        guard !fast else {
            cancelWake()
            return
        }
        // Each card takes its numbers on its beat of the second to come, not
        // at once.
        let time = now()
        for id in waiting.keys {
            waiting[id]?.due = nextSlot(for: id, after: time)
        }
        scheduleWake()
    }

    /// Shows the numbers whose beat has come: all the cards of a beat in one
    /// update.
    func publishDue() {
        guard !listMovesFast else { return }
        // A wake that comes a moment early still counts.
        let time = now() + .milliseconds(2)
        let due = waiting
            .filter { $0.value.due <= time }
            .sorted { $0.value.due < $1.value.due }
        for (id, entry) in due {
            waiting[id] = nil
            entry.model?.update(state: entry.state)
        }
        if !due.isEmpty {
            onWaitingCountChange?(waiting.count)
        }
        scheduleWake()
    }

    private func drop(_ id: UUID) {
        guard waiting.removeValue(forKey: id) != nil else { return }
        onWaitingCountChange?(waiting.count)
    }

    private func nextSlot(for id: UUID, after time: ContinuousClock.Instant) -> ContinuousClock.Instant {
        let phase = phases[id] ?? Self.fallbackPhase(of: id)
        let elapsed = Self.seconds(start.duration(to: time))
        let turn = (elapsed - phase).rounded(.up)
        return start + .seconds(turn + phase)
    }

    private func scheduleWake() {
        guard schedulesWakes, !listMovesFast, let next = waiting.values.map(\.due).min() else {
            cancelWake()
            return
        }
        if wake != nil, let wakeAt, wakeAt <= next {
            return
        }
        wake?.cancel()
        wakeAt = next
        wake = Task { @MainActor [weak self] in
            try? await Task.sleep(until: next, clock: .continuous)
            guard let self, !Task.isCancelled else { return }
            self.wake = nil
            self.wakeAt = nil
            self.publishDue()
        }
    }

    private func cancelWake() {
        wake?.cancel()
        wake = nil
        wakeAt = nil
    }

    /// An order of the cards that has nothing to do with their order in the
    /// list, the same every time.
    private static func shuffleKey(of id: UUID) -> UInt64 {
        let bytes = id.uuid
        return [bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15]
            .reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }

    /// For a card not arranged yet.
    private static func fallbackPhase(of id: UUID) -> Double {
        Double(shuffleKey(of: id) >> 11) / Double(UInt64(1) << 53)
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

extension TorrentRowState {
    /// The two states differ in their numbers alone: the speed set, the
    /// expanded groups and the progress. What the conductor holds back.
    func differsOnlyInNumbers(from other: TorrentRowState) -> Bool {
        var withOtherNumbers = self
        withOtherNumbers.progress = other.progress
        withOtherNumbers.compactTransferMetricSet = other.compactTransferMetricSet
        withOtherNumbers.expandedMetricGroups = other.expandedMetricGroups
        return withOtherNumbers == other
    }
}
