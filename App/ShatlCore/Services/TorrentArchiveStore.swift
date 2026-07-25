// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Stores local `.torrent` files for reliable session restoration.
/// The archive does not depend on the user's original source file.
actor TorrentArchiveStore {
    private let directories: ShatlDirectories
    private let fileManager: FileManager

    init(directories: ShatlDirectories, fileManager: FileManager = .default) {
        self.directories = directories
        self.fileManager = fileManager
    }

    func destinationURL(for torrentID: UUID) throws -> URL {
        try directories.ensureSessionDirectories()
        return directories.archivedTorrentsDirectoryURL
            .appendingPathComponent(torrentID.uuidString, isDirectory: false)
            .appendingPathExtension("torrent")
    }

    nonisolated func relativeArchivePath(for torrentID: UUID) -> String {
        "\(torrentID.uuidString).torrent"
    }

    func resolveArchiveURL(relativePath: String) -> URL {
        directories.archivedTorrentsDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)
    }

    func removeArchive(for torrentID: UUID) async {
        let url = directories.archivedTorrentsDirectoryURL
            .appendingPathComponent(relativeArchivePath(for: torrentID), isDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    func cleanupOrphanedArchives(validTorrentIDs: Set<UUID>) async {
        let validFileNames = Set(validTorrentIDs.map { relativeArchivePath(for: $0) })
        let directoryURL = directories.archivedTorrentsDirectoryURL

        guard let items = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for item in items where !validFileNames.contains(item.lastPathComponent) {
            try? fileManager.removeItem(at: item)
        }
    }
}
