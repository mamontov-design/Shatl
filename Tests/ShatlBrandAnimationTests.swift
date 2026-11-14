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

    func testLogomarkResumesTheSameMorphAfterBeingHidden() {
        let player = ShatlBrandAnimationState(originalStrokeWidth: 8, strokeWidths: 4...8)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        player.setPlaying(true)
        XCTAssertEqual(player.phase(at: start), 1)
        let middle = start + ShatlBrandAnimation.pauseDuration + ShatlBrandAnimation.fullDuration / 2
        let frame = player.phase(at: middle)
        XCTAssertLessThan(frame, 1)

        let resumedAt = middle + 30
        player.setPlaying(false)
        XCTAssertEqual(player.phase(at: resumedAt), frame)
        XCTAssertEqual(player.phase(at: resumedAt, reduceMotion: true), 1)
        player.setPlaying(true)
        XCTAssertEqual(player.phase(at: resumedAt), frame)
        XCTAssertLessThan(player.phase(at: resumedAt + 0.1), frame)
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
