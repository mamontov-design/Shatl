import Foundation
import XCTest
@testable import Shatl

final class DiskIssueDetectorTests: XCTestCase {
    func testStartupCheckFlagsMissingContentForCompletedTorrent() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Season 3/Episode 01.mkv", sizeBytes: 1_024, fileIndex: 0),
        ])

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskIssueDetector-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let archiveStore = TorrentArchiveStore(directories: directories)
        let bookmarkStore = BookmarkStore(directories: directories)
        let detector = DiskIssueDetector(
            engine: engine,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore
        )

        let saveURL = rootURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveURL, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveURL.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .completed,
            progress: 1.0
        )

        let archiveURL = try await archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bookmarkStore.saveBookmark(for: record.id, url: saveURL)

        let evaluation = await detector.startupCheck(for: [record])

        XCTAssertEqual(evaluation.checkedTorrentIDs, [record.id])
        XCTAssertEqual(evaluation.issuesByTorrentID[record.id]?.kind, .missingContent)
        XCTAssertEqual(evaluation.issuesByTorrentID[record.id]?.statusBeforeIssue, .completed)
    }

    func testStartupCheckDoesNotFlagMissingContentForIncompleteMultiFileTorrent() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Season 3/Episode 01.mkv", sizeBytes: 1_024, fileIndex: 0),
            TorrentContentFileDescriptor(relativePath: "Season 3/Episode 02.mkv", sizeBytes: 1_024, fileIndex: 1),
        ])

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskIssueDetector-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let archiveStore = TorrentArchiveStore(directories: directories)
        let bookmarkStore = BookmarkStore(directories: directories)
        let detector = DiskIssueDetector(
            engine: engine,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore
        )

        let saveURL = rootURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveURL, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveURL.path,
            selectedFileIndices: [0, 1],
            selectedFileCount: 2,
            totalFileCount: 2,
            status: .stopped,
            progress: 0.4
        )

        let archiveURL = try await archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bookmarkStore.saveBookmark(for: record.id, url: saveURL)

        let evaluation = await detector.startupCheck(for: [record])

        XCTAssertEqual(evaluation.checkedTorrentIDs, [record.id])
        XCTAssertNil(evaluation.issuesByTorrentID[record.id])
    }

    func testStartupCheckFlagsMissingContentForIncompleteMultiFileWhenTrackedFileIsMissing() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Season 1/Episode 01.mkv", sizeBytes: 1_024, fileIndex: 0),
            TorrentContentFileDescriptor(relativePath: "Season 1/Episode 02.mkv", sizeBytes: 1_024, fileIndex: 1),
            TorrentContentFileDescriptor(relativePath: "Season 2/Episode 01.mkv", sizeBytes: 1_024, fileIndex: 2),
        ])

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskIssueDetector-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let archiveStore = TorrentArchiveStore(directories: directories)
        let bookmarkStore = BookmarkStore(directories: directories)
        let detector = DiskIssueDetector(
            engine: engine,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore
        )

        let saveURL = rootURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: saveURL.appendingPathComponent("Season 1", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("episode".utf8).write(
            to: saveURL.appendingPathComponent("Season 1/Episode 02.mkv", isDirectory: false),
            options: .atomic
        )

        let record = makeTestRecord(
            savePath: saveURL.path,
            selectedFileIndices: [0, 1, 2],
            selectedFileCount: 3,
            totalFileCount: 3,
            status: .stopped,
            progress: 0.5,
            materializedSelectionFootprint: MaterializedSelectionFootprint(
                selectedFileCount: 3,
                materializedOrdinals: Set([0, 1])
            )
        )

        let archiveURL = try await archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bookmarkStore.saveBookmark(for: record.id, url: saveURL)

        let evaluation = await detector.startupCheck(for: [record])

        XCTAssertEqual(evaluation.issuesByTorrentID[record.id]?.kind, .missingContent)
        XCTAssertEqual(
            evaluation.issuesByTorrentID[record.id]?.debugReason,
            "Не найден выбранный файл: Season 1/Episode 01.mkv"
        )
    }

    func testStartupCheckFlagsMissingContentForIncompleteSingleFileTorrentWithProgress() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Movie.mkv", sizeBytes: 4_096, fileIndex: 0),
        ])

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskIssueDetector-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let archiveStore = TorrentArchiveStore(directories: directories)
        let bookmarkStore = BookmarkStore(directories: directories)
        let detector = DiskIssueDetector(
            engine: engine,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore
        )

        let saveURL = rootURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveURL, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveURL.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .stopped,
            progress: 0.4
        )

        let archiveURL = try await archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bookmarkStore.saveBookmark(for: record.id, url: saveURL)

        let evaluation = await detector.startupCheck(for: [record])

        XCTAssertEqual(evaluation.issuesByTorrentID[record.id]?.kind, .missingContent)
        XCTAssertEqual(evaluation.issuesByTorrentID[record.id]?.statusBeforeIssue, .stopped)
    }

    func testStartupCheckFlagsUnavailableSavePath() async {
        let engine = FakeTorrentEngine()
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskIssueDetector-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let archiveStore = TorrentArchiveStore(directories: directories)
        let bookmarkStore = BookmarkStore(directories: directories)
        let detector = DiskIssueDetector(
            engine: engine,
            archiveStore: archiveStore,
            bookmarkStore: bookmarkStore
        )

        let missingPath = rootURL.appendingPathComponent("MissingFolder", isDirectory: true).path
        let record = makeTestRecord(
            savePath: missingPath,
            status: .completed,
            progress: 1.0
        )

        let evaluation = await detector.startupCheck(for: [record])

        XCTAssertEqual(evaluation.issuesByTorrentID[record.id]?.kind, .savePathUnavailable)
        XCTAssertEqual(evaluation.issuesByTorrentID[record.id]?.statusBeforeIssue, .completed)
    }

}
