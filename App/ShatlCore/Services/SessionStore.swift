// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Persists durable session state and must not behave like a cache.
actor SessionStore {
    private let directories: ShatlDirectories
    private let archiveStore: TorrentArchiveStore
    private let bookmarkStore: BookmarkStore
    private let resumeDataStore: ResumeDataStore?
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directories: ShatlDirectories,
        archiveStore: TorrentArchiveStore,
        bookmarkStore: BookmarkStore,
        resumeDataStore: ResumeDataStore? = nil,
        fileManager: FileManager = .default
    ) {
        self.directories = directories
        self.archiveStore = archiveStore
        self.bookmarkStore = bookmarkStore
        self.resumeDataStore = resumeDataStore
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func load() async -> SessionSnapshot? {
        do {
            try directories.ensureSessionDirectories()
            let data = try Data(contentsOf: directories.sessionSnapshotURL)
            return try decoder.decode(SessionSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    func saveCriticalState(
        from records: [TorrentRecord],
        pruneRestoreArtifacts: Bool = true
    ) async {
        await save(records: records, pruneRestoreArtifacts: pruneRestoreArtifacts)
    }

    func saveProgressBatch(
        from records: [TorrentRecord],
        pruneRestoreArtifacts: Bool = true
    ) async {
        await save(records: records, pruneRestoreArtifacts: pruneRestoreArtifacts)
    }

    private func save(
        records: [TorrentRecord],
        pruneRestoreArtifacts: Bool
    ) async {
        do {
            try directories.ensureSessionDirectories()
        } catch {
            return
        }

        let validIDs = Set(records.map(\.id))

        if records.isEmpty {
            if fileManager.fileExists(atPath: directories.sessionSnapshotURL.path) {
                try? fileManager.removeItem(at: directories.sessionSnapshotURL)
            }

            if pruneRestoreArtifacts {
                await archiveStore.cleanupOrphanedArchives(validTorrentIDs: validIDs)
                await bookmarkStore.cleanupOrphanedBookmarks(validTorrentIDs: validIDs)
                await resumeDataStore?.cleanupOrphanedResumeData(validTorrentIDs: validIDs)
            }
            return
        }

        let snapshot = makeSnapshot(from: records)

        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: directories.sessionSnapshotURL, options: .atomic)

            if pruneRestoreArtifacts {
                await archiveStore.cleanupOrphanedArchives(validTorrentIDs: validIDs)
                await bookmarkStore.cleanupOrphanedBookmarks(validTorrentIDs: validIDs)
                await resumeDataStore?.cleanupOrphanedResumeData(validTorrentIDs: validIDs)
            }
        } catch {
            return
        }
    }

    private func makeSnapshot(from records: [TorrentRecord]) -> SessionSnapshot {
        SessionSnapshot(
            schemaVersion: 5,
            savedAt: Date(),
            torrents: records.map {
                let normalizedStatus = normalizedPersistedStatus(for: $0)
                return SessionTorrentRecord(
                    torrentID: $0.id,
                    attemptID: $0.attemptID,
                    infoHash: $0.infoHash,
                    originalName: $0.originalName,
                    alias: $0.alias,
                    status: normalizedStatus,
                    // libtorrent can temporarily lower progress during a recheck.
                    // Persist the last confirmed maximum to avoid showing a false
                    // rollback to zero after relaunch.
                    progress: max($0.progress, $0.lastKnownProgress),
                    canonicalSavePath: $0.canonicalSavePath,
                    stopAfterDownload: $0.stopAfterDownload,
                    selectedFileIndices: $0.selectedFileIndices,
                    selectedFileRelativePaths: TorrentPathSafety.normalizedRelativePaths($0.selectedFileRelativePaths),
                    selectedFileCount: $0.selectedFileCount,
                    totalFileCount: $0.totalFileCount,
                    archivedTorrentRelativePath: archiveStore.relativeArchivePath(for: $0.id),
                    materializedSelectionFootprint: $0.materializedSelectionFootprint,
                    persistentIssue: $0.persistentIssue,
                    resumeCheckpointedAt: $0.resumeCheckpointedAt,
                    resumeCheckpointProgress: $0.resumeCheckpointProgress
                )
            }
        )
    }

    private func normalizedPersistedStatus(for record: TorrentRecord) -> TorrentStatus {
        guard record.persistentIssue == nil,
              record.runtimeErrorState != nil,
              record.status == .error else {
            return record.status
        }

        let durableProgress = max(record.progress, record.lastKnownProgress)
        return durableProgress >= 1.0 ? .completed : .stopped
    }
}
