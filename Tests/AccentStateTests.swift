// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// macOS keeps the picked accent as a number in the global domain; the
/// theme previews grey their window buttons by it in the monochrome
/// appearance, so only Graphite may read as Graphite.
@MainActor
final class AccentStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AccentStateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testGraphiteReadsAsGraphite() {
        defaults.set(-1, forKey: "AppleAccentColor")

        XCTAssertTrue(ShatlAccentState.accentIsGraphite(in: defaults))
    }

    func testAColouredAccentIsNotGraphite() {
        for accent in 0...6 {
            defaults.set(accent, forKey: "AppleAccentColor")

            XCTAssertFalse(ShatlAccentState.accentIsGraphite(in: defaults), "accent \(accent)")
        }
    }
}
