// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// The logomark breathes from 4 to 8 pt: its compact letter closes up above 8.
@MainActor
final class ShatlBrandAnimationTests: XCTestCase {
    func testLogomarkBreathesFromFourToEightPoints() {
        let widths = ShatlBrandAnimation.phases.map {
            ShatlBrandAnimation.strokeWidth(for: $0, in: ShatlBrandAnimation.logomarkStrokeWidths)
        }
        XCTAssertEqual(widths, [4, 5, 6, 7, 8])
    }

    func testLogomarkRestsAtEightPoints() {
        let logomarkPhase = ShatlBrandAnimation.phase(
            forStrokeWidth: ShatlBrandAnimation.logomarkOriginalStrokeWidth,
            in: ShatlBrandAnimation.logomarkStrokeWidths
        )

        XCTAssertEqual(logomarkPhase, 1)
        XCTAssertEqual(
            ShatlBrandAnimation.strokeWidth(for: logomarkPhase, in: ShatlBrandAnimation.logomarkStrokeWidths),
            8
        )
    }

    func testLogomarkNeverLeavesItsRange() {
        for _ in 0..<200 {
            let phase = ShatlBrandAnimation.randomPhase(excluding: 1, originalPhase: 1)
            let width = ShatlBrandAnimation.strokeWidth(for: phase, in: ShatlBrandAnimation.logomarkStrokeWidths)
            XCTAssertTrue(ShatlBrandAnimation.logomarkStrokeWidths.contains(width), "\(width) pt")
            XCTAssertNotEqual(phase, 1)
        }
    }
}
