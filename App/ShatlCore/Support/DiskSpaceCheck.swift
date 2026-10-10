// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Whether a download fits on its disk and, if not, how much it lacks.
nonisolated struct DiskSpaceCheck: Equatable, Codable, Sendable {
    var neededBytes: Int64
    var availableBytes: Int64
    /// The disk as macOS names it: "Macintosh HD".
    var volumeName: String

    var fits: Bool {
        neededBytes <= availableBytes
    }

    /// The check, when `neededBytes` do not fit on the disk; `nil` when
    /// they do or nothing is to be saved.
    static func shortfall(neededBytes: Int64, on disk: DiskSpaceInfo) -> DiskSpaceCheck? {
        guard neededBytes > 0 else { return nil }
        let check = DiskSpaceCheck(
            neededBytes: neededBytes,
            availableBytes: disk.availableBytes,
            volumeName: disk.volumeName
        )
        return check.fits ? nil : check
    }

    /// The size a text names, rounded up as the add window rounds it.
    func neededText(mode: MetricsPresentationMode, localeOverride: AppLocaleOverride) -> String {
        Self.unbroken(
            AddTorrentSummaryByteFormatter.format(
                neededBytes,
                mode: mode,
                rounding: .up,
                localeOverride: localeOverride
            )
        )
    }

    /// The free space a text names, rounded down as the add window rounds it.
    func availableText(mode: MetricsPresentationMode, localeOverride: AppLocaleOverride) -> String {
        Self.unbroken(
            AddTorrentSummaryByteFormatter.format(
                availableBytes,
                mode: mode,
                rounding: .down,
                localeOverride: localeOverride
            )
        )
    }

    /// Inside a sentence a number stays on one line with its unit.
    private static func unbroken(_ size: String) -> String {
        size.replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// What is missing. With rounded numbers it is the difference of the two
    /// numbers shown, so "needs 172 GB, 16 GB free" lacks 156 GB and not the
    /// 155 the exact bytes would round to.
    func shortfallText(mode: MetricsPresentationMode, localeOverride: AppLocaleOverride) -> String {
        let shortfall: Int64
        switch mode {
        case .detailed:
            shortfall = max(0, neededBytes - availableBytes)
        case .simplified:
            shortfall = max(
                0,
                AddTorrentSummaryByteFormatter.roundedBytes(neededBytes, rounding: .up)
                    - AddTorrentSummaryByteFormatter.roundedBytes(availableBytes, rounding: .down)
            )
        }

        return Self.unbroken(
            AddTorrentSummaryByteFormatter.format(
                shortfall,
                mode: mode,
                rounding: .up,
                localeOverride: localeOverride
            )
        )
    }
}

/// What the "i" of a saved download answers: can it start now.
nonisolated enum SavedDownloadSpaceStatus: Equatable, Sendable {
    case known(DiskSpaceCheck)
    /// The folder cannot be reached, so its disk says nothing.
    case unknown(folderName: String)
}

nonisolated enum AddTorrentSummaryByteRounding: Sendable {
    case up
    case down
}

/// Sizes as the add window's summary shows them: whole numbers in the
/// simplified mode, a size rounded up and free space rounded down, so the
/// window never promises room that is not there.
nonisolated enum AddTorrentSummaryByteFormatter {
    static func format(
        _ bytes: Int64,
        mode: MetricsPresentationMode,
        rounding: AddTorrentSummaryByteRounding,
        localeOverride: AppLocaleOverride
    ) -> String {
        switch mode {
        case .detailed:
            Metrics.formatBytes(bytes, mode: mode, localeOverride: localeOverride)
        case .simplified:
            formatSimplified(bytes, rounding: rounding, localeOverride: localeOverride)
        }
    }

    /// The bytes behind the whole number the simplified mode shows.
    static func roundedBytes(_ bytes: Int64, rounding: AddTorrentSummaryByteRounding) -> Int64 {
        let positiveBytes = max(bytes, 0)
        guard let threshold = unitThresholds.first(where: { Double(positiveBytes) >= $0 }) else {
            return positiveBytes
        }
        return Int64(roundedValue(Double(positiveBytes) / threshold, rounding: rounding)) * Int64(threshold)
    }

    private static func formatSimplified(
        _ bytes: Int64,
        rounding: AddTorrentSummaryByteRounding,
        localeOverride: AppLocaleOverride
    ) -> String {
        let positiveBytes = max(bytes, 0)
        guard let unit = units(localeOverride: localeOverride).first(where: { Double(positiveBytes) >= $0.threshold }) else {
            return metricValue(positiveBytes, unitKey: "unit.byte", fallback: "Б", localeOverride: localeOverride)
        }

        let visibleValue = roundedValue(Double(positiveBytes) / unit.threshold, rounding: rounding)
        return "\(localizedInteger(visibleValue, localeOverride: localeOverride)) \(unit.label)"
    }

    private static func roundedValue(_ value: Double, rounding: AddTorrentSummaryByteRounding) -> Int64 {
        switch rounding {
        case .up:
            Int64(value.rounded(.up))
        case .down:
            Int64(value.rounded(.down))
        }
    }

    private static func metricValue<T>(
        _ value: T,
        unitKey: String,
        fallback: String,
        localeOverride: AppLocaleOverride
    ) -> String {
        "\(value) \(L10n.string(unitKey, localeOverride: localeOverride, defaultValue: fallback))"
    }

    private static func localizedInteger(
        _ value: Int64,
        localeOverride: AppLocaleOverride
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = L10n.locale(for: localeOverride)
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let unitThresholds: [Double] = [
        1_000_000_000_000,
        1_000_000_000,
        1_000_000,
        1_000,
    ]

    private static func units(
        localeOverride: AppLocaleOverride
    ) -> [(threshold: Double, label: String)] {
        [
            (
                unitThresholds[0],
                L10n.string("unit.terabyte", localeOverride: localeOverride, defaultValue: "ТБ")
            ),
            (
                unitThresholds[1],
                L10n.string("unit.gigabyte", localeOverride: localeOverride, defaultValue: "ГБ")
            ),
            (
                unitThresholds[2],
                L10n.string("unit.megabyte", localeOverride: localeOverride, defaultValue: "МБ")
            ),
            (
                unitThresholds[3],
                L10n.string("unit.kilobyte", localeOverride: localeOverride, defaultValue: "КБ")
            ),
        ]
    }
}
