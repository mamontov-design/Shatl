// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import XCTest
@testable import Shatl

/// The add window answers "may it close?" itself and hands every other call
/// to the delegate SwiftUI set. A test host has no SwiftUI scene window, so
/// a stand-in delegate plays SwiftUI's part; the real window is the owner's
/// to check.
@MainActor
final class AddTorrentReviewWindowCloseGuardTests: XCTestCase {
    private final class StandInDelegate: NSObject, NSWindowDelegate {
        var becameKeyCount = 0
        var shouldCloseAnswer = true
        var shouldCloseCount = 0

        func windowDidBecomeKey(_ notification: Notification) {
            becameKeyCount += 1
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            shouldCloseCount += 1
            return shouldCloseAnswer
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }

    func testTheGuardAnswersCloseAndHandsTheRestOver() {
        let window = makeWindow()
        let standIn = StandInDelegate()
        window.delegate = standIn

        var asks = 0
        AddTorrentReviewWindowCloseGuard.install(on: window) { _ in
            asks += 1
            return false
        }

        XCTAssertTrue(window.delegate is AddTorrentReviewWindowCloseGuard)
        // "May it close?" is answered here, and SwiftUI's delegate is not
        // asked once the answer is no.
        XCTAssertEqual(window.delegate?.windowShouldClose?(window), false)
        XCTAssertEqual(asks, 1)
        XCTAssertEqual(standIn.shouldCloseCount, 0)

        // Everything else reaches SwiftUI's delegate as before.
        let delegate = window.delegate as? NSObject
        XCTAssertEqual(delegate?.responds(to: #selector(NSWindowDelegate.windowDidBecomeKey(_:))), true)
        window.delegate?.windowDidBecomeKey?(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        XCTAssertEqual(standIn.becameKeyCount, 1)
    }

    func testAYesStillAsksSwiftUIsDelegate() {
        let window = makeWindow()
        let standIn = StandInDelegate()
        standIn.shouldCloseAnswer = false
        window.delegate = standIn

        AddTorrentReviewWindowCloseGuard.install(on: window) { _ in true }

        XCTAssertEqual(window.delegate?.windowShouldClose?(window), false)
        XCTAssertEqual(standIn.shouldCloseCount, 1)
    }

    func testInstallingAgainGivesTheGuardItsNewAnswerWithoutWrappingItself() {
        let window = makeWindow()
        let standIn = StandInDelegate()
        window.delegate = standIn

        AddTorrentReviewWindowCloseGuard.install(on: window) { _ in false }
        let firstGuard = window.delegate as AnyObject?
        AddTorrentReviewWindowCloseGuard.install(on: window) { _ in true }

        XCTAssertTrue(window.delegate as AnyObject? === firstGuard)
        XCTAssertTrue((window.delegate as? AddTorrentReviewWindowCloseGuard)?.wrappedDelegate === standIn)
        XCTAssertEqual(window.delegate?.windowShouldClose?(window), true)
    }

    /// A window holds its delegate weakly: the guard must live as long as
    /// the window, or the window would be left with no delegate at all.
    func testTheWindowKeepsItsGuard() {
        let window = makeWindow()
        let standIn = StandInDelegate()
        window.delegate = standIn

        autoreleasepool {
            AddTorrentReviewWindowCloseGuard.install(on: window) { _ in true }
        }

        XCTAssertTrue(window.delegate is AddTorrentReviewWindowCloseGuard)
        XCTAssertTrue((window.delegate as? AddTorrentReviewWindowCloseGuard)?.wrappedDelegate === standIn)
    }
}
