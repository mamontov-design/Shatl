// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// The dot next to "Open a port on the router automatically" in Settings.
nonisolated enum PortForwardingIndicator: Equatable, Sendable {
    /// The switch is off.
    case hidden
    /// The switch is on and the router has not answered yet.
    case checking
    case open
    case closed

    /// A router without UPnP and NAT-PMP never refuses, it stays silent: after
    /// this long without an opened port it counts as closed. A refusal alone
    /// does not close it, since the other way may still open the port.
    static let routerAnswerTimeout: Duration = .seconds(10)

    init(isEnabled: Bool, status: EnginePortMappingStatus?) {
        guard isEnabled else {
            self = .hidden
            return
        }
        switch status {
        case .mapped:
            self = .open
        case .searching(let waiting?, _) where waiting >= Self.routerAnswerTimeout:
            self = .closed
        case nil, .off, .searching:
            // Right after the switch turns on, the engine may not have the
            // setting yet: the check has only started.
            self = .checking
        }
    }
}
