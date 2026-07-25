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

    func testDefaultAnimationModeUsesLivelyEffects() {
        XCTAssertEqual(AppPreferences.defaultValue.animationMode, .lively)
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
