// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated enum MetricWidthAnimationPattern {
    static func forText(_ text: String) -> String {
        String(text.map { $0.isNumber ? "#" : $0 })
    }
}

nonisolated struct MetricItemPresentation: Identifiable, Equatable, Sendable {
    var id: String
    var iconName: String?
    var number: String?
    var unit: String?
    var usesAccentIcon: Bool

    var widthAnimationSignature: MetricItemWidthAnimationSignature {
        MetricItemWidthAnimationSignature(
            id: id,
            iconName: iconName,
            numberPattern: number.map(MetricWidthAnimationPattern.forText),
            unit: unit
        )
    }
}

nonisolated struct MetricItemWidthAnimationSignature: Hashable, Sendable {
    var id: String
    var iconName: String?
    var numberPattern: String?
    var unit: String?
}

nonisolated extension Array where Element == MetricItemPresentation {
    var metricWidthAnimationSignature: [MetricItemWidthAnimationSignature] {
        map(\.widthAnimationSignature)
    }
}

nonisolated struct CompactTransferMetricSet: Equatable, Sendable {
    var items: [MetricItemPresentation]
}

nonisolated struct MetricGroupPresentation: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var items: [MetricItemPresentation]

    var widthAnimationSignature: MetricGroupWidthAnimationSignature {
        MetricGroupWidthAnimationSignature(
            id: id,
            title: title,
            items: items.metricWidthAnimationSignature
        )
    }
}

nonisolated struct MetricGroupWidthAnimationSignature: Hashable, Sendable {
    var id: String
    var title: String
    var items: [MetricItemWidthAnimationSignature]
}

nonisolated extension Array where Element == MetricGroupPresentation {
    var groupWidthAnimationSignature: [MetricGroupWidthAnimationSignature] {
        map(\.widthAnimationSignature)
    }
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

/// How fast a transfer goes, as its speed icon shows it. A level goes up as
/// soon as the speed reaches the next threshold, but comes down only once the
/// speed falls 10 % below the threshold of the level it holds: a speed that
/// wavers at a threshold would otherwise swap the icon, and bounce the metric
/// set, every second.
nonisolated enum TransferSpeedLevel: Int, CaseIterable, Comparable, Sendable {
    case tortoise
    case walk
    case run
    case hare
    case bolt

    static let fallMargin = 0.1

    /// The lowest speed of the level, in bytes per second.
    var threshold: Int64 {
        switch self {
        case .tortoise: 1
        case .walk: 250 * 1_024
        case .run: 2 * 1_024 * 1_024
        case .hare: 8 * 1_024 * 1_024
        case .bolt: 25 * 1_024 * 1_024
        }
    }

    /// The level of a speed seen for the first time.
    init(bytesPerSecond: Int64) {
        self = Self.allCases.last { bytesPerSecond >= $0.threshold } ?? .tortoise
    }

    /// The level of a speed that follows `previous`.
    init(bytesPerSecond: Int64, after previous: TransferSpeedLevel?) {
        let plain = TransferSpeedLevel(bytesPerSecond: bytesPerSecond)
        guard var level = previous, level > plain else {
            self = plain
            return
        }
        while level > plain,
              Double(bytesPerSecond) < Double(level.threshold) * (1 - Self.fallMargin),
              let lower = TransferSpeedLevel(rawValue: level.rawValue - 1) {
            level = lower
        }
        self = level
    }

    /// The level an icon stands for, whether a download or an upload icon.
    init?(iconName: String) {
        guard let level = Self.allCases.first(where: {
            $0.downloadIconName == iconName || $0.uploadIconName == iconName
        }) else { return nil }
        self = level
    }

    var downloadIconName: String {
        switch self {
        case .tortoise: "tortoise.fill"
        case .walk: "figure.walk"
        case .run: "figure.run"
        case .hare: "hare.fill"
        case .bolt: "bolt.fill"
        }
    }

    var uploadIconName: String {
        switch self {
        case .tortoise: "tortoise"
        case .walk: "figure.walk"
        case .run: "figure.run"
        case .hare: "hare"
        case .bolt: "bolt"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The speed levels a torrent's icons show, kept from one update to the next.
nonisolated struct TransferSpeedLevels: Equatable, Sendable {
    var download: TransferSpeedLevel?
    var upload: TransferSpeedLevel?

    /// The levels for new metrics that follow these. A speed of zero shows no
    /// icon, and the next speed starts afresh.
    func following(_ metrics: TorrentMetrics) -> TransferSpeedLevels {
        TransferSpeedLevels(
            download: Self.level(metrics.downloadSpeedBytesPerSecond, after: download),
            upload: Self.level(metrics.uploadSpeedBytesPerSecond, after: upload)
        )
    }

    private static func level(_ bytesPerSecond: Int64, after previous: TransferSpeedLevel?) -> TransferSpeedLevel? {
        bytesPerSecond > 0 ? TransferSpeedLevel(bytesPerSecond: bytesPerSecond, after: previous) : nil
    }
}

/// Decides what a torrent card displays without exposing UI details to the engine.
nonisolated enum TorrentPresentation {
    nonisolated static func compactTransferMetricSet(
        for record: TorrentRecord,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride = .russian,
        speedLevels: TransferSpeedLevels? = nil
    ) -> CompactTransferMetricSet? {
        guard record.status == .downloading else { return nil }

        let speed = record.metrics.downloadSpeedBytesPerSecond
        guard speed > 0 else { return nil }

        let speedComponents = splitMetricValue(Metrics.formatSpeed(speed, mode: mode, localeOverride: localeOverride))
        let speedLevel = speedLevels?.download ?? TransferSpeedLevel(bytesPerSecond: speed)
        var items = [
            MetricItemPresentation(
                id: "download-speed",
                iconName: speedLevel.downloadIconName,
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
        localeOverride: AppLocaleOverride = .russian,
        speedLevels: TransferSpeedLevels? = nil
    ) -> ExpandedMetricGroupsPresentation {
        var dynamicGroups: [MetricGroupPresentation] = []
        let showsConnectivityMetrics = record.status == .downloading || record.status == .seeding

        let peerItems = peerMetricItems(for: record, mode: mode)
        if showsConnectivityMetrics && !peerItems.isEmpty {
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
                    items: [
                        uploadSpeedMetricItem(
                            for: record,
                            mode: mode,
                            localeOverride: localeOverride,
                            level: speedLevels?.upload
                        ),
                    ]
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

    private nonisolated static func peerMetricItems(
        for record: TorrentRecord,
        mode: MetricsPresentationMode
    ) -> [MetricItemPresentation] {
        var items: [MetricItemPresentation] = []
        let seeds = record.metrics.seeds ?? 0
        let peers = record.metrics.peers ?? 0

        if seeds > 0 {
            items.append(
                MetricItemPresentation(
                    id: "seeds",
                    iconName: "arrow.up",
                    number: Metrics.formatPeerCount(seeds, mode: mode),
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
                    number: Metrics.formatPeerCount(peers, mode: mode),
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
        localeOverride: AppLocaleOverride,
        level: TransferSpeedLevel?
    ) -> MetricItemPresentation {
        let speed = record.metrics.uploadSpeedBytesPerSecond
        let components = splitMetricValue(Metrics.formatSpeed(speed, mode: mode, localeOverride: localeOverride))
        return MetricItemPresentation(
            id: "upload-speed",
            iconName: (level ?? TransferSpeedLevel(bytesPerSecond: speed)).uploadIconName,
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

    private nonisolated static func splitMetricValue(_ value: String) -> (number: String, unit: String?) {
        let parts = value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return (value, nil)
        }

        return (String(parts[0]), String(parts[1]))
    }
}
