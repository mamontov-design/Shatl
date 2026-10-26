// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// A message about no results quotes the query as the reader typed it,
/// trimmed, and a long one shortened: the main list and the add window's
/// files quote it the same way.
final class SearchQueryDisplayTests: XCTestCase {
    func testAShortQueryIsQuotedAsTyped() {
        XCTAssertEqual(ShatlSearchQueryDisplay.quoted("  сезон 5 "), "сезон 5")
    }

    func testALongQueryIsCutToThirtyTwoCharacters() {
        let query = String(repeating: "а", count: 40)
        let quoted = ShatlSearchQueryDisplay.quoted(query)
        XCTAssertEqual(quoted.count, ShatlSearchQueryDisplay.maximumLength)
        XCTAssertTrue(quoted.hasSuffix("…"))
    }

    func testAQueryOfExactlyThirtyTwoCharactersIsNotCut() {
        let query = String(repeating: "б", count: 32)
        XCTAssertEqual(ShatlSearchQueryDisplay.quoted(query), query)
    }
}
