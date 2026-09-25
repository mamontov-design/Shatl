// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// Decides who owns the data folder before SwiftUI builds a window, the
/// session loads, orphans are cleaned or Sparkle starts. A second copy of
/// Shatl hands its launch to the running one and quits.
@main
enum ShatlMain {
    static func main() {
        guard usesSingleInstanceLock(ShatlLaunchMode.current) else {
            ShatlApp.main()
            return
        }

        switch SingleInstanceGate.resolve(directoryURL: AppEnvironment.liveDirectories.applicationSupportURL) {
        case .primary(let lock):
            ShatlSingleInstance.lock = lock
            ShatlApp.main()
        case .secondary(let holder):
            ShatlSecondaryInstance.run(handoff: .live(holder: holder))
        }
    }

    /// The unit-test host and Xcode previews run on temporary folders and must
    /// not take the user's data folder.
    static func usesSingleInstanceLock(_ launchMode: ShatlLaunchMode) -> Bool {
        launchMode == .live
    }
}

/// The data folder lock of this copy. It lives as long as the process: the
/// kernel releases it on exit or crash.
enum ShatlSingleInstance {
    static var lock: SingleInstanceLock?

    /// A copy launched while this one quits waits for the folder instead of
    /// handing its torrents over.
    static func setClosing(_ isClosing: Bool) {
        lock?.setClosing(isClosing)
    }
}
