// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated struct UsageTelemetryPayload: Codable, Equatable, Sendable {
    var installID: String
    var week: String
    /// Launches in `week` up to the moment the report was built. One report is
    /// sent per ISO week, at the first launch or when Shatl keeps running into
    /// a new week, so the value is usually 1 and can be 0. The report itself
    /// marks the install as active in that week.
    var launchCount: Int
    var locale: String
    var appVersion: String

    private enum CodingKeys: String, CodingKey {
        case installID = "install_id"
        case week
        case launchCount = "launch_count"
        case locale
        case appVersion = "app_version"
    }
}

nonisolated struct UsageTelemetryState: Codable, Equatable, Sendable {
    var anonymousInstallID: String
    var currentWeek: String
    var launchCount: Int
    var lastPayloadGeneratedAt: Date?

    init(
        anonymousInstallID: String,
        currentWeek: String,
        launchCount: Int,
        lastPayloadGeneratedAt: Date? = nil
    ) {
        self.anonymousInstallID = anonymousInstallID
        self.currentWeek = currentWeek
        self.launchCount = launchCount
        self.lastPayloadGeneratedAt = lastPayloadGeneratedAt
    }
}

nonisolated enum UsageTelemetryWeek {
    static func identifier(for date: Date, calendar inputCalendar: Calendar = Calendar(identifier: .iso8601)) -> String {
        var calendar = inputCalendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4

        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? components.year ?? 1970
        let week = components.weekOfYear ?? 1
        return String(format: "%04d-W%02d", year, week)
    }
}

nonisolated enum UsageTelemetryPayloadBuilder {
    static func payload(
        from state: UsageTelemetryState,
        localeIdentifier: String,
        appVersion: String
    ) -> UsageTelemetryPayload {
        UsageTelemetryPayload(
            installID: state.anonymousInstallID,
            week: state.currentWeek,
            launchCount: state.launchCount,
            locale: localeIdentifier,
            appVersion: appVersion
        )
    }
}

nonisolated enum UsageTelemetrySendStatus: Equatable {
    case neverSent(isEnabled: Bool)
    case sentToday(isEnabled: Bool)
    case sentYesterday(isEnabled: Bool)
    case sentTwoDaysAgo(isEnabled: Bool)
    /// `showsYear` when the report went in another calendar year, so the
    /// date in brackets names it.
    case sentEarlier(age: UsageTelemetryReportAge, date: Date, showsYear: Bool, isEnabled: Bool)
}

/// How long ago the last report went, from three days on, in the largest
/// whole unit, always rounded down: days up to a week, then weeks up to a
/// month, months (with half a year as its own step) up to a year, years
/// (with a year and a half as its own step). Months count by the calendar.
nonisolated enum UsageTelemetryReportAge: Equatable {
    /// 3 to 6.
    case days(Int)
    /// 1 to 3.
    case weeks(Int)
    /// 1 to 5 and 7 to 11.
    case months(Int)
    case halfYear
    /// 1, then 2 and on.
    case years(Int)
    case yearAndHalf

    static func age(sentAt: Date, now: Date, calendar: Calendar) -> UsageTelemetryReportAge {
        let start = calendar.startOfDay(for: sentAt)
        let end = calendar.startOfDay(for: now)
        let parts = calendar.dateComponents([.year, .month], from: start, to: end)
        let months = max(0, (parts.year ?? 0) * 12 + (parts.month ?? 0))

        switch months {
        case 0:
            let days = max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
            return days < 7 ? .days(days) : .weeks(min(3, days / 7))
        case 6:
            return .halfYear
        case 1..<12:
            return .months(months)
        case 18..<24:
            return .yearAndHalf
        default:
            return .years(months / 12)
        }
    }
}

nonisolated enum UsageTelemetrySendStatusFormatter {
    static func status(
        lastSentAt: Date?,
        isEnabled: Bool,
        now: Date = Date(),
        calendar inputCalendar: Calendar = .current
    ) -> UsageTelemetrySendStatus {
        guard let lastSentAt else {
            return .neverSent(isEnabled: isEnabled)
        }

        let calendar = inputCalendar
        let startOfNow = calendar.startOfDay(for: now)
        let startOfSentDate = calendar.startOfDay(for: lastSentAt)
        let daysAgo = calendar.dateComponents([.day], from: startOfSentDate, to: startOfNow).day ?? 0

        switch daysAgo {
        case ..<1:
            return .sentToday(isEnabled: isEnabled)
        case 1:
            return .sentYesterday(isEnabled: isEnabled)
        case 2:
            return .sentTwoDaysAgo(isEnabled: isEnabled)
        default:
            return .sentEarlier(
                age: UsageTelemetryReportAge.age(sentAt: lastSentAt, now: now, calendar: calendar),
                date: lastSentAt,
                showsYear: calendar.component(.year, from: lastSentAt) != calendar.component(.year, from: now),
                isEnabled: isEnabled
            )
        }
    }
}
