// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// Port forwarding asks the user's router to open a port. No test turns it on
/// in a running session: that would open ports on the router of whoever runs
/// the tests.
final class PortForwardingTests: XCTestCase {
    /// `default_settings()` behind the Orbit profile turns UPnP on, and the
    /// other profiles leave it out: every profile switch must carry the
    /// preference, or it would silently open or close the port.
    func testEveryProfileKeepsPortForwardingAsThePreferenceSays() {
        let profiles: [LTPerformanceProfile] = [.economical, .balanced, .maximum]
        for profile in profiles {
            XCTAssertFalse(
                LibtorrentSessionBridge.sessionSettingsForwardPort(for: profile, portForwarding: false),
                "Profile \(profile.rawValue) opens the router port although the switch is off"
            )
            XCTAssertTrue(
                LibtorrentSessionBridge.sessionSettingsForwardPort(for: profile, portForwarding: true),
                "Profile \(profile.rawValue) drops port forwarding although the switch is on"
            )
        }
    }

    /// The engine gets the preference with its settings before it boots.
    func testEngineReportsPortForwardingAsTheSettingsSay() async throws {
        let fixture = try EngineFixture.make(named: "PortForwarding")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories)

        let initialStatus = await engine.portMappingStatus()
        XCTAssertEqual(initialStatus, .off)

        try await engine.applyPerformanceSettings(EnginePerformanceSettings(mode: .balanced, opensRouterPort: true))
        let enabledStatus = await engine.portMappingStatus()
        XCTAssertEqual(enabledStatus, .searching)

        try await engine.applyPerformanceSettings(EnginePerformanceSettings(mode: .maximum, opensRouterPort: false))
        let disabledStatus = await engine.portMappingStatus()
        XCTAssertEqual(disabledStatus, .off)
    }
}
