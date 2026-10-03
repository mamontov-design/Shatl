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

    /// A window as SwiftUI makes it has no size limit yet: CGFloat's largest
    /// value, far past Int. The lock must take such a window as it is.
    func testLockTakesAWindowWithNoSizeLimit() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        XCTAssertGreaterThan(window.contentMaxSize.width, CGFloat(Int.max))

        let coordinator = OnboardingWindowSizeLock(onWindowClose: {}).makeCoordinator()
        coordinator.lock(window: window)
        coordinator.restoreWindow()

        XCTAssertGreaterThan(window.contentMaxSize.width, CGFloat(Int.max))
    }

    /// The onboarding takes the locked content height as its own, so SwiftUI
    /// sizes the window as the lock does: the height without the title bar,
    /// told once however often the lock runs.
    func testLockTellsTheOnboardingItsHeightOnce() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        var heights: [CGFloat] = []
        let coordinator = OnboardingWindowSizeLock(
            onWindowClose: {},
            onContentHeightChange: { heights.append($0) }
        ).makeCoordinator()
        coordinator.lock(window: window)
        coordinator.lock(window: window)

        let didTell = await waitForCondition { !heights.isEmpty }
        XCTAssertTrue(didTell)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(heights, [OnboardingWindowLayout.contentSize(for: window).height])
        XCTAssertLessThan(heights[0], OnboardingWindowLayout.windowSize.height)

        coordinator.restoreWindow()
    }

    /// SwiftUI gave the window back its resizing on every animation frame,
    /// and macOS turned the zoom button on with it; no layout pass or window
    /// event told the lock (traced October 2026). The fixed onboarding
    /// height ended that; the style watch stays as a safety net: resizing
    /// given back goes again at once. Once onboarding ends, the restored
    /// window keeps it.
    func testResizingGivenBackIsTakenAgain() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let zoomButton = try XCTUnwrap(window.standardWindowButton(.zoomButton))
        let coordinator = OnboardingWindowSizeLock(onWindowClose: {}).makeCoordinator()
        coordinator.lock(window: window)
        // The lock checks itself twice right after it is applied; past that,
        // only the watch can notice.
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(window.styleMask.contains(.resizable))

        window.styleMask.insert(.resizable)
        XCTAssertTrue(zoomButton.isEnabled, "Resizing alone turns the zoom button on")

        let relocked = await waitForCondition { !window.styleMask.contains(.resizable) }
        XCTAssertTrue(relocked, "The window kept its resizing")
        XCTAssertFalse(zoomButton.isEnabled)

        coordinator.restoreWindow()
        XCTAssertTrue(window.styleMask.contains(.resizable))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(window.styleMask.contains(.resizable), "The watch outlived onboarding")
    }
}
