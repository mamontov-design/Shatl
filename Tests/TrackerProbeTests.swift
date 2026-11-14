// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

#if DEBUG
import XCTest
@testable import Shatl

/// The Debug tracker probe: a stopped download asks each of its trackers
/// for seeds and leechers, and every answer, a failure too, comes back once
/// per tracker. Offline: libtorrent refuses to scrape a tracker on this Mac
/// (its SSRF guard), which is an answer all the same. On a local tracker
/// with the guard off, a paused torrent got 42 seeds and 13 leechers back
/// with no announce and no peer (the probe of 2026-11-13).
@MainActor
final class TrackerProbeTests: XCTestCase {
    func testAStoppedDownloadAsksItsTrackersAndEveryTrackerAnswersOnce() async throws {
        let fixture = try EngineFixture.make(named: "TrackerProbe", announceURL: "http://127.0.0.1:9/announce")
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
        XCTAssertNil(bridge.trackerScrapeForTorrent(withIdentifier: recordID), "Nothing before it was asked")

        XCTAssertTrue(bridge.scrapeTrackersForTorrent(withIdentifier: recordID))

        var scrape: LTTrackerScrape?
        for _ in 0..<50 {
            scrape = bridge.trackerScrapeForTorrent(withIdentifier: recordID)
            if let scrape, !scrape.answers.isEmpty { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let answered = try XCTUnwrap(scrape)
        XCTAssertEqual(answered.trackerCount, 1)
        XCTAssertEqual(answered.answers.count, 1, "One answer per tracker")
        let answer = try XCTUnwrap(answered.answers.first)
        XCTAssertTrue(answer.tracker.hasPrefix("http://127.0.0.1"), answer.tracker)
        XCTAssertFalse(answer.tracker.contains("announce"), "Scheme and host only")
        XCTAssertEqual(answer.seeds, -1)
        XCTAssertNotNil(answer.errorMessage)
    }

    func testADownloadTheEngineDoesNotHoldIsNotAsked() throws {
        let bridge = LibtorrentSessionBridge(
            resumeDataDirectoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("TrackerProbe-\(UUID().uuidString)", isDirectory: true)
        )
        try bridge.boot()
        XCTAssertFalse(bridge.scrapeTrackersForTorrent(withIdentifier: UUID().uuidString))
        XCTAssertNil(bridge.trackerScrapeForTorrent(withIdentifier: UUID().uuidString))
    }
}
#endif
