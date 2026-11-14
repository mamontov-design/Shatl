// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// Orbit holds a torrent to 120 connections and lets TCP go first, closer
/// to qBittorrent's defaults (the owner, 2026-11-13); Halo and Nova keep
/// their own. libtorrent has no session setting for a torrent's
/// connections: each torrent takes it as it comes and on a switch of
/// profile.
@MainActor
final class OrbitConnectionsTests: XCTestCase {
    func testOrbitHoldsATorrentTo120ConnectionsAndOthersDoNot() throws {
        let fixture = try EngineFixture.make(named: "OrbitConnections")
        addTeardownBlock { fixture.remove() }
        let bridge = LibtorrentSessionBridge(resumeDataDirectoryURL: fixture.directories.resumeDataDirectoryURL)
        try bridge.boot()
        let recordID = fixture.torrentID.uuidString
        _ = try bridge.restoreTorrent(
            withTorrentFilePath: fixture.entry.archivedTorrentPath,
            suggestedSavePath: fixture.entry.suggestedSavePath,
            stopAfterDownload: false,
            selectedFileIndices: [0],
            recordIdentifier: recordID,
            shouldStart: false
        )

        XCTAssertEqual(bridge.maxConnectionsForTorrent(withIdentifier: recordID), 120, "Orbit from the start")
        XCTAssertTrue(bridge.prefersTCPOverUTP)

        for (profile, limit, prefersTCP): (LTPerformanceProfile, Int, Bool) in [
            (.maximum, -1, false),
            (.economical, -1, false),
            (.balanced, 120, true),
        ] {
            try bridge.apply(profile)
            XCTAssertEqual(
                bridge.maxConnectionsForTorrent(withIdentifier: recordID)?.intValue,
                limit,
                "profile \(profile.rawValue)"
            )
            XCTAssertEqual(bridge.prefersTCPOverUTP, prefersTCP, "profile \(profile.rawValue)")
        }
    }
}
