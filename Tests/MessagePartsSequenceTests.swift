// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// A message whose parts change together changes them one after another,
/// in order; a part whose numbers alone change rolls them in place.
final class MessagePartsSequenceTests: XCTestCase {
    private func steps(from shown: [String], to target: [String]) -> [[String]] {
        var result: [[String]] = []
        var current = shown
        while let next = ShatlMessagePartsSequence.nextStep(from: current, to: target) {
            result.append(next)
            current = next
            XCTAssertLessThan(result.count, 10, "The steps must end")
            if result.count >= 10 { break }
        }
        return result
    }

    /// Two parts changed: the first changes, then the second.
    func testChangedPartsChangeOneAfterAnother() {
        XCTAssertEqual(
            steps(from: ["Title 1", "Fix one", "Wait"], to: ["Title 2", "Fix many", "Wait"]),
            [
                ["Title 2", "Fix one", "Wait"],
                ["Title 2", "Fix many", "Wait"],
            ]
        )
    }

    func testNothingChangedTakesNoStep() {
        XCTAssertNil(ShatlMessagePartsSequence.nextStep(from: ["A", "B"], to: ["A", "B"]))
    }

    /// A part that comes is added at the end; parts that go leave one at a time.
    func testPartsComeAndGoOneAtATime() {
        XCTAssertEqual(steps(from: ["A"], to: ["A", "B", "C"]), [["A", "B"], ["A", "B", "C"]])
        XCTAssertEqual(steps(from: ["A", "B", "C"], to: ["A"]), [["A", "B"], ["A"]])
        XCTAssertEqual(steps(from: ["A", "B", "C"], to: ["X"]), [["X", "B", "C"], ["X", "B"], ["X"]])
    }

    /// The disk lacks 156 GB, then 155 GB: the same part, its digits roll.
    /// Another unit or other words make it a new part, which blurs in.
    func testNumbersAloneKeepAPartsIdentity() {
        let identity = ShatlMessagePartsSequence.identity(of:)
        XCTAssertEqual(
            identity("На диске «Macintosh HD» не хватает 156 ГБ."),
            identity("На диске «Macintosh HD» не хватает 155 ГБ.")
        )
        XCTAssertEqual(
            identity("ещё 1\u{00A0}657 ГБ займут"),
            identity("ещё 99 ГБ займут")
        )
        XCTAssertEqual(identity("2,4 ГБ"), identity("12 ГБ"))
        XCTAssertNotEqual(identity("156 ГБ"), identity("156 МБ"))
        XCTAssertNotEqual(identity("Освободите место"), identity("Освободите место, снимите часть файлов"))
        // A space between a number and a word stays.
        XCTAssertEqual(identity("не хватает 156 ГБ"), "не хватает # ГБ")
    }
}
