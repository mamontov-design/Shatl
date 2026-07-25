// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

final class ShatlUpdaterConfigurationTests: XCTestCase {
    func testHostBundleContainsHardenedSparkleConfiguration() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)

        XCTAssertEqual(
            info["SUFeedURL"] as? String,
            "https://mamontov-design.github.io/shatl-updates/appcast.xml"
        )
        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(info["SUScheduledCheckInterval"] as? Int, 86_400)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)

        let publicKey = try XCTUnwrap(info["SUPublicEDKey"] as? String)
        let decodedPublicKey = try XCTUnwrap(Data(base64Encoded: publicKey))
        XCTAssertEqual(decodedPublicKey.count, 32)
    }
}
