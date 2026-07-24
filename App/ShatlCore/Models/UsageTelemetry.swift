import Foundation

nonisolated struct UsageTelemetryPayload: Codable, Equatable, Sendable {
    var installID: String
    var week: String
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
    case sentEarlier(daysAgo: Int, date: Date, isEnabled: Bool)
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
            return .sentEarlier(daysAgo: daysAgo, date: lastSentAt, isEnabled: isEnabled)
        }
    }
}
