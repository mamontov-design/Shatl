// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated enum TorrentPayloadDeletionOutcome: Sendable, Equatable {
    case deleted(TorrentPayloadDeletionResult)
    case unresolved(ManagedTorrentPayloadResolutionFailure)
}

nonisolated struct TorrentPayloadDeletionResult: Sendable, Equatable {
    var payloadSource: ManagedTorrentPayloadSource = .archive
    var deletedManagedFileCount: Int = 0
    var missingManagedFileCount: Int = 0
    var failedManagedFileCount: Int = 0
    var deletedDirectoryCount: Int = 0
    var deletedSystemSidecarCount: Int = 0
}

/// Keeps payload deletion separate from the engine so Shatl controls
/// partial selections, nested folders, and safe cleanup of empty directories.
actor TorrentPayloadDeletionService {
    private let payloadLocator: TorrentPayloadLocator
    private let fileManager: FileManager

    init(
        payloadLocator: TorrentPayloadLocator,
        fileManager: FileManager = .default
    ) {
        self.payloadLocator = payloadLocator
        self.fileManager = fileManager
    }

    func deletePayload(for record: TorrentRecord) async -> TorrentPayloadDeletionOutcome {
        let payload: ManagedTorrentPayload
        switch await payloadLocator.managedPayloadResolution(for: record) {
        case .resolved(let resolvedPayload):
            payload = resolvedPayload
        case .unresolved(let failure):
            return .unresolved(failure)
        }

        let saveURL = payload.saveURL.standardizedFileURL
        var result = TorrentPayloadDeletionResult(payloadSource: payload.source)
        var candidateDirectoryPaths: Set<String> = []

        let managedFiles = payload.managedFiles
            .map {
                ManagedTorrentFile(
                    relativePath: $0.relativePath,
                    fileURL: $0.fileURL.standardizedFileURL
                )
            }
            .sorted { deeperPathComesFirst(lhs: $0.fileURL, rhs: $1.fileURL) }

        for managedFile in managedFiles {
            let fileURL = managedFile.fileURL
            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    try fileManager.removeItem(at: fileURL)
                    result.deletedManagedFileCount += 1
                    logFileDeletionEvent(
                        "payload.delete.file.deleted",
                        record: record,
                        payload: payload,
                        managedFile: managedFile
                    )
                } catch {
                    result.failedManagedFileCount += 1
                    logFileDeletionEvent(
                        "payload.delete.file.failed",
                        record: record,
                        payload: payload,
                        managedFile: managedFile,
                        error: error
                    )
                }
            } else {
                result.missingManagedFileCount += 1
                logFileDeletionEvent(
                    "payload.delete.file.missing",
                    record: record,
                    payload: payload,
                    managedFile: managedFile
                )
            }

            for directoryURL in candidateDirectories(
                for: fileURL,
                stopAt: saveURL
            ) {
                candidateDirectoryPaths.insert(directoryURL.path)
            }
        }

        let candidateDirectories = candidateDirectoryPaths
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
            .sorted(by: deeperPathComesFirst(lhs:rhs:))

        for directoryURL in candidateDirectories {
            let cleanupResult = cleanupDirectoryIfEffectivelyEmpty(directoryURL)
            result.deletedDirectoryCount += cleanupResult.deletedDirectoryCount
            result.deletedSystemSidecarCount += cleanupResult.deletedSystemSidecarCount
        }

        return .deleted(result)
    }

    private func logFileDeletionEvent(
        _ event: String,
        record: TorrentRecord,
        payload: ManagedTorrentPayload,
        managedFile: ManagedTorrentFile,
        error: Error? = nil
    ) {
        guard ShatlDiskDiagnosticsLog.isEnabled else { return }

        var fields: [String: String] = [
            "torrentID": record.id.uuidString,
            "source": payload.source.rawValue,
            "relativePath": managedFile.relativePath,
            "path": managedFile.fileURL.path
        ]

        if let error {
            fields["reason"] = (error as NSError).localizedDescription
        }

        ShatlDiskDiagnosticsLog.event(event, fields: fields)
    }

    private func candidateDirectories(for fileURL: URL, stopAt boundaryURL: URL) -> [URL] {
        let normalizedBoundary = boundaryURL.standardizedFileURL
        var currentDirectory = fileURL.deletingLastPathComponent().standardizedFileURL
        var directories: [URL] = []

        while isDescendant(currentDirectory, of: normalizedBoundary) {
            directories.append(currentDirectory)
            currentDirectory = currentDirectory.deletingLastPathComponent().standardizedFileURL
        }

        return directories
    }

    private func cleanupDirectoryIfEffectivelyEmpty(
        _ directoryURL: URL
    ) -> (deletedDirectoryCount: Int, deletedSystemSidecarCount: Int) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return (0, 0)
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return (0, 0)
        }

        let ignorableItems = contents.filter { isIgnorableSystemSidecar($0.lastPathComponent) }
        guard contents.count == ignorableItems.count else {
            return (0, 0)
        }

        var deletedSidecars = 0
        for ignorableItem in ignorableItems {
            do {
                try fileManager.removeItem(at: ignorableItem)
                deletedSidecars += 1
            } catch {
                // Preserve the directory when an auxiliary file could not be removed.
                return (0, 0)
            }
        }

        do {
            try fileManager.removeItem(at: directoryURL)
            return (1, deletedSidecars)
        } catch {
            return (0, 0)
        }
    }

    private func isIgnorableSystemSidecar(_ name: String) -> Bool {
        name == ".DS_Store" || name.hasPrefix("._")
    }

    private func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents

        guard candidateComponents.count > ancestorComponents.count else {
            return false
        }

        return Array(candidateComponents.prefix(ancestorComponents.count)) == ancestorComponents
    }

    private func deeperPathComesFirst(lhs: URL, rhs: URL) -> Bool {
        let lhsDepth = lhs.standardizedFileURL.pathComponents.count
        let rhsDepth = rhs.standardizedFileURL.pathComponents.count

        if lhsDepth != rhsDepth {
            return lhsDepth > rhsDepth
        }

        return lhs.path > rhs.path
    }
}
