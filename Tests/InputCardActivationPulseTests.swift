// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XCTest
@testable import Shatl

/// A Settings option card winks in one of the wordmark's hues, any but the
/// hue of the wink before it.
@MainActor
final class InputCardActivationPulseTests: XCTestCase {
    func testAWinkNeverTakesTheHueOfTheOneBefore() {
        let count = ShatlColor.InputCardActivationPulse.hues.count
        XCTAssertEqual(count, ShatlColor.Wordmark.hues.count)

        var random = SystemRandomNumberGenerator()
        var last: Int?
        var seen = Set<Int>()
        for _ in 0..<2000 {
            let hue = ShatlInputCardPulseHue.next(after: last, of: count, using: &random)
            XCTAssertNotEqual(hue, last)
            XCTAssertTrue((0..<count).contains(hue))
            seen.insert(hue)
            last = hue
        }
        XCTAssertEqual(seen.count, count, "every hue comes")
    }

    func testTheWinkIsStepTwoInLightAndA3InDark() throws {
        let steps: [(light: Color, dark: Color)] = [
            (ShatlPalette.iris2, ShatlPalette.irisDarkA3),
            (ShatlPalette.violet2, ShatlPalette.violetDarkA3),
            (ShatlPalette.purple2, ShatlPalette.purpleDarkA3),
            (ShatlPalette.plum2, ShatlPalette.plumDarkA3),
        ]
        for (hue, step) in zip(ShatlColor.InputCardActivationPulse.hues, steps) {
            XCTAssertEqual(try components(hue, in: .light), try components(step.light, in: .light))
            XCTAssertEqual(try components(hue, in: .dark), try components(step.dark, in: .dark))
        }
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
