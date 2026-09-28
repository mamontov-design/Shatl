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

/// With many downloads running, the cards leave out their costliest motion,
/// and a count wavering at a threshold does not switch them back and forth.
@MainActor
final class CardSimplificationTests: XCTestCase {
    func testLevelsStartAtFifteenAndTwentyFiveActiveDownloads() {
        func level(_ count: Int) -> CardSimplificationLevel {
            CardSimplificationLevel.level(activeDownloads: count, previous: .full)
        }
        XCTAssertEqual(level(0), .full)
        XCTAssertEqual(level(14), .full)
        XCTAssertEqual(level(15), .lighter)
        XCTAssertEqual(level(24), .lighter)
        XCTAssertEqual(level(25), .lightest)
        XCTAssertEqual(level(100), .lightest)
    }

    func testLevelsEndOnlyThreeBelowTheirThreshold() {
        XCTAssertEqual(CardSimplificationLevel.level(activeDownloads: 22, previous: .lightest), .lightest)
        XCTAssertEqual(CardSimplificationLevel.level(activeDownloads: 21, previous: .lightest), .lighter)
        XCTAssertEqual(CardSimplificationLevel.level(activeDownloads: 12, previous: .lighter), .lighter)
        XCTAssertEqual(CardSimplificationLevel.level(activeDownloads: 11, previous: .lighter), .full)
        // A fall through both thresholds lands where the count is.
        XCTAssertEqual(CardSimplificationLevel.level(activeDownloads: 3, previous: .lightest), .full)
    }

    func testOnlyDownloadingAndCheckingCount() {
        let records = [
            makeTestRecord(status: .downloading, progress: 0.4),
            makeTestRecord(status: .checking, progress: 0.4),
            makeTestRecord(status: .seeding, progress: 1),
            makeTestRecord(status: .completed, progress: 1),
            makeTestRecord(status: .stopped, progress: 0.2),
        ]
        XCTAssertEqual(CardSimplificationLevel.activeDownloadCount(in: records), 2)
    }

    /// The level reaches every card through its row, and a Debug pick
    /// replaces the one the count gives.
    func testStoreHandsTheLevelToTheCards() throws {
        let active = (0..<16).map { _ in makeTestRecord(status: .downloading, progress: 0.4) }
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: active)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        let rowModel = try XCTUnwrap(bundle.store.torrentRowPresentationModel(for: active[0].id))

        XCTAssertEqual(bundle.store.cardSimplification, .lighter)
        XCTAssertEqual(rowModel.state.simplification, .lighter)

        bundle.store.setDebugCardSimplificationOverride(.lightest)
        XCTAssertEqual(rowModel.state.simplification, .lightest)
        bundle.store.setDebugCardSimplificationOverride(nil)
        XCTAssertEqual(rowModel.state.simplification, .lighter)
    }
}
