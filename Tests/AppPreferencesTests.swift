// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Darwin
import XCTest
@testable import Shatl

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testUpdateMessageIsForOlderPreferencesAndOnlyIn106() throws {
        let fresh = AppPreferences.defaultValue
        XCTAssertFalse(fresh.showsUpdateMessage106(appVersion: "1.0.6"))

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(fresh)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "skipsUpdateMessage106")
        var upgraded = try decoder.decode(
            AppPreferences.self,
            from: JSONSerialization.data(withJSONObject: old)
        )
        XCTAssertFalse(upgraded.showsUpdateMessage106(appVersion: "1.0.5"))
        XCTAssertTrue(upgraded.showsUpdateMessage106(appVersion: "1.0.6"))
        XCTAssertFalse(upgraded.showsUpdateMessage106(appVersion: "1.0.7"))

        upgraded.skipsUpdateMessage106 = true
        let reopened = try decoder.decode(AppPreferences.self, from: encoder.encode(upgraded))
        XCTAssertFalse(reopened.showsUpdateMessage106(appVersion: "1.0.6"))
    }

    func testDefaultDownloadPathUsesSystemDownloadsDirectory() {
        let expectedPath = resolvedRealUserDownloadsPath()

        XCTAssertEqual(AppPreferences.defaultValue.defaultDownloadPath, expectedPath)
        XCTAssertFalse(AppPreferences.defaultValue.defaultDownloadPath.contains("/Library/Containers/"))
    }

    /// Speed colours are on by default since 1.0.6, for new preferences and
    /// for those saved before that knew nothing of them. The once-only turn
    /// for preferences that had them off is in `AppPreferencesStoreTests`.
    func testSpeedColorsDefaultToOnForNewAndExistingPreferences() throws {
        XCTAssertTrue(AppPreferences.defaultValue.colorizesDownloadSpeed)
        let data = try JSONEncoder().encode(AppPreferences.defaultValue)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "colorizesDownloadSpeed")
        legacy.removeValue(forKey: "hasAppliedSpeedColorsDefault")
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
