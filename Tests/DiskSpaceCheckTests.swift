// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// A download that does not fit on its disk is named with what it lacks, and
/// the numbers in one sentence agree with each other.
final class DiskSpaceCheckTests: XCTestCase {
    private let gigabyte: Int64 = 1_000_000_000

    private func check(needed: Int64, available: Int64) -> DiskSpaceCheck {
        DiskSpaceCheck(neededBytes: needed, availableBytes: available, volumeName: "Macintosh HD")
    }

    func testDownloadFitsUpToTheLastByte() {
        XCTAssertTrue(check(needed: 10, available: 10).fits)
        XCTAssertTrue(check(needed: 10, available: 11).fits)
        XCTAssertFalse(check(needed: 11, available: 10).fits)
    }

    func testShortfallIsReportedOnlyWhenTheDownloadDoesNotFit() {
        let disk = DiskSpaceInfo(availableBytes: 16 * gigabyte, volumeName: "Macintosh HD")

        XCTAssertNil(DiskSpaceCheck.shortfall(neededBytes: 16 * gigabyte, on: disk))
        XCTAssertNil(DiskSpaceCheck.shortfall(neededBytes: 0, on: disk))
        XCTAssertEqual(
            DiskSpaceCheck.shortfall(neededBytes: 172 * gigabyte, on: disk),
            DiskSpaceCheck(neededBytes: 172 * gigabyte, availableBytes: 16 * gigabyte, volumeName: "Macintosh HD")
        )
    }

    /// 171.3 GB needed and 16.8 GB free show as 172 and 16; the sentence
    /// then lacks 156 GB, not the 155 the exact bytes round up to.
    func testRoundedShortfallIsTheDifferenceOfTheNumbersShown() {
        let space = check(needed: 171_300_000_000, available: 16_800_000_000)

        XCTAssertEqual(space.neededText(mode: .simplified, localeOverride: .russian), "172\u{00A0}ГБ")
        XCTAssertEqual(space.availableText(mode: .simplified, localeOverride: .russian), "16\u{00A0}ГБ")
        XCTAssertEqual(space.shortfallText(mode: .simplified, localeOverride: .russian), "156\u{00A0}ГБ")
    }

    func testShortfallAcrossUnitsStaysAboveZero() {
        let space = check(needed: 2_100_000_000, available: 800_000_000)

        XCTAssertEqual(space.neededText(mode: .simplified, localeOverride: .russian), "3\u{00A0}ГБ")
        XCTAssertEqual(space.availableText(mode: .simplified, localeOverride: .russian), "800\u{00A0}МБ")
        XCTAssertEqual(space.shortfallText(mode: .simplified, localeOverride: .russian), "3\u{00A0}ГБ")
    }

    func testDetailedShortfallUsesTheExactBytes() {
        let space = check(needed: 171_300_000_000, available: 16_800_000_000)

        XCTAssertEqual(
            space.shortfallText(mode: .detailed, localeOverride: .russian),
            Metrics.formatBytes(154_500_000_000, mode: .detailed, localeOverride: .russian)
                .replacingOccurrences(of: " ", with: "\u{00A0}")
        )
    }

    func testRoundedBytesFollowTheUnitShown() {
        XCTAssertEqual(AddTorrentSummaryByteFormatter.roundedBytes(171_300_000_000, rounding: .up), 172 * gigabyte)
        XCTAssertEqual(AddTorrentSummaryByteFormatter.roundedBytes(16_800_000_000, rounding: .down), 16 * gigabyte)
        XCTAssertEqual(AddTorrentSummaryByteFormatter.roundedBytes(800_400_000, rounding: .down), 800_000_000)
        XCTAssertEqual(AddTorrentSummaryByteFormatter.roundedBytes(512, rounding: .up), 512)
    }
}
