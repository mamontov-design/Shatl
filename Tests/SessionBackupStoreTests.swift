// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

final class SessionBackupStoreTests: XCTestCase {
    func testCreatesVerifiedCompleteBackup() async throws {
        let fixture = try await makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let status = await fixture.backupStore.createBackup()
        guard case .current(let details) = status else {
            return XCTFail("Expected a current backup, got \(status)")
        }

        XCTAssertEqual(details.torrentCount, 1)
        let backupURL = fixture.backupParentURL
            .appendingPathComponent(SessionBackupStore.directoryName, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.appendingPathComponent("session.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: backupURL.appendingPathComponent("Torrents/\(fixture.record.id.uuidString).torrent").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: backupURL.appendingPathComponent("Bookmarks/\(fixture.record.id.uuidString).bookmark").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: backupURL.appendingPathComponent("ResumeData/\(fixture.record.id.uuidString).fastresume").path
        ))
    }

    func testReplacesSingleBackupAndRemovesDeletedTorrentArtifacts() async throws {
        let fixture = try await makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture.rootURL) }

        _ = await fixture.backupStore.createBackup()
        _ = await fixture.sessionStore.saveCriticalState(from: [])
        let status = await fixture.backupStore.createBackup()

        guard case .current(let details) = status else {
            return XCTFail("Expected a current backup, got \(status)")
        }
        XCTAssertEqual(details.torrentCount, 0)

        let backupURL = fixture.backupParentURL
            .appendingPathComponent(SessionBackupStore.directoryName, isDirectory: true)
        let torrentURL = backupURL.appendingPathComponent(
            "Torrents/\(fixture.record.id.uuidString).torrent"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: torrentURL.path))

        let backupItems = try FileManager.default.contentsOfDirectory(
            at: fixture.backupParentURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(
            backupItems.filter { $0.lastPathComponent.hasPrefix(SessionBackupStore.directoryName) }.count,
            1
        )
    }

    func testDetectsDamagedBackupWithoutChangingPrimarySession() async throws {
        let fixture = try await makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture.rootURL) }

        _ = await fixture.backupStore.createBackup()
        let primaryData = try Data(contentsOf: fixture.directories.sessionSnapshotURL)
        let backupSessionURL = fixture.backupParentURL
            .appendingPathComponent(SessionBackupStore.directoryName, isDirectory: true)
            .appendingPathComponent("session.json")
        try Data("damaged".utf8).write(to: backupSessionURL)

        let status = await fixture.backupStore.inspect()
        guard case .stale(_, let issue) = status else {
            return XCTFail("Expected damaged backup status, got \(status)")
        }
        XCTAssertEqual(issue, .invalidBackup)
        XCTAssertEqual(try Data(contentsOf: fixture.directories.sessionSnapshotURL), primaryData)
    }

    func testReportsValidBackupAsOutOfDateAfterPrimarySessionChanges() async throws {
        let fixture = try await makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture.rootURL) }

        _ = await fixture.backupStore.createBackup()
        _ = await fixture.sessionStore.saveCriticalState(from: [])

        let status = await fixture.backupStore.inspect()
        guard case .stale(let details, let issue) = status else {
            return XCTFail("Expected an out-of-date backup, got \(status)")
        }
        XCTAssertEqual(details?.torrentCount, 1)
        XCTAssertEqual(issue, .outOfDate)
    }

    func testDisabledBackupDoesNotCreateBackupDirectory() async throws {
        let fixture = try await makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let status = await fixture.backupStore.configure(
            SessionBackupConfiguration(
                isEnabled: false,
                parentDirectoryPath: fixture.backupParentURL.path,
                parentDirectoryBookmarkData: nil
            )
        )
        XCTAssertEqual(status, .disabled)
        let createStatus = await fixture.backupStore.createBackup()
        XCTAssertEqual(createStatus, .disabled)

        let backupURL = fixture.backupParentURL
            .appendingPathComponent(SessionBackupStore.directoryName, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }

    func testSessionSaveAutomaticallyCreatesCurrentBackup() async throws {
        let fixture = try await makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let archiveStore = TorrentArchiveStore(directories: fixture.directories)
        let bookmarkStore = BookmarkStore(directories: fixture.directories)
        let resumeDataStore = ResumeDataStore(directories: fixture.directories)
        let sessionStore = SessionStore(
            directories: fixture.directories,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore,
            resumeDataStore: resumeDataStore,
            backupStore: fixture.backupStore,
            startupMode: .alreadyInitialized
        )

        let saveOutcome = await sessionStore.saveCriticalState(from: [fixture.record])
        XCTAssertEqual(saveOutcome, .saved)
        guard case .current(let details) = await fixture.backupStore.status() else {
            return XCTFail("Expected SessionStore to create the backup automatically")
        }
        XCTAssertEqual(details.torrentCount, 1)
    }

    func testFailedReplacementLeavesPreviousBackupUntouched() async throws {
        let fixture = try await makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture.rootURL) }

        _ = await fixture.backupStore.createBackup()
        let backupSessionURL = fixture.backupParentURL
            .appendingPathComponent(SessionBackupStore.directoryName, isDirectory: true)
            .appendingPathComponent("session.json")
        let previousBackupData = try Data(contentsOf: backupSessionURL)

        try Data("damaged-primary".utf8).write(to: fixture.directories.sessionSnapshotURL)
        guard case .stale = await fixture.backupStore.createBackup() else {
            return XCTFail("Expected the attempted update to fail validation")
        }
        XCTAssertEqual(try Data(contentsOf: backupSessionURL), previousBackupData)
    }

    func testUnavailableParentReportsSpecificFailureAndKeepsPrimarySession() async throws {
        let fixture = try await makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let primaryData = try Data(contentsOf: fixture.directories.sessionSnapshotURL)
        try FileManager.default.removeItem(at: fixture.backupParentURL)

        let status = await fixture.backupStore.createBackup()
        guard case .stale(nil, let issue) = status else {
            return XCTFail("Expected unavailable backup status, got \(status)")
        }
        XCTAssertEqual(issue, .folderUnavailable)
        XCTAssertEqual(try Data(contentsOf: fixture.directories.sessionSnapshotURL), primaryData)
    }

    func testRestoresVerifiedBackupOverDamagedPrimaryBundle() async throws {
        let fixture = try await makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture.rootURL) }

        _ = await fixture.backupStore.createBackup()
        try Data("damaged-primary".utf8).write(to: fixture.directories.sessionSnapshotURL)

        let outcome = await fixture.backupStore.restoreBackup()
        guard case .restored(let snapshot) = outcome else {
            return XCTFail("Expected restored backup")
        }

        XCTAssertEqual(snapshot.torrents.map(\.torrentID), [fixture.record.id])
        let restoredData = try Data(contentsOf: fixture.directories.sessionSnapshotURL)
        XCTAssertNoThrow(try JSONDecoder().decode(SessionSnapshot.self, from: restoredData))
    }

    func testSessionStoreUnlocksOnlyAfterVerifiedBackupIsRestoredAndAccepted() async throws {
        let fixture = try await makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture.rootURL) }
        _ = await fixture.backupStore.createBackup()
        try Data("damaged-primary".utf8).write(to: fixture.directories.sessionSnapshotURL)

        let archiveStore = TorrentArchiveStore(directories: fixture.directories)
        let bookmarkStore = BookmarkStore(directories: fixture.directories)
        let resumeDataStore = ResumeDataStore(directories: fixture.directories)
        let sessionStore = SessionStore(
            directories: fixture.directories,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore,
            resumeDataStore: resumeDataStore,
            backupStore: fixture.backupStore
        )

        guard case .failure(.unreadable) = await sessionStore.load() else {
            return XCTFail("Expected the damaged primary session to block persistence")
        }
        let saveBeforeRestore = await sessionStore.saveCriticalState(from: [])
        XCTAssertEqual(saveBeforeRestore, .blocked)

        guard case .restored(let snapshot) = await sessionStore.restoreSessionBackup() else {
            return XCTFail("Expected the verified backup to restore")
        }
        XCTAssertEqual(snapshot.torrents.map(\.torrentID), [fixture.record.id])
        let saveBeforeAcceptance = await sessionStore.saveCriticalState(from: [fixture.record])
        XCTAssertEqual(saveBeforeAcceptance, .blocked)

        await sessionStore.acceptInitialLoad()
        let saveAfterAcceptance = await sessionStore.saveCriticalState(from: [fixture.record])
        XCTAssertEqual(saveAfterAcceptance, .saved)
    }

    func testExplicitEmptyResetReplacesDamagedSessionAndBackupWithoutDeletingPayload() async throws {
        let fixture = try await makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture.rootURL) }
        _ = await fixture.backupStore.createBackup()
        try Data("damaged-primary".utf8).write(to: fixture.directories.sessionSnapshotURL)

        let payloadURL = fixture.rootURL.appendingPathComponent("downloaded-payload.bin")
        try Data("payload".utf8).write(to: payloadURL)
        let archiveStore = TorrentArchiveStore(directories: fixture.directories)
        let bookmarkStore = BookmarkStore(directories: fixture.directories)
        let resumeDataStore = ResumeDataStore(directories: fixture.directories)
        let sessionStore = SessionStore(
            directories: fixture.directories,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore,
            resumeDataStore: resumeDataStore,
            backupStore: fixture.backupStore
        )

        guard case .failure = await sessionStore.load() else {
            return XCTFail("Expected damaged primary session")
        }
        let resetOutcome = await sessionStore.discardFailedSessionAndCreateEmpty()
        XCTAssertEqual(resetOutcome, .saved)

        let primarySnapshot = try JSONDecoder().decode(
            SessionSnapshot.self,
            from: Data(contentsOf: fixture.directories.sessionSnapshotURL)
        )
        XCTAssertTrue(primarySnapshot.torrents.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadURL.path))

        guard case .current(let details) = await fixture.backupStore.inspect() else {
            return XCTFail("Expected a new valid empty backup")
        }
        XCTAssertEqual(details.torrentCount, 0)
    }

    private func makeFixture() async throws -> Fixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShatlBackupTests-\(UUID().uuidString)", isDirectory: true)
        let backupParentURL = rootURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(
            at: backupParentURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

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
        let record = makeTestRecord(originalName: "Backup Test")

        let archiveURL = try await archiveStore.destinationURL(for: record.id)
        try Data("torrent".utf8).write(to: archiveURL)
        await bookmarkStore.saveBookmarkData(for: record.id, data: Data("bookmark".utf8))
        try Data("resume".utf8).write(
            to: directories.resumeDataDirectoryURL
                .appendingPathComponent("\(record.id.uuidString).fastresume")
        )
        let saveOutcome = await sessionStore.saveCriticalState(from: [record])
        XCTAssertEqual(saveOutcome, .saved)

        let backupStore = SessionBackupStore(
            sourceDirectories: directories,
            configuration: SessionBackupConfiguration(
                isEnabled: true,
                parentDirectoryPath: backupParentURL.path,
                parentDirectoryBookmarkData: nil
            )
        )

        return Fixture(
            rootURL: rootURL,
            backupParentURL: backupParentURL,
            directories: directories,
            sessionStore: sessionStore,
            backupStore: backupStore,
            record: record
        )
    }
}

private struct Fixture {
    var rootURL: URL
    var backupParentURL: URL
    var directories: ShatlDirectories
    var sessionStore: SessionStore
    var backupStore: SessionBackupStore
    var record: TorrentRecord
}
