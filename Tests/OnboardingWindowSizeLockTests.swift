// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import XCTest
@testable import Shatl

@MainActor
final class OnboardingWindowSizeLockTests: XCTestCase {
    func testLockPinsOnboardingSizeAndRestoresNormalResizeLimits() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let originalMinimum = NSSize(width: 440, height: 440)
        let originalMaximum = NSSize(width: 1_200, height: 1_000)
        let originalStyleMask = window.styleMask
        let originalTitleVisibility = window.titleVisibility
        let originalTitlebarAppearsTransparent = window.titlebarAppearsTransparent
        window.contentMinSize = originalMinimum
        window.contentMaxSize = originalMaximum
        window.standardWindowButton(.zoomButton)?.isEnabled = true

        let lock = OnboardingWindowSizeLock(onWindowClose: {})
        let coordinator = lock.makeCoordinator()
        coordinator.lock(window: window)
        let lockedContentSize = OnboardingWindowLayout.contentSize(for: window)

        XCTAssertEqual(window.frame.size, OnboardingWindowLayout.windowSize)
        XCTAssertEqual(window.contentView?.frame.size, lockedContentSize)
        XCTAssertEqual(window.contentMinSize, lockedContentSize)
        XCTAssertEqual(window.contentMaxSize, lockedContentSize)
        XCTAssertFalse(window.standardWindowButton(.zoomButton)?.isEnabled ?? true)
        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertFalse(window.titlebarAppearsTransparent)

        // Simulate a SwiftUI scene update that attempts to restore the
        // ordinary window configuration after the representable is attached.
        window.styleMask.insert(.resizable)
        window.contentMinSize = originalMinimum
        window.contentMaxSize = originalMaximum
        window.setContentSize(NSSize(width: 900, height: 700))
        window.standardWindowButton(.zoomButton)?.isEnabled = true
        coordinator.enforceWindowLock()

        XCTAssertEqual(window.frame.size, OnboardingWindowLayout.windowSize)
        XCTAssertEqual(window.contentView?.frame.size, lockedContentSize)
        XCTAssertEqual(window.contentMinSize, lockedContentSize)
        XCTAssertEqual(window.contentMaxSize, lockedContentSize)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.standardWindowButton(.zoomButton)?.isEnabled ?? true)

        coordinator.restoreWindow()

        XCTAssertEqual(window.contentMinSize, originalMinimum)
        XCTAssertEqual(window.contentMaxSize, originalMaximum)
        XCTAssertTrue(window.standardWindowButton(.zoomButton)?.isEnabled ?? false)
        XCTAssertEqual(window.styleMask, originalStyleMask)
        XCTAssertEqual(window.titleVisibility, originalTitleVisibility)
        XCTAssertEqual(window.titlebarAppearsTransparent, originalTitlebarAppearsTransparent)
    }
}
