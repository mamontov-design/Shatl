// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

final class AppPreferencesStoreTests: XCTestCase {
    func testLoadReturnsDefaultWhenNothingWasSaved() {
        let suiteName = "AppPreferencesStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Не удалось создать isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppPreferencesStore(userDefaults: defaults)

        XCTAssertEqual(store.load(), .defaultValue)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSaveAndLoadRoundTripPreferences() {
        let suiteName = "AppPreferencesStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Не удалось создать isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppPreferencesStore(userDefaults: defaults)
        var preferences = AppPreferences.defaultValue
        preferences.isLoggingEnabled = true
        preferences.isDiskDiagnosticsLoggingEnabled = true
        preferences.isMetricAnimationDiagnosticsLoggingEnabled = true
        preferences.isSnapshotDiagnosticsLoggingEnabled = true
        preferences.isAddTorrentReviewDiagnosticsLoggingEnabled = true
        preferences.launchAtLogin = true
        preferences.defaultDownloadPath = "/tmp/Shatl Downloads"
        preferences.defaultDownloadBookmarkData = Data("selected-folder-bookmark".utf8)
        preferences.alwaysStopAfterDownload = true
        preferences.performanceProfile = .maximum
        preferences.metricsMode = .detailed
        preferences.animationMode = .calm
        preferences.sendsAnonymousUsageStatistics = true
        preferences.hasAnsweredUsageStatisticsOnboarding = true
        preferences.lastUsageStatisticsSentAt = Date(timeIntervalSince1970: 1_780_000_000)
        preferences.hasCompletedOnboarding = true
        preferences.preferredBrandMark = .logomark

        store.save(preferences)

        XCTAssertEqual(store.load(), preferences)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testAnonymousUsageStatisticsRequiresOptInAndAnsweredOnboarding() {
        var preferences = AppPreferences.defaultValue
        XCTAssertFalse(preferences.canSendAnonymousUsageStatistics)

        preferences.sendsAnonymousUsageStatistics = true
        XCTAssertFalse(preferences.canSendAnonymousUsageStatistics)

        preferences.hasAnsweredUsageStatisticsOnboarding = true
        XCTAssertTrue(preferences.canSendAnonymousUsageStatistics)
    }

    func testUpdaterSettingsAreNotEncodedInAppPreferences() throws {
        let data = try JSONEncoder().encode(AppPreferences.defaultValue)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertNil(object["checkForUpdates"])
        XCTAssertNil(object["automaticallyInstallUpdates"])
    }

    func testLoadMigratesPreferencesWithoutDiskDiagnosticsFlag() throws {
        let suiteName = "AppPreferencesStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Не удалось создать isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let legacyJSON = """
        {
          "launchAtLogin": false,
          "launchMinimized": false,
          "showNotifications": true,
          "playSoundOnCompletion": true,
          "isLoggingEnabled": false,
          "defaultDownloadPath": "/tmp/Shatl Downloads",
          "alwaysStopAfterDownload": false,
          "cacheSizeBytes": 0,
          "theme": "system",
          "metricsMode": "simplified",
          "checkForUpdates": true,
          "automaticallyInstallUpdates": false
        }
        """
        defaults.set(Data(legacyJSON.utf8), forKey: "mamontov.design.shatl.app-preferences")

        let store = AppPreferencesStore(userDefaults: defaults)
        let preferences = store.load()

        XCTAssertEqual(preferences.defaultDownloadPath, "/tmp/Shatl Downloads")
        XCTAssertFalse(preferences.isDiskDiagnosticsLoggingEnabled)
        XCTAssertFalse(preferences.isMetricAnimationDiagnosticsLoggingEnabled)
        XCTAssertFalse(preferences.isSnapshotDiagnosticsLoggingEnabled)
        XCTAssertFalse(preferences.isAddTorrentReviewDiagnosticsLoggingEnabled)
        XCTAssertNil(preferences.defaultDownloadBookmarkData)
        XCTAssertEqual(preferences.performanceProfile, .balanced)
        XCTAssertFalse(preferences.usesUnrestrictedPerformanceMode)
        XCTAssertEqual(preferences.animationMode, .lively)
        XCTAssertFalse(preferences.sendsAnonymousUsageStatistics)
        XCTAssertFalse(preferences.hasAnsweredUsageStatisticsOnboarding)
        XCTAssertNil(preferences.lastUsageStatisticsSentAt)
        XCTAssertFalse(preferences.hasCompletedOnboarding)
        XCTAssertEqual(preferences.preferredBrandMark, .wordmark)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLoadMigratesLegacyUnrestrictedPerformanceModeToMaximum() throws {
        let suiteName = "AppPreferencesStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Не удалось создать isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let legacyJSON = """
        {
          "launchAtLogin": false,
          "launchMinimized": false,
          "showNotifications": true,
          "playSoundOnCompletion": true,
          "isLoggingEnabled": false,
          "isDiskDiagnosticsLoggingEnabled": false,
          "defaultDownloadPath": "/tmp/Shatl Downloads",
          "alwaysStopAfterDownload": false,
          "performanceProfile": "economical",
          "usesUnrestrictedPerformanceMode": true,
          "theme": "system",
          "metricsMode": "simplified",
          "animationMode": "lively",
          "checkForUpdates": true,
          "automaticallyInstallUpdates": false
        }
        """
        defaults.set(Data(legacyJSON.utf8), forKey: "mamontov.design.shatl.app-preferences")

        let store = AppPreferencesStore(userDefaults: defaults)
        let preferences = store.load()

        XCTAssertEqual(preferences.performanceProfile, .maximum)
        XCTAssertFalse(preferences.isMetricAnimationDiagnosticsLoggingEnabled)
        XCTAssertFalse(preferences.isSnapshotDiagnosticsLoggingEnabled)
        XCTAssertFalse(preferences.isAddTorrentReviewDiagnosticsLoggingEnabled)
        XCTAssertFalse(preferences.usesUnrestrictedPerformanceMode)
        XCTAssertFalse(preferences.sendsAnonymousUsageStatistics)
        XCTAssertFalse(preferences.hasAnsweredUsageStatisticsOnboarding)
        XCTAssertNil(preferences.lastUsageStatisticsSentAt)
        XCTAssertFalse(preferences.hasCompletedOnboarding)
        XCTAssertEqual(preferences.preferredBrandMark, .wordmark)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
