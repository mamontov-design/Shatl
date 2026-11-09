// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Whether a download fits on its disk and, if not, how much it lacks.
nonisolated struct DiskSpaceCheck: Equatable, Codable, Sendable {
    var neededBytes: Int64
    var availableBytes: Int64
    /// The disk as macOS names it: "Macintosh HD".
    var volumeName: String
    /// What downloads already writing to the same disk will still write
    /// (`PromisedDiskSpace`). Only the add window counts it; a saved
    /// download's "i" and its "Пуск" do not, so starting it by hand stays
    /// the person's choice. `nil` when nothing is promised, and in checks
    /// saved before it was counted.
    var promisedBytes: Int64? = nil

    var fits: Bool {
        neededBytes + (promisedBytes ?? 0) <= availableBytes
    }

    /// The check, when `neededBytes` do not fit on the disk beside what is
    /// promised on it; `nil` when they do or nothing is to be saved.
    static func shortfall(
        neededBytes: Int64,
        promisedBytes: Int64 = 0,
        on disk: DiskSpaceInfo
    ) -> DiskSpaceCheck? {
        guard neededBytes > 0 else { return nil }
        let check = DiskSpaceCheck(
            neededBytes: neededBytes,
            availableBytes: disk.availableBytes,
            volumeName: disk.volumeName,
            promisedBytes: promisedBytes > 0 ? promisedBytes : nil
        )
        return check.fits ? nil : check
    }

    /// What the downloads writing to the disk will still take, rounded as a
    /// size is.
    func promisedText(mode: MetricsPresentationMode, localeOverride: AppLocaleOverride) -> String {
        Self.unbroken(
            AddTorrentSummaryByteFormatter.format(
                promisedBytes ?? 0,
                mode: mode,
                rounding: .nearest,
                localeOverride: localeOverride
            )
        )
    }

    /// The size a text names, rounded as the add window rounds it.
    func neededText(mode: MetricsPresentationMode, localeOverride: AppLocaleOverride) -> String {
        Self.unbroken(
            AddTorrentSummaryByteFormatter.format(
                neededBytes,
                mode: mode,
                rounding: .nearest,
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

    /// What is missing. With rounded numbers it is what the numbers shown
    /// add up to, so "needs 172 GB, 16 GB free" lacks 156 GB and not the 155
    /// the exact bytes would round to, and "needs 60 GB, 100 GB free, 60 GB
    /// promised" lacks 20 GB. When the numbers shown leave nothing missing,
    /// "needs 2 GB, 2 GB free", it is what the exact bytes lack: "100 MB".
    func shortfallText(mode: MetricsPresentationMode, localeOverride: AppLocaleOverride) -> String {
        let promised = promisedBytes ?? 0
        let exact = max(0, neededBytes + promised - availableBytes)
        let shortfall: Int64
        switch mode {
        case .detailed:
            shortfall = exact
        case .simplified:
            let shown = AddTorrentSummaryByteFormatter.roundedBytes(neededBytes, rounding: .nearest)
                + (promised > 0 ? AddTorrentSummaryByteFormatter.roundedBytes(promised, rounding: .nearest) : 0)
                - AddTorrentSummaryByteFormatter.roundedBytes(availableBytes, rounding: .down)
            shortfall = shown > 0 ? shown : exact
        }

        return Self.unbroken(
            AddTorrentSummaryByteFormatter.format(
                shortfall,
                mode: mode,
                rounding: .nearest,
                localeOverride: localeOverride
            )
        )
    }
}

/// Space the downloads in the list will still take by themselves: what the
/// add window counts beside the free space Finder shows.
nonisolated enum PromisedDiskSpace {
    /// Whether a download writes to its disk without anyone starting it:
    /// it is downloading or checking. A stopped one waits for "Пуск", and a
    /// saved one waits for room itself; counting it would keep every next
    /// download out too.
    static func isWriting(_ record: TorrentRecord) -> Bool {
        guard !record.isSavedForLater else { return false }
        switch record.status {
        case .downloading, .checking:
            return true
        case .stopped, .seeding, .completed, .error:
            return false
        }
    }

    /// What a download still has to write: the files chosen, less what it
    /// has. With sparse files, written bytes are already off the free space.
    static func remainingBytes(of record: TorrentRecord) -> Int64 {
        let selected = max(0, record.metrics.selectedBytes)
        let progress = min(max(record.progress, 0), 1)
        return max(0, selected - Int64((Double(selected) * progress).rounded(.down)))
    }

    /// One spelling for a folder, so a download's folder and the add
    /// window's compare as the same.
    static func folderKey(_ path: String) -> String {
        NSString(string: path.trimmingCharacters(in: .whitespacesAndNewlines)).standardizingPath
    }
}

/// What the "i" of a saved download answers: can it start now.
nonisolated enum SavedDownloadSpaceStatus: Equatable, Sendable {
    case known(DiskSpaceCheck)
    /// The folder cannot be reached, so its disk says nothing.
    case unknown(folderName: String)
}

nonisolated enum AddTorrentSummaryByteRounding: Sendable {
    /// Sizes: a file, a folder, what is chosen, what is missing.
    case nearest
    /// Free space, so the window never promises room that is not there.
    case down
}

/// Sizes as the add window shows them, in its files and its summary, and
/// as the texts about a disk's room name them: whole numbers in the
/// simplified mode, the exact value in the detailed one, as the card's
/// metrics follow the same switch. A size is rounded to the nearest whole
/// number, so a file and the summary of that file name one size (the
/// owner's decision, November 2026; until then the summary rounded up and
/// the files to a tenth); free space is rounded down.
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
        guard let shown = shownValue(positiveBytes, rounding: rounding) else {
            return positiveBytes
        }
        return shown.value * Int64(unitThresholds[shown.unitIndex])
    }

    private static func formatSimplified(
        _ bytes: Int64,
        rounding: AddTorrentSummaryByteRounding,
        localeOverride: AppLocaleOverride
    ) -> String {
        let positiveBytes = max(bytes, 0)
        guard let shown = shownValue(positiveBytes, rounding: rounding) else {
            return metricValue(positiveBytes, unitKey: "unit.byte", fallback: "Б", localeOverride: localeOverride)
        }

        let label = units(localeOverride: localeOverride)[shown.unitIndex].label
        return "\(localizedInteger(shown.value, localeOverride: localeOverride)) \(label)"
    }

    /// The whole number shown and the index of its unit. A value that rounds
    /// to 1 000 of its unit is 1 of the next one: "1 ГБ", not "1 000 МБ".
    private static func shownValue(
        _ bytes: Int64,
        rounding: AddTorrentSummaryByteRounding
    ) -> (value: Int64, unitIndex: Int)? {
        guard var index = unitThresholds.firstIndex(where: { Double(bytes) >= $0 }) else {
            return nil
        }
        var value = roundedValue(Double(bytes) / unitThresholds[index], rounding: rounding)
        if value >= 1_000, index > 0 {
            index -= 1
            value = roundedValue(Double(bytes) / unitThresholds[index], rounding: rounding)
        }
        return (value, index)
    }

    private static func roundedValue(_ value: Double, rounding: AddTorrentSummaryByteRounding) -> Int64 {
        switch rounding {
        case .nearest:
            Int64(value.rounded())
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
