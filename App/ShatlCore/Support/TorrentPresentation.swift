// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated struct VisibleMetric: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var value: String
}

nonisolated struct MetricItemPresentation: Identifiable, Equatable, Sendable {
    var id: String
    var iconName: String?
    var number: String?
    var unit: String?
    var usesAccentIcon: Bool
}

nonisolated struct CompactTransferMetricSet: Equatable, Sendable {
    var items: [MetricItemPresentation]
}

nonisolated struct MetricGroupPresentation: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var items: [MetricItemPresentation]
}

nonisolated struct ExpandedMetricGroupsPresentation: Equatable, Sendable {
    var dynamicGroups: [MetricGroupPresentation]
    var sizeGroup: MetricGroupPresentation
}

nonisolated enum BottomTransferChipKind: String, Identifiable, Sendable {
    case download
    case upload

    nonisolated var id: String { rawValue }
}

nonisolated struct BottomTransferChipPresentation: Identifiable, Equatable, Sendable {
    var kind: BottomTransferChipKind
    var item: MetricItemPresentation

    nonisolated var id: String { kind.id }
}

/// Decides what a torrent card displays without exposing UI details to the engine.
nonisolated enum TorrentPresentation {
    nonisolated static func compactMetrics(
        for record: TorrentRecord,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride = .russian
    ) -> [VisibleMetric] {
        var metrics: [VisibleMetric] = []
        let isDownloadPhase = record.status == .downloading

        // Download speed and ETA belong only to the downloading phase.
        // Hide them while seeding even if the engine briefly reports a nonzero
        // download rate.
        if isDownloadPhase && record.metrics.hasVisibleDownloadSpeed {
            metrics.append(
                VisibleMetric(
                    id: "download-speed",
                    title: L10n.string("torrent.metric.download_speed", localeOverride: localeOverride, defaultValue: "Скорость загрузки"),
                    value: Metrics.formatSpeed(record.metrics.downloadSpeedBytesPerSecond, mode: mode, localeOverride: localeOverride)
                )
            )
        }

        if isDownloadPhase, let etaSeconds = record.metrics.etaSeconds, etaSeconds > 0 {
            metrics.append(
                VisibleMetric(
                    id: "eta",
                    title: L10n.string("torrent.metric.eta", localeOverride: localeOverride, defaultValue: "Осталось"),
                    value: Metrics.formatETA(etaSeconds, mode: mode, localeOverride: localeOverride)
                )
            )
        }

        return metrics
    }

    nonisolated static func compactTransferMetricSet(
        for record: TorrentRecord,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride = .russian
    ) -> CompactTransferMetricSet? {
        guard record.status == .downloading else { return nil }

        let speed = record.metrics.downloadSpeedBytesPerSecond
        guard speed > 0 else { return nil }

        let speedComponents = splitMetricValue(Metrics.formatSpeed(speed, mode: mode, localeOverride: localeOverride))
        var items = [
            MetricItemPresentation(
                id: "download-speed",
                iconName: downloadSpeedIconName(for: speed),
                number: speedComponents.number,
                unit: speedComponents.unit,
                usesAccentIcon: true
            ),
        ]

        if let etaSeconds = record.metrics.etaSeconds, etaSeconds > 0 {
            let etaComponents = splitMetricValue(Metrics.formatETA(etaSeconds, mode: mode, localeOverride: localeOverride))
            items.append(
                MetricItemPresentation(
                    id: "eta",
                    iconName: nil,
                    number: etaComponents.number,
                    unit: etaComponents.unit,
                    usesAccentIcon: true
                )
            )
        }

        return CompactTransferMetricSet(items: items)
    }

    nonisolated static func expandedMetricGroups(
        for record: TorrentRecord,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride = .russian
    ) -> ExpandedMetricGroupsPresentation {
        var dynamicGroups: [MetricGroupPresentation] = []
        let showsConnectivityMetrics = record.status == .downloading || record.status == .seeding

        let peerItems = peerMetricItems(for: record)
        if !peerItems.isEmpty {
            dynamicGroups.append(
                MetricGroupPresentation(
                    id: "peers",
                    title: L10n.string("torrent.metric.seeds_and_peers", localeOverride: localeOverride, defaultValue: "Сиды и Пиры"),
                    items: peerItems
                )
            )
        }

        if showsConnectivityMetrics && record.metrics.hasVisibleUploadSpeed {
            dynamicGroups.append(
                MetricGroupPresentation(
                    id: "upload-speed",
                    title: L10n.string("torrent.metric.upload_speed", localeOverride: localeOverride, defaultValue: "Скорость раздачи"),
                    items: [uploadSpeedMetricItem(for: record, mode: mode, localeOverride: localeOverride)]
                )
            )
        }

        if record.metrics.uploadedBytes > 0 {
            dynamicGroups.append(
                MetricGroupPresentation(
                    id: "uploaded",
                    title: L10n.string("torrent.metric.uploaded", localeOverride: localeOverride, defaultValue: "Отдано"),
                    items: [
                        bytesMetricItem(
                            id: "uploaded",
                            iconName: "shippingbox.and.arrow.backward",
                            bytes: record.metrics.uploadedBytes,
                            purpose: .uploaded,
                            mode: mode,
                            localeOverride: localeOverride
                        ),
                    ]
                )
            )
        }

        return ExpandedMetricGroupsPresentation(
            dynamicGroups: dynamicGroups,
            sizeGroup: MetricGroupPresentation(
                id: "size",
                title: L10n.string("torrent.metric.size", localeOverride: localeOverride, defaultValue: "Размер"),
                items: [
                    bytesMetricItem(
                        id: "size",
                        iconName: "scalemass",
                        bytes: selectedSizeBytes(for: record),
                        purpose: .size,
                        mode: mode,
                        localeOverride: localeOverride
                    ),
                ]
            )
        )
    }

    nonisolated static func bottomTransferChips(
        for records: [TorrentRecord],
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride = .russian
    ) -> [BottomTransferChipPresentation] {
        var chips: [BottomTransferChipPresentation] = []

        let downloadingRecords = records.filter {
            $0.status == .downloading && $0.metrics.downloadSpeedBytesPerSecond > 0
        }

        if downloadingRecords.count > 1 {
            let totalDownloadSpeed = downloadingRecords.reduce(Int64(0)) {
                $0 + $1.metrics.downloadSpeedBytesPerSecond
            }
            chips.append(
                bottomTransferChip(
                    kind: .download,
                    iconName: "square.and.arrow.down.fill",
                    bytesPerSecond: totalDownloadSpeed,
                    mode: mode,
                    localeOverride: localeOverride
                )
            )
        }

        let uploadingRecords = records.filter {
            ($0.status == .downloading || $0.status == .seeding)
                && $0.metrics.uploadSpeedBytesPerSecond > 0
        }

        if uploadingRecords.count > 1 {
            let totalUploadSpeed = uploadingRecords.reduce(Int64(0)) {
                $0 + $1.metrics.uploadSpeedBytesPerSecond
            }
            chips.append(
                bottomTransferChip(
                    kind: .upload,
                    iconName: "square.and.arrow.up.fill",
                    bytesPerSecond: totalUploadSpeed,
                    mode: mode,
                    localeOverride: localeOverride
                )
            )
        }

        return chips
    }

    nonisolated static func expandedMetrics(
        for record: TorrentRecord,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride = .russian
    ) -> [VisibleMetric] {
        var metrics: [VisibleMetric] = []
        let showsConnectivityMetrics = record.status == .downloading || record.status == .seeding

        if showsConnectivityMetrics && record.metrics.hasVisiblePeerStats {
            metrics.append(
                VisibleMetric(
                    id: "peers",
                    title: L10n.string("torrent.metric.seeds_and_peers", localeOverride: localeOverride, defaultValue: "Сиды и Пиры"),
                    value: "\(Metrics.formatPeerCount(record.metrics.seeds ?? 0)) ↑  \(Metrics.formatPeerCount(record.metrics.peers ?? 0)) ↓"
                )
            )
        }

        if showsConnectivityMetrics && record.metrics.hasVisibleUploadSpeed {
            metrics.append(
                VisibleMetric(
                    id: "upload-speed",
                    title: L10n.string("torrent.metric.upload_speed", localeOverride: localeOverride, defaultValue: "Скорость раздачи"),
                    value: Metrics.formatSpeed(record.metrics.uploadSpeedBytesPerSecond, mode: mode, localeOverride: localeOverride)
                )
            )
        }

        if record.metrics.uploadedBytes > 0 {
            metrics.append(
                VisibleMetric(
                    id: "uploaded",
                    title: L10n.string("torrent.metric.uploaded", localeOverride: localeOverride, defaultValue: "Отдано"),
                    value: Metrics.formatBytes(record.metrics.uploadedBytes, purpose: .uploaded, mode: mode, localeOverride: localeOverride)
                )
            )
        }

        if record.metrics.totalBytes > 0 {
            metrics.append(
                VisibleMetric(
                    id: "size",
                    title: L10n.string("torrent.metric.size", localeOverride: localeOverride, defaultValue: "Размер"),
                    value: Metrics.formatBytes(record.metrics.totalBytes, purpose: .size, mode: mode, localeOverride: localeOverride)
                )
            )
        }

        return metrics
    }

    private nonisolated static func bottomTransferChip(
        kind: BottomTransferChipKind,
        iconName: String,
        bytesPerSecond: Int64,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride
    ) -> BottomTransferChipPresentation {
        let components = splitMetricValue(Metrics.formatSpeed(bytesPerSecond, mode: mode, localeOverride: localeOverride))
        return BottomTransferChipPresentation(
            kind: kind,
            item: MetricItemPresentation(
                id: "bottom-\(kind.id)-speed",
                iconName: iconName,
                number: components.number,
                unit: components.unit,
                usesAccentIcon: true
            )
        )
    }

    private nonisolated static func peerMetricItems(for record: TorrentRecord) -> [MetricItemPresentation] {
        var items: [MetricItemPresentation] = []
        let seeds = record.metrics.seeds ?? 0
        let peers = record.metrics.peers ?? 0

        if seeds > 0 {
            items.append(
                MetricItemPresentation(
                    id: "seeds",
                    iconName: "arrow.up",
                    number: Metrics.formatPeerCount(seeds),
                    unit: nil,
                    usesAccentIcon: false
                )
            )
        }

        if peers > 0 {
            items.append(
                MetricItemPresentation(
                    id: "peers",
                    iconName: "arrow.up.arrow.down",
                    number: Metrics.formatPeerCount(peers),
                    unit: nil,
                    usesAccentIcon: false
                )
            )
        }

        return items
    }

    private nonisolated static func uploadSpeedMetricItem(
        for record: TorrentRecord,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride
    ) -> MetricItemPresentation {
        let speed = record.metrics.uploadSpeedBytesPerSecond
        let components = splitMetricValue(Metrics.formatSpeed(speed, mode: mode, localeOverride: localeOverride))
        return MetricItemPresentation(
            id: "upload-speed",
            iconName: downloadSpeedIconName(for: speed),
            number: components.number,
            unit: components.unit,
            usesAccentIcon: false
        )
    }

    private nonisolated static func bytesMetricItem(
        id: String,
        iconName: String,
        bytes: Int64,
        purpose: MetricsBytePurpose,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride
    ) -> MetricItemPresentation {
        let components = splitMetricValue(Metrics.formatBytes(bytes, purpose: purpose, mode: mode, localeOverride: localeOverride))
        return MetricItemPresentation(
            id: id,
            iconName: iconName,
            number: components.number,
            unit: components.unit,
            usesAccentIcon: false
        )
    }

    private nonisolated static func selectedSizeBytes(for record: TorrentRecord) -> Int64 {
        record.metrics.selectedBytes > 0 ? record.metrics.selectedBytes : record.metrics.totalBytes
    }

    private nonisolated static func downloadSpeedIconName(for bytesPerSecond: Int64) -> String {
        let kilobytesPerSecond = Int64(250 * 1_024)
        let twoMegabytesPerSecond = Int64(2 * 1_024 * 1_024)
        let eightMegabytesPerSecond = Int64(8 * 1_024 * 1_024)
        let twentyFiveMegabytesPerSecond = Int64(25 * 1_024 * 1_024)

        switch bytesPerSecond {
        case 1..<kilobytesPerSecond:
            return "tortoise.fill"
        case kilobytesPerSecond..<twoMegabytesPerSecond:
            return "figure.walk"
        case twoMegabytesPerSecond..<eightMegabytesPerSecond:
            return "figure.run"
        case eightMegabytesPerSecond..<twentyFiveMegabytesPerSecond:
            return "hare.fill"
        default:
            return "bolt.fill"
        }
    }

    private nonisolated static func splitMetricValue(_ value: String) -> (number: String, unit: String?) {
        let parts = value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return (value, nil)
        }

        return (String(parts[0]), String(parts[1]))
    }
}
