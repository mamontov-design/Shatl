// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated enum MetricsPresentationMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case simplified
    case detailed

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .simplified:
            "Упрощённо"
        case .detailed:
            "Подробно"
        }
    }
}

nonisolated enum MetricsBytePurpose: Sendable {
    case general
    case uploaded
    case size
}

/// Defines metric presentation rules independently from view code.
nonisolated enum Metrics {
    nonisolated static func formatSpeed(
        _ bytesPerSecond: Int64,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride = .russian
    ) -> String {
        MetricsDisplayRules.rules(for: mode, localeOverride: localeOverride).formatSpeed(bytesPerSecond)
    }

    nonisolated static func formatBytes(
        _ bytes: Int64,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride = .russian
    ) -> String {
        MetricsDisplayRules.rules(for: mode, localeOverride: localeOverride).formatBytes(bytes, purpose: .general)
    }

    nonisolated static func formatBytes(
        _ bytes: Int64,
        purpose: MetricsBytePurpose,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride = .russian
    ) -> String {
        MetricsDisplayRules.rules(for: mode, localeOverride: localeOverride).formatBytes(bytes, purpose: purpose)
    }

    nonisolated static func formatETA(
        _ seconds: Int?,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride = .russian
    ) -> String {
        MetricsDisplayRules.rules(for: mode, localeOverride: localeOverride).formatETA(seconds)
    }

    nonisolated static func formatPeerCount(_ count: Int) -> String {
        count > 999 ? ">999" : "\(max(0, count))"
    }
}
