// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Whether the list of downloads has rushed and not calmed down since: then
/// its cards start no new changes of their numbers
/// (`TorrentRowUpdateConductor`).
///
/// Speed is how far the list went over the last tenth of a second, in
/// points per second; a card is about 100 points tall. The list rushes
/// above 1 500 (some 15 cards a second, which nobody reads) and calms down
/// once it has stood still for 1.5 s. Moving slowly does not calm it: a
/// list stopped for a second and flicked again met the cards taking their
/// numbers (the owner's check with 46 downloads, 2026-11-13). A list that
/// never rushed keeps its numbers live, however it moves. A wheel, a
/// trackpad and the coasting after a flick all count alike: only where the
/// list stands is read.
nonisolated struct TorrentListScrollPace: Equatable, Sendable {
    static let fastSpeed = 1_500.0
    /// How long a list that rushed has to stand still to calm down.
    static let calmAfter = 1.5
    /// A list that has not moved for this long stands: its speed is 0.
    static let stillAfter = 0.15
    /// The stretch of time the speed is measured over.
    static let window = 0.1

    private struct Sample: Equatable, Sendable {
        var time: Double
        var origin: Double
    }

    /// Rushed, and not calm since.
    private(set) var isFast = false
    /// Points per second, as last measured; 0 while the list stands.
    private(set) var speed = 0.0
    private(set) var lastMoveAt: Double?
    private var samples: [Sample] = []

    /// The list stands at `origin` (the top of what is in sight) at `time`,
    /// in seconds.
    mutating func note(origin: Double, at time: Double) {
        if let last = samples.last, last.origin == origin {
            return
        }
        lastMoveAt = time
        samples.append(Sample(time: time, origin: origin))
        // The sample just before the window stays: the window's first move
        // is measured from it.
        while samples.count > 2, samples[1].time <= time - Self.window {
            samples.removeFirst()
        }
        if let first = samples.first, time - first.time > Self.window * 2 {
            // The list stood before this move: there is nothing to measure
            // it against yet.
            samples = [samples[samples.count - 1]]
        }
        guard let first = samples.first, samples.count > 1, time > first.time else {
            speed = 0
            return
        }
        speed = abs(origin - first.origin) / (time - first.time)
        if speed > Self.fastSpeed {
            isFast = true
        }
    }

    /// Asked a while after the last move: a list that has not moved since
    /// `stillAfter` stands, and one that has stood for `calmAfter` is calm.
    mutating func noteStill(at time: Double) {
        guard let lastMoveAt else { return }
        let standing = time - lastMoveAt + 0.000_1
        if standing >= Self.stillAfter {
            speed = 0
            samples = samples.last.map { [$0] } ?? []
        }
        if standing >= Self.calmAfter {
            isFast = false
        }
    }

    /// When to ask `noteStill` next; `nil` when nothing is left to wait
    /// for.
    func nextStillCheck(after time: Double) -> Double? {
        guard let lastMoveAt else { return nil }
        if speed > 0 {
            return lastMoveAt + Self.stillAfter
        }
        if isFast {
            return lastMoveAt + Self.calmAfter
        }
        return nil
    }
}
