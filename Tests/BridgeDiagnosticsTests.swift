// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// The bridge builds its log fields only while the log is on. Guards that
/// the lazy wrapper still writes them when it is.
final class BridgeDiagnosticsTests: XCTestCase {
    func testBridgeWritesItsEventsOnlyWhileTheLogIsOn() throws {
        let wasEnabled = ShatlFileLogger.shared.loggingEnabled
        addTeardownBlock { ShatlFileLogger.shared.setEnabled(wasEnabled) }
        let logURL = AppPreferences.defaultLogsDirectoryURL()
            .appendingPathComponent("Shatl.log", isDirectory: false)

        ShatlFileLogger.shared.setEnabled(false)
        let silentFixture = try restoreFixture(named: "SilentLog")
        ShatlFileLogger.shared.setEnabled(true)
        let loggedFixture = try restoreFixture(named: "Logged")
        ShatlFileLogger.shared.flushForTests()

        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(log.contains("torrent=\(loggedFixture.uuidString) phase=restore.begin"))
        XCTAssertFalse(log.contains(silentFixture.uuidString))
    }

    /// The card of a torrent in error shows a generic text; the libtorrent
    /// reason goes to the main log once, so an unexplained «Ошибка» in a long
    /// test can be traced without the heavy snapshot log.
    func testBridgeLogsTheReasonWhenATorrentFallsIntoError() async throws {
        let wasEnabled = ShatlFileLogger.shared.loggingEnabled
        addTeardownBlock { ShatlFileLogger.shared.setEnabled(wasEnabled) }
        ShatlFileLogger.shared.setEnabled(true)
        let fixture = try EngineFixture.make(named: "ErrorReason")
        addTeardownBlock { fixture.remove() }
        // An unreadable payload makes the full check fail with a file error.
        let payloadURL = URL(fileURLWithPath: fixture.entry.suggestedSavePath)
            .appendingPathComponent("payload.bin", isDirectory: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: payloadURL.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: payloadURL.path)
        }
        let bridge = LibtorrentSessionBridge(resumeDataDirectoryURL: fixture.directories.resumeDataDirectoryURL)
        let recordID = fixture.torrentID.uuidString

        _ = try bridge.restoreTorrent(
            withTorrentFilePath: fixture.entry.archivedTorrentPath,
            suggestedSavePath: fixture.entry.suggestedSavePath,
            stopAfterDownload: false,
            selectedFileIndices: [0],
            recordIdentifier: recordID,
            shouldStart: true
        )
        var fellIntoError = false
        let deadline = ContinuousClock.now + .seconds(5)
        while !fellIntoError, ContinuousClock.now < deadline {
            fellIntoError = try bridge.fetchActiveSnapshots()
                .contains { $0.recordIdentifier == recordID && $0.status == .error }
            if !fellIntoError {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        _ = try bridge.fetchActiveSnapshots()
        ShatlFileLogger.shared.flushForTests()

        XCTAssertTrue(fellIntoError, "The unreadable payload did not put the torrent into error")
        let logURL = AppPreferences.defaultLogsDirectoryURL()
            .appendingPathComponent("Shatl.log", isDirectory: false)
        let errorLines = ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "")
            .split(separator: "\n")
            .filter { $0.contains("torrent=\(recordID) phase=snapshot.error") }
        XCTAssertEqual(errorLines.count, 1, "\(errorLines)")
        XCTAssertTrue(errorLines.first?.contains("[ERROR]") == true, "\(errorLines)")
        XCTAssertTrue(errorLines.first?.contains("reason=") == true, "\(errorLines)")
    }

    /// A torrent that stays slow after a relaunch can be traced only through its
    /// tracker and peers. The tracker's answer goes to the log with its reason
    /// and interface, while the passkey in the tracker URL stays out of it.
    func testBridgeLogsTrackerErrorsAndTheSwarmWithoutThePasskey() async throws {
        let wasEnabled = ShatlFileLogger.shared.loggingEnabled
        addTeardownBlock { ShatlFileLogger.shared.setEnabled(wasEnabled) }
        ShatlFileLogger.shared.setEnabled(true)
        // Nothing listens on port 1, so the announce fails at once.
        let passkey = "PASSKEY\(UUID().uuidString.prefix(8))"
        let fixture = try EngineFixture.make(
            named: "TrackerError",
            announceURL: "http://127.0.0.1:1/announce?uk=\(passkey)"
        )
        addTeardownBlock { fixture.remove() }
        let bridge = LibtorrentSessionBridge(resumeDataDirectoryURL: fixture.directories.resumeDataDirectoryURL)
        let recordID = fixture.torrentID.uuidString
        let logURL = AppPreferences.defaultLogsDirectoryURL()
            .appendingPathComponent("Shatl.log", isDirectory: false)

        _ = try bridge.restoreTorrent(
            withTorrentFilePath: fixture.entry.archivedTorrentPath,
            suggestedSavePath: fixture.entry.suggestedSavePath,
            stopAfterDownload: false,
            selectedFileIndices: [0],
            recordIdentifier: recordID,
            shouldStart: true
        )
        var errorLines: [Substring] = []
        var log = ""
        let deadline = ContinuousClock.now + .seconds(10)
        while errorLines.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(200))
            _ = try bridge.fetchActiveSnapshots()
            ShatlFileLogger.shared.flushForTests()
            log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            errorLines = log.split(separator: "\n")
                .filter { $0.contains("torrent=\(recordID) phase=tracker.error") }
        }

        XCTAssertFalse(errorLines.isEmpty, "The failed announce was not logged")
        XCTAssertTrue(errorLines.first?.contains("tracker=http://127.0.0.1:1 ") == true, "\(errorLines)")
        XCTAssertTrue(errorLines.first?.contains("via=") == true, "\(errorLines)")
        XCTAssertTrue(log.contains("torrent=\(recordID) phase=tracker.announce event=started"))
        XCTAssertTrue(log.contains("torrent=\(recordID) phase=swarm.changed"))
        XCTAssertFalse(log.contains(passkey), "The tracker passkey leaked into the log")
    }

    /// Restores a fixture torrent through the real bridge and returns its record ID.
    private func restoreFixture(named name: String) throws -> UUID {
        let fixture = try EngineFixture.make(named: name)
        addTeardownBlock { fixture.remove() }
        let bridge = LibtorrentSessionBridge(resumeDataDirectoryURL: fixture.directories.resumeDataDirectoryURL)
        _ = try bridge.restoreTorrent(
            withTorrentFilePath: fixture.entry.archivedTorrentPath,
            suggestedSavePath: fixture.entry.suggestedSavePath,
            stopAfterDownload: false,
            selectedFileIndices: [0],
            recordIdentifier: fixture.torrentID.uuidString,
            shouldStart: false
        )
        return fixture.torrentID
    }
}
