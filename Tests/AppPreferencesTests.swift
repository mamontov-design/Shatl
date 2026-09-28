// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Darwin
import XCTest
@testable import Shatl

final class AppPreferencesTests: XCTestCase {
    func testDefaultDownloadPathUsesSystemDownloadsDirectory() {
        let expectedPath = resolvedRealUserDownloadsPath()

        XCTAssertEqual(AppPreferences.defaultValue.defaultDownloadPath, expectedPath)
        XCTAssertFalse(AppPreferences.defaultValue.defaultDownloadPath.contains("/Library/Containers/"))
    }

    func testSpeedColorsDefaultToOffForNewAndExistingPreferences() throws {
        XCTAssertFalse(AppPreferences.defaultValue.colorizesDownloadSpeed)
        let data = try JSONEncoder().encode(AppPreferences.defaultValue)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "colorizesDownloadSpeed")
        let decoded = try JSONDecoder().decode(
            AppPreferences.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertEqual(decoded, .defaultValue)
    }

    /// Existing users get the router port opened too, like new ones: other
    /// clients do it by default, and the switch in Settings turns it off.
    func testRouterPortOpensByDefaultForNewAndExistingPreferences() throws {
        XCTAssertTrue(AppPreferences.defaultValue.opensRouterPortAutomatically)
        XCTAssertTrue(AppPreferences.defaultValue.enginePerformanceSettings.opensRouterPort)
        let data = try JSONEncoder().encode(AppPreferences.defaultValue)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "opensRouterPortAutomatically")
        let decoded = try JSONDecoder().decode(
            AppPreferences.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertTrue(decoded.opensRouterPortAutomatically)

        var disabled = AppPreferences.defaultValue
        disabled.opensRouterPortAutomatically = false
        let roundTrip = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(disabled))
        XCTAssertFalse(roundTrip.opensRouterPortAutomatically)
        XCTAssertFalse(roundTrip.enginePerformanceSettings.opensRouterPort)
    }

    func testDefaultBrandMarkUsesWordmark() {
        XCTAssertEqual(AppPreferences.defaultValue.preferredBrandMark, .wordmark)
    }

    func testAllFileDiagnosticsAreDisabledByDefault() {
        XCTAssertFalse(AppPreferences.defaultValue.isLoggingEnabled)
        XCTAssertFalse(AppPreferences.defaultValue.isDiskDiagnosticsLoggingEnabled)
        XCTAssertFalse(AppPreferences.defaultValue.isMetricAnimationDiagnosticsLoggingEnabled)
        XCTAssertFalse(AppPreferences.defaultValue.isSnapshotDiagnosticsLoggingEnabled)
        XCTAssertFalse(AppPreferences.defaultValue.isAddTorrentReviewDiagnosticsLoggingEnabled)
        XCTAssertFalse(AppPreferences.defaultValue.isCardLayoutDiagnosticsLoggingEnabled)
    }

    private func resolvedRealUserDownloadsPath() -> String? {
        let uid = getuid()
        guard let passwd = getpwuid(uid), let directory = passwd.pointee.pw_dir else {
            return nil
        }

        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
            .path
    }
}
