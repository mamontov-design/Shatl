// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated struct SessionRestoreResult: Sendable {
    var snapshots: [EngineTorrentSnapshot]
    var persistentIssues: [UUID: TorrentPersistentIssue]
    var fallbackStatusesByID: [UUID: TorrentStatus]
}

/// Restores the engine in the background and returns a normalized
/// restoration result to the store.
actor SessionRestoreCoordinator {
    private let engine: any TorrentEngine
    private let archiveStore: TorrentArchiveStore
    private let bookmarkStore: BookmarkStore
    private let fileManager: FileManager

    init(
        engine: any TorrentEngine,
        archiveStore: TorrentArchiveStore,
        bookmarkStore: BookmarkStore,
        fileManager: FileManager = .default
    ) {
        self.engine = engine
        self.archiveStore = archiveStore
        self.bookmarkStore = bookmarkStore
        self.fileManager = fileManager
    }

    func restore(records: [TorrentRecord]) async -> SessionRestoreResult {
        var snapshots: [EngineTorrentSnapshot] = []
        var persistentIssues: [UUID: TorrentPersistentIssue] = [:]
        var fallbackStatusesByID: [UUID: TorrentStatus] = [:]

        for record in records {
            let restoredIssue = record.persistentIssue
            let baseStatus = restoredIssue?.statusBeforeIssue ?? record.status

            if restoredIssue?.kind == .missingContent {
                persistentIssues[record.id] = restoredIssue
                continue
            }

            guard let saveURL = await bookmarkStore.resolveURL(
                for: record.id,
                fallbackPath: record.canonicalSavePath
            ) else {
                let issue = TorrentPersistentIssue(
                    kind: .savePathUnavailable,
                    detectedAt: Date(),
                    statusBeforeIssue: baseStatus,
                    debugReason: "Не удалось разрешить bookmark или canonical path."
                )
                persistentIssues[record.id] = issue
                continue
            }

            let archiveURL = await archiveStore.resolveArchiveURL(
                relativePath: archiveStore.relativeArchivePath(for: record.id)
            )
            guard fileManager.fileExists(atPath: archiveURL.path) else {
                if baseStatus.isActive, restoredIssue == nil {
                    fallbackStatusesByID[record.id] = record.progress >= 1.0 ? .completed : .stopped
                }
                continue
            }

            // Do not register sleeping torrents with the engine automatically at relaunch.
            // Otherwise libtorrent starts a recheck even for paused state and overwrites
            // saved progress with an intermediate `checking` value.
            guard baseStatus.isActive, restoredIssue == nil else {
                if let restoredIssue {
                    persistentIssues[record.id] = restoredIssue
                }
                continue
            }

            let restoreEntry = SessionRestoreEntry(
                torrentID: record.id,
                attemptID: record.attemptID,
                archivedTorrentPath: archiveURL.path,
                suggestedSavePath: saveURL.path,
                selectedFileIndices: record.selectedFileIndices,
                stopAfterDownload: record.stopAfterDownload,
                shouldStart: true
            )

            if let restoredIssue {
                persistentIssues[record.id] = restoredIssue
            }

            do {
                let restoredSnapshots = try await engine.restoreSession([restoreEntry])
                snapshots.append(contentsOf: restoredSnapshots)
            } catch {
                fallbackStatusesByID[record.id] = record.progress >= 1.0 ? .completed : .stopped
            }
        }

        return SessionRestoreResult(
            snapshots: snapshots,
            persistentIssues: persistentIssues,
            fallbackStatusesByID: fallbackStatusesByID
        )
    }
}
