// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Network
import Synchronization

/// Whether the Mac has no network path at all: Wi-Fi off, cable out. Asked
/// once, when a wait for a magnet link's file list runs out, so the message
/// can name the real cause. A network that is up but slow counts as online.
nonisolated enum NetworkReachability {
    /// Waits for the system's first answer, at most `timeoutSeconds`. No
    /// answer counts as online, so a slow answer never blames the network.
    static func isOffline(timeoutSeconds: Double = 1) async -> Bool {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "Shatl.NetworkReachability")
        defer { monitor.cancel() }

        return await withCheckedContinuation { continuation in
            let answer = OneAnswer(continuation)
            monitor.pathUpdateHandler = { path in
                answer.resume(path.status == .unsatisfied)
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                answer.resume(false)
            }
        }
    }

    /// The monitor and the timer race; only the first resumes the wait.
    private final class OneAnswer: Sendable {
        private let continuation: Mutex<CheckedContinuation<Bool, Never>?>

        init(_ continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = Mutex(continuation)
        }

        func resume(_ isOffline: Bool) {
            continuation.withLock { pending in
                pending?.resume(returning: isOffline)
                pending = nil
            }
        }
    }
}
