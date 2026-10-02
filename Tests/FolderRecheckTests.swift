// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// A download whose folder was unavailable stays in error even after the
/// folder is back: the issue is never re-checked on its own (by contract),
/// and Start is off on an error card. "Проверить снова" looks for the folder
/// again and returns the download to where it was, progress kept.
@MainActor
final class FolderRecheckTests: XCTestCase {
    private struct Fixture {
        let bundle: TestStoreBundle
        let engine: FakeTorrentEngine
        let record: TorrentRecord
        let folderURL: URL
    }

    /// A download at 40 % whose folder went missing; the folder and its file
    /// are on disk again unless `folderIsBack` is false.
    private func makeFixture(
        statusBeforeIssue: TorrentStatus = .downloading,
        folderIsBack: Bool = true,
        fileIsBack: Bool = true
    ) async throws -> Fixture {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShatlFolderRecheck-\(UUID().uuidString)", isDirectory: true)
        if folderIsBack {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            if fileIsBack {
                try Data(count: 1_024).write(to: folderURL.appendingPathComponent("test-file.bin"))
            }
        }
        let engine = FakeTorrentEngine()
        let record = makeTestRecord(
            savePath: folderURL.path,
            status: .error,
            progress: 0.4,
            persistentIssue: TorrentPersistentIssue(
                kind: .savePathUnavailable,
                detectedAt: Date(),
                statusBeforeIssue: statusBeforeIssue,
                debugReason: nil
            )
        )
        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folderURL)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        await bundle.sessionStore.replaceAllRecordsForTesting(from: [record])
        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        return Fixture(bundle: bundle, engine: engine, record: record, folderURL: folderURL)
    }

    /// The dead end this work removes: Start is off on an error card, so a
    /// folder that came back changes nothing.
    func testStartDoesNothingOnAnErrorCardEvenWithTheFolderBack() async throws {
        let fixture = try await makeFixture()

        fixture.bundle.store.startTorrent(id: fixture.record.id)
        try await Task.sleep(for: .milliseconds(200))

        let restoreCount = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCount, 0)
        XCTAssertEqual(fixture.bundle.store.torrents.first?.persistentIssue?.kind, .savePathUnavailable)
    }

    private func waitForRecheck(_ fixture: Fixture) async {
        _ = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            !fixture.bundle.store.transitioningTorrentIDs.contains(fixture.record.id)
        }
    }

    func testFolderBackResumesTheDownloadWithItsProgress() async throws {
        let fixture = try await makeFixture(statusBeforeIssue: .downloading)

        fixture.bundle.store.recheckUnavailableFolder(id: fixture.record.id)
        await waitForRecheck(fixture)

        let record = try XCTUnwrap(fixture.bundle.store.torrents.first)
        XCTAssertNil(record.persistentIssue)
        XCTAssertNotEqual(record.status, .error)
        let entries = await fixture.engine.recordedRestoreSessionEntries()
        XCTAssertEqual(entries.count, 1)
        // A resume, not a fresh download: the same attempt, started.
        XCTAssertEqual(entries.first?.attemptID, fixture.record.attemptID)
        XCTAssertEqual(entries.first?.shouldStart, true)
        XCTAssertGreaterThanOrEqual(record.progress, 0.4)
    }

    /// Manual Start stays manual: a download stopped before the error is
    /// stopped again, not started.
    func testFolderBackLeavesAStoppedDownloadStopped() async throws {
        let fixture = try await makeFixture(statusBeforeIssue: .stopped)

        fixture.bundle.store.recheckUnavailableFolder(id: fixture.record.id)
        await waitForRecheck(fixture)

        let record = try XCTUnwrap(fixture.bundle.store.torrents.first)
        XCTAssertNil(record.persistentIssue)
        XCTAssertEqual(record.status, .stopped)
        let restoreCount = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCount, 0)
    }

    func testFolderStillMissingKeepsTheError() async throws {
        let fixture = try await makeFixture(folderIsBack: false)

        fixture.bundle.store.recheckUnavailableFolder(id: fixture.record.id)
        await waitForRecheck(fixture)

        XCTAssertEqual(fixture.bundle.store.torrents.first?.persistentIssue?.kind, .savePathUnavailable)
        let restoreCount = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCount, 0)
    }

    /// Another disk with a folder of the same name: the folder is back, its
    /// files are not, and the card says so.
    func testFolderBackWithoutTheFilesShowsMissingFiles() async throws {
        let fixture = try await makeFixture(fileIsBack: false)

        fixture.bundle.store.recheckUnavailableFolder(id: fixture.record.id)
        await waitForRecheck(fixture)

        XCTAssertEqual(fixture.bundle.store.torrents.first?.persistentIssue?.kind, .missingContent)
        let restoreCount = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCount, 0)
    }

    /// The button shows "Проверка…" for at least a second, and a second
    /// press meanwhile does nothing.
    func testRecheckShowsCheckingAndIgnoresASecondPress() async throws {
        let fixture = try await makeFixture(statusBeforeIssue: .downloading)
        let store = fixture.bundle.store

        store.recheckUnavailableFolder(id: fixture.record.id)
        store.recheckUnavailableFolder(id: fixture.record.id)
        XCTAssertEqual(store.rowState(for: fixture.record.id)?.isRecovering, true)

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(store.transitioningTorrentIDs.contains(fixture.record.id))

        await waitForRecheck(fixture)
        let restoreCount = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCount, 1)
    }

    /// A folder renamed in Finder is found through its bookmark, and the
    /// download's path follows it.
    func testRenamedFolderIsFoundAndThePathFollows() async throws {
        let fixture = try await makeFixture(statusBeforeIssue: .stopped)
        await fixture.bundle.bookmarkStore.saveBookmark(for: fixture.record.id, url: fixture.folderURL)
        let renamedURL = fixture.folderURL.deletingLastPathComponent()
            .appendingPathComponent("Renamed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: fixture.folderURL, to: renamedURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: renamedURL) }

        fixture.bundle.store.recheckUnavailableFolder(id: fixture.record.id)
        await waitForRecheck(fixture)

        let record = try XCTUnwrap(fixture.bundle.store.torrents.first)
        XCTAssertNil(record.persistentIssue)
        XCTAssertEqual(
            URL(fileURLWithPath: record.canonicalSavePath).resolvingSymlinksInPath().path,
            renamedURL.resolvingSymlinksInPath().path
        )
    }
}
