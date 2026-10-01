// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// Runs the real libtorrent bridge to prove that each prepared draft owns its
/// metadata until it is released, so nothing stays in memory after Review
/// closes or an addition finishes.
final class LibtorrentEnginePreparedDraftTests: XCTestCase {
    func testEachDraftOfTheSameSourceHoldsItsOwnMetadataUntilReleased() async throws {
        let fixture = try EngineFixture.make(named: "DraftRelease")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories)

        let first = try await prepare(fixture, in: engine)
        let second = try await prepare(fixture, in: engine)
        XCTAssertNotEqual(first.id, second.id)
        let heldCount = await engine.preparedDraftCount()
        XCTAssertEqual(heldCount, 2)

        // Closing one Review must not take the metadata of another draft of
        // the same file, for example one that is still being added.
        await engine.releasePreparedDraft(id: first.id)
        let secondArchiveURL = fixture.rootURL.appendingPathComponent("second.torrent", isDirectory: false)
        try await engine.exportPreparedTorrent(draftID: second.id, to: secondArchiveURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondArchiveURL.path))

        do {
            let firstArchiveURL = fixture.rootURL.appendingPathComponent("first.torrent", isDirectory: false)
            try await engine.exportPreparedTorrent(draftID: first.id, to: firstArchiveURL.path)
            XCTFail("Expected the released draft to be gone")
        } catch {
            XCTAssertEqual((error as? TorrentEngineError)?.kind, .draftPreparationLost, "Unexpected error: \(error)")
        }

        await engine.releasePreparedDraft(id: second.id)
        let remainingCount = await engine.preparedDraftCount()
        XCTAssertEqual(remainingCount, 0)
    }

    func testAddAndExportUseTheDraftMetadata() async throws {
        let fixture = try EngineFixture.make(named: "DraftAdd")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories)

        let draft = try await prepare(fixture, in: engine)
        let record = try await engine.addTorrent(using: draft, recordID: UUID(), attemptID: UUID())
        XCTAssertEqual(record.infoHash, draft.infoHash)

        let archiveURL = fixture.rootURL.appendingPathComponent("archived.torrent", isDirectory: false)
        try await engine.exportPreparedTorrent(draftID: draft.id, to: archiveURL.path)
        let archivedFiles = try await engine.inspectTorrentContents(at: archiveURL.path)
        XCTAssertEqual(archivedFiles.map(\.relativePath), ["payload.bin"])

        await engine.releasePreparedDraft(id: draft.id)
        let remainingCount = await engine.preparedDraftCount()
        XCTAssertEqual(remainingCount, 0)
    }

    /// Opening a torrent the session already has fails as a duplicate that
    /// names it, so the add window can say which download it is.
    func testDuplicateNamesTheTorrentAlreadyInTheSession() async throws {
        let fixture = try EngineFixture.make(named: "DraftDuplicate")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories)

        let draft = try await prepare(fixture, in: engine)
        _ = try await engine.addTorrent(using: draft, recordID: UUID(), attemptID: UUID())
        await engine.releasePreparedDraft(id: draft.id)

        do {
            _ = try await prepare(fixture, in: engine)
            XCTFail("Expected a duplicate")
        } catch {
            let engineError = try XCTUnwrap(error as? TorrentEngineError, "Unexpected error: \(error)")
            XCTAssertEqual(engineError.kind, .duplicateTorrent)
            XCTAssertEqual(engineError.torrentName, draft.originalName)
            XCTAssertFalse(draft.originalName.isEmpty)
        }
    }

    private func prepare(_ fixture: EngineFixture, in engine: LibtorrentEngine) async throws -> AddTorrentDraft {
        try await engine.prepareDraft(
            from: AddTorrentSource(kind: .torrentFile, rawValue: fixture.entry.archivedTorrentPath),
            suggestedSavePath: fixture.entry.suggestedSavePath,
            stopAfterDownload: false
        )
    }
}
