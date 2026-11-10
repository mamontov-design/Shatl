// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Restores access to user-selected folders after relaunch
/// without asking the user to choose the path again.
actor BookmarkStore {
    private let directories: ShatlDirectories
    private let fileManager: FileManager
    private var activeScopedURLs: [UUID: URL] = [:]

    init(directories: ShatlDirectories, fileManager: FileManager = .default) {
        self.directories = directories
        self.fileManager = fileManager
    }

    func saveBookmark(for torrentID: UUID, url: URL) async {
        do {
            try directories.ensureSessionDirectories()
            clearActiveScopedURL(for: torrentID)
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            try bookmarkData.write(to: bookmarkURL(for: torrentID), options: .atomic)
        } catch {
            // A bookmark is an additional reliability layer. If saving it fails,
            // session restoration can still try the canonical path.
        }
    }

    func saveBookmarkData(for torrentID: UUID, data: Data) async {
        do {
            try directories.ensureSessionDirectories()
            clearActiveScopedURL(for: torrentID)
            try data.write(to: bookmarkURL(for: torrentID), options: .atomic)
        } catch {
            // A bookmark is an additional reliability layer. If saving it fails,
            // session restoration can still try the canonical path.
        }
    }

    /// The folder a download is saved to, where it is now. A bookmark
    /// follows its folder wherever it moves: a folder renamed or moved in
    /// Finder is found there, as it should be. A folder moved to the Trash
    /// is found there too, and a download started or restored in it went on
    /// in the Trash (the owner's check, November 2026). A folder in a Trash
    /// counts as unreachable, as one on a disk that is off: the download
    /// says its folder is unavailable, and finds it again once it is put
    /// back.
    func resolveURL(for torrentID: UUID, fallbackPath: String) async -> URL? {
        if let activeURL = activeScopedURLs[torrentID] {
            guard !Self.isInTrash(activeURL) else { return nil }
            return fileManager.fileExists(atPath: activeURL.path) ? activeURL : nil
        }

        let bookmarkFileURL = bookmarkURL(for: torrentID)
        if let data = try? Data(contentsOf: bookmarkFileURL) {
            var isStale = false

            if let resolvedURL = try? URL(
                resolvingBookmarkData: data,
                options: [.withoutUI, .withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                // Before access, a refreshed bookmark or the cache: nothing
                // keeps the folder's place in the Trash.
                guard !Self.isInTrash(resolvedURL) else { return nil }
                guard resolvedURL.startAccessingSecurityScopedResource() else {
                    return nil
                }

                if isStale {
                    try? refreshedBookmarkData(for: resolvedURL)
                        .write(to: bookmarkURL(for: torrentID), options: .atomic)
                }

                activeScopedURLs[torrentID] = resolvedURL
                if fileManager.fileExists(atPath: resolvedURL.path) {
                    return resolvedURL
                }

                return nil
            }

            // If a stored bookmark cannot be resolved, do not fall back to a plain path.
            // For a user-selected folder this almost certainly means the security scope
            // is stale or unavailable rather than that plain-path access is valid.
            return nil
        }

        let fallbackURL = URL(fileURLWithPath: fallbackPath)
        guard !Self.isInTrash(fallbackURL) else { return nil }
        return fileManager.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil
    }

    /// Whether a folder lies in a Trash: the home folder's `.Trash`, a
    /// disk's `.Trashes`, iCloud Drive's `.Trash`. The system reserves
    /// these names; no folder chosen to save to is called so.
    nonisolated static func isInTrash(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    /// Resolves the bookmark again instead of trusting the path kept since the
    /// last access: a disk plugged back in, or a folder renamed in Finder,
    /// is found where it is now. Only for an explicit "check again".
    func resolveFreshURL(for torrentID: UUID, fallbackPath: String) async -> URL? {
        if let activeURL = activeScopedURLs.removeValue(forKey: torrentID) {
            activeURL.stopAccessingSecurityScopedResource()
        }
        return await resolveURL(for: torrentID, fallbackPath: fallbackPath)
    }

    func removeBookmark(for torrentID: UUID) async {
        if let activeURL = activeScopedURLs.removeValue(forKey: torrentID) {
            activeURL.stopAccessingSecurityScopedResource()
        }

        let url = bookmarkURL(for: torrentID)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    func cleanupOrphanedBookmarks(validTorrentIDs: Set<UUID>) async {
        let validFileNames = Set(validTorrentIDs.map { bookmarkFileName(for: $0) })
        let directoryURL = directories.bookmarksDirectoryURL

        guard let items = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for item in items where !validFileNames.contains(item.lastPathComponent) {
            try? fileManager.removeItem(at: item)
        }

        for torrentID in activeScopedURLs.keys where !validTorrentIDs.contains(torrentID) {
            if let activeURL = activeScopedURLs.removeValue(forKey: torrentID) {
                activeURL.stopAccessingSecurityScopedResource()
            }
        }
    }

    private func bookmarkURL(for torrentID: UUID) -> URL {
        directories.bookmarksDirectoryURL.appendingPathComponent(bookmarkFileName(for: torrentID), isDirectory: false)
    }

    private func bookmarkFileName(for torrentID: UUID) -> String {
        "\(torrentID.uuidString).bookmark"
    }

    private func clearActiveScopedURL(for torrentID: UUID) {
        if let activeURL = activeScopedURLs.removeValue(forKey: torrentID) {
            activeURL.stopAccessingSecurityScopedResource()
        }
    }

    private func refreshedBookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
