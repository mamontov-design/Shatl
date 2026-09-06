// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

final class SessionRestoreStatusTests: XCTestCase {
    func testBannerAppearsOnlyAfterOneSecond() {
        XCTAssertEqual(SessionRestoreStatusTiming.revealDelay, 1)
    }

    func testEarlyCompletionExtendsSuccessToMinimumTotalVisibility() {
        XCTAssertEqual(
            SessionRestoreStatusTiming.completionVisibilityDuration(visibleFor: 0.25),
            1.75,
            accuracy: 0.001
        )
    }

    func testLateCompletionStillShowsSuccessForOneSecond() {
        XCTAssertEqual(
            SessionRestoreStatusTiming.completionVisibilityDuration(visibleFor: 5),
            1,
            accuracy: 0.001
        )
    }
}
