// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

@MainActor
final class BookmarkStoreTests: XCTestCase {
    func testResolveURLUsesFallbackWhenNoBookmarkExists() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreTests-\(UUID().uuidString)", isDirectory: true)
        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let store = BookmarkStore(directories: directories)
        let fallbackURL = rootURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: fallbackURL, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: rootURL) }

        let resolvedURL = await store.resolveURL(for: UUID(), fallbackPath: fallbackURL.path)
        XCTAssertEqual(resolvedURL?.path, fallbackURL.path)
    }

    func testResolveURLDoesNotFallbackWhenStoredBookmarkCannotBeResolved() async throws {
        let torrentID = UUID()
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreTests-\(UUID().uuidString)", isDirectory: true)
        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let store = BookmarkStore(directories: directories)
        let fallbackURL = rootURL.appendingPathComponent("Movies", isDirectory: true)
        try FileManager.default.createDirectory(at: fallbackURL, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: rootURL) }

        await store.saveBookmarkData(for: torrentID, data: Data("broken-bookmark".utf8))

        let resolvedURL = await store.resolveURL(for: torrentID, fallbackPath: fallbackURL.path)
        XCTAssertNil(resolvedURL)
    }

    /// A folder deleted in Finder goes to the Trash, renamed if a folder of
    /// its name is there already, and its bookmark follows it there: a saved
    /// download started went on in the Trash (the owner's check, November
    /// 2026). A folder in a Trash is unreachable, and found again once it is
    /// put back. The Trash here is a folder of the test's own: the real one
    /// is never touched.
    func testAFolderMovedToTheTrashIsUnreachableUntilPutBack() async throws {
        let torrentID = UUID()
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreTests-\(UUID().uuidString)", isDirectory: true)
        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let store = BookmarkStore(directories: directories)
        let folder = rootURL.appendingPathComponent("Movies/Test", isDirectory: true)
        let trash = rootURL.appendingPathComponent(".Trash", isDirectory: true)
        let trashed = trash.appendingPathComponent("Test 6.51.46 PM", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: rootURL) }

        await store.saveBookmark(for: torrentID, url: folder)
        try FileManager.default.moveItem(at: folder, to: trashed)

        let inTrash = await store.resolveURL(for: torrentID, fallbackPath: folder.path)
        XCTAssertNil(inTrash, "Found in the Trash: \(inTrash?.path ?? "")")

        try FileManager.default.moveItem(at: trashed, to: folder)
        let putBack = await store.resolveFreshURL(for: torrentID, fallbackPath: folder.path)
        XCTAssertEqual(putBack?.resolvingSymlinksInPath().path, folder.resolvingSymlinksInPath().path)
    }

    func testAPathInATrashIsUnreachableAndOthersAreNot() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreTests-\(UUID().uuidString)", isDirectory: true)
        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let store = BookmarkStore(directories: directories)
        let inTrash = rootURL.appendingPathComponent(".Trashes/501/Movies", isDirectory: true)
        try FileManager.default.createDirectory(at: inTrash, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: rootURL) }

        let resolved = await store.resolveURL(for: UUID(), fallbackPath: inTrash.path)
        XCTAssertNil(resolved)
        XCTAssertTrue(BookmarkStore.isInTrash(URL(fileURLWithPath: "/Users/me/.Trash/Test")))
        XCTAssertTrue(BookmarkStore.isInTrash(URL(fileURLWithPath: "/Volumes/Backup/.Trashes/501/Test")))
        XCTAssertFalse(BookmarkStore.isInTrash(URL(fileURLWithPath: "/Users/me/Movies/Trash")))
        XCTAssertFalse(BookmarkStore.isInTrash(URL(fileURLWithPath: "/Users/me/Movies/.Trash bin")))
    }

    func testSavingReplacementBookmarkClearsStaleActiveScopedURL() async throws {
        let torrentID = UUID()
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreTests-\(UUID().uuidString)", isDirectory: true)
        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        let store = BookmarkStore(directories: directories)
        let oldURL = rootURL.appendingPathComponent("ExternalDisk", isDirectory: true)
        let newURL = rootURL.appendingPathComponent("Movies", isDirectory: true)
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: rootURL) }

        await store.saveBookmark(for: torrentID, url: oldURL)
        let firstResolvedURL = await store.resolveURL(for: torrentID, fallbackPath: oldURL.path)
        XCTAssertEqual(
            firstResolvedURL?.resolvingSymlinksInPath().path,
            oldURL.resolvingSymlinksInPath().path
        )

        try FileManager.default.removeItem(at: oldURL)
        await store.saveBookmark(for: torrentID, url: newURL)

        let replacementResolvedURL = await store.resolveURL(for: torrentID, fallbackPath: oldURL.path)
        XCTAssertEqual(
            replacementResolvedURL?.resolvingSymlinksInPath().path,
            newURL.resolvingSymlinksInPath().path
        )
    }
}
