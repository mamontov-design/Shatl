// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Fast-resume files restore incomplete torrent sessions accurately
/// without a false progress rollback after detach or relaunch.
actor ResumeDataStore {
    private let directories: ShatlDirectories
    private let fileManager: FileManager

    init(directories: ShatlDirectories, fileManager: FileManager = .default) {
        self.directories = directories
        self.fileManager = fileManager
    }

    nonisolated func relativeResumeDataPath(for torrentID: UUID) -> String {
        "\(torrentID.uuidString).fastresume"
    }

    func removeResumeData(for torrentID: UUID) async {
        let url = directories.resumeDataDirectoryURL
            .appendingPathComponent(relativeResumeDataPath(for: torrentID), isDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    func cleanupOrphanedResumeData(validTorrentIDs: Set<UUID>) async {
        let validFileNames = Set(validTorrentIDs.map { relativeResumeDataPath(for: $0) })
        let directoryURL = directories.resumeDataDirectoryURL

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
