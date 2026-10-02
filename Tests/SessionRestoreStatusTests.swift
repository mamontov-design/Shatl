// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// A quick launch shows no message about preparing downloads; a slower one
/// shows it long enough to read, and it leaves without a "ready" step.
final class SessionRestoreStatusTests: XCTestCase {
    func testMessageAppearsOnlyAfterHalfASecond() {
        XCTAssertEqual(SessionRestoreStatusTiming.revealDelay, 0.5)
    }

    func testEarlyCompletionKeepsTheMessageForTwoSeconds() {
        XCTAssertEqual(
            SessionRestoreStatusTiming.remainingVisibility(visibleFor: 0.25),
            1.75,
            accuracy: 0.001
        )
    }

    func testLateCompletionHidesTheMessageAtOnce() {
        XCTAssertEqual(SessionRestoreStatusTiming.remainingVisibility(visibleFor: 5), 0)
    }
}
