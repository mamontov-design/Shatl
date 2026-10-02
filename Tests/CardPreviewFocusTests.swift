// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// A Settings toggle flashes the part of the demo card it changes and blurs
/// the rest. The title never blurs; the speed row on top stays sharp for
/// both toggles; the expanded metrics stay sharp only for the simplified
/// mode, which changes them too.
final class CardPreviewFocusTests: XCTestCase {
    func testWhatEachToggleKeepsSharp() {
        let sharpForSpeedColors: Set<TorrentCardPreviewElement> = [.title, .compactMetrics]
        let sharpForSimplifiedMode: Set<TorrentCardPreviewElement> = [.title, .compactMetrics, .expandedMetrics]

        for element in TorrentCardPreviewElement.allCases {
            XCTAssertFalse(TorrentCardPreviewFocus.blurs(element, under: nil), "\(element) blurs with no focus")
            XCTAssertEqual(
                TorrentCardPreviewFocus.blurs(element, under: .downloadSpeed),
                !sharpForSpeedColors.contains(element),
                "\(element) under the speed colors toggle"
            )
            XCTAssertEqual(
                TorrentCardPreviewFocus.blurs(element, under: .metrics),
                !sharpForSimplifiedMode.contains(element),
                "\(element) under the simplified mode toggle"
            )
        }
    }

    func testFocusHoldsFourSecondsAfterTheFlash() {
        XCTAssertEqual(
            ShatlMotion.previewFocusHold,
            .seconds(ShatlMotion.metricSetBounceTotalDuration + 4)
        )
        XCTAssertEqual(ShatlMotion.previewFocusBlurRadius, 3)
    }
}
