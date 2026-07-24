import Foundation
import XCTest
@testable import Shatl

@MainActor
final class TorrentPayloadDeletionServiceTests: XCTestCase {
    func testDeletePayloadRemovesSingleFileAndKeepsSaveDirectory() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Movie.mkv", sizeBytes: 4_096, fileIndex: 0),
        ])

        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PayloadDelete-Single-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let payloadFileURL = saveRoot.appendingPathComponent("Movie.mkv", isDirectory: false)
        try Data("payload".utf8).write(to: payloadFileURL, options: .atomic)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1
        )

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let result = await bundle.payloadDeletionService.deletePayload(for: record)

        guard case .deleted(let deletionResult) = result else {
            return XCTFail("Expected resolved payload deletion")
        }

        XCTAssertEqual(deletionResult.deletedManagedFileCount, 1)
        XCTAssertEqual(deletionResult.missingManagedFileCount, 0)
        XCTAssertEqual(deletionResult.deletedDirectoryCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saveRoot.path))
    }

    func testDeletePayloadRemovesEmptyDirectoriesAndIgnoresSystemSidecars() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Torrent Root/Season 1/E01.mkv", sizeBytes: 4_096, fileIndex: 0),
        ])

        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PayloadDelete-Tree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let seasonDirectory = saveRoot
            .appendingPathComponent("Torrent Root", isDirectory: true)
            .appendingPathComponent("Season 1", isDirectory: true)
        try FileManager.default.createDirectory(at: seasonDirectory, withIntermediateDirectories: true)

        let payloadFileURL = seasonDirectory.appendingPathComponent("E01.mkv", isDirectory: false)
        let seasonSidecarURL = seasonDirectory.appendingPathComponent(".DS_Store", isDirectory: false)
        let rootSidecarURL = saveRoot
            .appendingPathComponent("Torrent Root", isDirectory: true)
            .appendingPathComponent(".DS_Store", isDirectory: false)

        try Data("payload".utf8).write(to: payloadFileURL, options: .atomic)
        try Data("sidecar".utf8).write(to: seasonSidecarURL, options: .atomic)
        try Data("sidecar".utf8).write(to: rootSidecarURL, options: .atomic)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1
        )

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let result = await bundle.payloadDeletionService.deletePayload(for: record)

        guard case .deleted(let deletionResult) = result else {
            return XCTFail("Expected resolved payload deletion")
        }

        XCTAssertEqual(deletionResult.deletedManagedFileCount, 1)
        XCTAssertEqual(deletionResult.deletedDirectoryCount, 2)
        XCTAssertEqual(deletionResult.deletedSystemSidecarCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: seasonDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: saveRoot.appendingPathComponent("Torrent Root", isDirectory: true).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saveRoot.path))
    }

    func testDeletePayloadKeepsDirectoryWhenUnmanagedFilesRemain() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Show/E01.mkv", sizeBytes: 4_096, fileIndex: 0),
            TorrentContentFileDescriptor(relativePath: "Show/E02.mkv", sizeBytes: 4_096, fileIndex: 1),
        ])

        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PayloadDelete-Partial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let showDirectory = saveRoot.appendingPathComponent("Show", isDirectory: true)
        try FileManager.default.createDirectory(at: showDirectory, withIntermediateDirectories: true)
        let selectedFileURL = showDirectory.appendingPathComponent("E01.mkv", isDirectory: false)
        let unmanagedFileURL = showDirectory.appendingPathComponent("E02.mkv", isDirectory: false)
        try Data("selected".utf8).write(to: selectedFileURL, options: .atomic)
        try Data("unmanaged".utf8).write(to: unmanagedFileURL, options: .atomic)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 2
        )

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let result = await bundle.payloadDeletionService.deletePayload(for: record)

        guard case .deleted(let deletionResult) = result else {
            return XCTFail("Expected resolved payload deletion")
        }

        XCTAssertEqual(deletionResult.deletedManagedFileCount, 1)
        XCTAssertEqual(deletionResult.deletedDirectoryCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: selectedFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unmanagedFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: showDirectory.path))
    }

    func testDeletePayloadReturnsArchiveMissingReasonWhenArchiveWasPruned() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Show/E01.mkv", sizeBytes: 4_096, fileIndex: 0),
        ])

        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PayloadDelete-MissingArchive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1
        )

        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let result = await bundle.payloadDeletionService.deletePayload(for: record)

        guard case .unresolved(let failure) = result else {
            return XCTFail("Expected unresolved payload deletion")
        }

        XCTAssertEqual(failure.reason, .archiveMissing)
        XCTAssertEqual(
            failure.savePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
            saveRoot.standardizedFileURL.path
        )
        XCTAssertEqual(failure.selectedFileCount, 1)
        XCTAssertEqual(failure.totalFileCount, 1)
        XCTAssertNil(failure.inspectedFileCount)
    }

    func testDeletePayloadUsesStoredManifestWhenArchiveIsMissing() async throws {
        let engine = FakeTorrentEngine()
        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PayloadDelete-Manifest-\(UUID().uuidString)", isDirectory: true)
        let showDirectory = saveRoot.appendingPathComponent("Show", isDirectory: true)
        try FileManager.default.createDirectory(at: showDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let payloadFileURL = showDirectory.appendingPathComponent("E01.mkv", isDirectory: false)
        try Data("payload".utf8).write(to: payloadFileURL, options: .atomic)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileRelativePaths: ["Show/E01.mkv"],
            selectedFileCount: 1,
            totalFileCount: 1
        )

        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let result = await bundle.payloadDeletionService.deletePayload(for: record)

        guard case .deleted(let deletionResult) = result else {
            return XCTFail("Expected payload deletion from stored manifest")
        }

        XCTAssertEqual(deletionResult.payloadSource, .storedManifest)
        XCTAssertEqual(deletionResult.deletedManagedFileCount, 1)
        XCTAssertEqual(deletionResult.failedManagedFileCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadFileURL.path))
    }
}
