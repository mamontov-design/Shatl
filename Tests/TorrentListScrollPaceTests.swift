// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// When the list counts as rushed: above 1 500 points a second, and calm
/// again only once it has stood still for 1.5 s.
final class TorrentListScrollPaceTests: XCTestCase {
    private let frame = 1.0 / 60

    /// Moves the list at `speed` points a second for `seconds`, a frame at
    /// a time, from `origin` at `time`; returns where it stands and when.
    @discardableResult
    private func scroll(
        _ pace: inout TorrentListScrollPace,
        speed: Double,
        for seconds: Double,
        from start: (origin: Double, time: Double)
    ) -> (origin: Double, time: Double) {
        var origin = start.origin
        var time = start.time
        let frames = Int((seconds / frame).rounded())
        for _ in 0..<frames {
            time += frame
            origin += speed * frame
            pace.note(origin: origin, at: time)
        }
        return (origin, time)
    }

    func testReadingSpeedNeverCountsAsFast() {
        var pace = TorrentListScrollPace()
        scroll(&pace, speed: 400, for: 2, from: (0, 10))
        XCTAssertFalse(pace.isFast)
        XCTAssertEqual(pace.speed, 400, accuracy: 1)
    }

    func testAFlickIsFastWithinAFewFrames() {
        var pace = TorrentListScrollPace()
        scroll(&pace, speed: 3_000, for: 3 * frame, from: (0, 10))
        XCTAssertTrue(pace.isFast)
    }

    /// Moving slowly does not calm a list that rushed: only standing still
    /// for 1.5 s does.
    func testAListThatRushedIsCalmOnlyAfterStandingStillFor15Seconds() {
        var pace = TorrentListScrollPace()
        var at = scroll(&pace, speed: 3_000, for: 0.5, from: (0, 10))
        XCTAssertTrue(pace.isFast)

        at = scroll(&pace, speed: 300, for: 3, from: at)
        XCTAssertTrue(pace.isFast, "Slow movement does not calm it")

        pace.noteStill(at: at.time + TorrentListScrollPace.stillAfter)
        XCTAssertEqual(pace.speed, 0, "Standing")
        XCTAssertTrue(pace.isFast, "Not calm yet")
        pace.noteStill(at: at.time + 1.4)
        XCTAssertTrue(pace.isFast)
        pace.noteStill(at: at.time + TorrentListScrollPace.calmAfter)
        XCTAssertFalse(pace.isFast)
    }

    /// Stopped for a second and flicked again: still rushed, the cards wait.
    func testAFlickAfterAShortStopFindsTheListStillRushed() {
        var pace = TorrentListScrollPace()
        var at = scroll(&pace, speed: 3_000, for: 0.4, from: (0, 10))
        pace.noteStill(at: at.time + 1)
        XCTAssertTrue(pace.isFast)
        at = scroll(&pace, speed: 3_000, for: 0.4, from: (at.origin, at.time + 1))
        pace.noteStill(at: at.time + 1)
        XCTAssertTrue(pace.isFast)
    }

    func testTheNextCheckIsWhenTheListStandsThenWhenItIsCalm() throws {
        var pace = TorrentListScrollPace()
        let at = scroll(&pace, speed: 3_000, for: 0.3, from: (0, 10))
        let stands = try XCTUnwrap(pace.nextStillCheck(after: at.time))
        XCTAssertEqual(stands, at.time + TorrentListScrollPace.stillAfter, accuracy: 0.000_1)
        pace.noteStill(at: stands)
        let calm = try XCTUnwrap(pace.nextStillCheck(after: stands))
        XCTAssertEqual(calm, at.time + TorrentListScrollPace.calmAfter, accuracy: 0.000_1)
        pace.noteStill(at: calm)
        XCTAssertNil(pace.nextStillCheck(after: calm))
    }

    /// A jump of the list after a rest (a page, "Show in List") has nothing
    /// to be measured against: it is not a fast scroll.
    func testALoneJumpAfterARestIsNotFast() {
        var pace = TorrentListScrollPace()
        pace.note(origin: 0, at: 10)
        pace.note(origin: 2_000, at: 12)
        XCTAssertFalse(pace.isFast)
        XCTAssertEqual(pace.speed, 0)
    }

    func testBothWaysCount() {
        var pace = TorrentListScrollPace()
        scroll(&pace, speed: -3_000, for: 0.2, from: (5_000, 10))
        XCTAssertTrue(pace.isFast)
    }
}
