// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Combine
import CoreText
import Foundation
import SwiftUI

/// The wordmark set in the system font: "Shatl" at 64 pt, whose weight and
/// width, two axes of SF Pro, keep changing. The standard set comes back
/// more often than any other. The optical size stays the system's own for
/// 64 pt: smaller ones are made for small text and open wide gaps between
/// large letters.
nonisolated enum ShatlTypeWordmark {
    static let text = "Shatl"
    static let fontSize: CGFloat = 64
    /// Wide enough for the widest letters (weight 1000 at width 150 make
    /// 230 pt); as tall as the logomark's box, so where the box stays (About)
    /// one fits both marks.
    static let frameSize = CGSize(width: 240, height: 85)
    /// The letters at any set: 46.1 pt over the baseline, 1 pt under it.
    /// They lie centred on the frame, so a box this high and centred on it
    /// holds them, with about the half point the logomark leaves in its own.
    static let lettersHeight: CGFloat = 48

    /// Weight and width of the letters; also their speeds, per second.
    struct Axes: Equatable {
        var weight: Double
        var width: Double
    }

    /// Width 132 is the system's Expanded; weight 540 lies between Medium
    /// and Semibold.
    static let standard = Axes(weight: 540, width: 132)

    /// Where the axes may go. Below weight 100 the letters are too thin;
    /// below width 100, the system's standard one, they turn condensed.
    static let weights: ClosedRange<Double> = 100...1000
    static let widths: ClosedRange<Double> = 100...150

    /// What the wordmark draws at a moment: its axes and its hue, a place
    /// on `ShatlColor.Wordmark.hues` from 0 (iris) to 3 (plum).
    struct Style: Equatable {
        var weight: Double
        var width: Double
        var hue: Double

        init(_ axes: Axes, hue: Double) {
            weight = axes.weight
            width = axes.width
            self.hue = hue
        }

        var axes: Axes {
            Axes(weight: weight, width: width)
        }
    }

    // MARK: Letters

    private static let weightTag = 0x7767_6874 // 'wght'
    private static let widthTag = 0x7764_7468 // 'wdth'

    /// The system font itself: SF Pro, with all its axes and the optical
    /// size the system sets for 64 pt. A copy of it is made for every set of
    /// axes, keeping that optical size; Core Text keeps no more of the copies
    /// than it needs (80 000 sets in a row left the memory where it was).
    nonisolated(unsafe) private static let systemFont: CTFont = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
        ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)

    /// The baseline stays where the capitals of the standard set stand in
    /// the middle of the frame, whatever the axes.
    static let capHeight: CGFloat = CTFontGetCapHeight(font(standard))

    static func font(_ axes: Axes) -> CTFont {
        let variation: [NSNumber: Double] = [
            NSNumber(value: weightTag): axes.weight,
            NSNumber(value: widthTag): axes.width,
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontVariationAttribute: variation] as CFDictionary
        )
        return CTFontCreateCopyWithAttributes(systemFont, fontSize, nil, descriptor)
    }

    /// The outlines of the letters in Core Text's space: the baseline at
    /// y = 0, y up.
    static func letters(_ axes: Axes) -> CGPath {
        let font = font(axes)
        let string = NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        let line = CTLineCreateWithAttributedString(string)
        let letters = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            for index in 0..<count {
                var place = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
                if let glyph = CTFontCreatePathForGlyph(font, glyphs[index], &place) {
                    letters.addPath(glyph)
                }
            }
        }
        return letters
    }
}

/// The letters for one set of axes, drawn as a shape rather than as text:
/// text takes no weight between the named ones, such as 540. The ink is centred
/// across the frame, so the word grows and narrows to both sides, and the
/// baseline never moves.
nonisolated struct ShatlTypeWordmarkShape: Shape {
    var axes: ShatlTypeWordmark.Axes

    func path(in rect: CGRect) -> Path {
        let letters = ShatlTypeWordmark.letters(axes)
        let ink = letters.boundingBoxOfPath
        let baseline = rect.midY + ShatlTypeWordmark.capHeight / 2
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: rect.midX - ink.midX, ty: baseline)
        return Path(letters.copy(using: &flip) ?? letters)
    }
}

/// How the type wordmark moves. A cycle is a rebuild to a new set, the hue
/// and one or both axes at once, then a slow glide on the way the rebuild
/// went. An axis the rebuild leaves keeps gliding through it. The glide is
/// centred on the set, so the standard set reads as itself for its whole
/// glide. The speed at the end of one part is the speed at the start of the
/// next: the wordmark never stops, except for an instant when an axis turns
/// back.
enum ShatlTypeWordmarkMotion {
    /// What a rebuild changes. Each axis goes up or down by chance, the
    /// other's way or not.
    nonisolated enum Change: Equatable {
        case both
        case weight
        case width
    }

    /// Half the rebuilds change both axes, a quarter the weight alone, a
    /// quarter the width alone.
    static let bothAxesShare = 0.5
    static let weightAloneShare = 0.25
    /// A rebuild moves the weight it changes at least this far, so it reads
    /// as one. The width moves less with the weight, more alone; with the
    /// weight it is free after the standard set and into it.
    static let minimumWeightChange: Double = 200
    static let minimumWidthChange: Double = 15
    static let minimumWidthAloneChange: Double = 20
    /// How far each axis glides.
    static let glideWeights: ClosedRange<Double> = 50...80
    static let glideWidths: ClosedRange<Double> = 6...12
    /// A rebuild moves the hue one or two places along the colour wheel.
    static let maximumHueStep = 2
    static let hueCount = 4
    /// The standard set comes about once in three rebuilds, never twice in
    /// a row, and after three other sets for sure.
    static let standardShare = 1.0 / 3
    static let maximumSetsBetweenStandards = 3

    static var rebuildDuration: TimeInterval { ShatlMotion.wordmarkRebuildDuration }
    static var glideDuration: TimeInterval { ShatlMotion.wordmarkGlideDuration }

    /// A set a rebuild goes to. An axis it leaves has the middle of its
    /// glide here, as a changed one has.
    nonisolated struct Target: Equatable {
        var axes: ShatlTypeWordmark.Axes
        var hue: Int
        var isStandard: Bool
        var change: Change
    }

    struct Cycle {
        let target: Target
        /// Other sets since the last standard one, this one counted.
        let setsSinceStandard: Int
        let timeline: KeyframeTimeline<ShatlTypeWordmark.Style>
        let end: ShatlTypeWordmark.Style
        let glideSpeed: ShatlTypeWordmark.Axes

        var duration: TimeInterval { timeline.duration }
    }

    /// Where one axis goes in a cycle: to `landing` with the rebuild, on to
    /// `end` with the glide.
    private struct AxisWay {
        let landing: Double
        let end: Double
    }

    /// The first cycle: the standard set, already gliding, in a random hue
    /// or in `hue`, the one the letters stood in.
    static func firstCycle<R: RandomNumberGenerator>(hue: Double? = nil, using random: inout R) -> Cycle {
        let standard = ShatlTypeWordmark.standard
        let startHue = hue ?? Double(Int.random(in: 0..<hueCount, using: &random))
        let target = Target(
            axes: standard,
            hue: Int(startHue.rounded()),
            isStandard: true,
            change: .both
        )
        let start = ShatlTypeWordmark.Style(standard, hue: startHue)
        let glide = glideAmounts(using: &random)
        let direction = ShatlTypeWordmark.Axes(
            weight: Bool.random(using: &random) ? 1 : -1,
            width: Bool.random(using: &random) ? 1 : -1
        )
        let end = clamped(ShatlTypeWordmark.Axes(
            weight: standard.weight + direction.weight * glide.weight,
            width: standard.width + direction.width * glide.width
        ))
        let speed = speed(from: standard, to: end, in: glideDuration)

        let timeline = KeyframeTimeline(initialValue: start) {
            KeyframeTrack(\ShatlTypeWordmark.Style.weight) {
                CubicKeyframe(end.weight, duration: glideDuration, startVelocity: speed.weight, endVelocity: speed.weight)
            }
            KeyframeTrack(\ShatlTypeWordmark.Style.width) {
                CubicKeyframe(end.width, duration: glideDuration, startVelocity: speed.width, endVelocity: speed.width)
            }
            KeyframeTrack(\ShatlTypeWordmark.Style.hue) {
                CubicKeyframe(start.hue, duration: glideDuration, startVelocity: 0, endVelocity: 0)
            }
        }

        return Cycle(
            target: target,
            setsSinceStandard: 0,
            timeline: timeline,
            end: ShatlTypeWordmark.Style(end, hue: start.hue),
            glideSpeed: speed
        )
    }

    static func nextCycle<R: RandomNumberGenerator>(after previous: Cycle, using random: inout R) -> Cycle {
        var target = nextTarget(after: previous, using: &random)
        let start = previous.end
        let carried = previous.glideSpeed
        let glide = glideAmounts(using: &random)

        let weight = target.change == .width
            ? keptWay(from: start.weight, speed: carried.weight, glide: glide.weight, in: ShatlTypeWordmark.weights)
            : rebuiltWay(from: start.weight, to: target.axes.weight, glide: glide.weight, in: ShatlTypeWordmark.weights)
        let width = target.change == .weight
            ? keptWay(from: start.width, speed: carried.width, glide: glide.width, in: ShatlTypeWordmark.widths)
            : rebuiltWay(from: start.width, to: target.axes.width, glide: glide.width, in: ShatlTypeWordmark.widths)
        if target.change == .width {
            target.axes.weight = (weight.landing + weight.end) / 2
        }
        if target.change == .weight {
            target.axes.width = (width.landing + width.end) / 2
        }

        let landing = ShatlTypeWordmark.Axes(weight: weight.landing, width: width.landing)
        let end = ShatlTypeWordmark.Axes(weight: weight.end, width: width.end)
        let speed = speed(from: landing, to: end, in: glideDuration)
        let hue = Double(target.hue)

        let timeline = KeyframeTimeline(initialValue: start) {
            KeyframeTrack(\ShatlTypeWordmark.Style.weight) {
                CubicKeyframe(landing.weight, duration: rebuildDuration, startVelocity: carried.weight, endVelocity: speed.weight)
                CubicKeyframe(end.weight, duration: glideDuration, startVelocity: speed.weight, endVelocity: speed.weight)
            }
            KeyframeTrack(\ShatlTypeWordmark.Style.width) {
                CubicKeyframe(landing.width, duration: rebuildDuration, startVelocity: carried.width, endVelocity: speed.width)
                CubicKeyframe(end.width, duration: glideDuration, startVelocity: speed.width, endVelocity: speed.width)
            }
            KeyframeTrack(\ShatlTypeWordmark.Style.hue) {
                CubicKeyframe(hue, duration: rebuildDuration, startVelocity: 0, endVelocity: 0)
                CubicKeyframe(hue, duration: glideDuration, startVelocity: 0, endVelocity: 0)
            }
        }

        return Cycle(
            target: target,
            setsSinceStandard: target.isStandard ? 0 : previous.setsSinceStandard + 1,
            timeline: timeline,
            end: ShatlTypeWordmark.Style(end, hue: hue),
            glideSpeed: speed
        )
    }

    /// A curve may carry an axis a little past its range as it turns back;
    /// the letters never go there.
    static func clamped(_ style: ShatlTypeWordmark.Style) -> ShatlTypeWordmark.Style {
        ShatlTypeWordmark.Style(
            clamped(style.axes),
            hue: min(max(style.hue, 0), Double(hueCount - 1))
        )
    }

    // MARK: Standing still

    /// Under Reduce Motion the letters stand at the standard set and only
    /// the hue moves, one or two places at a time as with the rebuilds. Each
    /// move takes a whole cycle and the moves join into one smooth curve
    /// through the hues (Catmull–Rom): at a hue the colour passes through it
    /// goes on at the speed of the moves around it, so nothing blinks every
    /// few seconds. At a hue it turns back from it slows to a stop for an
    /// instant, as an axis does: carried on, it would run past the hue, and
    /// past the end of the wheel stand still there.
    struct HueDrift {
        /// The hue before the move, its two ends, the hue after it.
        private(set) var hues: [Double]
        private(set) var moveStart: Date

        static var moveDuration: TimeInterval { ShatlMotion.wordmarkStillHueMoveDuration }

        init<R: RandomNumberGenerator>(from hue: Double, at date: Date, using random: inout R) {
            let next = Double(nextHue(after: Int(hue.rounded()), using: &random))
            let after = Double(nextHue(after: Int(next), using: &random))
            hues = [hue, hue, next, after]
            moveStart = date
        }

        mutating func hue<R: RandomNumberGenerator>(at date: Date, using random: inout R) -> Double {
            var elapsed = max(0, date.timeIntervalSince(moveStart))
            if elapsed > Self.moveDuration * 3 {
                // Out of sight a while: go on from where it stopped.
                self = HueDrift(from: hues[1], at: date, using: &random)
                elapsed = 0
            }
            while elapsed >= Self.moveDuration {
                elapsed -= Self.moveDuration
                moveStart += Self.moveDuration
                hues.removeFirst()
                hues.append(Double(nextHue(after: Int(hues[2]), using: &random)))
            }
            let t = elapsed / Self.moveDuration
            let (before, from, to, after) = (hues[0], hues[1], hues[2], hues[3])
            let speedFrom = Self.speed(at: from, between: before, and: to)
            let speedTo = Self.speed(at: to, between: from, and: after)
            let hue = (2 * t * t * t - 3 * t * t + 1) * from
                + (t * t * t - 2 * t * t + t) * speedFrom
                + (3 * t * t - 2 * t * t * t) * to
                + (t * t * t - t * t) * speedTo
            return min(max(hue, 0), Double(hueCount - 1))
        }

        /// The speed at `hue`, in hues a move: that of the moves around it,
        /// or none where the colour turns back.
        private static func speed(at hue: Double, between previous: Double, and next: Double) -> Double {
            (hue - previous) * (next - hue) < 0 ? 0 : (next - previous) / 2
        }
    }

    // MARK: Sets

    private static func nextTarget<R: RandomNumberGenerator>(after previous: Cycle, using random: inout R) -> Target {
        let hue = nextHue(after: previous.target.hue, using: &random)
        let standard = ShatlTypeWordmark.standard
        let last = previous.target.axes

        if !previous.target.isStandard {
            let isDue = previous.setsSinceStandard >= maximumSetsBetweenStandards
            let comesByChance = Double.random(in: 0..<1, using: &random) < standardShare
                && abs(standard.weight - last.weight) >= minimumWeightChange
            if isDue || comesByChance {
                return Target(axes: standard, hue: hue, isStandard: true, change: .both)
            }
        }

        // Before a standard set that is due the weight moves and keeps clear
        // of the standard weight, so that rebuild reads as one too.
        let setsSinceStandard = previous.target.isStandard ? 1 : previous.setsSinceStandard + 1
        let standardIsDueNext = setsSinceStandard >= maximumSetsBetweenStandards
        var change = randomChange(using: &random)
        if change == .width, standardIsDueNext {
            change = .both
        }

        var axes = last
        if change != .width {
            axes.weight = randomValue(
                in: ShatlTypeWordmark.weights,
                awayFrom: standardIsDueNext ? [last.weight, standard.weight] : [last.weight],
                by: minimumWeightChange,
                using: &random
            )
        }
        if change != .weight {
            // With the weight, the width after the standard set is free:
            // keeping clear of 132, high in the widths, would send it down
            // almost every time, and thin letters with it. Alone, it has to
            // move to be seen, and from 132 that is down.
            let isFree = change == .both && previous.target.isStandard
            axes.width = randomValue(
                in: ShatlTypeWordmark.widths,
                awayFrom: isFree ? [] : [last.width],
                by: change == .width ? minimumWidthAloneChange : minimumWidthChange,
                using: &random
            )
        }
        return Target(axes: axes, hue: hue, isStandard: false, change: change)
    }

    private static func randomChange<R: RandomNumberGenerator>(using random: inout R) -> Change {
        let roll = Double.random(in: 0..<1, using: &random)
        if roll < bothAxesShare { return .both }
        if roll < bothAxesShare + weightAloneShare { return .weight }
        return .width
    }

    private static func nextHue<R: RandomNumberGenerator>(after hue: Int, using random: inout R) -> Int {
        let choices = (-maximumHueStep...maximumHueStep)
            .map { hue + $0 }
            .filter { $0 != hue && (0..<hueCount).contains($0) }
        return choices.randomElement(using: &random) ?? hue
    }

    /// A random value of `range` at least `gap` from each of `others`, any
    /// of them as likely. The ranges always leave room: the weight has 900
    /// to keep clear of two gaps of 400, the width 50 to keep clear of one
    /// gap of 40. Should none be left, the end of the range farthest from
    /// the first of `others`.
    private static func randomValue<R: RandomNumberGenerator>(
        in range: ClosedRange<Double>,
        awayFrom others: [Double],
        by gap: Double,
        using random: inout R
    ) -> Double {
        var pieces = [range]
        for other in others {
            pieces = pieces.flatMap { piece -> [ClosedRange<Double>] in
                var kept: [ClosedRange<Double>] = []
                if piece.lowerBound <= other - gap {
                    kept.append(piece.lowerBound...min(piece.upperBound, other - gap))
                }
                if piece.upperBound >= other + gap {
                    kept.append(max(piece.lowerBound, other + gap)...piece.upperBound)
                }
                return kept
            }
        }
        guard let first = pieces.first else {
            let last = others.first ?? range.lowerBound
            return last - range.lowerBound > range.upperBound - last ? range.lowerBound : range.upperBound
        }
        let total = pieces.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
        guard total > 0 else { return first.lowerBound }
        var place = Double.random(in: 0..<total, using: &random)
        for piece in pieces {
            let length = piece.upperBound - piece.lowerBound
            if place <= length {
                return piece.lowerBound + place
            }
            place -= length
        }
        return pieces[pieces.count - 1].upperBound
    }

    // MARK: Glides

    private static func glideAmounts<R: RandomNumberGenerator>(using random: inout R) -> ShatlTypeWordmark.Axes {
        ShatlTypeWordmark.Axes(
            weight: Double.random(in: glideWeights, using: &random),
            width: Double.random(in: glideWidths, using: &random)
        )
    }

    /// An axis the rebuild changes: the glide after it is centred on the
    /// set and goes on the way the rebuild went.
    private static func rebuiltWay(
        from start: Double,
        to target: Double,
        glide: Double,
        in range: ClosedRange<Double>
    ) -> AxisWay {
        let direction: Double
        if abs(target - start) > 0.001 {
            direction = target > start ? 1 : -1
        } else {
            direction = target < (range.lowerBound + range.upperBound) / 2 ? 1 : -1
        }
        return AxisWay(
            landing: clamped(target - direction * glide / 2, to: range),
            end: clamped(target + direction * glide / 2, to: range)
        )
    }

    /// An axis the rebuild leaves: it glides on the way it went, through the
    /// rebuild too, and turns back before it would leave its range.
    private static func keptWay(
        from start: Double,
        speed: Double,
        glide: Double,
        in range: ClosedRange<Double>
    ) -> AxisWay {
        var direction: Double
        if abs(speed) > 0.001 {
            direction = speed > 0 ? 1 : -1
        } else {
            direction = start < (range.lowerBound + range.upperBound) / 2 ? 1 : -1
        }
        let distance = glide * (rebuildDuration + glideDuration) / glideDuration
        if !range.contains(start + direction * distance) {
            direction = -direction
        }
        let perSecond = direction * glide / glideDuration
        let landing = clamped(start + perSecond * rebuildDuration, to: range)
        return AxisWay(landing: landing, end: clamped(landing + perSecond * glideDuration, to: range))
    }

    private static func speed(
        from start: ShatlTypeWordmark.Axes,
        to end: ShatlTypeWordmark.Axes,
        in duration: TimeInterval
    ) -> ShatlTypeWordmark.Axes {
        ShatlTypeWordmark.Axes(
            weight: (end.weight - start.weight) / duration,
            width: (end.width - start.width) / duration
        )
    }

    private static func clamped(_ axes: ShatlTypeWordmark.Axes) -> ShatlTypeWordmark.Axes {
        ShatlTypeWordmark.Axes(
            weight: clamped(axes.weight, to: ShatlTypeWordmark.weights),
            width: clamped(axes.width, to: ShatlTypeWordmark.widths)
        )
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Plays the cycles one after another against the clock. It publishes
/// nothing: the timeline view asks it for every frame.
@MainActor
final class ShatlTypeWordmarkPlayer: ObservableObject {
    private var random: ShatlAnyRandom
    private var cycle: ShatlTypeWordmarkMotion.Cycle
    private var cycleStart: Date
    /// Set while the letters stand still.
    private var drift: ShatlTypeWordmarkMotion.HueDrift?
    /// The hue of the last frame: the letters stop and set off again in it.
    private var lastHue: Double

    /// Tests pass a seeded `random`, so a run can be read again.
    init(random: any RandomNumberGenerator = SystemRandomNumberGenerator(), start: Date = .now) {
        var random = ShatlAnyRandom(base: random)
        cycle = ShatlTypeWordmarkMotion.firstCycle(using: &random)
        self.random = random
        cycleStart = start
        lastHue = cycle.end.hue
    }

    /// Back to the standard set in a random hue, as the wordmark comes back
    /// from the logomark.
    func restart(at date: Date) {
        if drift != nil {
            let hue = Double(Int.random(in: 0..<ShatlTypeWordmarkMotion.hueCount, using: &random))
            drift = ShatlTypeWordmarkMotion.HueDrift(from: hue, at: date, using: &random)
        } else {
            cycle = ShatlTypeWordmarkMotion.firstCycle(using: &random)
            cycleStart = date
        }
    }

    /// `standsStill` under Reduce Motion: the letters stand at the standard
    /// set, at once when it is turned on, and only the hue moves.
    func style(at date: Date, standsStill: Bool = false) -> ShatlTypeWordmark.Style {
        if standsStill {
            if drift == nil {
                drift = ShatlTypeWordmarkMotion.HueDrift(from: lastHue, at: date, using: &random)
            }
            lastHue = drift!.hue(at: date, using: &random)
            return ShatlTypeWordmark.Style(ShatlTypeWordmark.standard, hue: lastHue)
        }
        if drift != nil {
            drift = nil
            cycle = ShatlTypeWordmarkMotion.firstCycle(hue: lastHue, using: &random)
            cycleStart = date
        }
        let style = movingStyle(at: date)
        lastHue = style.hue
        return style
    }

    private func movingStyle(at date: Date) -> ShatlTypeWordmark.Style {
        var elapsed = max(0, date.timeIntervalSince(cycleStart))
        if elapsed > cycle.duration * 3 {
            // The clock went on while the wordmark was out of sight: go on
            // from where it stopped rather than play the cycles it missed.
            cycle = ShatlTypeWordmarkMotion.nextCycle(after: cycle, using: &random)
            cycleStart = date
            elapsed = 0
        }
        while elapsed >= cycle.duration {
            elapsed -= cycle.duration
            cycleStart += cycle.duration
            cycle = ShatlTypeWordmarkMotion.nextCycle(after: cycle, using: &random)
        }
        return ShatlTypeWordmarkMotion.clamped(cycle.timeline.value(time: elapsed))
    }
}

private struct ShatlAnyRandom: RandomNumberGenerator {
    var base: any RandomNumberGenerator

    mutating func next() -> UInt64 {
        base.next()
    }
}

/// The wordmark in the system font, filled without glass. Its colour
/// follows the weight, the bolder the paler (`ShatlColor.Wordmark`): in the
/// app's own accent through four hues, in the monochrome appearance in grey,
/// with the accent of macOS in that colour. It moves only while it is the
/// mark shown, and under Reduce Motion it stands at the standard set and
/// changes only its hue.
struct ShatlTypeWordmarkArtwork: View {
    @EnvironmentObject private var accentState: ShatlAccentState
    @Environment(\.shatlUsesMonochromeAppearance) private var usesMonochrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var player = ShatlTypeWordmarkPlayer()

    let isAnimating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isAnimating || standsStillInOneColour)) { context in
            let style = player.style(at: context.date, standsStill: reduceMotion)
            ShatlTypeWordmarkShape(axes: style.axes)
                .fill(fillColor(for: style))
        }
        .frame(width: ShatlTypeWordmark.frameSize.width, height: ShatlTypeWordmark.frameSize.height)
        .onChange(of: isAnimating) { _, isAnimating in
            guard isAnimating else { return }
            player.restart(at: .now)
        }
    }

    /// Standing still, the letters change only their hue, and only the
    /// app's own accent has hues: nothing is left to draw anew.
    private var standsStillInOneColour: Bool {
        reduceMotion && (usesMonochrome || !accentState.isUsingAppAccent)
    }

    private func fillColor(for style: ShatlTypeWordmark.Style) -> Color {
        if usesMonochrome {
            ShatlColor.Wordmark.gray.color(weight: style.weight)
        } else if accentState.isUsingAppAccent {
            ShatlColor.Wordmark.color(hue: style.hue, weight: style.weight)
        } else {
            ShatlColor.Wordmark.systemAccent(
                accentState.systemAccentColor,
                weight: style.weight,
                colorScheme: colorScheme
            )
        }
    }
}
