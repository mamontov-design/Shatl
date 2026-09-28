// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

#if DEBUG
/// Debug builds only: the flight recorder behind the frame meter. Hot paths
/// count what they did and time their spans; when a frame comes late, the
/// meter logs what happened on the main thread while the frame waited. While
/// the meter is off, every call returns at once.
@MainActor
enum ShatlFrameTrace {
    enum Counter: Int, CaseIterable {
        case cardUpdates
        case cardBodies
        case cardHovers
        case scrollEvents

        var logName: String {
            switch self {
            case .cardUpdates: "cards.updated"
            case .cardBodies: "cards.drawn"
            case .cardHovers: "cards.hover"
            case .scrollEvents: "scroll.events"
            }
        }
    }

    struct Span: Equatable {
        var name: String
        var duration: Double
    }

    /// Animations the meter counts while they run. SwiftUI does not say what
    /// it is animating, so each is noted where it starts, with its length.
    enum AnimationKind: Int, CaseIterable {
        case digits
        case chipDigits
        case bounce
        case highlight
        case speedColor
        case progressBar
        case hover
        case metricWidth
        case status
        case state

        var logName: String {
            switch self {
            case .digits: "digits"
            case .chipDigits: "chipdigits"
            case .bounce: "bounce"
            case .highlight: "highlight"
            case .speedColor: "speedcolor"
            case .progressBar: "progressbar"
            case .hover: "hover"
            case .metricWidth: "metricwidth"
            case .status: "status"
            case .state: "state"
            }
        }
    }

    private struct RunningAnimation {
        var kind: AnimationKind
        var cardID: UUID?
        var startedAt: Double
        var endsAt: Double
    }

    private static let spanLimit = 64

    private(set) static var isEnabled = false
    private static var counters = [Int](repeating: 0, count: Counter.allCases.count)
    private static var spans: [Span] = []
    private static var runningAnimations: [RunningAnimation] = []
    private static var startedAnimations = [Int](repeating: 0, count: AnimationKind.allCases.count)

    static func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        reset()
        runningAnimations.removeAll()
        startedAnimations = [Int](repeating: 0, count: AnimationKind.allCases.count)
    }

    static func animationStarted(_ kind: AnimationKind, cardID: UUID?, duration: Double, at time: Double = now()) {
        guard isEnabled else { return }
        runningAnimations.removeAll { $0.endsAt < time - 1 }
        runningAnimations.append(
            RunningAnimation(kind: kind, cardID: cardID, startedAt: time, endsAt: time + duration)
        )
        startedAnimations[kind.rawValue] += 1
    }

    /// Animations that ran at some point between `start` and `end`, as
    /// `kind:animations/cards`, e.g. `digits:7/4,bounce:2/2` (`-` for none),
    /// and how many cards animated anything.
    static func runningAnimations(from start: Double, to end: Double) -> (summary: String, cards: Int) {
        let running = runningAnimations.filter { $0.startedAt <= end && $0.endsAt > start }
        let fields: [String] = AnimationKind.allCases.compactMap { kind in
            let ofKind = running.filter { $0.kind == kind }
            guard !ofKind.isEmpty else { return nil }
            let cards = Set(ofKind.compactMap(\.cardID)).count
            return "\(kind.logName):\(ofKind.count)/\(cards)"
        }
        let cards = Set(running.compactMap(\.cardID)).count
        return (fields.isEmpty ? "-" : fields.joined(separator: ","), cards)
    }

    /// Animations started since the last call, as `kind:count`; `-` for none.
    static func drainStartedAnimations() -> String {
        defer { startedAnimations = [Int](repeating: 0, count: AnimationKind.allCases.count) }
        let fields: [String] = AnimationKind.allCases.compactMap { kind in
            let count = startedAnimations[kind.rawValue]
            return count > 0 ? "\(kind.logName):\(count)" : nil
        }
        return fields.isEmpty ? "-" : fields.joined(separator: ",")
    }

    /// Seconds on the clock `CADisplayLink` timestamps use.
    nonisolated static func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    static func count(_ counter: Counter, by amount: Int = 1) {
        guard isEnabled else { return }
        counters[counter.rawValue] += amount
    }

    static func beginSpan() -> Double {
        isEnabled ? now() : 0
    }

    static func endSpan(_ name: String, startedAt start: Double) {
        guard isEnabled, start > 0 else { return }
        spans.append(Span(name: name, duration: now() - start))
        if spans.count > spanLimit {
            spans.removeFirst(spans.count - spanLimit)
        }
    }

    /// Hands over the counts and spans gathered since the previous frame.
    static func drain() -> (counters: [Int], spans: [Span]) {
        defer { reset() }
        return (counters, spans)
    }

    private static func reset() {
        counters = [Int](repeating: 0, count: Counter.allCases.count)
        spans.removeAll(keepingCapacity: true)
    }
}
#endif
