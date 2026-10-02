// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import SystemConfiguration

/// One of the Mac's own ways to a router: Wi-Fi or a cable.
nonisolated struct PhysicalNetworkConnection: Equatable, Sendable {
    var interface: String
    /// The Mac's addresses on it, sorted.
    var addresses: [String]
    /// The router's address and hardware address: two networks whose
    /// routers share 192.168.1.1 still differ.
    var routerSignature: String
}

/// The Mac's physical connections, never a VPN tunnel.
nonisolated struct PhysicalNetwork: Equatable, Sendable {
    /// Sorted by interface.
    var connections: [PhysicalNetworkConnection]

    init(connections: [PhysicalNetworkConnection]) {
        self.connections = connections.sorted { $0.interface < $1.interface }
    }

    /// From the IPv4 records of the system's network services. A VPN is a
    /// tunnel interface of its own and is left out, so turning it on or off
    /// changes nothing here.
    init(serviceRecords: [[String: Any]]) {
        self.init(connections: serviceRecords.compactMap { record in
            guard let interface = record["InterfaceName"] as? String,
                  !Self.isTunnel(interface) else { return nil }
            return PhysicalNetworkConnection(
                interface: interface,
                addresses: ((record["Addresses"] as? [String]) ?? []).sorted(),
                routerSignature: (record["NetworkSignature"] as? String)
                    ?? (record["Router"] as? String)
                    ?? ""
            )
        })
    }

    private static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "gif", "stf", "lo"]

    private static func isTunnel(_ interface: String) -> Bool {
        tunnelPrefixes.contains { interface.hasPrefix($0) }
    }
}

/// Tells when the Mac moved to another network: the router that opened a
/// port may not be the one the Mac talks to now.
nonisolated protocol PhysicalNetworkMonitoring: AnyObject, Sendable {
    /// `onChange` runs on the monitor's own queue.
    func start(onChange: @escaping @Sendable () -> Void)
    func stop()
}

/// The network as it stands after a quiet pause, against the last one that
/// stood. The first answer only sets the baseline: the app just started.
nonisolated struct PhysicalNetworkChangeFilter {
    private(set) var settled: PhysicalNetwork?

    /// True when the network moved: another network or router, or the Mac
    /// lost or found a connection.
    mutating func settle(_ network: PhysicalNetwork) -> Bool {
        defer { settled = network }
        guard let settled else { return false }
        return settled != network
    }
}

/// Watches the system's network registry, the one `scutil` shows: it keeps
/// each physical connection with its own address and router even while a
/// VPN takes all traffic, when the network path reports Wi-Fi as
/// unavailable. macOS sends several updates while a network changes, so a
/// change counts once the registry has been still for `settlePause`.
nonisolated final class PhysicalNetworkMonitor: PhysicalNetworkMonitoring, @unchecked Sendable {
    static let settlePause: DispatchTimeInterval = .seconds(2)
    private static let serviceKeyPattern = "State:/Network/Service/[^/]+/IPv4"

    private let queue = DispatchQueue(label: "Shatl.PhysicalNetworkMonitor")
    // Touched only on `queue`, which is what makes the class Sendable.
    private var store: SCDynamicStore?
    private var onChange: (@Sendable () -> Void)?
    private var filter = PhysicalNetworkChangeFilter()
    private var pendingSettle: DispatchWorkItem?

    func start(onChange: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            guard store == nil else { return }
            self.onChange = onChange
            var context = SCDynamicStoreContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            guard let store = SCDynamicStoreCreate(nil, "Shatl" as CFString, { _, _, info in
                guard let info else { return }
                Unmanaged<PhysicalNetworkMonitor>.fromOpaque(info).takeUnretainedValue().scheduleSettle()
            }, &context) else { return }
            SCDynamicStoreSetNotificationKeys(store, nil, [Self.serviceKeyPattern] as CFArray)
            SCDynamicStoreSetDispatchQueue(store, queue)
            self.store = store
            // The baseline.
            scheduleSettle()
        }
    }

    func stop() {
        queue.async { [self] in
            if let store {
                SCDynamicStoreSetDispatchQueue(store, nil)
            }
            store = nil
            onChange = nil
            pendingSettle?.cancel()
            pendingSettle = nil
        }
    }

    /// The registry as it stands now; `nil` when it cannot be read.
    static func readCurrentNetwork() -> PhysicalNetwork? {
        guard let store = SCDynamicStoreCreate(nil, "Shatl" as CFString, nil, nil) else { return nil }
        return currentNetwork(in: store)
    }

    private static func currentNetwork(in store: SCDynamicStore) -> PhysicalNetwork? {
        guard let keys = SCDynamicStoreCopyKeyList(store, serviceKeyPattern as CFString) as? [String] else {
            return nil
        }
        let records = keys.compactMap { SCDynamicStoreCopyValue(store, $0 as CFString) as? [String: Any] }
        return PhysicalNetwork(serviceRecords: records)
    }

    /// On `queue`: reads the registry once it has been still for a pause.
    private func scheduleSettle() {
        pendingSettle?.cancel()
        let settle = DispatchWorkItem { [weak self] in
            guard let self,
                  let store = self.store,
                  let network = Self.currentNetwork(in: store),
                  self.filter.settle(network) else { return }
            self.onChange?()
        }
        pendingSettle = settle
        queue.asyncAfter(deadline: .now() + Self.settlePause, execute: settle)
    }
}
