// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// A download with no room on its disk is saved to the list instead of
/// started: stopped, past the engine, and started by hand only once it fits.
@MainActor
final class SavedDownloadTests: XCTestCase {
    private static let megabyte: Int64 = 1_000_000
    /// The two ticked files of `makeDraft`.
    private static let selectedBytes = 1_000 * megabyte

    private struct Fixture {
        let bundle: TestStoreBundle
        let engine: FakeTorrentEngine
        let disk: FakeDiskSpaceReader
        let saveURL: URL

        var store: AppStore { bundle.store }
    }

    private func makeFixture(availableBytes: Int64 = 100 * megabyte) throws -> Fixture {
        let engine = FakeTorrentEngine()
        let disk = FakeDiskSpaceReader(availableBytes: availableBytes)
        let bundle = makeTestStoreBundle(engine: engine, diskSpaceReader: disk)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        let saveURL = bundle.rootURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveURL, withIntermediateDirectories: true)
        return Fixture(bundle: bundle, engine: engine, disk: disk, saveURL: saveURL)
    }

    private func makeDraft(savePath: String) -> AddTorrentDraft {
        AddTorrentDraft(
            source: AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/northstar.torrent"),
            originalName: "Northstar",
            infoHash: "northstar-info-hash",
            suggestedSavePath: savePath,
            alias: "",
            stopAfterDownload: true,
            files: [
                AddTorrentFileOption(name: "Northstar/A.bin", sizeBytes: 600 * Self.megabyte, fileIndex: 0, isSelected: true),
                AddTorrentFileOption(name: "Northstar/B.bin", sizeBytes: 400 * Self.megabyte, fileIndex: 1, isSelected: true),
                AddTorrentFileOption(name: "Northstar/C.bin", sizeBytes: 50 * Self.megabyte, fileIndex: 2, isSelected: false),
            ],
            reviewState: .ready,
            errorState: nil
        )
    }

    /// Saves the draft to the list and waits for its card.
    private func saveDraft(in fixture: Fixture) async throws -> UUID {
        fixture.store.currentAddTorrentDraft = makeDraft(savePath: fixture.saveURL.path)
        fixture.store.saveDraftToList()

        let didSave = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            fixture.store.torrents.count == 1
        }
        XCTAssertTrue(didSave)
        return try XCTUnwrap(fixture.store.torrents.first?.id)
    }

    private func record(_ id: UUID, in fixture: Fixture) throws -> TorrentRecord {
        try XCTUnwrap(fixture.store.torrents.first(where: { $0.id == id }))
    }

    private func savedSessionRecord(in fixture: Fixture) throws -> SessionTorrentRecord {
        let data = try Data(contentsOf: fixture.bundle.directories.sessionSnapshotURL)
        return try XCTUnwrap(JSONDecoder().decode(SessionSnapshot.self, from: data).torrents.first)
    }

    func testSavingToListSkipsTheEngineAndKeepsTheDownloadStopped() async throws {
        let fixture = try makeFixture()
        let id = try await saveDraft(in: fixture)

        let addCalls = await fixture.engine.addCallCount()
        let restoreCalls = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(addCalls, 0)
        XCTAssertEqual(restoreCalls, 0)

        let saved = try record(id, in: fixture)
        XCTAssertEqual(saved.status, .stopped)
        XCTAssertTrue(saved.isSavedForLater)
        XCTAssertEqual(saved.progress, 0)
        XCTAssertEqual(saved.infoHash, "northstar-info-hash")
        XCTAssertEqual(saved.canonicalSavePath, fixture.saveURL.path)
        XCTAssertEqual(saved.selectedFileIndices, [0, 1])
        XCTAssertEqual(saved.selectedFileRelativePaths, ["Northstar/A.bin", "Northstar/B.bin"])
        XCTAssertEqual(saved.selectedFileCount, 2)
        XCTAssertEqual(saved.totalFileCount, 3)
        XCTAssertEqual(saved.metrics.selectedBytes, Self.selectedBytes)
        XCTAssertEqual(saved.metrics.totalBytes, 1_050 * Self.megabyte)
        XCTAssertTrue(saved.stopAfterDownload)

        // What a later Start needs: the torrent itself and the list entry.
        let archiveURL = try await fixture.bundle.archiveStore.destinationURL(for: id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        let sessionRecord = try savedSessionRecord(in: fixture)
        XCTAssertEqual(sessionRecord.torrentID, id)
        XCTAssertEqual(sessionRecord.status, .stopped)
        XCTAssertEqual(sessionRecord.savedForLater, true)
        XCTAssertEqual(sessionRecord.selectedBytes, Self.selectedBytes)

        // Nothing of the download is on the disk that had no room.
        let contents = try FileManager.default.contentsOfDirectory(atPath: fixture.saveURL.path)
        XCTAssertTrue(contents.isEmpty)
    }

    func testSavedDownloadLooksSavedAndNotStopped() async throws {
        let fixture = try makeFixture()
        let id = try await saveDraft(in: fixture)

        let row = try XCTUnwrap(fixture.store.rowState(for: id))
        XCTAssertTrue(row.isSavedForLater)
        XCTAssertEqual(row.status, .stopped)
        XCTAssertEqual(
            row.statusTitle,
            L10n.string("torrent.status.saved", localeOverride: fixture.store.preferences.localeOverride)
        )
        XCTAssertTrue(row.canToggleRunningState)
    }

    func testOrdinaryListEntryCarriesNoSavedMark() throws {
        let data = try JSONEncoder().encode(
            SessionTorrentRecord(
                torrentID: UUID(),
                attemptID: UUID(),
                infoHash: "plain",
                originalName: "Plain",
                alias: nil,
                status: .stopped,
                progress: 0,
                canonicalSavePath: "/tmp",
                stopAfterDownload: false,
                selectedFileIndices: [0],
                selectedFileCount: 1,
                totalFileCount: 1,
                archivedTorrentRelativePath: "Torrents/plain.torrent",
                materializedSelectionFootprint: nil,
                persistentIssue: nil
            )
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["savedForLater"])
        XCTAssertNil(try JSONDecoder().decode(SessionTorrentRecord.self, from: data).savedForLater)
    }

    func testSavedDownloadSurvivesRelaunch() async throws {
        let fixture = try makeFixture()
        let id = try await saveDraft(in: fixture)

        let relaunchedEngine = FakeTorrentEngine()
        let relaunched = makeTestStoreBundle(
            engine: relaunchedEngine,
            router: ExternalOpenRouter(),
            sessionStoreStartupMode: .requiresInitialLoad
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: relaunched.rootURL)
        }
        let source = fixture.bundle.directories.applicationSupportURL
        let destination = relaunched.directories.applicationSupportURL
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: destination)

        relaunched.store.bootstrapRuntimeState()
        let didLoad = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            relaunched.store.torrents.count == 1 && !relaunched.store.isRestoringSession
        }
        XCTAssertTrue(didLoad)

        let restored = try XCTUnwrap(relaunched.store.torrents.first)
        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.status, .stopped)
        XCTAssertTrue(restored.isSavedForLater)
        XCTAssertEqual(restored.metrics.selectedBytes, Self.selectedBytes)
        XCTAssertTrue(try XCTUnwrap(relaunched.store.rowState(for: id)).isSavedForLater)
        // A stopped download stays stopped after a relaunch.
        let restoreCalls = await relaunchedEngine.restoreSessionCallCount()
        XCTAssertEqual(restoreCalls, 0)
    }

    func testStartWithRoomStartsTheDownloadAndEndsItsSavedState() async throws {
        let fixture = try makeFixture()
        let id = try await saveDraft(in: fixture)
        fixture.disk.setAvailableBytes(Self.selectedBytes)

        fixture.store.startTorrent(id: id)

        let didStart = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            fixture.store.torrents.first?.isSavedForLater == false
        }
        XCTAssertTrue(didStart)
        let entries = await fixture.engine.recordedRestoreSessionEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.torrentID, id)
        XCTAssertEqual(entries.first?.selectedFileIndices, [0, 1])
        XCTAssertEqual(entries.first?.suggestedSavePath, fixture.saveURL.path)
        XCTAssertEqual(entries.first?.shouldStart, true)

        let started = try record(id, in: fixture)
        XCTAssertNil(started.errorState)
        XCTAssertFalse(try XCTUnwrap(fixture.store.rowState(for: id)).isSavedForLater)

        // The list no longer carries the mark either.
        let didPersist = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            (try? self.savedSessionRecord(in: fixture).savedForLater) == .some(nil)
        }
        XCTAssertTrue(didPersist)
    }

    func testStartWithoutRoomSaysWhatTheDiskLacksAndWritesNothing() async throws {
        let fixture = try makeFixture(availableBytes: 100 * Self.megabyte)
        let id = try await saveDraft(in: fixture)

        fixture.store.startTorrent(id: id)

        let didReport = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            fixture.store.torrents.first?.runtimeErrorState?.kind == .notEnoughSpace
                && !fixture.store.transitioningTorrentIDs.contains(id)
        }
        XCTAssertTrue(didReport)

        let blocked = try record(id, in: fixture)
        XCTAssertTrue(blocked.isSavedForLater)
        XCTAssertEqual(blocked.status, .error)
        XCTAssertEqual(
            blocked.runtimeErrorState?.recoveryOptions,
            [.retry, .chooseAnotherFolder, .removeFromList]
        )
        XCTAssertEqual(
            blocked.runtimeErrorState?.spaceCheck,
            DiskSpaceCheck(
                neededBytes: Self.selectedBytes,
                availableBytes: 100 * Self.megabyte,
                volumeName: "Test Disk"
            )
        )

        let restoreCalls = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCalls, 0)
        let contents = try FileManager.default.contentsOfDirectory(atPath: fixture.saveURL.path)
        XCTAssertTrue(contents.isEmpty)

        // The card names the disk and the 900 MB it lacks.
        let message = try XCTUnwrap(fixture.store.rowState(for: id)?.errorState?.message)
        XCTAssertTrue(message.contains("Test Disk"), message)
        XCTAssertTrue(message.contains("900"), message)
    }

    func testRetryStartsOnlyOnceTheDiskHasRoom() async throws {
        let fixture = try makeFixture(availableBytes: 100 * Self.megabyte)
        let id = try await saveDraft(in: fixture)
        fixture.store.startTorrent(id: id)
        let didReport = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            fixture.store.torrents.first?.runtimeErrorState?.kind == .notEnoughSpace
                && !fixture.store.transitioningTorrentIDs.contains(id)
        }
        XCTAssertTrue(didReport)

        // Still no room: the card keeps its error and nothing starts.
        fixture.disk.setAvailableBytes(500 * Self.megabyte)
        fixture.store.retryAfterRuntimeError(id: id)
        let didFinishFirstRetry = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            !fixture.store.transitioningTorrentIDs.contains(id)
        }
        XCTAssertTrue(didFinishFirstRetry)
        var restoreCalls = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCalls, 0)
        XCTAssertEqual(
            try record(id, in: fixture).runtimeErrorState?.spaceCheck?.availableBytes,
            500 * Self.megabyte
        )

        fixture.disk.setAvailableBytes(2 * Self.selectedBytes)
        fixture.store.retryAfterRuntimeError(id: id)
        let didStart = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            fixture.store.torrents.first?.isSavedForLater == false
                && fixture.store.torrents.first?.errorState == nil
        }
        XCTAssertTrue(didStart)
        restoreCalls = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCalls, 1)
    }

    func testAnotherFolderIsCheckedOnItsOwnDisk() async throws {
        let fixture = try makeFixture(availableBytes: 100 * Self.megabyte)
        let id = try await saveDraft(in: fixture)
        fixture.store.startTorrent(id: id)
        let didReport = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            fixture.store.torrents.first?.runtimeErrorState?.kind == .notEnoughSpace
                && !fixture.store.transitioningTorrentIDs.contains(id)
        }
        XCTAssertTrue(didReport)

        // A folder on a disk as full: the download moves there and waits.
        let crampedURL = fixture.bundle.rootURL.appendingPathComponent("Cramped", isDirectory: true)
        try FileManager.default.createDirectory(at: crampedURL, withIntermediateDirectories: true)
        fixture.disk.setAvailableBytes(200 * Self.megabyte, volumeName: "Cramped Disk", atPath: crampedURL.path)
        fixture.store.redownloadTorrent(id: id, toSaveLocation: crampedURL, bookmarkData: nil)
        let didMove = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            fixture.store.torrents.first?.canonicalSavePath == crampedURL.path
                && !fixture.store.transitioningTorrentIDs.contains(id)
        }
        XCTAssertTrue(didMove)
        var restoreCalls = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCalls, 0)
        let waiting = try record(id, in: fixture)
        XCTAssertTrue(waiting.isSavedForLater)
        XCTAssertEqual(waiting.runtimeErrorState?.spaceCheck?.volumeName, "Cramped Disk")

        // A folder on a disk with room: the download starts there.
        let roomyURL = fixture.bundle.rootURL.appendingPathComponent("Roomy", isDirectory: true)
        try FileManager.default.createDirectory(at: roomyURL, withIntermediateDirectories: true)
        fixture.disk.setAvailableBytes(5 * Self.selectedBytes, volumeName: "Roomy Disk", atPath: roomyURL.path)
        fixture.store.redownloadTorrent(id: id, toSaveLocation: roomyURL, bookmarkData: nil)
        let didStart = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            fixture.store.torrents.first?.isSavedForLater == false
                && fixture.store.torrents.first?.errorState == nil
        }
        XCTAssertTrue(didStart)
        restoreCalls = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCalls, 1)
        let entries = await fixture.engine.recordedRestoreSessionEntries()
        XCTAssertEqual(entries.first?.suggestedSavePath, roomyURL.path)
        XCTAssertEqual(try record(id, in: fixture).canonicalSavePath, roomyURL.path)
    }

    func testSavingTheSameDownloadAgainIsRefused() async throws {
        let fixture = try makeFixture()
        _ = try await saveDraft(in: fixture)

        fixture.store.currentAddTorrentDraft = makeDraft(savePath: fixture.saveURL.path)
        fixture.store.saveDraftToList()

        XCTAssertEqual(fixture.store.currentAddTorrentDraft?.errorState?.kind, .duplicateTorrent)
        XCTAssertEqual(fixture.store.torrents.count, 1)
    }

    /// Only a saved download asks its disk before Start; a stopped one
    /// starts as it always did.
    func testOrdinaryStoppedDownloadStartsWithoutAskingTheDisk() async throws {
        let engine = FakeTorrentEngine()
        let disk = FakeDiskSpaceReader(availableBytes: 1)
        let stopped = makeTestRecord(status: .stopped, progress: 0)
        let bundle = makeTestStoreBundle(engine: engine, torrents: [stopped], diskSpaceReader: disk)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.startTorrent(id: stopped.id)

        let didAttemptStart = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            !bundle.store.transitioningTorrentIDs.contains(stopped.id)
        }
        XCTAssertTrue(didAttemptStart)
        XCTAssertNotEqual(bundle.store.torrents.first?.runtimeErrorState?.kind, .notEnoughSpace)
    }

    func testInfoOfSavedDownloadAnswersWhetherItFitsNow() async throws {
        let fixture = try makeFixture(availableBytes: 100 * Self.megabyte)
        let id = try await saveDraft(in: fixture)

        let short = await fixture.store.savedDownloadSpaceStatus(for: id)
        XCTAssertEqual(
            short,
            .known(DiskSpaceCheck(
                neededBytes: Self.selectedBytes,
                availableBytes: 100 * Self.megabyte,
                volumeName: "Test Disk"
            ))
        )

        fixture.disk.setAvailableBytes(3 * Self.selectedBytes)
        let fits = await fixture.store.savedDownloadSpaceStatus(for: id)
        guard case let .known(check) = fits else {
            return XCTFail("The disk answered, so the status is known")
        }
        XCTAssertTrue(check.fits)

        // A disk unplugged says nothing; the popover names the folder.
        fixture.disk.setAvailableBytes(nil)
        let unknown = await fixture.store.savedDownloadSpaceStatus(for: id)
        XCTAssertEqual(unknown, .unknown(folderName: "Downloads"))
    }
}
