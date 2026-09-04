// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XCTest
@testable import Shatl

@MainActor
final class SpeedMetricLayoutTests: XCTestCase {
    private let speed = MetricItemPresentation(
        id: "download-speed", iconName: "figure.run", number: "8", unit: "МБ/с", usesAccentIcon: true
    )
    private let eta = MetricItemPresentation(
        id: "eta", iconName: nil, number: "1", unit: "час", usesAccentIcon: true
    )

    func testColorToggleOnlyRemovesDividerSpaceAndPreservesHeight() throws {
        let plain = try size(items: [speed, eta], colored: false)
        let colored = try size(items: [speed, eta], colored: true)
        XCTAssertEqual(plain.height, 27, accuracy: 0.01)
        XCTAssertEqual(colored.height, plain.height, accuracy: 0.01)
        XCTAssertEqual(plain.width - colored.width, 7, accuracy: 0.01)
    }

    func testSingleSpeedKeepsSameGeometryWhenColorToggles() throws {
        let plain = try size(items: [speed], colored: false)
        let colored = try size(items: [speed], colored: true)
        XCTAssertEqual(plain.width, colored.width, accuracy: 0.01)
        XCTAssertEqual(plain.height, 27, accuracy: 0.01)
        XCTAssertEqual(colored.height, 27, accuracy: 0.01)
    }

    func testRemovingETARetainsSpeedItemAndOuterPadding() throws {
        let itemRenderer = ImageRenderer(content: ShatlMetricItem(item: speed).fixedSize())
        let item = try XCTUnwrap(itemRenderer.cgImage)
        let single = try size(items: [speed], colored: true)
        XCTAssertEqual(single.width, CGFloat(item.width) + 6, accuracy: 1)
        XCTAssertLessThan(single.width, try size(items: [speed, eta], colored: true).width)
    }

    private func size(items: [MetricItemPresentation], colored: Bool) throws -> CGSize {
        let renderer = ImageRenderer(content: ShatlMetricSet(items: items, colorizesDownloadSpeed: colored).fixedSize())
        let image = try XCTUnwrap(renderer.cgImage)
        return CGSize(width: image.width, height: image.height)
    }
}
