// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

final class UsageTelemetryTests: XCTestCase {
    func testISOWeekIdentifierUsesWeekYear() throws {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(secondsFromGMT: 0),
                    year: 2021,
                    month: 1,
                    day: 1
                )
            )
        )

        XCTAssertEqual(UsageTelemetryWeek.identifier(for: date, calendar: calendar), "2020-W53")
    }

    func testDisabledTelemetryDoesNotCreateStateOrPayload() throws {
        let bundle = try makeTelemetryBundle()
        let result = try bundle.coordinator.recordLaunchIfEnabled(
            isEnabled: false,
            localeIdentifier: "ru",
            appVersion: "1.0"
        )

        XCTAssertNil(result)
        XCTAssertNil(try bundle.store.loadState())
        XCTAssertNil(try bundle.store.readInspectablePayload())
    }

    func testRecordLaunchCreatesStateAndInspectablePayload() throws {
        let bundle = try makeTelemetryBundle()
        let payload = try bundle.coordinator.recordLaunchIfEnabled(
            isEnabled: true,
            localeIdentifier: "ru",
            appVersion: "1.0"
        )

        XCTAssertEqual(
            payload,
            UsageTelemetryPayload(
                installID: "fixed-install-id",
                week: "2026-W22",
                launchCount: 1,
                locale: "ru",
                appVersion: "1.0"
            )
        )
        XCTAssertEqual(try bundle.store.loadState()?.anonymousInstallID, "fixed-install-id")
        XCTAssertEqual(try bundle.store.loadState()?.launchCount, 1)
        XCTAssertEqual(try bundle.store.readInspectablePayload(), payload)
    }

    func testDeletedInspectablePayloadIsRecreatedWithoutChangingInstallID() throws {
        let bundle = try makeTelemetryBundle()
        _ = try bundle.coordinator.recordLaunchIfEnabled(
            isEnabled: true,
            localeIdentifier: "ru",
            appVersion: "1.0"
        )
        try bundle.store.deleteInspectablePayload()

        let payloadURL = try XCTUnwrap(
            try bundle.coordinator.ensureInspectablePayloadIfAvailable(
                isEnabled: true,
                localeIdentifier: "ru",
                appVersion: "1.0"
            )
        )

        XCTAssertEqual(payloadURL, bundle.store.payloadURL)
        let recreatedPayload = try XCTUnwrap(try bundle.store.readInspectablePayload())
        XCTAssertEqual(recreatedPayload.installID, "fixed-install-id")
        XCTAssertEqual(recreatedPayload.launchCount, 1)
    }

    func testOptOutDeletesActiveStateAndInspectablePayload() throws {
        let bundle = try makeTelemetryBundle()
        _ = try bundle.coordinator.setStatisticsEnabled(
            true,
            localeIdentifier: "ru",
            appVersion: "1.0"
        )

        _ = try bundle.coordinator.setStatisticsEnabled(
            false,
            localeIdentifier: "ru",
            appVersion: "1.0"
        )

        XCTAssertNil(try bundle.store.loadState())
        XCTAssertNil(try bundle.store.readInspectablePayload())
    }

    func testNewWeekKeepsInstallIDAndResetsLaunchCount() throws {
        var currentDate = try date(year: 2026, month: 5, day: 29)
        let bundle = try makeTelemetryBundle(now: { currentDate })

        _ = try bundle.coordinator.recordLaunchIfEnabled(
            isEnabled: true,
            localeIdentifier: "ru",
            appVersion: "1.0"
        )
        _ = try bundle.coordinator.recordLaunchIfEnabled(
            isEnabled: true,
            localeIdentifier: "ru",
            appVersion: "1.0"
        )

        currentDate = try date(year: 2026, month: 6, day: 8)
        let nextWeekPayload = try bundle.coordinator.recordLaunchIfEnabled(
            isEnabled: true,
            localeIdentifier: "ru",
            appVersion: "1.0"
        )

        XCTAssertEqual(nextWeekPayload?.installID, "fixed-install-id")
        XCTAssertEqual(nextWeekPayload?.week, "2026-W24")
        XCTAssertEqual(nextWeekPayload?.launchCount, 1)
    }

    func testCurrentWeekPayloadRollsOverWithoutCountingALaunch() throws {
        var currentDate = try date(year: 2026, month: 6, day: 3)
        let bundle = try makeTelemetryBundle(now: { currentDate })
        for _ in 0..<2 {
            _ = try bundle.coordinator.recordLaunchIfEnabled(
                isEnabled: true,
                localeIdentifier: "ru",
                appVersion: "1.0"
            )
        }

        let sameWeekPayload = try bundle.coordinator.currentWeekPayloadIfEnabled(
            isEnabled: true,
            localeIdentifier: "ru",
            appVersion: "1.0"
        )
        XCTAssertEqual(sameWeekPayload?.week, "2026-W23")
        XCTAssertEqual(sameWeekPayload?.launchCount, 2)
        XCTAssertEqual(try bundle.store.loadState()?.launchCount, 2)

        currentDate = try date(year: 2026, month: 6, day: 10)
        let nextWeekPayload = try bundle.coordinator.currentWeekPayloadIfEnabled(
            isEnabled: true,
            localeIdentifier: "ru",
            appVersion: "1.0"
        )
        XCTAssertEqual(
            nextWeekPayload,
            UsageTelemetryPayload(
                installID: "fixed-install-id",
                week: "2026-W24",
                launchCount: 0,
                locale: "ru",
                appVersion: "1.0"
            )
        )
        XCTAssertEqual(try bundle.store.readInspectablePayload(), nextWeekPayload)

        let launchPayload = try bundle.coordinator.recordLaunchIfEnabled(
            isEnabled: true,
            localeIdentifier: "ru",
            appVersion: "1.0"
        )
        XCTAssertEqual(launchPayload?.week, "2026-W24")
        XCTAssertEqual(launchPayload?.launchCount, 1)
    }

    func testCurrentWeekPayloadIsNilWhenTelemetryIsDisabled() throws {
        let bundle = try makeTelemetryBundle()

        let payload = try bundle.coordinator.currentWeekPayloadIfEnabled(
            isEnabled: false,
            localeIdentifier: "ru",
            appVersion: "1.0"
        )

        XCTAssertNil(payload)
        XCTAssertNil(try bundle.store.loadState())
    }

    func testSendStatusKeepsLastSentDateWhenTelemetryIsDisabled() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try date(year: 2026, month: 5, day: 29)
        let lastSentAt = try date(year: 2026, month: 5, day: 26)

        let status = UsageTelemetrySendStatusFormatter.status(
            lastSentAt: lastSentAt,
            isEnabled: false,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(status, .sentEarlier(daysAgo: 3, date: lastSentAt, isEnabled: false))
    }

    func testRequestBuilderCreatesPostJSONRequest() throws {
        let payload = UsageTelemetryPayload(
            installID: "fixed-install-id",
            week: "2026-W22",
            launchCount: 3,
            locale: "ru",
            appVersion: "1.0"
        )
        let endpointURL = try XCTUnwrap(URL(string: "https://example.com/launch"))

        let request = try UsageTelemetryRequestBuilder.request(
            payload: payload,
            endpointURL: endpointURL
        )

        XCTAssertEqual(request.url, endpointURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        XCTAssertEqual(
            try JSONDecoder().decode(UsageTelemetryPayload.self, from: try XCTUnwrap(request.httpBody)),
            payload
        )
    }

    @MainActor
    func testAppStoreRecordsAndSendsTelemetryOnLaunchWhenEnabled() async throws {
        let bundle = try makeTelemetryBundle()
        let sender = SpyUsageTelemetrySender()
        var preferences = AppPreferences.defaultValue
        preferences.sendsAnonymousUsageStatistics = true
        preferences.hasAnsweredUsageStatisticsOnboarding = true

        let storeBundle = makeTestStoreBundle(
            engine: FakeTorrentEngine(),
            preferences: preferences,
            usageTelemetryCoordinator: bundle.coordinator,
            usageTelemetrySender: sender
        )

        var didSend = false
        for _ in 0..<100 {
            if await sender.sentPayloadCount == 1,
               storeBundle.store.preferences.lastUsageStatisticsSentAt != nil {
                didSend = true
                break
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(didSend)
        let sentPayload = await sender.sentPayloads.first
        XCTAssertEqual(sentPayload?.installID, "fixed-install-id")
        XCTAssertEqual(sentPayload?.launchCount, 1)
    }

    /// One report per week: a later launch in the same week is counted
    /// locally but not sent.
    @MainActor
    func testSecondLaunchInSameWeekIsCountedButNotSent() async throws {
        let bundle = try makeTelemetryBundle()
        let sender = SpyUsageTelemetrySender()
        var preferences = AppPreferences.defaultValue
        preferences.sendsAnonymousUsageStatistics = true
        preferences.hasAnsweredUsageStatisticsOnboarding = true

        let firstLaunch = makeTestStoreBundle(
            engine: FakeTorrentEngine(),
            preferences: preferences,
            usageTelemetryCoordinator: bundle.coordinator,
            usageTelemetrySender: sender
        )
        let didSendFirst = await waitForCondition {
            firstLaunch.store.preferences.lastUsageStatisticsSentAt != nil
        }
        XCTAssertTrue(didSendFirst)

        let secondLaunch = makeTestStoreBundle(
            engine: FakeTorrentEngine(),
            preferences: firstLaunch.store.preferences,
            usageTelemetryCoordinator: bundle.coordinator,
            usageTelemetrySender: sender
        )
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(secondLaunch.store.preferences.lastUsageStatisticsSentAt)

        let sentPayloads = await sender.sentPayloads
        XCTAssertEqual(sentPayloads.map(\.launchCount), [1])
        XCTAssertEqual(try bundle.store.loadState()?.launchCount, 2)
    }

    /// Shatl that keeps running into a new week reports that week without a
    /// launch, once, with the same install ID.
    @MainActor
    func testRunningAppStoreReportsNewWeekOnceWithoutLaunch() async throws {
        let clock = TelemetryTestClock(date: try date(year: 2026, month: 6, day: 3))
        let bundle = try makeTelemetryBundle(now: { clock.date })
        let sender = SpyUsageTelemetrySender()
        var preferences = AppPreferences.defaultValue
        preferences.sendsAnonymousUsageStatistics = true
        preferences.hasAnsweredUsageStatisticsOnboarding = true

        let storeBundle = makeTestStoreBundle(
            engine: FakeTorrentEngine(),
            preferences: preferences,
            usageTelemetryCoordinator: bundle.coordinator,
            usageTelemetrySender: sender,
            usageTelemetryWeekCheckInterval: .milliseconds(50)
        )
        let didSendLaunch = await waitForAsyncCondition {
            await sender.sentPayloadCount == 1
        }
        XCTAssertTrue(didSendLaunch)

        // Checks within the same week send nothing more.
        try await Task.sleep(for: .milliseconds(300))
        let sameWeekCount = await sender.sentPayloadCount
        XCTAssertEqual(sameWeekCount, 1)

        clock.date = try date(year: 2026, month: 6, day: 10)
        let didSendNewWeek = await waitForAsyncCondition {
            await sender.sentPayloadCount == 2
        }
        XCTAssertTrue(didSendNewWeek)
        try await Task.sleep(for: .milliseconds(300))

        let sentPayloads = await sender.sentPayloads
        XCTAssertEqual(sentPayloads.map(\.week), ["2026-W23", "2026-W24"])
        XCTAssertEqual(sentPayloads.map(\.launchCount), [1, 0])
        XCTAssertEqual(Set(sentPayloads.map(\.installID)), ["fixed-install-id"])
        let lastSentAt = try XCTUnwrap(storeBundle.store.preferences.lastUsageStatisticsSentAt)
        XCTAssertEqual(bundle.coordinator.weekIdentifier(for: lastSentAt), "2026-W24")
    }

    @MainActor
    func testRunningAppStoreDoesNotReportNewWeekWhenStatisticsAreOff() async throws {
        let clock = TelemetryTestClock(date: try date(year: 2026, month: 6, day: 3))
        let bundle = try makeTelemetryBundle(now: { clock.date })
        let sender = SpyUsageTelemetrySender()
        var preferences = AppPreferences.defaultValue
        preferences.sendsAnonymousUsageStatistics = false
        preferences.hasAnsweredUsageStatisticsOnboarding = true

        let storeBundle = makeTestStoreBundle(
            engine: FakeTorrentEngine(),
            preferences: preferences,
            usageTelemetryCoordinator: bundle.coordinator,
            usageTelemetrySender: sender,
            usageTelemetryWeekCheckInterval: .milliseconds(50)
        )
        clock.date = try date(year: 2026, month: 6, day: 10)
        try await Task.sleep(for: .milliseconds(300))

        // Using the store after the wait keeps it running through the checks.
        XCTAssertFalse(storeBundle.store.preferences.canSendAnonymousUsageStatistics)
        let sentPayloadCount = await sender.sentPayloadCount
        XCTAssertEqual(sentPayloadCount, 0)
        XCTAssertNil(try bundle.store.loadState())
    }

    @MainActor
    func testAppStoreDoesNotRecordTelemetryBeforeOnboardingAnswer() async throws {
        let bundle = try makeTelemetryBundle()
        let sender = SpyUsageTelemetrySender()
        var preferences = AppPreferences.defaultValue
        preferences.sendsAnonymousUsageStatistics = true

        _ = makeTestStoreBundle(
            engine: FakeTorrentEngine(),
            preferences: preferences,
            usageTelemetryCoordinator: bundle.coordinator,
            usageTelemetrySender: sender
        )

        XCTAssertEqual(bundle.store.payloadURL.lastPathComponent, "weekly-launch-payload.json")
        let sentPayloadCount = await sender.sentPayloadCount
        XCTAssertEqual(sentPayloadCount, 0)
        XCTAssertNil(try bundle.store.loadState())
        XCTAssertNil(try bundle.store.readInspectablePayload())
    }

    @MainActor
    func testAnswerUsageStatisticsOnboardingOptsInAndSends() async throws {
        let bundle = try makeTelemetryBundle()
        let sender = SpyUsageTelemetrySender()
        let storeBundle = makeTestStoreBundle(
            engine: FakeTorrentEngine(),
            usageTelemetryCoordinator: bundle.coordinator,
            usageTelemetrySender: sender
        )

        storeBundle.store.answerUsageStatisticsOnboarding(allowStatistics: true)

        var didSend = false
        for _ in 0..<100 {
            if await sender.sentPayloadCount == 1,
               storeBundle.store.preferences.lastUsageStatisticsSentAt != nil {
                didSend = true
                break
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(didSend)
        XCTAssertTrue(storeBundle.store.preferences.sendsAnonymousUsageStatistics)
        XCTAssertTrue(storeBundle.store.preferences.hasAnsweredUsageStatisticsOnboarding)
        XCTAssertEqual(try bundle.store.loadState()?.anonymousInstallID, "fixed-install-id")
    }

    @MainActor
    func testAnswerUsageStatisticsOnboardingDeclinesWithoutCreatingTelemetryState() async throws {
        let bundle = try makeTelemetryBundle()
        let sender = SpyUsageTelemetrySender()
        let storeBundle = makeTestStoreBundle(
            engine: FakeTorrentEngine(),
            usageTelemetryCoordinator: bundle.coordinator,
            usageTelemetrySender: sender
        )

        storeBundle.store.answerUsageStatisticsOnboarding(allowStatistics: false)

        XCTAssertFalse(storeBundle.store.preferences.sendsAnonymousUsageStatistics)
        XCTAssertTrue(storeBundle.store.preferences.hasAnsweredUsageStatisticsOnboarding)
        let sentPayloadCount = await sender.sentPayloadCount
        XCTAssertEqual(sentPayloadCount, 0)
        XCTAssertNil(try bundle.store.loadState())
        XCTAssertNil(try bundle.store.readInspectablePayload())
    }

    private func makeTelemetryBundle(
        now: @escaping () -> Date = {
            try! date(year: 2026, month: 5, day: 29)
        }
    ) throws -> (store: UsageTelemetryStore, coordinator: UsageTelemetryLocalCoordinator) {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageTelemetryTests-\(UUID().uuidString)", isDirectory: true)
        let directories = ShatlDirectories(applicationSupportURL: baseURL, cachesURL: nil)
        let store = UsageTelemetryStore(directories: directories)
        let coordinator = UsageTelemetryLocalCoordinator(
            store: store,
            makeInstallID: { "fixed-install-id" },
            now: now,
            calendar: isoCalendar
        )
        return (store, coordinator)
    }

    private static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var isoCalendar: Calendar {
        Self.isoCalendar
    }
}

private actor SpyUsageTelemetrySender: UsageTelemetrySending {
    private var payloads: [UsageTelemetryPayload] = []

    var sentPayloads: [UsageTelemetryPayload] {
        payloads
    }

    var sentPayloadCount: Int {
        payloads.count
    }

    func send(_ payload: UsageTelemetryPayload) async throws {
        payloads.append(payload)
    }
}

/// A clock the test moves forward while the store keeps running.
private final class TelemetryTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var currentDate: Date

    init(date: Date) {
        currentDate = date
    }

    var date: Date {
        get { lock.withLock { currentDate } }
        set { lock.withLock { currentDate = newValue } }
    }
}

private func date(year: Int, month: Int, day: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return try XCTUnwrap(
        calendar.date(
            from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: year,
                month: month,
                day: day
            )
        )
    )
}
