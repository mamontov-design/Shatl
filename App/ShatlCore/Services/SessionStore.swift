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

nonisolated struct SessionAddLease: Equatable, Sendable {
    fileprivate let torrentID: UUID
    fileprivate let token: UUID
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
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let readSessionData: @Sendable (URL) async throws -> Data
    private let writeSessionData: @Sendable (Data, URL) throws -> Void
    private var persistenceState: PersistenceState
    private var canonicalTorrentRecords: [SessionTorrentRecord]
    private var lastPersistedTorrentRecords: [SessionTorrentRecord]?
    private var addLeaseTokensByTorrentID: [UUID: UUID] = [:]
    private var removalArtifactReservations: Set<UUID> = []
    private var isReconcilingArtifacts = false

    init(
        directories: ShatlDirectories,
        archiveStore: TorrentArchiveStore,
        bookmarkStore: BookmarkStore,
        resumeDataStore: ResumeDataStore? = nil,
        fileManager: FileManager = .default,
        startupMode: SessionStoreStartupMode = .requiresInitialLoad,
        initialRecords: [TorrentRecord] = [],
        readSessionData: @escaping @Sendable (URL) async throws -> Data = { url in
            try Data(contentsOf: url)
        },
        writeSessionData: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.directories = directories
        self.archiveStore = archiveStore
        self.bookmarkStore = bookmarkStore
        self.resumeDataStore = resumeDataStore
        self.fileManager = fileManager
        self.readSessionData = readSessionData
        self.writeSessionData = writeSessionData
        self.persistenceState = startupMode == .alreadyInitialized ? .writable : .awaitingInitialLoad
        self.canonicalTorrentRecords = initialRecords.map {
            Self.makeSessionRecord(from: $0, archiveStore: archiveStore)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func load(expectsExistingSession: Bool = false) async -> SessionLoadResult {
        let applicationSupportDirectoryExists = fileManager.fileExists(
            atPath: directories.applicationSupportURL.path
        )
        let sessionDirectoryExists = fileManager.fileExists(
            atPath: directories.sessionDirectoryURL.path
        )
        let sessionSnapshotExists = fileManager.fileExists(
            atPath: directories.sessionSnapshotURL.path
        )

        if !sessionSnapshotExists, case .writable = persistenceState {
            do {
                try directories.ensureSessionDirectories()
                return .missing
            } catch {
                return .failure(.unreadable)
            }
        }

        if !sessionSnapshotExists {
            do {
                let hasPrimaryRecoveryArtifacts = try hasRecoveryArtifacts()
                let knownSessionStorageIsMissing = expectsExistingSession
                    && (!applicationSupportDirectoryExists
                        || !sessionDirectoryExists
                        || !sessionSnapshotExists)

                if knownSessionStorageIsMissing
                    || hasPrimaryRecoveryArtifacts {
                    return register(.failure(.missingWithRecoveryArtifacts))
                }
            } catch {
                return register(.failure(.unreadable))
            }
        }

        // A persisted snapshot is only one part of the primary restore bundle.
        // Detect deleted or replaced support directories before
        // `ensureSessionDirectories()` can silently recreate them and erase the
        // evidence that the primary session was damaged.
        if sessionSnapshotExists, !hasCompletePrimarySessionStructure() {
            return register(.failure(.missingWithRecoveryArtifacts))
        }

        do {
            try directories.ensureSessionDirectories()
        } catch {
            return register(.failure(.unreadable))
        }

        guard sessionSnapshotExists else {
            if persistenceState == .writable {
                return .missing
            }
            return register(.missing)
        }

        do {
            let data = try await readSessionData(directories.sessionSnapshotURL)
            let header = try decoder.decode(SessionSchemaHeader.self, from: data)
            let supportedVersions = SessionSnapshot.oldestSupportedSchemaVersion...SessionSnapshot.currentSchemaVersion
            guard supportedVersions.contains(header.schemaVersion) else {
                return register(.failure(.unsupportedVersion(found: header.schemaVersion)))
            }

            let snapshot = try decoder.decode(SessionSnapshot.self, from: data)
            canonicalTorrentRecords = snapshot.torrents
            lastPersistedTorrentRecords = snapshot.torrents
            return register(.loaded(snapshot))
        } catch {
            return register(.failure(.unreadable))
        }
    }

    /// Saving stays locked until AppStore has applied the successfully loaded state.
    func acceptInitialLoad() {
        guard persistenceState == .awaitingAcceptance else { return }
        persistenceState = .writable
    }

    func discardFailedSessionAndCreateEmpty() async -> SessionSaveOutcome {
        guard persistenceState == .blocked else { return .blocked }
        persistenceState = .writable
        addLeaseTokensByTorrentID.removeAll()
        removalArtifactReservations.removeAll()
        let outcome = persistCandidate([])
        if outcome != .saved {
            persistenceState = .blocked
            return outcome
        }
        _ = await reconcileOrphanedArtifacts()
        return outcome
    }

    func beginAdd(torrentID: UUID) -> SessionAddLease? {
        guard persistenceState == .writable,
              !isReconcilingArtifacts,
              !canonicalTorrentRecords.contains(where: { $0.torrentID == torrentID }),
              addLeaseTokensByTorrentID[torrentID] == nil,
              !removalArtifactReservations.contains(torrentID) else {
            return nil
        }

        let lease = SessionAddLease(torrentID: torrentID, token: UUID())
        addLeaseTokensByTorrentID[torrentID] = lease.token
        return lease
    }

    @discardableResult
    func commitAdd(_ record: TorrentRecord, lease: SessionAddLease) -> SessionSaveOutcome {
        guard persistenceState == .writable else { return .blocked }
        guard lease.torrentID == record.id,
              addLeaseTokensByTorrentID[record.id] == lease.token,
              !canonicalTorrentRecords.contains(where: { $0.torrentID == record.id }) else {
            return .failed
        }

        var nextRecords = canonicalTorrentRecords
        nextRecords.insert(makeSessionRecord(from: record), at: 0)
        let outcome = persistCandidate(nextRecords)
        if outcome == .saved {
            addLeaseTokensByTorrentID[record.id] = nil
        }
        return outcome
    }

    func abortAdd(_ lease: SessionAddLease) async {
        guard addLeaseTokensByTorrentID[lease.torrentID] == lease.token else { return }
        await archiveStore.removeArchive(for: lease.torrentID)
        await bookmarkStore.removeBookmark(for: lease.torrentID)
        await resumeDataStore?.removeResumeData(for: lease.torrentID)
        addLeaseTokensByTorrentID[lease.torrentID] = nil
    }

    /// Updates durable fields for records that already belong to the session.
    /// Missing records are intentionally preserved; this path cannot change membership.
    @discardableResult
    func updateExisting(from records: [TorrentRecord]) -> SessionSaveOutcome {
        guard persistenceState == .writable else {
            return .blocked
        }

        let updatesByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var nextRecords = canonicalTorrentRecords
        for index in nextRecords.indices {
            guard let record = updatesByID[nextRecords[index].torrentID],
                  record.attemptID == nextRecords[index].attemptID else {
                continue
            }
            nextRecords[index] = makeSessionRecord(from: record)
        }
        return persistCandidate(nextRecords)
    }

    /// Replaces one logical download attempt without allowing a stale update from
    /// the previous attempt to win later.
    @discardableResult
    func commitAttemptTransition(
        _ record: TorrentRecord,
        replacingAttemptID expectedAttemptID: UUID
    ) -> SessionSaveOutcome {
        guard persistenceState == .writable else { return .blocked }
        guard let index = canonicalTorrentRecords.firstIndex(where: {
            $0.torrentID == record.id && $0.attemptID == expectedAttemptID
        }) else {
            return .failed
        }

        var nextRecords = canonicalTorrentRecords
        nextRecords[index] = makeSessionRecord(from: record)
        return persistCandidate(nextRecords)
    }

    @discardableResult
    func commitRemoval(torrentID: UUID) -> SessionSaveOutcome {
        guard persistenceState == .writable else { return .blocked }
        guard canonicalTorrentRecords.contains(where: { $0.torrentID == torrentID }) else {
            return .failed
        }

        removalArtifactReservations.insert(torrentID)
        let nextRecords = canonicalTorrentRecords.filter { $0.torrentID != torrentID }
        let outcome = persistCandidate(nextRecords)
        if outcome != .saved {
            removalArtifactReservations.remove(torrentID)
        }
        return outcome
    }

    func finalizeRemovalArtifacts(torrentID: UUID) async {
        await archiveStore.removeArchive(for: torrentID)
        await bookmarkStore.removeBookmark(for: torrentID)
        await resumeDataStore?.removeResumeData(for: torrentID)
        removalArtifactReservations.remove(torrentID)
    }

    @discardableResult
    func flush() -> SessionSaveOutcome {
        persistCandidate(canonicalTorrentRecords)
    }

    /// Rewrites the last committed snapshot even when nothing changed. A
    /// `.saved` result from other commits may skip the write, so only this
    /// proves that session storage accepts writes again.
    @discardableResult
    func verifyWritable() -> SessionSaveOutcome {
        persistCandidate(canonicalTorrentRecords, forceWrite: true)
    }

    /// Directory-wide reconciliation is a maintenance operation, never part of
    /// progress/status persistence. Call it only while user mutations are blocked.
    @discardableResult
    func reconcileOrphanedArtifacts() async -> SessionSaveOutcome {
        guard persistenceState == .writable, !isReconcilingArtifacts else { return .blocked }
        isReconcilingArtifacts = true
        defer { isReconcilingArtifacts = false }

        let protectedIDs = Set(canonicalTorrentRecords.map(\.torrentID))
            .union(addLeaseTokensByTorrentID.keys)
            .union(removalArtifactReservations)
        await archiveStore.cleanupOrphanedArchives(validTorrentIDs: protectedIDs)
        await bookmarkStore.cleanupOrphanedBookmarks(validTorrentIDs: protectedIDs)
        await resumeDataStore?.cleanupOrphanedResumeData(validTorrentIDs: protectedIDs)
        return .saved
    }

    #if DEBUG
    /// Full replacement is intentionally test-only. Production callers must use
    /// add/update/remove commands so a stale snapshot cannot change membership.
    @discardableResult
    func replaceAllRecordsForTesting(
        from records: [TorrentRecord],
        reconcileOrphanedArtifacts: Bool = true
    ) async -> SessionSaveOutcome {
        let outcome = persistCandidate(records.map { makeSessionRecord(from: $0) })
        if outcome == .saved, reconcileOrphanedArtifacts {
            _ = await self.reconcileOrphanedArtifacts()
        }
        return outcome
    }
    #endif

    private func persistCandidate(
        _ records: [SessionTorrentRecord],
        forceWrite: Bool = false
    ) -> SessionSaveOutcome {
        guard persistenceState == .writable else { return .blocked }

        do {
            try directories.ensureSessionDirectories()
        } catch {
            return .failed
        }

        let snapshot = makeSnapshot(from: records)
        if !forceWrite, snapshot.torrents == lastPersistedTorrentRecords {
            canonicalTorrentRecords = records
            return .saved
        }

        do {
            let data = try encoder.encode(snapshot)
            try writeSessionData(data, directories.sessionSnapshotURL)
            canonicalTorrentRecords = records
            lastPersistedTorrentRecords = snapshot.torrents
            return .saved
        } catch {
            return .failed
        }
    }

    private func makeSnapshot(from records: [SessionTorrentRecord]) -> SessionSnapshot {
        SessionSnapshot(
            schemaVersion: SessionSnapshot.currentSchemaVersion,
            savedAt: Date(),
            torrents: records
        )
    }

    private func makeSessionRecord(from record: TorrentRecord) -> SessionTorrentRecord {
        Self.makeSessionRecord(from: record, archiveStore: archiveStore)
    }

    private nonisolated static func makeSessionRecord(
        from record: TorrentRecord,
        archiveStore: TorrentArchiveStore
    ) -> SessionTorrentRecord {
        SessionTorrentRecord(
            torrentID: record.id,
            attemptID: record.attemptID,
            infoHash: record.infoHash,
            originalName: record.originalName,
            alias: record.alias,
            status: normalizedPersistedStatus(for: record),
            // libtorrent can temporarily lower progress during a recheck.
            // Persist the last confirmed maximum to avoid showing a false
            // rollback to zero after relaunch.
            progress: max(record.progress, record.lastKnownProgress),
            canonicalSavePath: record.canonicalSavePath,
            stopAfterDownload: record.stopAfterDownload,
            selectedFileIndices: record.selectedFileIndices,
            selectedFileRelativePaths: TorrentPathSafety.normalizedRelativePaths(record.selectedFileRelativePaths),
            selectedFileCount: record.selectedFileCount,
            totalFileCount: record.totalFileCount,
            archivedTorrentRelativePath: archiveStore.relativeArchivePath(for: record.id),
            materializedSelectionFootprint: record.materializedSelectionFootprint,
            persistentIssue: record.persistentIssue,
            resumeCheckpointedAt: record.resumeCheckpointedAt,
            resumeCheckpointProgress: record.resumeCheckpointProgress
        )
    }

    private nonisolated static func normalizedPersistedStatus(for record: TorrentRecord) -> TorrentStatus {
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
            guard fileManager.fileExists(atPath: artifactDirectory.url.path) else {
                continue
            }
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

    private func hasCompletePrimarySessionStructure() -> Bool {
        let requiredDirectories = [
            directories.sessionDirectoryURL,
            directories.archivedTorrentsDirectoryURL,
            directories.bookmarksDirectoryURL,
            directories.resumeDataDirectoryURL,
        ]

        return requiredDirectories.allSatisfy { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }
}

private nonisolated struct SessionSchemaHeader: Decodable {
    var schemaVersion: Int
}
