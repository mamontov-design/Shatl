// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Darwin

protocol _AppPreferencesProcessInfoProviding: Sendable {
    nonisolated var environment: [String: String] { get }
}

extension ProcessInfo: _AppPreferencesProcessInfoProviding { }

nonisolated enum AppTheme: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "Как в системе"
        case .light:
            "Светлая"
        case .dark:
            "Тёмная"
        }
    }
}

nonisolated enum AppPerformanceProfile: String, CaseIterable, Codable, Sendable, Identifiable {
    case economical
    case balanced
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .economical:
            "Halo"
        case .balanced:
            "Orbit"
        case .maximum:
            "Nova"
        }
    }

}

nonisolated enum AppLocaleOverride: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"

    nonisolated var id: String { rawValue }

    nonisolated var localeIdentifier: String? {
        switch self {
        case .system:
            nil
        case .english:
            "en"
        case .russian:
            "ru"
        case .german:
            "de"
        case .spanish:
            "es"
        case .french:
            "fr"
        case .japanese:
            "ja"
        case .simplifiedChinese:
            "zh-Hans"
        }
    }
}

nonisolated enum EnginePerformanceMode: Int, Equatable, Sendable {
    case economical
    case balanced
    case maximum
}

nonisolated struct EnginePerformanceSettings: Equatable, Sendable {
    var mode: EnginePerformanceMode
    /// Asks the router to open the listen port, so peers can connect to Shatl.
    var opensRouterPort = false
}

nonisolated enum ShatlBrandMark: String, Codable, Sendable {
    case wordmark
    case logomark
}

/// Stores user preferences separately from torrent runtime state.
nonisolated struct AppPreferences: Equatable, Codable, Sendable {
    var launchAtLogin: Bool
    var launchMinimized: Bool
    var isLoggingEnabled: Bool
    var isDiskDiagnosticsLoggingEnabled: Bool
    var isMetricAnimationDiagnosticsLoggingEnabled: Bool
    var isSnapshotDiagnosticsLoggingEnabled: Bool
    var isAddTorrentReviewDiagnosticsLoggingEnabled: Bool
    /// A probe on every card that logs its height as it changes. It weighs
    /// on scrolling, so it has its own switch rather than riding on the log.
    var isCardLayoutDiagnosticsLoggingEnabled = false
    var defaultDownloadPath: String
    var defaultDownloadBookmarkData: Data?
    var alwaysStopAfterDownload: Bool
    var performanceProfile: AppPerformanceProfile
    var usesUnrestrictedPerformanceMode: Bool
    var theme: AppTheme
    var metricsMode: MetricsPresentationMode
    var colorizesDownloadSpeed: Bool = false
    var localeOverride: AppLocaleOverride
    var sendsAnonymousUsageStatistics: Bool
    var hasAnsweredUsageStatisticsOnboarding: Bool
    var lastUsageStatisticsSentAt: Date?
    var hasCompletedOnboarding: Bool
    var preferredBrandMark: ShatlBrandMark = .wordmark
    /// Settings → Downloads → Network. On by default, like other torrent clients.
    var opensRouterPortAutomatically = true
}

extension AppPreferences {
    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case launchMinimized
        case isLoggingEnabled
        case isDiskDiagnosticsLoggingEnabled
        case isMetricAnimationDiagnosticsLoggingEnabled
        case isSnapshotDiagnosticsLoggingEnabled
        case isAddTorrentReviewDiagnosticsLoggingEnabled
        case isCardLayoutDiagnosticsLoggingEnabled
        case defaultDownloadPath
        case defaultDownloadBookmarkData
        case alwaysStopAfterDownload
        case performanceProfile
        case usesUnrestrictedPerformanceMode
        case theme
        case metricsMode
        case colorizesDownloadSpeed
        case localeOverride
        case sendsAnonymousUsageStatistics
        case hasAnsweredUsageStatisticsOnboarding
        case lastUsageStatisticsSentAt
        case hasCompletedOnboarding
        case preferredBrandMark
        case opensRouterPortAutomatically
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        launchMinimized = try container.decode(Bool.self, forKey: .launchMinimized)
        isLoggingEnabled = try container.decode(Bool.self, forKey: .isLoggingEnabled)
        isDiskDiagnosticsLoggingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isDiskDiagnosticsLoggingEnabled
        ) ?? false
        isMetricAnimationDiagnosticsLoggingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isMetricAnimationDiagnosticsLoggingEnabled
        ) ?? false
        isSnapshotDiagnosticsLoggingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isSnapshotDiagnosticsLoggingEnabled
        ) ?? false
        isAddTorrentReviewDiagnosticsLoggingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isAddTorrentReviewDiagnosticsLoggingEnabled
        ) ?? false
        isCardLayoutDiagnosticsLoggingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isCardLayoutDiagnosticsLoggingEnabled
        ) ?? false
        defaultDownloadPath = try container.decode(String.self, forKey: .defaultDownloadPath)
        defaultDownloadBookmarkData = try container.decodeIfPresent(Data.self, forKey: .defaultDownloadBookmarkData)
        alwaysStopAfterDownload = try container.decode(Bool.self, forKey: .alwaysStopAfterDownload)
        let decodedPerformanceProfile = try container.decodeIfPresent(
            AppPerformanceProfile.self,
            forKey: .performanceProfile
        ) ?? .balanced
        let legacyUsesUnrestrictedPerformanceMode = try container.decodeIfPresent(
            Bool.self,
            forKey: .usesUnrestrictedPerformanceMode
        ) ?? false
        performanceProfile = legacyUsesUnrestrictedPerformanceMode ? .maximum : decodedPerformanceProfile
        usesUnrestrictedPerformanceMode = false
        theme = try container.decode(AppTheme.self, forKey: .theme)
        metricsMode = try container.decode(MetricsPresentationMode.self, forKey: .metricsMode)
        colorizesDownloadSpeed = try container.decodeIfPresent(Bool.self, forKey: .colorizesDownloadSpeed) ?? false
        localeOverride = try container.decodeIfPresent(
            AppLocaleOverride.self,
            forKey: .localeOverride
        ) ?? .system
        sendsAnonymousUsageStatistics = try container.decodeIfPresent(
            Bool.self,
            forKey: .sendsAnonymousUsageStatistics
        ) ?? false
        hasAnsweredUsageStatisticsOnboarding = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasAnsweredUsageStatisticsOnboarding
        ) ?? false
        lastUsageStatisticsSentAt = try container.decodeIfPresent(
            Date.self,
            forKey: .lastUsageStatisticsSentAt
        )
        hasCompletedOnboarding = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasCompletedOnboarding
        ) ?? false
        preferredBrandMark = try container.decodeIfPresent(
            ShatlBrandMark.self,
            forKey: .preferredBrandMark
        ) ?? .wordmark
        opensRouterPortAutomatically = try container.decodeIfPresent(
            Bool.self,
            forKey: .opensRouterPortAutomatically
        ) ?? true
    }
}

extension AppPreferences {
    private nonisolated static func resolvedRealUserHomePath() -> String? {
        let uid = getuid()
        guard let passwd = getpwuid(uid), let directory = passwd.pointee.pw_dir else {
            return nil
        }

        return String(cString: directory)
    }

    nonisolated static func systemDownloadsDirectoryURL() -> URL {
        if let homePath = resolvedRealUserHomePath() {
            return URL(fileURLWithPath: homePath, isDirectory: true)
                .appendingPathComponent("Downloads", isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    private nonisolated static func resolvedDefaultDownloadsPath() -> String {
        systemDownloadsDirectoryURL().path
    }

    nonisolated static func defaultLogsDirectoryURL(
        processInfo: any _AppPreferencesProcessInfoProviding = ProcessInfo.processInfo,
        fileManager: FileManager = .default
    ) -> URL {
        // Tests must not write into the user's real Downloads directory.
        if processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return fileManager.temporaryDirectory
                .appendingPathComponent("Shatl Test Logs", isDirectory: true)
        }

        return systemDownloadsDirectoryURL()
            .appendingPathComponent("Shatl Logs", isDirectory: true)
    }

    nonisolated static let defaultValue = AppPreferences(
        launchAtLogin: false,
        launchMinimized: false,
        isLoggingEnabled: false,
        isDiskDiagnosticsLoggingEnabled: false,
        isMetricAnimationDiagnosticsLoggingEnabled: false,
        isSnapshotDiagnosticsLoggingEnabled: false,
        isAddTorrentReviewDiagnosticsLoggingEnabled: false,
        defaultDownloadPath: resolvedDefaultDownloadsPath(),
        defaultDownloadBookmarkData: nil,
        alwaysStopAfterDownload: false,
        performanceProfile: .balanced,
        usesUnrestrictedPerformanceMode: false,
        theme: .system,
        metricsMode: .simplified,
        localeOverride: .system,
        sendsAnonymousUsageStatistics: false,
        hasAnsweredUsageStatisticsOnboarding: false,
        lastUsageStatisticsSentAt: nil,
        hasCompletedOnboarding: false,
        preferredBrandMark: .wordmark
    )
}

extension AppPreferences {
    nonisolated var canSendAnonymousUsageStatistics: Bool {
        sendsAnonymousUsageStatistics && hasAnsweredUsageStatisticsOnboarding
    }

    nonisolated var enginePerformanceSettings: EnginePerformanceSettings {
        let mode: EnginePerformanceMode = switch performanceProfile {
        case .economical: .economical
        case .balanced: .balanced
        case .maximum: .maximum
        }
        return EnginePerformanceSettings(mode: mode, opensRouterPort: opensRouterPortAutomatically)
    }
}
