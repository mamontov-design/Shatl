// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

@MainActor
final class TorrentPayloadLocatorTests: XCTestCase {
    func testPrimaryLocationReturnsSingleFileForSingleFileTorrent() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Movie.mkv", sizeBytes: 4_096, fileIndex: 0),
        ])

        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Locator-Single-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        let payloadFileURL = saveRoot.appendingPathComponent("Movie.mkv", isDirectory: false)
        try Data("payload".utf8).write(to: payloadFileURL, options: .atomic)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .completed,
            progress: 1.0
        )

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let location = await bundle.payloadLocator.primaryLocation(for: record)

        XCTAssertEqual(
            location?.saveURL.standardizedFileURL,
            saveRoot.standardizedFileURL
        )
        XCTAssertEqual(
            location?.openItemURL?.standardizedFileURL,
            payloadFileURL.standardizedFileURL
        )
        XCTAssertEqual(
            location?.revealItemURL.standardizedFileURL,
            payloadFileURL.standardizedFileURL
        )
    }

    func testPrimaryLocationDisablesOpenForIncompleteSingleFileTorrent() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Movie.mkv", sizeBytes: 4_096, fileIndex: 0),
        ])

        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Locator-IncompleteSingle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        let payloadFileURL = saveRoot.appendingPathComponent("Movie.mkv", isDirectory: false)
        try Data("partial payload".utf8).write(to: payloadFileURL, options: .atomic)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .downloading,
            progress: 0.5
        )

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let location = await bundle.payloadLocator.primaryLocation(for: record)

        XCTAssertNil(location?.openItemURL)
        XCTAssertEqual(
            location?.revealItemURL.standardizedFileURL,
            payloadFileURL.standardizedFileURL
        )
    }

    func testPrimaryLocationReturnsCommonFolderForMultiFileTorrent() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Show/Season 1/E01.mkv", sizeBytes: 4_096, fileIndex: 0),
            TorrentContentFileDescriptor(relativePath: "Show/Season 2/E01.mkv", sizeBytes: 4_096, fileIndex: 1),
        ])

        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Locator-Multi-\(UUID().uuidString)", isDirectory: true)
        let showRoot = saveRoot.appendingPathComponent("Show", isDirectory: true)
        try FileManager.default.createDirectory(
            at: showRoot.appendingPathComponent("Season 1", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: showRoot.appendingPathComponent("Season 2", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("payload".utf8).write(
            to: showRoot.appendingPathComponent("Season 1", isDirectory: true).appendingPathComponent("E01.mkv"),
            options: .atomic
        )
        try Data("payload".utf8).write(
            to: showRoot.appendingPathComponent("Season 2", isDirectory: true).appendingPathComponent("E01.mkv"),
            options: .atomic
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0, 1],
            selectedFileCount: 2,
            totalFileCount: 2
        )

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let location = await bundle.payloadLocator.primaryLocation(for: record)

        XCTAssertEqual(
            location?.saveURL.standardizedFileURL,
            saveRoot.standardizedFileURL
        )
        XCTAssertNil(location?.openItemURL)
        XCTAssertEqual(
            location?.revealItemURL.standardizedFileURL,
            showRoot.standardizedFileURL
        )
    }

    func testPrimaryLocationDisablesOpenForSingleFileInsideTorrentFolder() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Movie Pack/Movie.mkv", sizeBytes: 4_096, fileIndex: 0),
        ])

        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Locator-NestedSingle-\(UUID().uuidString)", isDirectory: true)
        let movieFolderURL = saveRoot.appendingPathComponent("Movie Pack", isDirectory: true)
        try FileManager.default.createDirectory(at: movieFolderURL, withIntermediateDirectories: true)
        let payloadFileURL = movieFolderURL.appendingPathComponent("Movie.mkv", isDirectory: false)
        try Data("payload".utf8).write(to: payloadFileURL, options: .atomic)
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

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let location = await bundle.payloadLocator.primaryLocation(for: record)

        XCTAssertNil(location?.openItemURL)
        XCTAssertEqual(
            location?.revealItemURL.standardizedFileURL,
            movieFolderURL.standardizedFileURL
        )
    }

    func testManagedPayloadResolutionReturnsSelectedFilesUnresolvedReason() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Show/E01.mkv", sizeBytes: 4_096, fileIndex: 0),
        ])

        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Locator-UnresolvedSelection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [4],
            selectedFileCount: 1,
            totalFileCount: 1
        )

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let resolution = await bundle.payloadLocator.managedPayloadResolution(for: record)

        guard case .unresolved(let failure) = resolution else {
            return XCTFail("Expected unresolved payload resolution")
        }

        XCTAssertEqual(failure.reason, .selectedFilesUnresolved)
        XCTAssertEqual(
            failure.savePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
            saveRoot.standardizedFileURL.path
        )
        XCTAssertEqual(
            URL(fileURLWithPath: failure.archivePath).standardizedFileURL.path,
            archiveURL.standardizedFileURL.path
        )
        XCTAssertEqual(failure.selectedFileCount, 1)
        XCTAssertEqual(failure.totalFileCount, 1)
        XCTAssertEqual(failure.inspectedFileCount, 1)
    }

    func testManagedPayloadResolutionRejectsUnsafeArchivePathWithoutUsingStoredFallback() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "../personal.bin", sizeBytes: 4_096, fileIndex: 0),
        ])
        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Locator-UnsafeArchive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileRelativePaths: ["safe-looking-fallback.bin"]
        )
        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let resolution = await bundle.payloadLocator.managedPayloadResolution(for: record)

        guard case .unresolved(let failure) = resolution else {
            return XCTFail("Expected unsafe manifest failure")
        }
        XCTAssertEqual(failure.reason, .unsafeManifest)
    }

    func testManagedPayloadResolutionRejectsDuplicateArchivePaths() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "movie.bin", sizeBytes: 4_096, fileIndex: 0),
            TorrentContentFileDescriptor(relativePath: "movie.bin", sizeBytes: 4_096, fileIndex: 1),
        ])
        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Locator-DuplicateArchive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0, 1],
            selectedFileCount: 2,
            totalFileCount: 2
        )
        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let resolution = await bundle.payloadLocator.managedPayloadResolution(for: record)

        guard case .unresolved(let failure) = resolution else {
            return XCTFail("Expected unsafe manifest failure")
        }
        XCTAssertEqual(failure.reason, .unsafeManifest)
    }

    func testManagedPayloadResolutionRejectsFileDirectoryPrefixConflict() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Show", sizeBytes: 4_096, fileIndex: 0),
            TorrentContentFileDescriptor(relativePath: "Show/movie.bin", sizeBytes: 4_096, fileIndex: 1),
        ])
        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Locator-PrefixConflict-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0, 1],
            selectedFileCount: 2,
            totalFileCount: 2
        )
        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        let resolution = await bundle.payloadLocator.managedPayloadResolution(for: record)

        guard case .unresolved(let failure) = resolution else {
            return XCTFail("Expected unsafe manifest failure")
        }
        XCTAssertEqual(failure.reason, .unsafeManifest)
    }
}
