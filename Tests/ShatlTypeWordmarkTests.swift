// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XCTest
@testable import Shatl

/// The wordmark in the system font: it starts at the standard set, every
/// rebuild reads as one, the standard set comes often, the motion never
/// stops or jumps, under Reduce Motion only the hue moves, and the colour
/// follows the hue and the weight only.
@MainActor
final class ShatlTypeWordmarkTests: XCTestCase {
    private typealias Motion = ShatlTypeWordmarkMotion
    private let standard = ShatlTypeWordmark.standard

    func testTheWordmarkStartsAtTheStandardSet() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let player = ShatlTypeWordmarkPlayer(random: SeededRandom(seed: 1), start: start)

        XCTAssertEqual(player.style(at: start).axes, standard)

        player.restart(at: start.addingTimeInterval(100))
        XCTAssertEqual(player.style(at: start.addingTimeInterval(100)).axes, standard)
    }

    /// What a rebuild changes moves far enough to be seen: the weight by
    /// 200, the width by 15 beside it (free after the standard set and into
    /// it) and by 20 alone. Before a standard set that is due the weight
    /// always moves.
    func testEveryRebuildReadsAsOneAndTheHueMovesOneOrTwoPlaces() {
        var problems: [String] = []
        for seed in UInt64(1)...8 {
            var random = SeededRandom(seed: seed)
            var cycle = Motion.firstCycle(using: &random)
            for index in 0..<5000 {
                let next = Motion.nextCycle(after: cycle, using: &random)
                let weightChange = abs(next.target.axes.weight - cycle.target.axes.weight)
                let widthChange = abs(next.target.axes.width - cycle.target.axes.width)
                let hueStep = abs(next.target.hue - cycle.target.hue)
                let movesEnough: Bool
                if next.target.isStandard {
                    movesEnough = weightChange >= Motion.minimumWeightChange
                } else {
                    switch next.target.change {
                    case .both:
                        movesEnough = weightChange >= Motion.minimumWeightChange
                            && (cycle.target.isStandard || widthChange >= Motion.minimumWidthChange)
                    case .weight:
                        movesEnough = weightChange >= Motion.minimumWeightChange
                    case .width:
                        movesEnough = widthChange >= Motion.minimumWidthAloneChange
                            && next.setsSinceStandard < Motion.maximumSetsBetweenStandards
                    }
                }
                if !movesEnough
                    || !(1...Motion.maximumHueStep).contains(hueStep)
                    || !(0..<ShatlColor.Wordmark.hues.count).contains(next.target.hue) {
                    problems.append("seed \(seed), rebuild \(index): \(cycle.target) → \(next.target)")
                }
                cycle = next
            }
        }
        XCTAssertEqual(problems.prefix(5), [])
    }

    /// Half the rebuilds change both axes, a quarter the weight alone, the
    /// rest the width alone, less often as it gives way before a standard
    /// set that is due. Both axes go the same way as often as not, and thin
    /// letters are wide about as often as narrow: after the standard set the
    /// width does not keep clear of 132, which sent thin letters narrow.
    func testRebuildsMixTheAxesAndThinLettersAreWideAsOftenAsNarrow() {
        var random = SeededRandom(seed: 13)
        var cycle = Motion.firstCycle(using: &random)
        var changes: [Motion.Change: Int] = [:]
        var others = 0
        var sameWay = 0
        var bothAxes = 0
        var thinWide = 0
        var thinNarrow = 0
        for _ in 0..<20000 {
            let next = Motion.nextCycle(after: cycle, using: &random)
            if !next.target.isStandard {
                others += 1
                changes[next.target.change, default: 0] += 1
                let axes = next.target.axes
                if axes.weight <= 300 {
                    if axes.width >= 140 { thinWide += 1 }
                    if axes.width <= 110 { thinNarrow += 1 }
                }
                if next.target.change == .both, !cycle.target.isStandard {
                    bothAxes += 1
                    let weightRises = axes.weight > cycle.target.axes.weight
                    let widthRises = axes.width > cycle.target.axes.width
                    if weightRises == widthRises { sameWay += 1 }
                }
            }
            cycle = next
        }

        func share(_ change: Motion.Change) -> Double {
            Double(changes[change, default: 0]) / Double(others)
        }
        XCTAssertTrue((0.5...0.62).contains(share(.both)), "both \(share(.both))")
        XCTAssertTrue((0.22...0.28).contains(share(.weight)), "weight alone \(share(.weight))")
        XCTAssertTrue((0.14...0.25).contains(share(.width)), "width alone \(share(.width))")
        let sameWayShare = Double(sameWay) / Double(bothAxes)
        XCTAssertTrue((0.45...0.55).contains(sameWayShare), "same way \(sameWayShare)")
        let wideToNarrow = Double(thinWide) / Double(thinNarrow)
        XCTAssertTrue((0.8...1.6).contains(wideToNarrow), "thin wide / thin narrow \(wideToNarrow)")
    }

    func testTheStandardSetComesOftenButNeverTwiceInARow() {
        var random = SeededRandom(seed: 3)
        var cycle = Motion.firstCycle(using: &random)
        var standards = 0
        var others = 0
        var othersInARow = 0
        var hues = Set<Int>()
        for _ in 0..<3000 {
            let next = Motion.nextCycle(after: cycle, using: &random)
            if next.target.isStandard {
                XCTAssertFalse(cycle.target.isStandard)
                XCTAssertEqual(next.target.axes, standard)
                hues.insert(next.target.hue)
                standards += 1
                othersInARow = 0
            } else {
                others += 1
                othersInARow += 1
                XCTAssertLessThanOrEqual(othersInARow, Motion.maximumSetsBetweenStandards)
            }
            cycle = next
        }

        let share = Double(standards) / Double(standards + others)
        XCTAssertTrue((0.25...0.4).contains(share), "standard share \(share)")
        XCTAssertEqual(hues.count, ShatlColor.Wordmark.hues.count, "the standard set takes any hue")
    }

    /// The glide is centred on its set: halfway through it the letters stand
    /// on the standard weight and width.
    func testTheGlidePassesThroughTheStandardSet() throws {
        var random = SeededRandom(seed: 5)
        var cycle = Motion.firstCycle(using: &random)
        var checked = 0
        for _ in 0..<300 {
            cycle = Motion.nextCycle(after: cycle, using: &random)
            guard cycle.target.isStandard else { continue }
            let middle = cycle.timeline.value(time: Motion.rebuildDuration + Motion.glideDuration / 2)
            XCTAssertEqual(middle.weight, standard.weight, accuracy: 0.01)
            XCTAssertEqual(middle.width, standard.width, accuracy: 0.01)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 50)
    }

    /// Ten minutes at 60 frames a second: every axis stays in its range,
    /// nothing jumps from one frame to the next, and the weight is always
    /// on its way somewhere.
    func testTheWordmarkNeverStopsNorJumpsAndStaysInItsRanges() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let player = ShatlTypeWordmarkPlayer(random: SeededRandom(seed: 11), start: start)
        let framesPerSecond = 60
        let halfSecond = framesPerSecond / 2
        var previous = player.style(at: start)
        var weightSteps: [Double] = []
        var problems: [String] = []
        var stillest = Double.infinity

        for frame in 1...(framesPerSecond * 600) {
            let style = player.style(at: start.addingTimeInterval(Double(frame) / Double(framesPerSecond)))
            if !ShatlTypeWordmark.weights.contains(style.weight)
                || !ShatlTypeWordmark.widths.contains(style.width)
                || !(0...4).contains(style.hue) {
                problems.append("out of range at frame \(frame): \(style)")
            }
            // A rebuild across the whole weight peaks near 850 a second,
            // 14 a frame; a jump would be hundreds.
            if abs(style.weight - previous.weight) > 25
                || abs(style.width - previous.width) > 4
                || abs(style.hue - previous.hue) > 0.1 {
                problems.append("jump at frame \(frame): \(previous) → \(style)")
            }
            weightSteps.append(abs(style.weight - previous.weight))
            if weightSteps.count > halfSecond {
                weightSteps.removeFirst()
                stillest = min(stillest, weightSteps.reduce(0, +))
            }
            previous = style
        }

        XCTAssertEqual(problems.prefix(5), [])
        // The slowest glide covers 50 in 2.8 s, 9 in half a second; a weight
        // the rebuild leaves turns back at the end of its range in less.
        XCTAssertGreaterThan(stillest, 2, "the weight stood almost still for half a second")
    }

    /// The step follows the weight: thin letters solid, the standard set on
    /// the pastel step, bold letters pale; the dark theme takes the step one
    /// up at the thin end, as `accentColored` does.
    func testTheColourFollowsTheWeight() throws {
        let palette: [(thin: Color, standard: Color, bold: Color, thinDark: Color, standardDark: Color, boldDark: Color)] = [
            (ShatlPalette.indigo9, ShatlPalette.indigo8, ShatlPalette.indigo6, ShatlPalette.indigoDark10, ShatlPalette.indigoDark8, ShatlPalette.indigoDark7),
            (ShatlPalette.iris9, ShatlPalette.iris8, ShatlPalette.iris6, ShatlPalette.irisDark10, ShatlPalette.irisDark8, ShatlPalette.irisDark7),
            (ShatlPalette.violet9, ShatlPalette.violet8, ShatlPalette.violet6, ShatlPalette.violetDark10, ShatlPalette.violetDark8, ShatlPalette.violetDark7),
            (ShatlPalette.purple9, ShatlPalette.purple8, ShatlPalette.purple6, ShatlPalette.purpleDark10, ShatlPalette.purpleDark8, ShatlPalette.purpleDark7),
            (ShatlPalette.plum9, ShatlPalette.plum8, ShatlPalette.plum6, ShatlPalette.plumDark10, ShatlPalette.plumDark8, ShatlPalette.plumDark7),
        ]
        for (index, steps) in palette.enumerated() {
            let hue = Double(index)
            let color = { (weight: Double) in ShatlColor.Wordmark.color(hue: hue, weight: weight) }
            XCTAssertEqual(try components(color(100), in: .light), try components(steps.thin, in: .light))
            XCTAssertEqual(try components(color(540), in: .light), try components(steps.standard, in: .light))
            XCTAssertEqual(try components(color(1000), in: .light), try components(steps.bold, in: .light))
            XCTAssertEqual(try components(color(100), in: .dark), try components(steps.thinDark, in: .dark))
            XCTAssertEqual(try components(color(540), in: .dark), try components(steps.standardDark, in: .dark))
            XCTAssertEqual(try components(color(1000), in: .dark), try components(steps.boldDark, in: .dark))

            // Between two steps, a colour between them.
            let between = try components(color(320), in: .light)
            let thin = try components(steps.thin, in: .light)
            let pastel = try components(steps.standard, in: .light)
            XCTAssertNotEqual(between, thin)
            XCTAssertNotEqual(between, pastel)
            for channel in 0..<3 {
                XCTAssertTrue(
                    (min(thin[channel], pastel[channel]) - 2...max(thin[channel], pastel[channel]) + 2).contains(between[channel]),
                    "channel \(channel) of \(between) lies outside \(thin)…\(pastel)"
                )
            }
        }

        // Between two hues, a colour between them too.
        let violet = try components(ShatlPalette.violet8, in: .light)
        let purple = try components(ShatlPalette.purple8, in: .light)
        let halfway = try components(ShatlColor.Wordmark.color(hue: 2.5, weight: 540), in: .light)
        XCTAssertNotEqual(halfway, violet)
        XCTAssertNotEqual(halfway, purple)
    }

    /// The letters are as wide as the font sets them, and the widest fit
    /// the frame.
    func testTheWidestLettersFitTheFrame() {
        let widest = ShatlTypeWordmark.letters(.init(weight: 1000, width: 150)).boundingBoxOfPath
        let standardLetters = ShatlTypeWordmark.letters(standard).boundingBoxOfPath
        XCTAssertLessThanOrEqual(widest.width, ShatlTypeWordmark.frameSize.width)
        XCTAssertGreaterThan(standardLetters.width, 150)
        XCTAssertLessThan(standardLetters.width, widest.width)
    }

    /// On the empty list the box is as high as the letters, centred on
    /// them, so no set reaches out of it.
    func testTheLettersFitTheBoxOnTheEmptyList() {
        let frame = CGRect(origin: .zero, size: ShatlTypeWordmark.frameSize)
        let box = frame.insetBy(dx: 0, dy: (frame.height - ShatlTypeWordmark.lettersHeight) / 2)
        for weight in [100.0, 540, 1000] {
            for width in [100.0, 132, 150] {
                let ink = ShatlTypeWordmarkShape(axes: .init(weight: weight, width: width))
                    .path(in: frame)
                    .boundingRect
                XCTAssertGreaterThanOrEqual(ink.minY, box.minY, "\(weight)/\(width) reaches over the box")
                XCTAssertLessThanOrEqual(ink.maxY, box.maxY, "\(weight)/\(width) reaches under the box")
                // Room for about a point at most on each side; the logomark
                // leaves half a point.
                XCTAssertLessThan(box.height - ink.height, 2)
            }
        }
    }

    /// Under Reduce Motion the letters stand at the standard set; the hue
    /// moves one or two places at a time, never stops for long and never
    /// jumps.
    func testUnderReduceMotionTheLettersStandAndTheHueFlows() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let player = ShatlTypeWordmarkPlayer(random: SeededRandom(seed: 21), start: start)
        let framesPerSecond = 60
        var previous = player.style(at: start, standsStill: true)
        var lastSecond: [Double] = []
        var stillest = Double.infinity
        var problems: [String] = []

        for frame in 1...(framesPerSecond * 600) {
            let style = player.style(at: start.addingTimeInterval(Double(frame) / Double(framesPerSecond)), standsStill: true)
            if style.axes != standard {
                problems.append("the letters moved at frame \(frame): \(style)")
            }
            if !(0...4).contains(style.hue) || abs(style.hue - previous.hue) > 0.05 {
                problems.append("hue out of range or jumped at frame \(frame): \(previous.hue) → \(style.hue)")
            }
            lastSecond.append(style.hue)
            if lastSecond.count > framesPerSecond {
                lastSecond.removeFirst()
                stillest = min(stillest, (lastSecond.max() ?? 0) - (lastSecond.min() ?? 0))
            }
            previous = style
        }

        XCTAssertEqual(problems.prefix(5), [])
        XCTAssertGreaterThan(stillest, 0.01, "the hue stood still for a second")

        var random = SeededRandom(seed: 22)
        var drift = Motion.HueDrift(from: 2, at: start, using: &random)
        var hue = 2
        for move in 1...2000 {
            let reached = drift.hue(at: start.addingTimeInterval(Double(move) * Motion.HueDrift.moveDuration), using: &random)
            XCTAssertEqual(reached, reached.rounded(), accuracy: 0.0001, "move \(move) ends between hues")
            XCTAssertTrue((1...2).contains(abs(Int(reached.rounded()) - hue)), "move \(move): \(hue) → \(reached)")
            hue = Int(reached.rounded())
        }
    }

    /// Reduce Motion turned on stops the letters at the standard set in the
    /// hue they had; turned off, they set off from there.
    func testTheLettersStopAndSetOffInTheirHue() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let player = ShatlTypeWordmarkPlayer(random: SeededRandom(seed: 31), start: start)
        let frame = 1.0 / 60
        var date = start.addingTimeInterval(13)
        let moving = player.style(at: date)

        date += frame
        let stopped = player.style(at: date, standsStill: true)
        XCTAssertEqual(stopped.axes, standard)
        XCTAssertEqual(stopped.hue, moving.hue, accuracy: 0.05)

        date += 7
        let still = player.style(at: date, standsStill: true)
        date += frame
        let setOff = player.style(at: date)
        XCTAssertEqual(setOff.axes.weight, standard.weight, accuracy: 1)
        XCTAssertEqual(setOff.axes.width, standard.width, accuracy: 0.2)
        XCTAssertEqual(setOff.hue, still.hue, accuracy: 0.05)
    }

    /// The monochrome appearance takes grey at the steps of the hues; the
    /// accent of macOS gets paler with the weight as the hues do, and in
    /// light never lighter than step 6.
    func testMonochromeAndTheMacOSAccentFollowTheWeight() throws {
        let gray = ShatlColor.Wordmark.gray
        XCTAssertEqual(try components(gray.color(weight: 100), in: .light), try components(ShatlPalette.gray9, in: .light))
        XCTAssertEqual(try components(gray.color(weight: 540), in: .light), try components(ShatlPalette.gray8, in: .light))
        XCTAssertEqual(try components(gray.color(weight: 1000), in: .light), try components(ShatlPalette.gray6, in: .light))
        XCTAssertEqual(try components(gray.color(weight: 100), in: .dark), try components(ShatlPalette.grayDark10, in: .dark))
        XCTAssertEqual(try components(gray.color(weight: 540), in: .dark), try components(ShatlPalette.grayDark8, in: .dark))
        XCTAssertEqual(try components(gray.color(weight: 1000), in: .dark), try components(ShatlPalette.grayDark7, in: .dark))

        // An accent of step 9 lands on steps 8 and 6 of its own scale, one of
        // step 10 in dark on steps 8 and 7.
        let accent = { (accent: Color, weight: Double, scheme: ColorScheme) in
            ShatlColor.Wordmark.systemAccent(accent, weight: weight, colorScheme: scheme)
        }
        XCTAssertEqual(try components(accent(ShatlPalette.violet9, 100, .light), in: .light), try components(ShatlPalette.violet9, in: .light))
        XCTAssertEqual(lightness(accent(ShatlPalette.violet9, 540, .light), in: .light), lightness(ShatlPalette.violet8, in: .light), accuracy: 0.02)
        XCTAssertEqual(lightness(accent(ShatlPalette.violet9, 1000, .light), in: .light), lightness(ShatlPalette.violet6, in: .light), accuracy: 0.02)
        XCTAssertEqual(lightness(accent(ShatlPalette.violetDark10, 540, .dark), in: .dark), lightness(ShatlPalette.violetDark8, in: .dark), accuracy: 0.03)
        XCTAssertEqual(lightness(accent(ShatlPalette.violetDark10, 1000, .dark), in: .dark), lightness(ShatlPalette.violetDark7, in: .dark), accuracy: 0.03)

        // The accents of macOS: paler with the weight, yellow no paler than it is.
        let limit = lightness(ShatlColor.Wordmark.lightestStep, in: .light)
        for system in [NSColor.systemBlue, .systemPink, .systemGreen, .systemOrange, .systemGray, .systemYellow] {
            let color = Color(nsColor: system)
            let light = [100.0, 320, 540, 770, 1000].map { lightness(accent(color, $0, .light), in: .light) }
            let dark = [100.0, 320, 540, 770, 1000].map { lightness(accent(color, $0, .dark), in: .dark) }
            XCTAssertEqual(light, light.sorted(), "\(system) gets darker with the weight in light")
            XCTAssertEqual(dark, dark.sorted(by: >), "\(system) gets lighter with the weight in dark")
            XCTAssertLessThanOrEqual(light.last ?? 1, max(limit, light[0]) + 0.005, "\(system) is lighter than step 6")
            XCTAssertLessThan(dark.last ?? 0, dark[0] - 0.03, "\(system) stays as it is in dark")
        }
        let yellow = Color(nsColor: .systemYellow)
        XCTAssertEqual(lightness(accent(yellow, 1000, .light), in: .light), lightness(yellow, in: .light), accuracy: 0.005)
    }

    private func lightness(_ color: Color, in scheme: ColorScheme) -> Double {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return ShatlOklab.lightness(of: color.resolve(in: environment))
    }

    private func components(_ color: Color, in scheme: ColorScheme) throws -> [Int] {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let resolved = color.resolve(in: environment).cgColor
        let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let converted = try XCTUnwrap(resolved.converted(to: srgb, intent: .defaultIntent, options: nil))
        let parts = try XCTUnwrap(converted.components)
        return parts.map { Int(($0 * 255).rounded()) }
    }
}

/// The same sequence on every run, so a failure can be read again.
private struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
