// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated struct DiskIssueEvaluation: Sendable {
    var checkedTorrentIDs: [UUID]
    var issuesByTorrentID: [UUID: TorrentPersistentIssue]
    var footprintsByTorrentID: [UUID: MaterializedSelectionFootprint]
}

nonisolated struct DiskIssueValidationResult: Sendable {
    var issue: TorrentPersistentIssue?
    var footprint: MaterializedSelectionFootprint?
}

/// Uses one disk-issue model for relaunch, sleeping torrents, and active runtime:
/// - selected files are described by the archived `.torrent`;
/// - durable state stores only the mask of materialized selected files;
/// - `missingContent` appears when a selected file previously observed by Shatl
///   is no longer present on disk.
actor DiskIssueDetector {
    private struct TrackedSelectedFile: Sendable {
        var selectedOrdinal: Int
        var fileIndex: Int
        var relativePath: String
    }

    private let engine: any TorrentEngine
    private let archiveStore: TorrentArchiveStore
    private let bookmarkStore: BookmarkStore
    private let fileManager: FileManager
    private var trackedFilesCache: [UUID: [TrackedSelectedFile]] = [:]

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

    func startupCheck(for records: [TorrentRecord]) async -> DiskIssueEvaluation {
        await evaluate(records: records)
    }

    func validateAfterUserAction(for record: TorrentRecord) async -> DiskIssueValidationResult {
        await evaluateRecord(for: record)
    }

    func captureCurrentFootprint(for record: TorrentRecord) async -> MaterializedSelectionFootprint? {
        guard let saveURL = await bookmarkStore.resolveURL(
            for: record.id,
            fallbackPath: record.canonicalSavePath
        ) else {
            return nil
        }

        return await captureCurrentFootprint(for: record, saveURL: saveURL)
    }

    func captureCurrentFootprint(for record: TorrentRecord, saveURL: URL) async -> MaterializedSelectionFootprint? {
        guard let trackedFiles = await trackedSelectedFiles(for: record) else {
            return nil
        }

        return diskFootprint(
            for: trackedFiles,
            saveURL: saveURL
        )
    }

    private func evaluate(records: [TorrentRecord]) async -> DiskIssueEvaluation {
        var checkedTorrentIDs: [UUID] = []
        var issuesByTorrentID: [UUID: TorrentPersistentIssue] = [:]
        var footprintsByTorrentID: [UUID: MaterializedSelectionFootprint] = [:]

        for record in records {
            checkedTorrentIDs.append(record.id)

            let result = await evaluateRecord(for: record)
            if let issue = result.issue {
                issuesByTorrentID[record.id] = issue
            }

            if let footprint = result.footprint {
                footprintsByTorrentID[record.id] = footprint
            }
        }

        return DiskIssueEvaluation(
            checkedTorrentIDs: checkedTorrentIDs,
            issuesByTorrentID: issuesByTorrentID,
            footprintsByTorrentID: footprintsByTorrentID
        )
    }

    private func evaluateRecord(for record: TorrentRecord) async -> DiskIssueValidationResult {
        let statusBeforeIssue = record.persistentIssue?.statusBeforeIssue ?? record.status

        guard let saveURL = await bookmarkStore.resolveURL(
            for: record.id,
            fallbackPath: record.canonicalSavePath
        ) else {
            return DiskIssueValidationResult(
                issue: TorrentPersistentIssue(
                    kind: .savePathUnavailable,
                    detectedAt: Date(),
                    statusBeforeIssue: statusBeforeIssue,
                    debugReason: "Не удалось получить доступ к папке сохранения."
                ),
                footprint: record.materializedSelectionFootprint
            )
        }

        guard let trackedFiles = await trackedSelectedFiles(for: record), !trackedFiles.isEmpty else {
            return DiskIssueValidationResult(
                issue: nil,
                footprint: record.materializedSelectionFootprint
            )
        }

        let previousFootprint = normalizedFootprint(
            record.materializedSelectionFootprint,
            selectedFileCount: trackedFiles.count
        )
        let expectedFootprint: MaterializedSelectionFootprint
        let currentFootprint: MaterializedSelectionFootprint

        currentFootprint = diskFootprint(for: trackedFiles, saveURL: saveURL)
        expectedFootprint = expectedMaterializedFootprint(
            for: record,
            trackedFiles: trackedFiles,
            previousFootprint: previousFootprint,
            candidateFootprint: currentFootprint
        )

        let missingOrdinals = expectedFootprint.missingOrdinals(comparedTo: currentFootprint)
        if let missingOrdinal = missingOrdinals.sorted().first,
           let missingFile = trackedFiles.first(where: { $0.selectedOrdinal == missingOrdinal }) {
            return DiskIssueValidationResult(
                issue: TorrentPersistentIssue(
                    kind: .missingContent,
                    detectedAt: Date(),
                    statusBeforeIssue: statusBeforeIssue,
                    debugReason: "Не найден выбранный файл: \(missingFile.relativePath)"
                ),
                footprint: previousFootprint.isEmpty ? nil : previousFootprint
            )
        }

        let nextFootprint = previousFootprint.union(currentFootprint)
        return DiskIssueValidationResult(
            issue: nil,
            footprint: nextFootprint
        )
    }

    private func trackedSelectedFiles(for record: TorrentRecord) async -> [TrackedSelectedFile]? {
        if let cached = trackedFilesCache[record.id] {
            return cached
        }

        let archiveURL = await archiveStore.resolveArchiveURL(
            relativePath: archiveStore.relativeArchivePath(for: record.id)
        )
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            return nil
        }

        let contentFiles: [TorrentContentFileDescriptor]
        do {
            contentFiles = try await engine.inspectTorrentContents(at: archiveURL.path)
        } catch {
            return nil
        }

        let selectedIndexToOrdinal = Dictionary(
            uniqueKeysWithValues: record.selectedFileIndices.enumerated().map { ($1, $0) }
        )

        let trackedFiles = contentFiles
            .compactMap { file -> TrackedSelectedFile? in
                guard let selectedOrdinal = selectedIndexToOrdinal[file.fileIndex] else { return nil }
                return TrackedSelectedFile(
                    selectedOrdinal: selectedOrdinal,
                    fileIndex: file.fileIndex,
                    relativePath: normalizeRelativePath(file.relativePath)
                )
            }
            .sorted { $0.selectedOrdinal < $1.selectedOrdinal }

        trackedFilesCache[record.id] = trackedFiles
        return trackedFiles
    }

    private func diskFootprint(
        for trackedFiles: [TrackedSelectedFile],
        saveURL: URL,
        limitedTo ordinalsFilter: Set<Int>? = nil
    ) -> MaterializedSelectionFootprint {
        var materializedOrdinals: Set<Int> = []

        for trackedFile in trackedFiles {
            if let ordinalsFilter, !ordinalsFilter.contains(trackedFile.selectedOrdinal) {
                continue
            }

            let fileURL = saveURL.appendingPathComponent(trackedFile.relativePath, isDirectory: false)
            if fileManager.fileExists(atPath: fileURL.path) {
                materializedOrdinals.insert(trackedFile.selectedOrdinal)
            }
        }

        return MaterializedSelectionFootprint(
            selectedFileCount: trackedFiles.count,
            materializedOrdinals: materializedOrdinals
        )
    }

    private func expectedMaterializedFootprint(
        for record: TorrentRecord,
        trackedFiles: [TrackedSelectedFile],
        previousFootprint: MaterializedSelectionFootprint,
        candidateFootprint: MaterializedSelectionFootprint
    ) -> MaterializedSelectionFootprint {
        let baseStatus = record.persistentIssue?.statusBeforeIssue ?? record.status

        if baseStatus == .completed || baseStatus == .seeding || record.progress >= 1.0 {
            return MaterializedSelectionFootprint(
                selectedFileCount: trackedFiles.count,
                materializedOrdinals: Set(0..<trackedFiles.count)
            )
        }

        if !candidateFootprint.isEmpty {
            return previousFootprint.union(candidateFootprint)
        }

        if !previousFootprint.isEmpty {
            return previousFootprint
        }

        if trackedFiles.count == 1 && record.progress > 0 {
            return MaterializedSelectionFootprint(
                selectedFileCount: 1,
                materializedOrdinals: Set([0])
            )
        }

        return MaterializedSelectionFootprint.empty(selectedFileCount: trackedFiles.count)
    }

    private func normalizedFootprint(
        _ footprint: MaterializedSelectionFootprint?,
        selectedFileCount: Int
    ) -> MaterializedSelectionFootprint {
        guard let footprint else {
            return .empty(selectedFileCount: selectedFileCount)
        }

        if footprint.selectedFileCount == selectedFileCount {
            return footprint
        }

        return MaterializedSelectionFootprint(
            selectedFileCount: selectedFileCount,
            materializedOrdinals: Set(
                footprint.materializedOrdinals.filter { $0 < selectedFileCount }
            )
        )
    }

    private func normalizeRelativePath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
