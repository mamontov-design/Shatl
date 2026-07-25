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
            resumeDataStore: resumeDataStore
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

        await sessionStore.saveCriticalState(from: [record])
        let loadedSnapshot = await sessionStore.load()
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
            resumeDataStore: resumeDataStore
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

        await sessionStore.saveCriticalState(
            from: [runtimeIncompleteRecord, runtimeCompletedRecord, persistentIssueRecord]
        )

        let loadedSnapshot = await sessionStore.load()
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
            resumeDataStore: resumeDataStore
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

        await sessionStore.saveCriticalState(from: [validRecord])

        XCTAssertTrue(FileManager.default.fileExists(atPath: validResumeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanResumeURL.path))
    }
}
