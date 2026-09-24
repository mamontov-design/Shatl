// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

final class UsageTelemetryStore: @unchecked Sendable {
    let payloadURL: URL

    private let stateURL: URL
    private let telemetryDirectoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directories: ShatlDirectories = ShatlDirectories(),
        fileManager: FileManager = .default
    ) {
        self.stateURL = directories.usageTelemetryStateURL
        self.payloadURL = directories.usageTelemetryPayloadURL
        self.telemetryDirectoryURL = directories.telemetryDirectoryURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func loadState() throws -> UsageTelemetryState? {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: stateURL)
        return try decoder.decode(UsageTelemetryState.self, from: data)
    }

    func saveState(_ state: UsageTelemetryState) throws {
        try ensureTelemetryDirectory()
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: [.atomic])
    }

    func deleteState() throws {
        try removeFileIfExists(at: stateURL)
    }

    func writeInspectablePayload(_ payload: UsageTelemetryPayload) throws {
        try ensureTelemetryDirectory()
        let data = try encoder.encode(payload)
        try data.write(to: payloadURL, options: [.atomic])
    }

    func readInspectablePayload() throws -> UsageTelemetryPayload? {
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: payloadURL)
        return try decoder.decode(UsageTelemetryPayload.self, from: data)
    }

    func deleteInspectablePayload() throws {
        try removeFileIfExists(at: payloadURL)
    }

    func deleteActiveState() throws {
        try deleteState()
        try deleteInspectablePayload()
    }

    private func ensureTelemetryDirectory() throws {
        try fileManager.createDirectory(at: telemetryDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }

    private func removeFileIfExists(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }
}

final class UsageTelemetryLocalCoordinator: @unchecked Sendable {
    private let store: UsageTelemetryStore
    private let makeInstallID: () -> String
    private let now: () -> Date
    private let calendar: Calendar

    init(
        store: UsageTelemetryStore,
        makeInstallID: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) {
        self.store = store
        self.makeInstallID = makeInstallID
        self.now = now
        self.calendar = calendar
    }

    var payloadURL: URL {
        store.payloadURL
    }

    /// The telemetry clock. The store dates sends with it, so the week of the
    /// last send and the week of a report always come from the same clock.
    var currentDate: Date {
        now()
    }

    func weekIdentifier(for date: Date) -> String {
        UsageTelemetryWeek.identifier(for: date, calendar: calendar)
    }

    func setStatisticsEnabled(
        _ isEnabled: Bool,
        localeIdentifier: String,
        appVersion: String
    ) throws -> UsageTelemetryPayload? {
        if isEnabled {
            return try recordLaunchIfEnabled(
                isEnabled: true,
                localeIdentifier: localeIdentifier,
                appVersion: appVersion
            )
        }

        try store.deleteActiveState()
        return nil
    }

    func recordLaunchIfEnabled(
        isEnabled: Bool,
        localeIdentifier: String,
        appVersion: String
    ) throws -> UsageTelemetryPayload? {
        guard isEnabled else {
            return nil
        }

        let currentDate = now()
        var state = try activeState(for: currentDate)
        state.launchCount += 1
        state.lastPayloadGeneratedAt = currentDate
        try store.saveState(state)

        let payload = UsageTelemetryPayloadBuilder.payload(
            from: state,
            localeIdentifier: localeIdentifier,
            appVersion: appVersion
        )
        try store.writeInspectablePayload(payload)
        return payload
    }

    /// Builds the report of the current week without counting a launch, for a
    /// Shatl that keeps running into a new week. A new week resets the launch
    /// count, so such a report can carry 0 launches. Within the same week the
    /// state is only read.
    func currentWeekPayloadIfEnabled(
        isEnabled: Bool,
        localeIdentifier: String,
        appVersion: String
    ) throws -> UsageTelemetryPayload? {
        guard isEnabled else {
            return nil
        }

        let currentDate = now()
        let storedState = try store.loadState()
        if let storedState, storedState.currentWeek == weekIdentifier(for: currentDate) {
            return UsageTelemetryPayloadBuilder.payload(
                from: storedState,
                localeIdentifier: localeIdentifier,
                appVersion: appVersion
            )
        }

        var state = activeState(from: storedState, for: currentDate)
        state.lastPayloadGeneratedAt = currentDate
        try store.saveState(state)

        let payload = UsageTelemetryPayloadBuilder.payload(
            from: state,
            localeIdentifier: localeIdentifier,
            appVersion: appVersion
        )
        try store.writeInspectablePayload(payload)
        return payload
    }

    func ensureInspectablePayloadIfAvailable(
        isEnabled: Bool,
        localeIdentifier: String,
        appVersion: String
    ) throws -> URL? {
        guard isEnabled, var state = try store.loadState() else {
            return nil
        }

        let currentDate = now()
        state.lastPayloadGeneratedAt = currentDate
        try store.saveState(state)

        let payload = UsageTelemetryPayloadBuilder.payload(
            from: state,
            localeIdentifier: localeIdentifier,
            appVersion: appVersion
        )
        try store.writeInspectablePayload(payload)
        return store.payloadURL
    }

    private func activeState(for date: Date) throws -> UsageTelemetryState {
        activeState(from: try store.loadState(), for: date)
    }

    private func activeState(from storedState: UsageTelemetryState?, for date: Date) -> UsageTelemetryState {
        let currentWeek = weekIdentifier(for: date)

        guard var state = storedState else {
            return UsageTelemetryState(
                anonymousInstallID: makeInstallID(),
                currentWeek: currentWeek,
                launchCount: 0
            )
        }

        if state.currentWeek != currentWeek {
            state.currentWeek = currentWeek
            state.launchCount = 0
        }

        return state
    }
}
