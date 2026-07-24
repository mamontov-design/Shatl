import Foundation

nonisolated struct MetricsDisplayRules: Sendable {
    private let mode: MetricsPresentationMode
    private let localeOverride: AppLocaleOverride

    nonisolated static func rules(
        for mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride = .russian
    ) -> MetricsDisplayRules {
        MetricsDisplayRules(mode: mode, localeOverride: localeOverride)
    }

    nonisolated func formatSpeed(_ bytesPerSecond: Int64) -> String {
        guard bytesPerSecond > 0 else { return metricValue(0, unitKey: "unit.speed.bytes_per_second", fallback: "Б/с") }

        switch mode {
        case .simplified:
            return formatSimplifiedSpeed(bytesPerSecond)
        case .detailed:
            return formatDetailedSpeed(bytesPerSecond)
        }
    }

    nonisolated func formatBytes(_ bytes: Int64, purpose: MetricsBytePurpose) -> String {
        switch mode {
        case .simplified:
            formatSimplifiedBytes(bytes, purpose: purpose)
        case .detailed:
            formatByteCount(bytes, allowedUnits: [.useBytes, .useKB, .useMB, .useGB, .useTB], suffix: nil)
        }
    }

    nonisolated func formatETA(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "—" }

        switch mode {
        case .simplified:
            return formatSimplifiedETA(seconds)
        case .detailed:
            return formatDetailedETA(seconds)
        }
    }

    private nonisolated func formatDetailedSpeed(_ bytesPerSecond: Int64) -> String {
        if bytesPerSecond < 103 {
            return metricValue(bytesPerSecond, unitKey: "unit.speed.bytes_per_second", fallback: "Б/с")
        }

        if bytesPerSecond < 1_024 {
            let kilobytesPerSecond = Double(bytesPerSecond) / 1_024
            return metricValue(
                formatDecimal(kilobytesPerSecond, fractionDigits: 1),
                unitKey: "unit.speed.kilobytes_per_second",
                fallback: "КБ/с"
            )
        }

        return formatByteCount(
            bytesPerSecond,
            allowedUnits: [.useKB, .useMB, .useGB],
            suffix: L10n.string("unit.speed.per_second_suffix", localeOverride: localeOverride, defaultValue: "/с")
        )
    }

    private nonisolated func formatSimplifiedSpeed(_ bytesPerSecond: Int64) -> String {
        let kilobytesPerSecond = Double(bytesPerSecond) / 1_024
        guard kilobytesPerSecond >= 1 else {
            return "<1 \(L10n.string("unit.speed.kilobytes_per_second", localeOverride: localeOverride, defaultValue: "КБ/с"))"
        }

        if kilobytesPerSecond < 100 {
            return metricValue(
                max(10, steppedKilobytes(kilobytesPerSecond, step: 10)),
                unitKey: "unit.speed.kilobytes_per_second",
                fallback: "КБ/с"
            )
        }

        if kilobytesPerSecond < 500 {
            return metricValue(
                max(120, steppedKilobytes(kilobytesPerSecond, step: 20)),
                unitKey: "unit.speed.kilobytes_per_second",
                fallback: "КБ/с"
            )
        }

        if kilobytesPerSecond < 1_000 {
            return metricValue(
                max(550, steppedKilobytes(kilobytesPerSecond, step: 50)),
                unitKey: "unit.speed.kilobytes_per_second",
                fallback: "КБ/с"
            )
        }

        let megabytesPerSecond = Double(bytesPerSecond) / 1_048_576
        if megabytesPerSecond < 10 {
            return metricValue(
                max(1, Int(megabytesPerSecond.rounded(.down))),
                unitKey: "unit.speed.megabytes_per_second",
                fallback: "МБ/с"
            )
        }

        let wholeMegabytes = Int(megabytesPerSecond.rounded(.down))
        return metricValue(
            max(10, (wholeMegabytes / 2) * 2),
            unitKey: "unit.speed.megabytes_per_second",
            fallback: "МБ/с"
        )
    }

    private nonisolated func formatSimplifiedBytes(_ bytes: Int64, purpose: MetricsBytePurpose) -> String {
        switch purpose {
        case .uploaded:
            if bytes > 0 && bytes < 1_000 {
                return "<1 \(L10n.string("unit.kilobyte", localeOverride: localeOverride, defaultValue: "КБ"))"
            }

            return formatDecimalByteCount(bytes, maximumFractionDigits: 0)
        case .size:
            return formatDecimalByteCount(bytes, maximumFractionDigits: 0)
        case .general:
            return formatDecimalByteCount(bytes, maximumFractionDigits: 1)
        }
    }

    private nonisolated func formatSimplifiedETA(_ seconds: Int) -> String {
        if seconds < 60 {
            let visibleSeconds = seconds <= 10 ? seconds : max(10, (seconds / 5) * 5)
            return metricValue(visibleSeconds, unitKey: "unit.time.seconds", fallback: "сек")
        }

        if seconds < 600 {
            return metricValue(ceilDiv(seconds, by: 60), unitKey: "unit.time.minutes", fallback: "мин")
        }

        if seconds < 3_600 {
            let minutes = ceilDiv(seconds, by: 60)
            let visibleMinutes = min(55, max(10, (minutes / 5) * 5))
            return metricValue(visibleMinutes, unitKey: "unit.time.minutes", fallback: "мин")
        }

        return formatDetailedETA(seconds)
    }

    private nonisolated func formatDetailedETA(_ seconds: Int) -> String {
        if seconds < 60 {
            return metricValue(seconds, unitKey: "unit.time.seconds", fallback: "сек")
        }

        if seconds < 3_600 {
            return metricValue(ceilDiv(seconds, by: 60), unitKey: "unit.time.minutes", fallback: "мин")
        }

        if seconds < 86_400 {
            return metricValue(ceilDiv(seconds, by: 3_600), unitKey: "unit.time.hours", fallback: "ч")
        }

        let days = ceilDiv(seconds, by: 86_400)
        if days <= 6 {
            return metricValue(days, unitKey: "unit.time.days", fallback: "дн")
        }

        if days <= 10 {
            return metricValue(1, unitKey: "unit.time.weeks", fallback: "нед")
        }

        return ">1 \(L10n.string("unit.time.weeks", localeOverride: localeOverride, defaultValue: "нед"))"
    }

    private nonisolated func formatDecimalByteCount(_ bytes: Int64, maximumFractionDigits: Int) -> String {
        let units: [(threshold: Double, unit: String)] = [
            (1_000_000_000_000, L10n.string("unit.terabyte", localeOverride: localeOverride, defaultValue: "ТБ")),
            (1_000_000_000, L10n.string("unit.gigabyte", localeOverride: localeOverride, defaultValue: "ГБ")),
            (1_000_000, L10n.string("unit.megabyte", localeOverride: localeOverride, defaultValue: "МБ")),
            (1_000, L10n.string("unit.kilobyte", localeOverride: localeOverride, defaultValue: "КБ")),
        ]
        let value = Double(max(bytes, 0))

        guard let unit = units.first(where: { value >= $0.threshold }) else {
            return metricValue(bytes, unitKey: "unit.byte", fallback: "Б")
        }

        return "\(formatDecimal(value / unit.threshold, maximumFractionDigits: maximumFractionDigits)) \(unit.unit)"
    }

    private nonisolated func formatByteCount(
        _ bytes: Int64,
        allowedUnits: ByteCountFormatter.Units,
        suffix: String?
    ) -> String {
        let units = byteUnits(allowedUnits: allowedUnits)
        let value = Double(max(bytes, 0))
        let formattedValue: String

        if let unit = units.first(where: { value >= $0.threshold }) {
            formattedValue = "\(formatDecimal(value / unit.threshold, maximumFractionDigits: 1)) \(unit.unit)"
        } else {
            formattedValue = metricValue(bytes, unitKey: "unit.byte", fallback: "Б")
        }

        guard let suffix else { return formattedValue }
        return "\(formattedValue)\(suffix)"
    }

    private nonisolated func formatDecimal(_ value: Double, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.locale = L10n.locale(for: localeOverride)
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maximumFractionDigits)f", value)
    }

    private nonisolated func formatDecimal(_ value: Double, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.locale = L10n.locale(for: localeOverride)
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(fractionDigits)f", value)
    }

    private nonisolated func ceilDiv(_ value: Int, by divisor: Int) -> Int {
        (value + divisor - 1) / divisor
    }

    private nonisolated func steppedKilobytes(_ value: Double, step: Int) -> Int {
        (Int(value.rounded(.down)) / step) * step
    }

    private nonisolated func metricValue<T>(_ value: T, unitKey: String, fallback: String) -> String {
        "\(value) \(L10n.string(unitKey, localeOverride: localeOverride, defaultValue: fallback))"
    }

    private nonisolated func byteUnits(
        allowedUnits: ByteCountFormatter.Units
    ) -> [(threshold: Double, unit: String)] {
        [
            (1_000_000_000_000, "unit.terabyte", "ТБ", ByteCountFormatter.Units.useTB),
            (1_000_000_000, "unit.gigabyte", "ГБ", ByteCountFormatter.Units.useGB),
            (1_000_000, "unit.megabyte", "МБ", ByteCountFormatter.Units.useMB),
            (1_000, "unit.kilobyte", "КБ", ByteCountFormatter.Units.useKB),
        ].compactMap { threshold, key, fallback, unit in
            guard allowedUnits.contains(unit) else { return nil }
            return (
                threshold,
                L10n.string(key, localeOverride: localeOverride, defaultValue: fallback)
            )
        }
    }
}
