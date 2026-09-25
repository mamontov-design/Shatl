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
