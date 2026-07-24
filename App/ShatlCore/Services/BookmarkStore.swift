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

    func resolveURL(for torrentID: UUID, fallbackPath: String) async -> URL? {
        if let activeURL = activeScopedURLs[torrentID] {
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
        return fileManager.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil
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
