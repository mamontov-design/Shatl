// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated struct TorrentRowErrorState: Equatable, Sendable {
    var kind: TorrentErrorState.Kind
    var title: String
    var message: String
    var recoveryOptions: [TorrentErrorState.RecoveryOption]

    init?(_ errorState: TorrentErrorState?, localeOverride: AppLocaleOverride = .russian) {
        guard let errorState else { return nil }

        self.kind = errorState.kind
        self.title = Self.localizedTitle(for: errorState, localeOverride: localeOverride)
        self.message = Self.localizedMessage(for: errorState, localeOverride: localeOverride)
        self.recoveryOptions = errorState.recoveryOptions
    }

    private static func localizedTitle(
        for errorState: TorrentErrorState,
        localeOverride: AppLocaleOverride
    ) -> String {
        switch errorState.kind {
        case .missingContent:
            L10n.string("torrent.error.missing_content.title", localeOverride: localeOverride, defaultValue: errorState.title)
        case .savePathUnavailable:
            L10n.string("torrent.error.save_path_unavailable.title", localeOverride: localeOverride, defaultValue: errorState.title)
        case .torrentNotFound:
            L10n.string("torrent.error.not_found.title", localeOverride: localeOverride, defaultValue: errorState.title)
        case .engineFailure:
            L10n.string("torrent.error.action_failed.title", localeOverride: localeOverride, defaultValue: errorState.title)
        default:
            errorState.title
        }
    }

    private static func localizedMessage(
        for errorState: TorrentErrorState,
        localeOverride: AppLocaleOverride
    ) -> String {
        switch errorState.kind {
        case .missingContent:
            L10n.string("torrent.error.missing_content.message", localeOverride: localeOverride, defaultValue: errorState.message)
        case .savePathUnavailable:
            L10n.string("torrent.error.save_path_unavailable.message", localeOverride: localeOverride, defaultValue: errorState.message)
        case .torrentNotFound:
            L10n.string("torrent.error.not_found.message", localeOverride: localeOverride, defaultValue: errorState.message)
        case .engineFailure:
            L10n.string("torrent.error.action_failed.message", localeOverride: localeOverride, defaultValue: errorState.message)
        default:
            errorState.message
        }
    }
}

nonisolated struct TorrentRowState: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var originalTitle: String
    var hasAlias: Bool
    var status: TorrentStatus
    var statusTitle: String
    var progress: Double
    var downloadSpeedBytesPerSecond: Int64
    var uploadSpeedBytesPerSecond: Int64
    var visibleProgressPercent: Int?
    var compactTransferMetricSet: CompactTransferMetricSet?
    var compactMetrics: [VisibleMetric]
    var expandedMetrics: [VisibleMetric]
    var expandedMetricGroups: ExpandedMetricGroupsPresentation?
    var metricsMode: MetricsPresentationMode
    var errorState: TorrentRowErrorState?
    var isSelected: Bool
    var isExpanded: Bool
    var canToggleRunningState: Bool
    var canRemoveFromList: Bool
    var canRemoveWithFiles: Bool
    var navigationAvailabilityKey: String
    var localeOverride: AppLocaleOverride
}
