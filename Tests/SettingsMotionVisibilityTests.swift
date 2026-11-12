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

    /// The empty list, Settings → About and the add window show the
    /// wordmark. In a closed window it took about 135 ms a second in a
    /// Debug build, about as much as on screen.
    func testTheWordmarkStandsInAClosedWindow() throws {
        try skipUnderReduceMotion()
        let window = makeWindow(
            ShatlWordmark()
                .environment(\.appearsActive, true)
                .environmentObject(ShatlAccentState()),
            size: CGSize(width: 260, height: 120)
        )
        defer { window.orderOut(nil) }

        let shown = show(window)
        let closed = hide(window)
        let shownAgain = show(window)

        XCTAssertGreaterThan(shown, Self.moving, "The wordmark must move on screen for this to test anything")
        XCTAssertLessThan(closed, Self.standing, "The wordmark went on moving in a closed window")
        XCTAssertGreaterThan(shownAgain, Self.moving, "The wordmark did not move again when its window came back")
    }

    /// The logomark moves for 2.2 s after a pause of 2 s: on screen it is
    /// read over a whole round, closed once the move under way is over.
    func testTheLogomarkStandsInAClosedWindow() throws {
        try skipUnderReduceMotion()
        let window = makeWindow(
            ShatlWordmark(initialSelection: .logomark)
                .environment(\.appearsActive, true)
                .environmentObject(ShatlAccentState()),
            size: CGSize(width: 260, height: 120)
        )
        defer { window.orderOut(nil) }

        let round = ShatlBrandAnimation.pauseDuration + ShatlBrandAnimation.fullDuration
        let shown = show(window, over: round + 0.3)
        let closed = hide(window, settling: ShatlBrandAnimation.fullDuration + 0.3)
        let shownAgain = show(window, over: round + 0.3)

        XCTAssertGreaterThan(shown, Self.moving, "The logomark must move on screen for this to test anything")
        XCTAssertLessThan(closed, Self.standing, "The logomark went on moving in a closed window")
        XCTAssertGreaterThan(shownAgain, Self.moving, "The logomark did not move again when its window came back")
    }

    /// Behind the window the user works in, the wordmark stands, as the
    /// inactive look will have it, and moves again once its window is
    /// worked in. On the empty list it took about a quarter of a core,
    /// inactive as active (measured on 2026-11-12).
    func testTheWordmarkStandsInAWindowThatIsNotWorkedIn() throws {
        try skipUnderReduceMotion()
        let focus = MotionFocusModel()
        let window = makeWindow(
            MotionFocusRoot(focus: focus, content: ShatlWordmark().environmentObject(ShatlAccentState())),
            size: CGSize(width: 260, height: 120)
        )
        defer { window.orderOut(nil) }

        let active = show(window)
        focus.isActive = false
        spin(for: 0.3)
        let inactive = mainThreadMilliseconds(over: 1)
        focus.isActive = true
        spin(for: 0.3)
        let activeAgain = mainThreadMilliseconds(over: 1)

        XCTAssertGreaterThan(active, Self.moving, "The wordmark must move in an active window for this to test anything")
        XCTAssertLessThan(inactive, Self.standing, "The wordmark went on moving in an inactive window")
        XCTAssertGreaterThan(activeAgain, Self.moving, "The wordmark did not move again when its window was active again")
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

    /// Main-thread milliseconds while the window is on screen, from half a
    /// second after it comes.
    private func show(_ window: NSWindow, over seconds: TimeInterval = 1) -> Double {
        window.orderFrontRegardless()
        spin(for: 0.5)
        return mainThreadMilliseconds(over: seconds)
    }

    /// Main-thread milliseconds in a second once the window has been closed
    /// for `settling`: a number that came just before the close still rolls
    /// for half a second, a move of the logomark for its whole length, and
    /// then nothing should move.
    private func hide(_ window: NSWindow, settling: TimeInterval = 1) -> Double {
        window.orderOut(nil)
        spin(for: settling)
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

/// Whether the window is the one the user works in, set by a test in place
/// of the system.
private final class MotionFocusModel: ObservableObject {
    @Published var isActive = true
}

private struct MotionFocusRoot<Content: View>: View {
    @ObservedObject var focus: MotionFocusModel
    let content: Content

    var body: some View {
        content.environment(\.appearsActive, focus.isActive)
    }
}
