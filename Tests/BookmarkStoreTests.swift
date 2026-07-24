import XCTest
@testable import Shatl

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
