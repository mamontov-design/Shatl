// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import CryptoKit
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

private struct EngineFixture {
    let rootURL: URL
    let directories: ShatlDirectories
    let torrentID: UUID
    let entry: SessionRestoreEntry

    var resumeDataURL: URL {
        directories.resumeDataDirectoryURL
            .appendingPathComponent("\(torrentID.uuidString).fastresume", isDirectory: false)
    }

    static func make(named name: String) throws -> EngineFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentEngine-\(name)-\(UUID().uuidString)", isDirectory: true)
        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        try directories.ensureSessionDirectories()

        let saveURL = rootURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveURL, withIntermediateDirectories: true)
        let payload = Data((0..<(32 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try payload.write(to: saveURL.appendingPathComponent("payload.bin", isDirectory: false))

        let torrentURL = rootURL.appendingPathComponent("fixture.torrent", isDirectory: false)
        try makeTorrentData(fileName: "payload.bin", payload: payload, pieceLength: 16 * 1024)
            .write(to: torrentURL)

        let torrentID = UUID()
        return EngineFixture(
            rootURL: rootURL,
            directories: directories,
            torrentID: torrentID,
            entry: SessionRestoreEntry(
                torrentID: torrentID,
                attemptID: UUID(),
                archivedTorrentPath: torrentURL.path,
                suggestedSavePath: saveURL.path,
                selectedFileIndices: [0],
                stopAfterDownload: false,
                shouldStart: false
            )
        )
    }

    func setResumeDataFolderWritable(_ isWritable: Bool) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: isWritable ? 0o755 : 0o555],
            ofItemAtPath: directories.resumeDataDirectoryURL.path
        )
    }

    func remove() {
        try? setResumeDataFolderWritable(true)
        try? FileManager.default.removeItem(at: rootURL)
    }

    /// A minimal single-file v1 torrent without trackers, so no peers are contacted for it.
    private static func makeTorrentData(fileName: String, payload: Data, pieceLength: Int) -> Data {
        var pieces = Data()
        var offset = 0
        while offset < payload.count {
            let piece = payload[offset..<min(offset + pieceLength, payload.count)]
            pieces.append(contentsOf: Insecure.SHA1.hash(data: piece))
            offset += pieceLength
        }

        func string(_ value: String) -> Data { Data("\(value.utf8.count):\(value)".utf8) }
        func bytes(_ value: Data) -> Data { Data("\(value.count):".utf8) + value }
        func integer(_ value: Int) -> Data { Data("i\(value)e".utf8) }

        // Bencoded dictionary keys must be sorted.
        let info = Data("d".utf8)
            + string("length") + integer(payload.count)
            + string("name") + string(fileName)
            + string("piece length") + integer(pieceLength)
            + string("pieces") + bytes(pieces)
            + Data("e".utf8)
        return Data("d".utf8) + string("info") + info + Data("e".utf8)
    }
}
