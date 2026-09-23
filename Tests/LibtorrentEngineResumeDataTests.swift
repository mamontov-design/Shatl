// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// Runs the real libtorrent bridge against a generated torrent in a temporary folder.
final class LibtorrentEngineResumeDataTests: XCTestCase {
    func testCheckpointWritesFastResumeThatRestoreLoads() async throws {
        let fixture = try EngineFixture.make(named: "RoundTrip")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories)

        let firstRestore = try await engine.restoreSession([fixture.entry])
        XCTAssertEqual(firstRestore.first?.resumeDataStatus, .missing)

        let checkpoints = await engine.checkpointTorrents(ids: [fixture.torrentID])

        XCTAssertEqual(checkpoints, [EngineResumeCheckpointResult(id: fixture.torrentID, status: .saved)])
        XCTAssertFalse(try Data(contentsOf: fixture.resumeDataURL).isEmpty)

        try await engine.removeTorrent(id: fixture.torrentID, deleteData: false)
        let secondRestore = try await engine.restoreSession([fixture.entry])

        XCTAssertEqual(secondRestore.first?.resumeDataStatus, .loaded)
    }

    func testCheckpointReportsFailureAndKeepsPreviousFastResumeWhenFolderIsReadOnly() async throws {
        let fixture = try EngineFixture.make(named: "ReadOnly")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories)
        _ = try await engine.restoreSession([fixture.entry])
        let firstCheckpoint = await engine.checkpointTorrents(ids: [fixture.torrentID])
        XCTAssertEqual(firstCheckpoint.first?.status, .saved)
        let previousResumeData = try Data(contentsOf: fixture.resumeDataURL)

        try fixture.setResumeDataFolderWritable(false)
        let failedCheckpoint = await engine.checkpointTorrents(ids: [fixture.torrentID])
        try fixture.setResumeDataFolderWritable(true)

        guard case .failed = failedCheckpoint.first?.status else {
            return XCTFail("Expected a failed checkpoint, got \(String(describing: failedCheckpoint))")
        }
        XCTAssertEqual(try Data(contentsOf: fixture.resumeDataURL), previousResumeData)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: fixture.directories.resumeDataDirectoryURL.path),
            [fixture.resumeDataURL.lastPathComponent]
        )
    }
}
