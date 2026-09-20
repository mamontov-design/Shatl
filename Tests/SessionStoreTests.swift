// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

final class SessionStoreTests: XCTestCase {
    func testSaveAndLoadPreservesPartialSelection() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let archiveStore = TorrentArchiveStore(directories: directories)
        let bookmarkStore = BookmarkStore(directories: directories)
        let resumeDataStore = ResumeDataStore(directories: directories)
        let sessionStore = SessionStore(
            directories: directories,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore,
            resumeDataStore: resumeDataStore,
            startupMode: .alreadyInitialized
        )

        let record = makeTestRecord(
            selectedFileIndices: [1, 3, 5],
            selectedFileRelativePaths: [
                "Season 1/Episode 01.mkv",
                "Season 1/Episode 03.mkv",
                "Season 1/Episode 05.mkv"
            ],
            selectedFileCount: 3,
            totalFileCount: 16,
            progress: 0.4
        )

        await sessionStore.replaceAllRecordsForTesting(from: [record])
        let loadedSnapshot = await sessionStore.load().snapshot
        let unwrappedSnapshot = try XCTUnwrap(loadedSnapshot)
        let loadedRecord = try XCTUnwrap(unwrappedSnapshot.torrents.first)

        XCTAssertEqual(loadedRecord.selectedFileIndices, [1, 3, 5])
        XCTAssertEqual(
            loadedRecord.selectedFileRelativePaths,
            [
                "Season 1/Episode 01.mkv",
                "Season 1/Episode 03.mkv",
                "Season 1/Episode 05.mkv"
            ]
        )
        XCTAssertEqual(loadedRecord.selectedFileCount, 3)
        XCTAssertEqual(loadedRecord.totalFileCount, 16)
        XCTAssertEqual(loadedRecord.progress, 0.4, accuracy: 0.0001)
    }

    func testSaveNormalizesRuntimeOnlyErrorStatusButKeepsPersistentIssueError() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let archiveStore = TorrentArchiveStore(directories: directories)
        let bookmarkStore = BookmarkStore(directories: directories)
        let resumeDataStore = ResumeDataStore(directories: directories)
        let sessionStore = SessionStore(
            directories: directories,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore,
            resumeDataStore: resumeDataStore,
            startupMode: .alreadyInitialized
        )

        let runtimeIncompleteRecord = makeTestRecord(
            status: .error,
            progress: 0.4,
            runtimeErrorState: ShatlErrorCatalog.runtimeSnapshotError(debugReason: "runtime failure")
        )
        let runtimeCompletedRecord = makeTestRecord(
            status: .error,
            progress: 1.0,
            runtimeErrorState: ShatlErrorCatalog.runtimeSnapshotError(debugReason: "runtime failure")
        )
        let persistentIssueRecord = makeTestRecord(
            status: .error,
            progress: 0.6,
            persistentIssue: TorrentPersistentIssue(
                kind: .savePathUnavailable,
                detectedAt: Date(),
                statusBeforeIssue: .downloading,
                debugReason: "bookmark lost"
            )
        )

        await sessionStore.replaceAllRecordsForTesting(
            from: [runtimeIncompleteRecord, runtimeCompletedRecord, persistentIssueRecord]
        )

        let loadedSnapshot = await sessionStore.load().snapshot
        let unwrappedSnapshot = try XCTUnwrap(loadedSnapshot)
        let statusesByID = Dictionary(
            uniqueKeysWithValues: unwrappedSnapshot.torrents.map { ($0.torrentID, $0.status) }
        )

        XCTAssertEqual(statusesByID[runtimeIncompleteRecord.id], .stopped)
        XCTAssertEqual(statusesByID[runtimeCompletedRecord.id], .completed)
        XCTAssertEqual(statusesByID[persistentIssueRecord.id], .error)
    }

    func testSavePrunesOrphanedResumeDataFiles() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let archiveStore = TorrentArchiveStore(directories: directories)
        let bookmarkStore = BookmarkStore(directories: directories)
        let resumeDataStore = ResumeDataStore(directories: directories)
        let sessionStore = SessionStore(
            directories: directories,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore,
            resumeDataStore: resumeDataStore,
            startupMode: .alreadyInitialized
        )

        let validRecord = makeTestRecord()
        let orphanID = UUID()
        try directories.ensureSessionDirectories()
        let validResumeURL = directories.resumeDataDirectoryURL
            .appendingPathComponent("\(validRecord.id.uuidString).fastresume", isDirectory: false)
        let orphanResumeURL = directories.resumeDataDirectoryURL
            .appendingPathComponent("\(orphanID.uuidString).fastresume", isDirectory: false)

        try Data("valid".utf8).write(to: validResumeURL, options: .atomic)
        try Data("orphan".utf8).write(to: orphanResumeURL, options: .atomic)

        await sessionStore.replaceAllRecordsForTesting(from: [validRecord])

        XCTAssertTrue(FileManager.default.fileExists(atPath: validResumeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanResumeURL.path))
    }

    func testAddLeaseProtectsArchiveAndUpdateCannotChangeMembership() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let archiveStore = TorrentArchiveStore(directories: directories)
        let bookmarkStore = BookmarkStore(directories: directories)
        let resumeDataStore = ResumeDataStore(directories: directories)
        let existingRecord = makeTestRecord(originalName: "Existing", progress: 0.41)
        let addedRecord = makeTestRecord(originalName: "Added", progress: 0.0)
        let sessionStore = SessionStore(
            directories: directories,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore,
            resumeDataStore: resumeDataStore,
            startupMode: .alreadyInitialized,
            initialRecords: [existingRecord]
        )

        let initialFlushOutcome = await sessionStore.flush()
        XCTAssertEqual(initialFlushOutcome, .saved)
        let pendingLease = await sessionStore.beginAdd(torrentID: addedRecord.id)
        let lease = try XCTUnwrap(pendingLease)
        let addedArchiveURL = try await archiveStore.destinationURL(for: addedRecord.id)
        try Data("added".utf8).write(to: addedArchiveURL, options: .atomic)

        let orphanArchiveURL = directories.archivedTorrentsDirectoryURL
            .appendingPathComponent("\(UUID().uuidString).torrent", isDirectory: false)
        try Data("orphan".utf8).write(to: orphanArchiveURL, options: .atomic)

        let reconciliationOutcome = await sessionStore.reconcileOrphanedArtifacts()
        XCTAssertEqual(reconciliationOutcome, .saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: addedArchiveURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanArchiveURL.path))
        let addOutcome = await sessionStore.commitAdd(addedRecord, lease: lease)
        XCTAssertEqual(addOutcome, .saved)

        var progressedExistingRecord = existingRecord
        progressedExistingRecord.progress = 0.42
        let updateOutcome = await sessionStore.updateExisting(from: [progressedExistingRecord])
        XCTAssertEqual(updateOutcome, .saved)

        let loadedSnapshot = await sessionStore.load().snapshot
        let snapshot = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(
            Set(snapshot.torrents.map(\.torrentID)),
            Set([existingRecord.id, addedRecord.id])
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: addedArchiveURL.path))
    }

    func testUpdateExistingDoesNotReconcileUnrelatedArtifacts() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let record = makeTestRecord(progress: 0.41)
        let sessionStore = SessionStore(
            directories: directories,
            archiveStore: TorrentArchiveStore(directories: directories),
            bookmarkStore: BookmarkStore(directories: directories),
            resumeDataStore: ResumeDataStore(directories: directories),
            startupMode: .alreadyInitialized,
            initialRecords: [record]
        )

        let initialFlushOutcome = await sessionStore.flush()
        XCTAssertEqual(initialFlushOutcome, .saved)
        let orphanResumeURL = directories.resumeDataDirectoryURL
            .appendingPathComponent("\(UUID().uuidString).fastresume", isDirectory: false)
        try Data("orphan".utf8).write(to: orphanResumeURL, options: .atomic)

        var progressedRecord = record
        progressedRecord.progress = 0.42
        let updateOutcome = await sessionStore.updateExisting(from: [progressedRecord])
        XCTAssertEqual(updateOutcome, .saved)

        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanResumeURL.path))
    }

    func testSavingUnchangedDurableStateDoesNotRewriteSessionFile() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let sessionStore = SessionStore(
            directories: directories,
            archiveStore: TorrentArchiveStore(directories: directories),
            bookmarkStore: BookmarkStore(directories: directories),
            resumeDataStore: ResumeDataStore(directories: directories),
            startupMode: .alreadyInitialized
        )
        let record = makeTestRecord(status: .stopped, progress: 0.42)

        let firstOutcome = await sessionStore.replaceAllRecordsForTesting(from: [record])
        XCTAssertEqual(firstOutcome, .saved)
        let firstData = try Data(contentsOf: directories.sessionSnapshotURL)

        let secondOutcome = await sessionStore.replaceAllRecordsForTesting(from: [record])
        XCTAssertEqual(secondOutcome, .saved)
        let secondData = try Data(contentsOf: directories.sessionSnapshotURL)

        XCTAssertEqual(secondData, firstData)
    }

    func testCleanFirstLaunchUnlocksOnlyAfterLoadIsAcceptedAndPersistsEmptySnapshot() async throws {
        let fixture = try makeFixture()

        let loadResult = await fixture.sessionStore.load()
        guard case .missing = loadResult else {
            return XCTFail("Expected a clean first launch")
        }

        let blockedOutcome = await fixture.sessionStore.replaceAllRecordsForTesting(from: [])
        XCTAssertEqual(blockedOutcome, .blocked)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directories.sessionSnapshotURL.path))

        await fixture.sessionStore.acceptInitialLoad()
        let savedOutcome = await fixture.sessionStore.replaceAllRecordsForTesting(from: [])
        XCTAssertEqual(savedOutcome, .saved)

        let data = try Data(contentsOf: fixture.directories.sessionSnapshotURL)
        let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        XCTAssertEqual(snapshot.schemaVersion, SessionSnapshot.currentSchemaVersion)
        XCTAssertTrue(snapshot.torrents.isEmpty)
    }

    func testValidEmptySnapshotLoadsAsSessionRatherThanMissingSession() async throws {
        let fixture = try makeFixture()
        try makeSnapshotData(torrents: []).write(
            to: fixture.directories.sessionSnapshotURL,
            options: .atomic
        )

        let result = await fixture.sessionStore.load()
        guard case let .loaded(snapshot) = result else {
            return XCTFail("Expected a valid saved session")
        }

        XCTAssertTrue(snapshot.torrents.isEmpty)
    }

    func testCorruptSnapshotsAreUnreadableAndRemainByteForByteUnchanged() async throws {
        let corruptPayloads = [
            Data(),
            Data(#"{"schemaVersion":5,"savedAt":"# .utf8),
            Data(#"{"schemaVersion":5,"savedAt":0,"torrents":"not-an-array"}"# .utf8),
        ]

        for corruptData in corruptPayloads {
            let fixture = try makeFixture()
            try corruptData.write(to: fixture.directories.sessionSnapshotURL, options: .atomic)
            let artifactURLs = try writeRecoveryArtifacts(in: fixture.directories)
            let artifactData = try artifactURLs.map { try Data(contentsOf: $0) }

            let result = await fixture.sessionStore.load()
            XCTAssertEqual(loadIssue(from: result), .unreadable)
            let criticalOutcome = await fixture.sessionStore.replaceAllRecordsForTesting(from: [])
            let progressOutcome = await fixture.sessionStore.updateExisting(from: [makeTestRecord()])
            XCTAssertEqual(criticalOutcome, .blocked)
            XCTAssertEqual(progressOutcome, .blocked)
            XCTAssertEqual(try Data(contentsOf: fixture.directories.sessionSnapshotURL), corruptData)
            for (url, originalData) in zip(artifactURLs, artifactData) {
                XCTAssertEqual(try Data(contentsOf: url), originalData)
            }
        }
    }

    func testUnsupportedSchemaIsReportedAndNotOverwritten() async throws {
        let fixture = try makeFixture()
        let unsupportedData = Data(#"{"schemaVersion":999,"savedAt":0,"torrents":[]}"# .utf8)
        try unsupportedData.write(to: fixture.directories.sessionSnapshotURL, options: .atomic)

        let result = await fixture.sessionStore.load()

        XCTAssertEqual(loadIssue(from: result), .unsupportedVersion(found: 999))
        let saveOutcome = await fixture.sessionStore.replaceAllRecordsForTesting(from: [])
        XCTAssertEqual(saveOutcome, .blocked)
        XCTAssertEqual(try Data(contentsOf: fixture.directories.sessionSnapshotURL), unsupportedData)
    }

    func testReadFailureIsReportedAndBlocksSaving() async throws {
        enum ExpectedReadError: Error { case denied }

        let fixture = try makeFixture(readSessionData: { _ in throw ExpectedReadError.denied })
        let originalData = makeSnapshotData(torrents: [])
        try originalData.write(to: fixture.directories.sessionSnapshotURL, options: .atomic)

        let result = await fixture.sessionStore.load()

        XCTAssertEqual(loadIssue(from: result), .unreadable)
        let saveOutcome = await fixture.sessionStore.replaceAllRecordsForTesting(from: [])
        XCTAssertEqual(saveOutcome, .blocked)
        XCTAssertEqual(try Data(contentsOf: fixture.directories.sessionSnapshotURL), originalData)
    }

    func testMissingSnapshotWithAnyRecoveryArtifactIsNotTreatedAsCleanLaunch() async throws {
        let artifactLocations: [(KeyPath<ShatlDirectories, URL>, String)] = [
            (\.archivedTorrentsDirectoryURL, "orphan.torrent"),
            (\.bookmarksDirectoryURL, "orphan.bookmark"),
            (\.resumeDataDirectoryURL, "orphan.fastresume"),
        ]

        for (directoryPath, fileName) in artifactLocations {
            let fixture = try makeFixture()
            let artifactURL = fixture.directories[keyPath: directoryPath]
                .appendingPathComponent(fileName, isDirectory: false)
            let originalData = Data("must survive".utf8)
            try originalData.write(to: artifactURL, options: .atomic)

            let result = await fixture.sessionStore.load()

            XCTAssertEqual(loadIssue(from: result), .missingWithRecoveryArtifacts)
            let saveOutcome = await fixture.sessionStore.replaceAllRecordsForTesting(from: [])
            XCTAssertEqual(saveOutcome, .blocked)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directories.sessionSnapshotURL.path))
            XCTAssertEqual(try Data(contentsOf: artifactURL), originalData)
        }
    }

    func testMissingApplicationSupportForExistingInstallationIsNotTreatedAsCleanLaunch() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingApplicationSupport-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let sessionStore = makeSessionStore(directories: directories)

        let result = await sessionStore.load(expectsExistingSession: true)

        XCTAssertEqual(loadIssue(from: result), .missingWithRecoveryArtifacts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directories.applicationSupportURL.path))
        let saveOutcome = await sessionStore.replaceAllRecordsForTesting(from: [])
        XCTAssertEqual(saveOutcome, .blocked)
    }

    func testMissingRequiredSessionDirectoryBlocksLoadWithoutRecreatingIt() async throws {
        let fixture = try makeFixture()
        let snapshotData = makeSnapshotData(torrents: [])
        try snapshotData.write(to: fixture.directories.sessionSnapshotURL, options: .atomic)
        try FileManager.default.removeItem(at: fixture.directories.archivedTorrentsDirectoryURL)

        let result = await fixture.sessionStore.load(expectsExistingSession: true)

        XCTAssertEqual(loadIssue(from: result), .missingWithRecoveryArtifacts)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.directories.archivedTorrentsDirectoryURL.path
        ))
        let saveOutcome = await fixture.sessionStore.replaceAllRecordsForTesting(from: [])
        XCTAssertEqual(saveOutcome, .blocked)
        XCTAssertEqual(try Data(contentsOf: fixture.directories.sessionSnapshotURL), snapshotData)
    }

    func testRelaunchAfterLoadFailureRemainsBlocked() async throws {
        let fixture = try makeFixture()
        let corruptData = Data("broken session".utf8)
        try corruptData.write(to: fixture.directories.sessionSnapshotURL, options: .atomic)

        let firstLoadResult = await fixture.sessionStore.load()
        XCTAssertEqual(loadIssue(from: firstLoadResult), .unreadable)

        let relaunchedStore = makeSessionStore(directories: fixture.directories)
        let relaunchedLoadResult = await relaunchedStore.load()
        let relaunchedSaveOutcome = await relaunchedStore.replaceAllRecordsForTesting(from: [])
        XCTAssertEqual(loadIssue(from: relaunchedLoadResult), .unreadable)
        XCTAssertEqual(relaunchedSaveOutcome, .blocked)
        XCTAssertEqual(try Data(contentsOf: fixture.directories.sessionSnapshotURL), corruptData)
    }

    private struct Fixture {
        var rootURL: URL
        var directories: ShatlDirectories
        var sessionStore: SessionStore
    }

    private func makeFixture(
        readSessionData: @escaping @Sendable (URL) async throws -> Data = { url in
            try Data(contentsOf: url)
        }
    ) throws -> Fixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreSafetyTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        try directories.ensureSessionDirectories()
        return Fixture(
            rootURL: rootURL,
            directories: directories,
            sessionStore: makeSessionStore(
                directories: directories,
                readSessionData: readSessionData
            )
        )
    }

    private func makeSessionStore(
        directories: ShatlDirectories,
        readSessionData: @escaping @Sendable (URL) async throws -> Data = { url in
            try Data(contentsOf: url)
        }
    ) -> SessionStore {
        SessionStore(
            directories: directories,
            archiveStore: TorrentArchiveStore(directories: directories),
            bookmarkStore: BookmarkStore(directories: directories),
            resumeDataStore: ResumeDataStore(directories: directories),
            readSessionData: readSessionData
        )
    }

    private func makeSnapshotData(torrents: [SessionTorrentRecord]) -> Data {
        let snapshot = SessionSnapshot(
            schemaVersion: SessionSnapshot.currentSchemaVersion,
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            torrents: torrents
        )
        return try! JSONEncoder().encode(snapshot)
    }

    private func loadIssue(from result: SessionLoadResult) -> SessionLoadIssue? {
        guard case let .failure(issue) = result else { return nil }
        return issue
    }

    private func writeRecoveryArtifacts(in directories: ShatlDirectories) throws -> [URL] {
        let urls = [
            directories.archivedTorrentsDirectoryURL.appendingPathComponent("orphan.torrent"),
            directories.bookmarksDirectoryURL.appendingPathComponent("orphan.bookmark"),
            directories.resumeDataDirectoryURL.appendingPathComponent("orphan.fastresume"),
        ]
        for (index, url) in urls.enumerated() {
            try Data("artifact-\(index)".utf8).write(to: url, options: .atomic)
        }
        return urls
    }
}
