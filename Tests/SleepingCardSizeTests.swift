// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// A stopped or finished download reaches the engine only on Start, and its
/// size came only from the engine: after relaunch the open card showed
/// "Размер 0 Б" until the download ran again. The list now keeps the size,
/// in two optional fields with no new schema version.
@MainActor
final class SleepingCardSizeTests: XCTestCase {
    private func makeSessionStore() -> (SessionStore, ShatlDirectories) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SleepingCardSize-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: rootURL) }
        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let store = SessionStore(
            directories: directories,
            archiveStore: TorrentArchiveStore(directories: directories),
            bookmarkStore: BookmarkStore(directories: directories),
            resumeDataStore: ResumeDataStore(directories: directories),
            startupMode: .alreadyInitialized
        )
        return (store, directories)
    }

    func testSaveAndLoadKeepsTheSize() async throws {
        let (sessionStore, _) = makeSessionStore()
        var record = makeTestRecord(status: .stopped)
        record.metrics.totalBytes = 4_000_000_000
        record.metrics.selectedBytes = 3_000_000_000

        await sessionStore.replaceAllRecordsForTesting(from: [record])
        let loadedSnapshot = await sessionStore.load().snapshot
        let loaded = try XCTUnwrap(loadedSnapshot?.torrents.first)

        XCTAssertEqual(loaded.totalBytes, 4_000_000_000)
        XCTAssertEqual(loaded.selectedBytes, 3_000_000_000)
    }

    /// An unknown size is left out rather than saved as zero.
    func testUnknownSizeIsNotWritten() async throws {
        let (sessionStore, directories) = makeSessionStore()
        var record = makeTestRecord(status: .stopped)
        record.metrics.totalBytes = 0
        record.metrics.selectedBytes = 0

        await sessionStore.replaceAllRecordsForTesting(from: [record])
        let loadedSnapshot = await sessionStore.load().snapshot
        let loaded = try XCTUnwrap(loadedSnapshot?.torrents.first)
        let json = try String(contentsOf: directories.sessionSnapshotURL, encoding: .utf8)

        XCTAssertNil(loaded.totalBytes)
        XCTAssertNil(loaded.selectedBytes)
        XCTAssertFalse(json.contains("totalBytes"))
        XCTAssertFalse(json.contains("selectedBytes"))
    }

    func testStoppedCardShowsItsSizeAfterRelaunch() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }
        var record = sessionRecord()
        record.totalBytes = 4_000_000_000
        record.selectedBytes = 3_000_000_000
        try writeSession([record], schemaVersion: SessionSnapshot.currentSchemaVersion, to: bundle.directories)

        bundle.store.bootstrapRuntimeState()
        let didLoad = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            !bundle.store.isRestoringSession && bundle.store.torrents.count == 1
        }

        XCTAssertTrue(didLoad)
        let loaded = try XCTUnwrap(bundle.store.torrents.first)
        XCTAssertEqual(loaded.status, .stopped)
        XCTAssertEqual(loaded.metrics.totalBytes, 4_000_000_000)
        XCTAssertEqual(loaded.metrics.selectedBytes, 3_000_000_000)
    }

    /// A list saved before the sizes were kept opens as before, without them.
    func testListWithoutSizesLoadsAsBefore() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }
        try writeSession([sessionRecord()], schemaVersion: SessionSnapshot.currentSchemaVersion, to: bundle.directories)
        let json = try String(contentsOf: bundle.directories.sessionSnapshotURL, encoding: .utf8)
        XCTAssertFalse(json.contains("totalBytes"))

        bundle.store.bootstrapRuntimeState()
        let didLoad = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            !bundle.store.isRestoringSession && bundle.store.torrents.count == 1
        }

        XCTAssertTrue(didLoad)
        XCTAssertNil(bundle.store.sessionLoadIssue)
        XCTAssertEqual(bundle.store.torrents.first?.metrics.totalBytes, 0)
        XCTAssertEqual(bundle.store.torrents.first?.metrics.selectedBytes, 0)
    }

    /// An older Shatl reads the list with JSONDecoder, which skips keys it
    /// does not know: the sizes do not stop it from opening the list.
    func testFieldsAnOlderReaderDoesNotKnowAreSkipped() throws {
        struct OlderRecord: Decodable {
            var torrentID: UUID
            var originalName: String
            var progress: Double
        }
        var record = sessionRecord()
        record.totalBytes = 4_000_000_000
        record.selectedBytes = 3_000_000_000
        let data = try JSONEncoder().encode(record)

        let older = try JSONDecoder().decode(OlderRecord.self, from: data)
        XCTAssertEqual(older.originalName, record.originalName)
    }

    // MARK: - Helpers

    private func sessionRecord() -> SessionTorrentRecord {
        SessionTorrentRecord(
            torrentID: UUID(),
            attemptID: UUID(),
            infoHash: "sleeping-card-size",
            originalName: "Stopped Download",
            alias: nil,
            status: .stopped,
            progress: 0.4,
            canonicalSavePath: FileManager.default.temporaryDirectory.path,
            stopAfterDownload: false,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            archivedTorrentRelativePath: "Torrents/stopped.torrent",
            materializedSelectionFootprint: nil,
            persistentIssue: nil
        )
    }

    private func writeSession(
        _ records: [SessionTorrentRecord],
        schemaVersion: Int,
        to directories: ShatlDirectories
    ) throws {
        try directories.ensureSessionDirectories()
        let snapshot = SessionSnapshot(schemaVersion: schemaVersion, savedAt: Date(), torrents: records)
        try JSONEncoder().encode(snapshot).write(to: directories.sessionSnapshotURL, options: .atomic)
    }
}
