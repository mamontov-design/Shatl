// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Darwin
import Foundation
import XCTest
@testable import Shatl

/// A 2 GB download into a 50 MB disk image "finished": libtorrent wrote it
/// into memory-mapped files, and macOS, finding no room on disk, dropped the
/// data without an error. The pieces passed their check against pages still
/// in memory, and the file broke once the disk was ejected. Written through
/// write calls, the download is refused with ENOSPC instead.
///
/// libtorrent answers a refused write (no space, no access, a read-only
/// disk) by seeding without downloading, with no error: the card showed
/// "Скачивается" at no speed. The bridge stops such a download and reports
/// the refusal, so the card says why and "Повторить" starts it again.
///
/// A folder that refuses new files takes the same path with EACCES, without
/// mounting a disk image in a test. The full disk itself was tried on APFS
/// images by hand (October 2026).
final class PayloadWriteModeTests: XCTestCase {
    func testEveryProfileWritesPayloadThroughWriteCalls() throws {
        let bridge = LibtorrentSessionBridge(
            resumeDataDirectoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("PayloadWriteMode-\(UUID().uuidString)", isDirectory: true)
        )
        XCTAssertFalse(bridge.writesPayloadThroughWriteCalls)

        try bridge.boot()
        XCTAssertTrue(bridge.writesPayloadThroughWriteCalls)

        for profile: LTPerformanceProfile in [.maximum, .economical, .balanced] {
            try bridge.apply(profile)
            XCTAssertTrue(bridge.writesPayloadThroughWriteCalls, "profile \(profile.rawValue)")
        }
    }

    func testRefusedWriteStopsTheDownloadWithItsCause() async throws {
        let seed = try LocalWebSeed()
        addTeardownBlock { seed.stop() }
        let fixture = try EngineFixture.make(
            named: "RefusedWrite",
            webSeedURL: "http://127.0.0.1:\(seed.port)/payload.bin"
        )
        addTeardownBlock { fixture.remove() }
        let saveURL = URL(fileURLWithPath: fixture.entry.suggestedSavePath, isDirectory: true)
        let payloadURL = saveURL.appendingPathComponent("payload.bin", isDirectory: false)
        seed.payload = try Data(contentsOf: payloadURL)
        try FileManager.default.removeItem(at: payloadURL)
        try setWritable(false, saveURL)
        addTeardownBlock { try? self.setWritable(true, saveURL) }

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

        let refused = try await firstSnapshot(of: recordID, in: bridge) { $0.status == .error }
        let snapshot = try XCTUnwrap(refused, "The download went on seeding without downloading")
        XCTAssertEqual(snapshot.errorCode, Int(EACCES))
        XCTAssertEqual(TorrentErrorState.Cause(posixCode: snapshot.errorCode), .noWriteAccess)

        // libtorrent counted the pieces against the blocks in memory before
        // their writes were refused; the check that follows the stop finds
        // nothing on disk.
        let checked = try await firstSnapshot(of: recordID, in: bridge) {
            $0.status == .error && $0.progress == 0
        }
        XCTAssertNotNil(checked, "Pieces that never reached the disk still count as downloaded")

        // Stopped, it stays so until Start: libtorrent's own retry does not
        // start it, and Start once the folder allows writing finishes it.
        let stillStopped = try await firstSnapshot(of: recordID, in: bridge, within: .seconds(1)) {
            $0.status != .error
        }
        XCTAssertNil(stillStopped)

        try setWritable(true, saveURL)
        try bridge.startTorrent(withIdentifier: recordID)
        let finished = try await firstSnapshot(of: recordID, in: bridge) { $0.progress >= 1 }
        XCTAssertNotNil(finished, "Start did not finish the download")
        // A piece counts once its hash passes; its write may still be on
        // the way.
        let written = await waitForCondition(timeoutNanoseconds: 5_000_000_000) {
            (try? Data(contentsOf: payloadURL)) == seed.payload
        }
        XCTAssertTrue(written, "The downloaded file is not on disk")
    }

    // MARK: - Helpers

    private func setWritable(_ isWritable: Bool, _ folderURL: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: isWritable ? 0o755 : 0o555],
            ofItemAtPath: folderURL.path
        )
    }

    private func firstSnapshot(
        of recordID: String,
        in bridge: LibtorrentSessionBridge,
        within timeout: Duration = .seconds(15),
        where predicate: (LTTorrentSnapshot) -> Bool
    ) async throws -> LTTorrentSnapshot? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let snapshot = try bridge.fetchActiveSnapshots().first { $0.recordIdentifier == recordID }
            if let snapshot, predicate(snapshot) {
                return snapshot
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }
}
