// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated enum SessionStoreStartupMode: Sendable {
    case requiresInitialLoad
    case alreadyInitialized
}

nonisolated enum SessionLoadIssue: Equatable, Sendable {
    case unreadable
    case unsupportedVersion(found: Int)
    case missingWithRecoveryArtifacts
}

nonisolated enum SessionLoadResult: Sendable {
    case missing
    case loaded(SessionSnapshot)
    case failure(SessionLoadIssue)

    var snapshot: SessionSnapshot? {
        guard case let .loaded(snapshot) = self else { return nil }
        return snapshot
    }
}

nonisolated enum SessionSaveOutcome: Equatable, Sendable {
    case saved
    case blocked
    case failed
}

/// Persists durable session state and must not behave like a cache.
actor SessionStore {
    private enum PersistenceState {
        case awaitingInitialLoad
        case awaitingAcceptance
        case writable
        case blocked
    }

    private let directories: ShatlDirectories
    private let archiveStore: TorrentArchiveStore
    private let bookmarkStore: BookmarkStore
    private let resumeDataStore: ResumeDataStore?
    private let backupStore: SessionBackupStore?
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let readSessionData: @Sendable (URL) async throws -> Data
    private var persistenceState: PersistenceState

    init(
        directories: ShatlDirectories,
        archiveStore: TorrentArchiveStore,
        bookmarkStore: BookmarkStore,
        resumeDataStore: ResumeDataStore? = nil,
        backupStore: SessionBackupStore? = nil,
        fileManager: FileManager = .default,
        startupMode: SessionStoreStartupMode = .requiresInitialLoad,
        readSessionData: @escaping @Sendable (URL) async throws -> Data = { url in
            try Data(contentsOf: url)
        }
    ) {
        self.directories = directories
        self.archiveStore = archiveStore
        self.bookmarkStore = bookmarkStore
        self.resumeDataStore = resumeDataStore
        self.backupStore = backupStore
        self.fileManager = fileManager
        self.readSessionData = readSessionData
        self.persistenceState = startupMode == .alreadyInitialized ? .writable : .awaitingInitialLoad

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func load() async -> SessionLoadResult {
        do {
            try directories.ensureSessionDirectories()
        } catch {
            return register(.failure(.unreadable))
        }

        guard fileManager.fileExists(atPath: directories.sessionSnapshotURL.path) else {
            if persistenceState == .writable {
                return .missing
            }
            do {
                return register(try hasRecoveryArtifacts() ? .failure(.missingWithRecoveryArtifacts) : .missing)
            } catch {
                return register(.failure(.unreadable))
            }
        }

        do {
            let data = try await readSessionData(directories.sessionSnapshotURL)
            let header = try decoder.decode(SessionSchemaHeader.self, from: data)
            let supportedVersions = SessionSnapshot.oldestSupportedSchemaVersion...SessionSnapshot.currentSchemaVersion
            guard supportedVersions.contains(header.schemaVersion) else {
                return register(.failure(.unsupportedVersion(found: header.schemaVersion)))
            }

            return register(.loaded(try decoder.decode(SessionSnapshot.self, from: data)))
        } catch {
            return register(.failure(.unreadable))
        }
    }

    /// Saving stays locked until AppStore has applied the successfully loaded state.
    func acceptInitialLoad() {
        guard persistenceState == .awaitingAcceptance else { return }
        persistenceState = .writable
    }

    func sessionBackupStatus() async -> SessionBackupStatus {
        guard let backupStore else { return .disabled }
        return await backupStore.status()
    }

    func configureSessionBackup(_ configuration: SessionBackupConfiguration) async -> SessionBackupStatus {
        guard let backupStore else { return .disabled }
        return await backupStore.configure(configuration)
    }

    func createSessionBackup() async -> SessionBackupStatus {
        guard let backupStore else { return .disabled }
        return await backupStore.createBackup()
    }

    func restoreSessionBackup() async -> SessionBackupRestoreOutcome {
        guard let backupStore else { return .unavailable(.folderUnavailable) }
        let outcome = await backupStore.restoreBackup()
        if case .restored = outcome {
            persistenceState = .awaitingAcceptance
        }
        return outcome
    }

    func discardFailedSessionAndCreateEmpty() async -> SessionSaveOutcome {
        guard persistenceState == .blocked else { return .blocked }
        persistenceState = .writable
        let outcome = await save(records: [], pruneRestoreArtifacts: true)
        if outcome != .saved {
            persistenceState = .blocked
        }
        return outcome
    }

    @discardableResult
    func saveCriticalState(
        from records: [TorrentRecord],
        pruneRestoreArtifacts: Bool = true
    ) async -> SessionSaveOutcome {
        await save(records: records, pruneRestoreArtifacts: pruneRestoreArtifacts)
    }

    @discardableResult
    func saveProgressBatch(
        from records: [TorrentRecord],
        pruneRestoreArtifacts: Bool = true
    ) async -> SessionSaveOutcome {
        await save(records: records, pruneRestoreArtifacts: pruneRestoreArtifacts)
    }

    private func save(
        records: [TorrentRecord],
        pruneRestoreArtifacts: Bool
    ) async -> SessionSaveOutcome {
        guard persistenceState == .writable else {
            return .blocked
        }

        do {
            try directories.ensureSessionDirectories()
        } catch {
            return .failed
        }

        let validIDs = Set(records.map(\.id))
        let snapshot = makeSnapshot(from: records)

        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: directories.sessionSnapshotURL, options: .atomic)

            if pruneRestoreArtifacts {
                await archiveStore.cleanupOrphanedArchives(validTorrentIDs: validIDs)
                await bookmarkStore.cleanupOrphanedBookmarks(validTorrentIDs: validIDs)
                await resumeDataStore?.cleanupOrphanedResumeData(validTorrentIDs: validIDs)
            }
            _ = await backupStore?.createBackup()
            return .saved
        } catch {
            return .failed
        }
    }

    private func makeSnapshot(from records: [TorrentRecord]) -> SessionSnapshot {
        SessionSnapshot(
            schemaVersion: SessionSnapshot.currentSchemaVersion,
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

    private func register(_ result: SessionLoadResult) -> SessionLoadResult {
        guard persistenceState != .writable else { return result }

        switch result {
        case .missing, .loaded:
            persistenceState = .awaitingAcceptance
        case .failure:
            persistenceState = .blocked
        }
        return result
    }

    private func hasRecoveryArtifacts() throws -> Bool {
        let artifactDirectories: [(url: URL, pathExtension: String)] = [
            (directories.archivedTorrentsDirectoryURL, "torrent"),
            (directories.bookmarksDirectoryURL, "bookmark"),
            (directories.resumeDataDirectoryURL, "fastresume"),
        ]

        for artifactDirectory in artifactDirectories {
            let items = try fileManager.contentsOfDirectory(
                at: artifactDirectory.url,
                includingPropertiesForKeys: nil
            )
            if items.contains(where: { $0.pathExtension.lowercased() == artifactDirectory.pathExtension }) {
                return true
            }
        }
        return false
    }
}

private nonisolated struct SessionSchemaHeader: Decodable {
    var schemaVersion: Int
}
