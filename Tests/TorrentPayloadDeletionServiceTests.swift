// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Darwin
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

    func testDeletionMustNotTraverseSymlinkParent() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        let saveRoot = bundle.rootURL.appendingPathComponent("Downloads", isDirectory: true)
        let outsideRoot = bundle.rootURL.appendingPathComponent("Personal", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        let victimURL = outsideRoot.appendingPathComponent("movie.bin", isDirectory: false)
        let symlinkURL = saveRoot.appendingPathComponent("Show", isDirectory: true)
        try Data("unrelated personal data".utf8).write(to: victimURL)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideRoot)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileRelativePaths: ["Show/movie.bin"]
        )
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let outcome = await bundle.payloadDeletionService.deletePayload(for: record)

        guard case .unsafe(let failure) = outcome else {
            return XCTFail("Expected deletion to be refused")
        }
        XCTAssertEqual(failure.issues.map(\.reason), [.symlinkComponent])
        XCTAssertTrue(FileManager.default.fileExists(atPath: victimURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkURL.path))
    }

    func testDeletionMustNotRecursivelyDeleteReplacementDirectory() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        let saveRoot = bundle.rootURL.appendingPathComponent("Downloads", isDirectory: true)
        let replacementURL = saveRoot.appendingPathComponent("movie.bin", isDirectory: true)
        try FileManager.default.createDirectory(at: replacementURL, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        let victimURL = replacementURL.appendingPathComponent("personal.txt", isDirectory: false)
        try Data("unrelated personal data".utf8).write(to: victimURL)
        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileRelativePaths: ["movie.bin"]
        )
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let outcome = await bundle.payloadDeletionService.deletePayload(for: record)

        guard case .unsafe(let failure) = outcome else {
            return XCTFail("Expected deletion to be refused")
        }
        XCTAssertEqual(failure.issues.first?.reason, .objectTypeMismatch)
        XCTAssertEqual(failure.issues.first?.actualType, .directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: victimURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacementURL.path))
    }

    func testDeletePayloadRefusesLeafSymlinkWithoutDeletingItsTarget() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        let saveRoot = bundle.rootURL.appendingPathComponent("Downloads", isDirectory: true)
        let outsideRoot = bundle.rootURL.appendingPathComponent("Personal", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        let victimURL = outsideRoot.appendingPathComponent("movie.bin", isDirectory: false)
        let symlinkURL = saveRoot.appendingPathComponent("movie.bin", isDirectory: false)
        try Data("unrelated personal data".utf8).write(to: victimURL)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: victimURL)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileRelativePaths: ["movie.bin"]
        )
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let outcome = await bundle.payloadDeletionService.deletePayload(for: record)

        guard case .unsafe(let failure) = outcome else {
            return XCTFail("Expected deletion to be refused")
        }
        XCTAssertEqual(failure.issues.first?.reason, .objectTypeMismatch)
        XCTAssertEqual(failure.issues.first?.actualType, .symbolicLink)
        XCTAssertTrue(FileManager.default.fileExists(atPath: victimURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkURL.path))
    }

    func testUnsafeEntryAbortsEntireManifestBeforeAnyFileIsDeleted() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        let saveRoot = bundle.rootURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        let safeFileURL = saveRoot.appendingPathComponent("safe.bin", isDirectory: false)
        let unsafeDirectoryURL = saveRoot.appendingPathComponent("unsafe.bin", isDirectory: true)
        try Data("payload".utf8).write(to: safeFileURL)
        try FileManager.default.createDirectory(at: unsafeDirectoryURL, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0, 1],
            selectedFileRelativePaths: ["safe.bin", "unsafe.bin"],
            selectedFileCount: 2,
            totalFileCount: 2
        )
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let outcome = await bundle.payloadDeletionService.deletePayload(for: record)

        guard case .unsafe = outcome else {
            return XCTFail("Expected deletion to be refused")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: safeFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unsafeDirectoryURL.path))
    }

    func testDeletePayloadRefusesSpecialFileType() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        let saveRoot = bundle.rootURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        let fifoURL = saveRoot.appendingPathComponent("movie.bin", isDirectory: false)
        let created = fifoURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.mkfifo(path, S_IRUSR | S_IWUSR)
        }
        XCTAssertEqual(created, 0)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileRelativePaths: ["movie.bin"]
        )
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let outcome = await bundle.payloadDeletionService.deletePayload(for: record)

        guard case .unsafe(let failure) = outcome else {
            return XCTFail("Expected deletion to be refused")
        }
        XCTAssertEqual(failure.issues.first?.actualType, .other)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fifoURL.path))
    }

    func testInvalidStoredManifestRefusesDeletionWithoutDeletingValidSibling() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        let saveRoot = bundle.rootURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        let validFileURL = saveRoot.appendingPathComponent("movie.bin", isDirectory: false)
        try Data("payload".utf8).write(to: validFileURL)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0, 1],
            selectedFileRelativePaths: ["movie.bin", "../personal.bin"],
            selectedFileCount: 2,
            totalFileCount: 2
        )
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let outcome = await bundle.payloadDeletionService.deletePayload(for: record)

        guard case .unresolved(let failure) = outcome else {
            return XCTFail("Expected unsafe manifest resolution failure")
        }
        XCTAssertEqual(failure.reason, .unsafeManifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: validFileURL.path))
    }
}
