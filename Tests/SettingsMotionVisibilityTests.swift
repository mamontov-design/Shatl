// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import XCTest
@testable import Shatl

/// Endless motion runs only while it can be seen. A closed Settings window
/// is hidden, not taken apart, and the speedometers' arrows went on swinging
/// in it sixty times a second until Shatl quit: about a tenth of a core, the
/// download list standing still (measured on 2026-11-12). Each test shows a
/// small window in the corner of the screen for a few seconds.
@MainActor
final class SettingsMotionVisibilityTests: XCTestCase {
    /// Main-thread milliseconds in a second that tell moving from standing:
    /// one arrow swinging took about 45 in a Debug build, standing well
    /// under one.
    private static let moving = 10.0
    private static let standing = 5.0

    func testASpeedometerSwingsOnScreenAndStandsInAClosedWindow() throws {
        try skipUnderReduceMotion()
        let window = makeWindow(
            ShatlPerformanceProfileSpeedometer(profile: .balanced)
                .environmentObject(ShatlAccentState()),
            size: CGSize(width: 48, height: 48)
        )
        defer { window.orderOut(nil) }

        let shown = show(window)
        let closed = hide(window)
        let shownAgain = show(window)

        XCTAssertGreaterThan(shown, Self.moving, "The arrow must swing on screen for this to test anything")
        XCTAssertLessThan(closed, Self.standing, "The arrow went on swinging in a closed window")
        XCTAssertGreaterThan(shownAgain, Self.moving, "The arrow did not swing again when its window came back")
    }

    func testASpeedometerStandsOnATabThatIsNotOpen() throws {
        try skipUnderReduceMotion()
        let window = makeWindow(
            ShatlPerformanceProfileSpeedometer(profile: .balanced)
                .environment(\.shatlTabIsShown, false)
                .environmentObject(ShatlAccentState()),
            size: CGSize(width: 48, height: 48)
        )
        defer { window.orderOut(nil) }

        let shown = show(window)
        XCTAssertLessThan(shown, Self.standing, "The arrow swung on a tab that is not open")
    }

    /// The onboarding's demo card pulses its expand hint and takes a new
    /// number every second; Settings → Appearance shows it without the hint.
    func testTheDemoCardStandsInAClosedWindow() throws {
        try skipUnderReduceMotion()
        let window = makeWindow(
            TorrentCardPreviewView()
                .environmentObject(ShatlAccentState()),
            size: CGSize(width: 400, height: 180)
        )
        defer { window.orderOut(nil) }

        let shown = show(window)
        let closed = hide(window)
        let shownAgain = show(window)

        XCTAssertGreaterThan(shown, Self.moving, "The hint must pulse on screen for this to test anything")
        XCTAssertLessThan(closed, Self.standing, "The demo card went on moving in a closed window")
        XCTAssertGreaterThan(shownAgain, Self.moving, "The hint did not pulse again when its window came back")
    }

    // MARK: - Helpers

    private func skipUnderReduceMotion() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            throw XCTSkip("Under Reduce Motion nothing moves, so there is nothing to stop.")
        }
    }

    /// A small window in the corner of the screen, above other windows so
    /// that the system counts it as seen.
    private func makeWindow<V: View>(_ view: V, size: CGSize) -> NSWindow {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(
            contentRect: CGRect(
                origin: CGPoint(x: visible.minX + 8, y: visible.maxY - size.height - 8),
                size: size
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        return window
    }

    /// Main-thread milliseconds in the second after the window comes on screen.
    private func show(_ window: NSWindow) -> Double {
        window.orderFrontRegardless()
        spin(for: 0.5)
        return mainThreadMilliseconds(over: 1)
    }

    /// Main-thread milliseconds in a second once the window has been closed
    /// for a second: a number that came just before the close still rolls
    /// for half a second, and then nothing should move.
    private func hide(_ window: NSWindow) -> Double {
        window.orderOut(nil)
        spin(for: 1)
        return mainThreadMilliseconds(over: 1)
    }

    private func spin(for seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func mainThreadMilliseconds(over seconds: TimeInterval) -> Double {
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        spin(for: seconds)
        return Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1_000_000
    }
}
