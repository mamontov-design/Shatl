// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// How often a card moves: the progress bar steps, and a card lights up only
/// under a resting pointer.
@MainActor
final class TorrentCardMotionTests: XCTestCase {
    func testProgressBarMovesInTwoPercentStepsThenEachPercentFrom95() {
        let cases: [(progress: Double, bar: Double)] = [
            (-0.1, 0),
            (0, 0),
            (0.019, 0),
            (0.03, 0.02),
            (0.515, 0.50),
            (0.949, 0.94),
            (0.95, 0.95),
            (0.955, 0.95),
            (0.961, 0.96),
            (0.999, 0.99),
            (1, 1),
            (1.2, 1),
            (.nan, 0),
        ]
        for (progress, bar) in cases {
            XCTAssertEqual(TorrentProgressBarSteps.displayedProgress(progress), bar, accuracy: 0.000_1, "\(progress)")
        }
    }

    /// The bar never runs ahead of the percent beside it, nor lags a step behind.
    func testProgressBarStaysWithinAStepBelowThePercent() {
        for thousandth in 0...1000 {
            let progress = Double(thousandth) / 1000
            let percent = Double(Int((progress * 100).rounded(.down))) / 100
            let bar = TorrentProgressBarSteps.displayedProgress(progress)

            XCTAssertLessThanOrEqual(bar, percent + 0.000_1, "\(progress)")
            let step = percent < 0.95 ? 0.02 : 0.01
            XCTAssertLessThan(percent - bar, step - 0.000_1, "\(progress)")
        }
    }

    func testPointerThatLeavesBeforeTheDelayLightsNothing() async throws {
        let intent = TorrentCardHoverIntent()
        let lit = LitUp()

        intent.pointerEntered(after: .milliseconds(80)) { lit.count += 1 }
        try await Task.sleep(for: .milliseconds(30))
        intent.pointerExited()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(lit.count, 0)

        intent.pointerEntered(after: .milliseconds(80)) { lit.count += 1 }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(lit.count, 0)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(lit.count, 1)
    }

    /// A pointer that moves on to the next card starts its wait afresh.
    func testNewEntryRestartsTheWait() async throws {
        let intent = TorrentCardHoverIntent()
        let lit = LitUp()

        intent.pointerEntered(after: .milliseconds(80)) { lit.count += 1 }
        try await Task.sleep(for: .milliseconds(50))
        intent.pointerEntered(after: .milliseconds(80)) { lit.count += 10 }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(lit.count, 10)
    }

    func testRestDelayIsEightyMilliseconds() {
        XCTAssertEqual(TorrentCardHoverTiming.restDelay, .milliseconds(80))
    }

    // MARK: - Helpers

    private final class LitUp {
        var count = 0
    }
}
