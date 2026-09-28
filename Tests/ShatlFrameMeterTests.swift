// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import XCTest
@testable import Shatl

/// The Debug frame meter: it must catch a late frame, say whether the main
/// thread computed or waited meanwhile, and stay out of the way of typing.
final class ShatlFrameMeterTests: XCTestCase {
    func testFrameIsLateOnceItMissesHalfAFrame() {
        let frame = 1.0 / 60

        XCTAssertFalse(ShatlFrameHitch.isHitch(frameDuration: frame, nominalFrameDuration: frame))
        XCTAssertFalse(ShatlFrameHitch.isHitch(frameDuration: frame * 1.4, nominalFrameDuration: frame))
        XCTAssertTrue(ShatlFrameHitch.isHitch(frameDuration: frame * 1.6, nominalFrameDuration: frame))
        XCTAssertEqual(hitch(frameDuration: frame * 2).missedFrames, 1)
        XCTAssertEqual(hitch(frameDuration: frame * 3).missedFrames, 2)
    }

    func testHitchLineSplitsComputingFromWaitingAndNamesTheWork() {
        var counters = [Int](repeating: 0, count: ShatlFrameTrace.Counter.allCases.count)
        counters[ShatlFrameTrace.Counter.cardUpdates.rawValue] = 11
        counters[ShatlFrameTrace.Counter.cardBodies.rawValue] = 11
        var hitch = hitch(frameDuration: 0.0384)
        hitch.mainThread = ShatlMainThreadTime(wall: 0.0350, cpu: 0.0101)
        hitch.longestSlice = ShatlMainThreadTime(wall: 0.0167, cpu: 0.0020)
        hitch.counters = counters
        hitch.spans = [
            ShatlFrameTrace.Span(name: "store.snapshots", duration: 0.0015),
            ShatlFrameTrace.Span(name: "store.snapshots", duration: 0.0006),
        ]
        hitch.context = ShatlFrameContext(
            metricsMode: "detailed",
            windowSize: "820x1180",
            cards: ShatlFrameCardCounts(total: 25, active: 10)
        )

        let line = hitch.logLine(timeFormatter: posixFormatter("HH:mm:ss.SSS"))

        for field in [
            "frame.hitch",
            "frame.ms=38.4",
            "missed=1",
            "removed=-",
            "scrolling=yes",
            "scroll.speed=0",
            "metrics=detailed",
            "window=820x1180",
            "cards=25",
            "active=10",
            "main.ms=35.0",
            "main.cpu.ms=10.1",
            "main.waiting.ms=24.9",
            "slice.ms=16.7",
            "slice.waiting.ms=14.7",
            "cards.updated=11",
            "cards.drawn=11",
            "spans=store.snapshots:2.1",
        ] {
            XCTAssertTrue(line.contains(field), "\(field) missing from \(line)")
        }
    }

    /// A late frame names the animations that ran during it and on how many
    /// cards; the summary counts the animations that started.
    func testLateFrameNamesTheAnimationsRunningDuringIt() {
        let wasEnabled = ShatlFrameTrace.isEnabled
        defer { ShatlFrameTrace.setEnabled(wasEnabled) }
        ShatlFrameTrace.setEnabled(true)
        let first = UUID()
        let second = UUID()

        // Ended before the frame began.
        ShatlFrameTrace.animationStarted(.hover, cardID: first, duration: 0.2, at: 9.5)
        // Running during the frame.
        ShatlFrameTrace.animationStarted(.digits, cardID: first, duration: 0.5, at: 9.8)
        ShatlFrameTrace.animationStarted(.digits, cardID: first, duration: 0.5, at: 9.9)
        ShatlFrameTrace.animationStarted(.digits, cardID: second, duration: 0.5, at: 10.01)
        ShatlFrameTrace.animationStarted(.bounce, cardID: second, duration: 0.52, at: 10.02)
        ShatlFrameTrace.animationStarted(.chipDigits, cardID: nil, duration: 0.5, at: 10.02)
        // Started after the frame.
        ShatlFrameTrace.animationStarted(.progressBar, cardID: first, duration: 0.45, at: 10.5)

        let running = ShatlFrameTrace.runningAnimations(from: 10, to: 10.04)
        XCTAssertEqual(running.summary, "digits:3/2,chipdigits:1/0,bounce:1/1")
        XCTAssertEqual(running.cards, 2)
        XCTAssertEqual(ShatlFrameTrace.runningAnimations(from: 20, to: 20.04).summary, "-")

        XCTAssertEqual(
            ShatlFrameTrace.drainStartedAnimations(),
            "digits:3,chipdigits:1,bounce:1,progressbar:1,hover:1"
        )
        XCTAssertEqual(ShatlFrameTrace.drainStartedAnimations(), "-")

        var hitch = hitch(frameDuration: 0.04)
        hitch.animations = running.summary
        hitch.animatingCards = running.cards
        let line = hitch.logLine(timeFormatter: posixFormatter("HH:mm:ss.SSS"))
        XCTAssertTrue(line.contains("anims=digits:3/2,chipdigits:1/0,bounce:1/1 anims.cards=2"), line)
    }

    /// While the meter is off, starting an animation records nothing.
    func testAnimationsAreNotRecordedWhileTheMeterIsOff() {
        let wasEnabled = ShatlFrameTrace.isEnabled
        defer { ShatlFrameTrace.setEnabled(wasEnabled) }
        ShatlFrameTrace.setEnabled(false)

        ShatlFrameTrace.animationStarted(.digits, cardID: UUID(), duration: 0.5, at: 10)

        XCTAssertEqual(ShatlFrameTrace.runningAnimations(from: 10, to: 10.1).summary, "-")
        XCTAssertEqual(ShatlFrameTrace.drainStartedAnimations(), "-")
    }

    func testMarkIsTheFKeyAloneAndNeverWhileTyping() {
        let key = ShatlFrameMarkerKey.keyCode

        XCTAssertTrue(ShatlFrameMarkerKey.matches(keyCode: key, modifierFlags: [], isRepeat: false, isEditingText: false))
        XCTAssertTrue(ShatlFrameMarkerKey.matches(keyCode: key, modifierFlags: [.capsLock], isRepeat: false, isEditingText: false))
        XCTAssertFalse(ShatlFrameMarkerKey.matches(keyCode: key, modifierFlags: [.command], isRepeat: false, isEditingText: false))
        XCTAssertFalse(ShatlFrameMarkerKey.matches(keyCode: key, modifierFlags: [.shift], isRepeat: false, isEditingText: false))
        XCTAssertFalse(ShatlFrameMarkerKey.matches(keyCode: key, modifierFlags: [], isRepeat: true, isEditingText: false))
        XCTAssertFalse(ShatlFrameMarkerKey.matches(keyCode: key, modifierFlags: [], isRepeat: false, isEditingText: true))
        XCTAssertFalse(ShatlFrameMarkerKey.matches(keyCode: 0, modifierFlags: [], isRepeat: false, isEditingText: false))
    }

    func testRemovedCardPartsAreNamedInTheLogAndCanBePutBack() {
        let options = TorrentCardDebugOptions.shared
        let saved = options.removedParts
        defer { options.removedParts = saved }

        options.removedParts = []
        XCTAssertEqual(options.logName, "-")
        XCTAssertFalse(isCardPartRemoved(.fileCheck))

        options.isRemoved(.fileCheck).wrappedValue = true
        options.isRemoved(.progressBarAnimation).wrappedValue = true
        XCTAssertTrue(isCardPartRemoved(.fileCheck))
        XCTAssertEqual(options.logName, "progressbar+filecheck")

        options.isRemoved(.fileCheck).wrappedValue = false
        XCTAssertFalse(isCardPartRemoved(.fileCheck))
        XCTAssertEqual(options.logName, "progressbar")
    }

    /// The switch for every animation takes each animation group off with it.
    func testAllAnimationsSwitchCoversEveryAnimationGroup() {
        let options = TorrentCardDebugOptions.shared
        let saved = options.removedParts
        defer { options.removedParts = saved }

        options.removedParts = [.progressBarAnimation]
        XCTAssertTrue(isCardPartRemoved(.progressBarAnimation))
        XCTAssertFalse(isCardPartRemoved(.hoverAnimations))

        options.removedParts = [.animations]
        for part in TorrentCardDebugPart.allCases where part.isAnimation {
            XCTAssertTrue(isCardPartRemoved(part), "\(part)")
        }
        XCTAssertFalse(isCardPartRemoved(.fileCheck))
    }

    func testDebugChoicesAreKeptBetweenLaunches() throws {
        let suiteName = "ShatlFrameMeterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(ShatlFrameDiagnosticsSettings(defaults: defaults).isEnabled)

        ShatlFrameDiagnosticsSettings(defaults: defaults).isEnabled = false

        XCTAssertFalse(ShatlFrameDiagnosticsSettings(defaults: defaults).isEnabled)
    }

    /// A main thread blocked between two frames shows up as waiting.
    func testBlockedMainThreadIsLoggedAsWaiting() throws {
        let hitchLine = try hitchLine {
            Thread.sleep(forTimeInterval: 0.05)
        }

        XCTAssertTrue(hitchLine.contains("cards.updated=3"), hitchLine)
        XCTAssertGreaterThan(try field("main.waiting.ms", in: hitchLine), 40, hitchLine)
        XCTAssertLessThan(try field("main.cpu.ms", in: hitchLine), 20, hitchLine)
    }

    /// A main thread busy computing between two frames shows up as CPU time.
    func testBusyMainThreadIsLoggedAsComputing() throws {
        let hitchLine = try hitchLine {
            let end = ShatlFrameTrace.now() + 0.05
            var spins = 0
            while ShatlFrameTrace.now() < end {
                spins &+= 1
            }
            XCTAssertGreaterThan(spins, 0)
        }

        XCTAssertGreaterThan(try field("main.cpu.ms", in: hitchLine), 40, hitchLine)
        XCTAssertLessThan(try field("main.waiting.ms", in: hitchLine), 20, hitchLine)
    }

    /// SwiftUI can keep two meters for a moment. The one that leaves must not
    /// end the session of the one that stays.
    func testMeterThatLeavesKeepsTheOtherOneRecording() throws {
        let directory = try temporaryDirectory()
        let logger = ShatlFileLogger(directoryURL: directory, fileName: "frames.log")
        let monitor = ShatlFrameMonitor(logger: logger)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let container = NSView(frame: window.contentLayoutRect)
        window.contentView = container
        let staying = ShatlFrameMeterView(monitor: monitor)
        let leaving = ShatlFrameMeterView(monitor: monitor)
        container.addSubview(staying)
        container.addSubview(leaving)

        leaving.removeFromSuperview()

        XCTAssertTrue(ShatlFrameTrace.isEnabled)
        XCTAssertTrue(logger.loggingEnabled)

        staying.removeFromSuperview()
        window.close()

        XCTAssertFalse(ShatlFrameTrace.isEnabled)
        XCTAssertFalse(logger.loggingEnabled)
    }

    // MARK: - Helpers

    /// Runs `work` on the main queue between two frames and returns the logged
    /// hitch, the way the owner's log would be read.
    private func hitchLine(_ work: @escaping @MainActor () -> Void) throws -> String {
        let directory = try temporaryDirectory()
        let logger = ShatlFileLogger(directoryURL: directory, fileName: "frames.log")
        let monitor = ShatlFrameMonitor(logger: logger)
        let frame = 1.0 / 60

        monitor.beginRecording()
        monitor.recordFrame(timestamp: ShatlFrameTrace.now(), nominalDuration: frame)
        // A card update inside the late frame.
        ShatlFrameTrace.count(.cardUpdates, by: 3)
        DispatchQueue.main.async {
            work()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        monitor.recordFrame(timestamp: ShatlFrameTrace.now(), nominalDuration: frame)
        monitor.stop()
        logger.flushForTests()
        XCTAssertFalse(ShatlFrameTrace.isEnabled)

        let log = try String(contentsOf: directory.appendingPathComponent("frames.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("frame.meter.stopped"), log)
        return try XCTUnwrap(log.components(separatedBy: "\n").first { $0.contains("frame.hitch") }, log)
    }

    private func field(_ name: String, in line: String) throws -> Double {
        let field = try XCTUnwrap(line.split(separator: " ").first { $0.hasPrefix("\(name)=") }, line)
        return try XCTUnwrap(Double(field.dropFirst(name.count + 1)), line)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShatlFrameMeterTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func hitch(frameDuration: Double) -> ShatlFrameHitch {
        ShatlFrameHitch(
            time: Date(timeIntervalSince1970: 0),
            frameDuration: frameDuration,
            nominalFrameDuration: 1.0 / 60,
            isScrolling: true,
            mainThread: ShatlMainThreadTime(),
            longestSlice: ShatlMainThreadTime(),
            counters: [Int](repeating: 0, count: ShatlFrameTrace.Counter.allCases.count),
            spans: []
        )
    }

    private func posixFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}
