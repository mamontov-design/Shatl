// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// Unit tests are hosted in Shatl.app. If the host is not recognized, every
/// test run bootstraps the user's real session, preferences and telemetry.
final class ShatlLaunchModeTests: XCTestCase {
    func testThisTestProcessIsRecognizedAsUnitTestHost() {
        XCTAssertEqual(ShatlLaunchMode.current, .unitTestHost)
    }

    func testLaunchModeResolution() {
        XCTAssertEqual(ShatlLaunchMode.resolve(environment: [:]), .live)
        XCTAssertEqual(
            ShatlLaunchMode.resolve(environment: ["XCTestConfigurationFilePath": "/tmp/config.xctestconfiguration"]),
            .unitTestHost
        )
        XCTAssertEqual(
            ShatlLaunchMode.resolve(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]),
            .xcodePreview
        )
        XCTAssertEqual(
            ShatlLaunchMode.resolve(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "0"]),
            .live
        )
    }
}
