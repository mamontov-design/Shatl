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

    /// Grey right after the switch turns on, green once the router opens the
    /// port. A refusal alone keeps it grey, since the other way may still open
    /// the port; red only after ten seconds without an opened port.
    func testIndicatorFollowsTheSwitchAndTheRouterAnswer() {
        let refusal = EnginePortMappingError(transport: "NAT-PMP", reason: "refused")
        let mapped = EnginePortMappingStatus.mapped(externalPort: 6881, transport: "UPnP")

        XCTAssertEqual(PortForwardingIndicator(isEnabled: false, status: mapped), .hidden)
        XCTAssertEqual(PortForwardingIndicator(isEnabled: false, status: nil), .hidden)

        XCTAssertEqual(PortForwardingIndicator(isEnabled: true, status: nil), .checking)
        XCTAssertEqual(PortForwardingIndicator(isEnabled: true, status: .off), .checking)
        XCTAssertEqual(PortForwardingIndicator(isEnabled: true, status: .searching(waiting: nil, lastError: nil)), .checking)
        XCTAssertEqual(
            PortForwardingIndicator(isEnabled: true, status: .searching(waiting: .milliseconds(9_900), lastError: refusal)),
            .checking
        )
        XCTAssertEqual(
            PortForwardingIndicator(isEnabled: true, status: .searching(waiting: .seconds(10), lastError: nil)),
            .closed
        )
        XCTAssertEqual(PortForwardingIndicator(isEnabled: true, status: mapped), .open)
    }

    /// A move counts once the registry stands still: another router (even
    /// one with the same address), another address, a cable plugged in, or
    /// the connection lost or found. The first answer is the baseline at
    /// launch, and the same network again is no move.
    func testNetworkMoveIsAnotherRouterAddressOrConnection() {
        let home = wifi(address: "192.168.1.91", router: "IPv4.Router=192.168.1.1;IPv4.RouterHardwareAddress=50:ff:20:ac:72:d4")
        var filter = PhysicalNetworkChangeFilter()

        XCTAssertFalse(filter.settle(PhysicalNetwork(serviceRecords: [home])))
        XCTAssertFalse(filter.settle(PhysicalNetwork(serviceRecords: [home])))

        let office = wifi(address: "192.168.1.91", router: "IPv4.Router=192.168.1.1;IPv4.RouterHardwareAddress=a4:2b:b0:01:02:03")
        XCTAssertTrue(filter.settle(PhysicalNetwork(serviceRecords: [office])), "Same router address, another router")

        let cable: [String: Any] = ["InterfaceName": "en5", "Addresses": ["10.0.0.7"], "Router": "10.0.0.1"]
        XCTAssertTrue(filter.settle(PhysicalNetwork(serviceRecords: [office, cable])))

        XCTAssertTrue(filter.settle(PhysicalNetwork(serviceRecords: [])), "The connection is lost")
        XCTAssertTrue(filter.settle(PhysicalNetwork(serviceRecords: [home])), "And found")
    }

    /// A VPN is a tunnel interface of its own: on or off, the network stays.
    func testVPNIsNoNetworkMove() {
        let home = wifi(address: "192.168.1.91", router: "IPv4.Router=192.168.1.1;IPv4.RouterHardwareAddress=50:ff:20:ac:72:d4")
        let vpn: [String: Any] = ["InterfaceName": "utun9", "Addresses": ["10.8.1.3"]]
        var filter = PhysicalNetworkChangeFilter()

        XCTAssertFalse(filter.settle(PhysicalNetwork(serviceRecords: [home])))
        XCTAssertFalse(filter.settle(PhysicalNetwork(serviceRecords: [home, vpn])))
        XCTAssertFalse(filter.settle(PhysicalNetwork(serviceRecords: [vpn, home])))
        XCTAssertFalse(filter.settle(PhysicalNetwork(serviceRecords: [home])))
    }

    /// The app runs in the sandbox, and so do these tests: the registry must
    /// be readable from it, or no move would ever be noticed.
    func testNetworkRegistryIsReadableInTheSandbox() {
        XCTAssertNotNil(PhysicalNetworkMonitor.readCurrentNetwork())
    }

    /// Another network turns the dot grey and asks the router again, as a
    /// laptop carried from home to the office would need.
    @MainActor
    func testNetworkMoveAsksTheRouterAgainWhilePortForwardingIsOn() async {
        let engine = FakeTorrentEngine()
        let monitor = FakePhysicalNetworkMonitor()
        var preferences = AppPreferences.defaultValue
        preferences.opensRouterPortAutomatically = true
        let bundle = makeTestStoreBundle(engine: engine, preferences: preferences, physicalNetworkMonitor: monitor)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }
        let store = bundle.store

        XCTAssertEqual(monitor.startCount, 0, "The monitor starts once the downloads are restored")
        store.bootstrapRuntimeState()
        let didStart = await waitForCondition { monitor.startCount == 1 }
        XCTAssertTrue(didStart)

        await engine.setPortMappingStatus(.mapped(externalPort: 6881, transport: "UPnP"))
        await store.refreshPortForwardingIndicator()
        XCTAssertEqual(store.portForwardingIndicator, .open)

        monitor.simulateNetworkChange()
        let didAskAgain = await waitForAsyncCondition {
            await engine.restartPortMappingCheckCount() == 1
        }
        XCTAssertTrue(didAskAgain)
        let didTurnGrey = await waitForCondition { store.portForwardingIndicator == .checking }
        XCTAssertTrue(didTurnGrey)
    }

    @MainActor
    func testNetworkMoveDoesNothingWhilePortForwardingIsOff() async throws {
        let engine = FakeTorrentEngine()
        let monitor = FakePhysicalNetworkMonitor()
        var preferences = AppPreferences.defaultValue
        preferences.opensRouterPortAutomatically = false
        let bundle = makeTestStoreBundle(engine: engine, preferences: preferences, physicalNetworkMonitor: monitor)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        bundle.store.bootstrapRuntimeState()
        _ = await waitForCondition { monitor.startCount == 1 }
        monitor.simulateNetworkChange()
        try await Task.sleep(for: .milliseconds(200))

        let restartCount = await engine.restartPortMappingCheckCount()
        XCTAssertEqual(restartCount, 0)
        XCTAssertEqual(bundle.store.portForwardingIndicator, .hidden)
    }

    /// Without a session there is no router to ask: before boot, and while
    /// the switch is off, asking again changes nothing.
    func testAskingAgainWithoutASessionChangesNothing() async throws {
        let fixture = try EngineFixture.make(named: "PortForwardingRestart")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories)

        await engine.restartPortMappingCheck()
        let offStatus = await engine.portMappingStatus()
        XCTAssertEqual(offStatus, .off)

        try await engine.applyPerformanceSettings(EnginePerformanceSettings(mode: .balanced, opensRouterPort: true))
        await engine.restartPortMappingCheck()
        let unbootedStatus = await engine.portMappingStatus()
        XCTAssertEqual(unbootedStatus, .searching(waiting: nil, lastError: nil))
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
        // Before boot nobody has asked the router yet, so no wait is counted.
        XCTAssertEqual(enabledStatus, .searching(waiting: nil, lastError: nil))

        try await engine.applyPerformanceSettings(EnginePerformanceSettings(mode: .maximum, opensRouterPort: false))
        let disabledStatus = await engine.portMappingStatus()
        XCTAssertEqual(disabledStatus, .off)
    }

    private func wifi(address: String, router: String) -> [String: Any] {
        ["InterfaceName": "en1", "Addresses": [address], "NetworkSignature": router]
    }
}
