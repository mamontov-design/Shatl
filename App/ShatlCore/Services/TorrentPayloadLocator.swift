// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated enum ManagedTorrentPayloadUnresolvedReason: String, Sendable, Equatable {
    case savePathUnresolved = "save-path-unresolved"
    case archiveMissing = "archive-missing"
    case archiveInspectFailed = "archive-inspect-failed"
    case selectedFilesUnresolved = "selected-files-unresolved"
}

nonisolated struct ManagedTorrentPayloadResolutionFailure: Sendable, Equatable {
    var reason: ManagedTorrentPayloadUnresolvedReason
    var savePath: String?
    var archivePath: String
    var selectedFileCount: Int
    var totalFileCount: Int
    var inspectedFileCount: Int?
}

nonisolated enum ManagedTorrentPayloadResolution: Sendable, Equatable {
    case resolved(ManagedTorrentPayload)
    case unresolved(ManagedTorrentPayloadResolutionFailure)
}

nonisolated enum ManagedTorrentPayloadSource: String, Sendable, Equatable {
    case archive
    case storedManifest = "stored-manifest"
}

nonisolated struct ManagedTorrentPayload: Sendable, Equatable {
    var saveURL: URL
    var managedFiles: [ManagedTorrentFile]
    var source: ManagedTorrentPayloadSource

    var managedFileURLs: [URL] {
        managedFiles.map(\.fileURL)
    }
}

nonisolated struct ManagedTorrentFile: Sendable, Equatable {
    var relativePath: String
    var fileURL: URL
}

nonisolated struct ManagedTorrentLocation: Sendable, Equatable {
    var saveURL: URL
    var openItemURL: URL?
    var revealItemURL: URL
}

/// Provides one source of truth for payload file locations used by deletion,
/// Reveal in Finder, and the future Open action.
actor TorrentPayloadLocator {
    private static let logger = ShatlLog.payload

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

    func managedPayloadResolution(for record: TorrentRecord) async -> ManagedTorrentPayloadResolution {
        guard let saveURL = await resolvedSaveURL(for: record) else {
            return .unresolved(
                ManagedTorrentPayloadResolutionFailure(
                    reason: .savePathUnresolved,
                    savePath: record.canonicalSavePath,
                    archivePath: await archivePath(for: record),
                    selectedFileCount: record.selectedFileCount,
                    totalFileCount: record.totalFileCount,
                    inspectedFileCount: nil
                )
            )
        }

        let archiveURL = await archiveStore.resolveArchiveURL(
            relativePath: archiveStore.relativeArchivePath(for: record.id)
        )
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            if let payload = managedPayloadFromStoredManifest(for: record, saveURL: saveURL) {
                Self.logger.notice(
                    "Managed payload resolved from stored manifest for torrent id=\(record.id.uuidString) reason=archive-missing fileCount=\(payload.managedFiles.count)"
                )
                return .resolved(payload)
            }

            return .unresolved(
                ManagedTorrentPayloadResolutionFailure(
                    reason: .archiveMissing,
                    savePath: saveURL.path,
                    archivePath: archiveURL.path,
                    selectedFileCount: record.selectedFileCount,
                    totalFileCount: record.totalFileCount,
                    inspectedFileCount: nil
                )
            )
        }

        let contentFiles: [TorrentContentFileDescriptor]
        do {
            contentFiles = try await engine.inspectTorrentContents(at: archiveURL.path)
        } catch {
            Self.logger.notice(
                "Managed payload inspect failed for torrent id=\(record.id.uuidString) archivePath=\(archiveURL.path) reason=\((error as NSError).localizedDescription)"
            )
            if let payload = managedPayloadFromStoredManifest(for: record, saveURL: saveURL) {
                Self.logger.notice(
                    "Managed payload resolved from stored manifest for torrent id=\(record.id.uuidString) reason=archive-inspect-failed fileCount=\(payload.managedFiles.count)"
                )
                return .resolved(payload)
            }

            return .unresolved(
                ManagedTorrentPayloadResolutionFailure(
                    reason: .archiveInspectFailed,
                    savePath: saveURL.path,
                    archivePath: archiveURL.path,
                    selectedFileCount: record.selectedFileCount,
                    totalFileCount: record.totalFileCount,
                    inspectedFileCount: nil
                )
            )
        }

        let selectedIndices = Set(record.selectedFileIndices)
        let managedFiles = contentFiles
            .filter { selectedIndices.contains($0.fileIndex) }
            .compactMap { TorrentPathSafety.normalizedRelativePath($0.relativePath) }
            .map {
                ManagedTorrentFile(
                    relativePath: $0,
                    fileURL: saveURL.appendingPathComponent($0, isDirectory: false)
                )
            }

        guard !managedFiles.isEmpty else {
            if let payload = managedPayloadFromStoredManifest(for: record, saveURL: saveURL) {
                Self.logger.notice(
                    "Managed payload resolved from stored manifest for torrent id=\(record.id.uuidString) reason=selected-files-unresolved fileCount=\(payload.managedFiles.count)"
                )
                return .resolved(payload)
            }

            return .unresolved(
                ManagedTorrentPayloadResolutionFailure(
                    reason: .selectedFilesUnresolved,
                    savePath: saveURL.path,
                    archivePath: archiveURL.path,
                    selectedFileCount: record.selectedFileCount,
                    totalFileCount: record.totalFileCount,
                    inspectedFileCount: contentFiles.count
                )
            )
        }

        return .resolved(
            ManagedTorrentPayload(
                saveURL: saveURL,
                managedFiles: managedFiles,
                source: .archive
            )
        )
    }

    func managedPayload(for record: TorrentRecord) async -> ManagedTorrentPayload? {
        switch await managedPayloadResolution(for: record) {
        case .resolved(let payload):
            return payload
        case .unresolved:
            return nil
        }
    }

    func primaryLocation(for record: TorrentRecord) async -> ManagedTorrentLocation? {
        guard let saveURL = await resolvedSaveURL(for: record) else {
            return nil
        }

        guard let payload = await managedPayload(for: record) else {
            return ManagedTorrentLocation(
                saveURL: saveURL,
                openItemURL: nil,
                revealItemURL: saveURL
            )
        }

        let revealItemURL: URL
        let openItemURL: URL?

        if payload.managedFiles.count == 1, let onlyManagedFile = payload.managedFiles.first {
            let onlyFileURL = onlyManagedFile.fileURL
            let normalizedRelativePath = TorrentPathSafety.normalizedRelativePath(onlyManagedFile.relativePath) ?? ""
            let hasTorrentRootFolder = normalizedRelativePath.contains("/")
            var isDirectory: ObjCBool = false
            let fileExists = fileManager.fileExists(atPath: onlyFileURL.path, isDirectory: &isDirectory)

            if fileExists, !isDirectory.boolValue, !hasTorrentRootFolder {
                openItemURL = record.isFinishedForOpening ? onlyFileURL : nil
                revealItemURL = onlyFileURL
            } else {
                let parentFolderURL = commonAncestorURL(
                    for: [onlyFileURL],
                    boundary: saveURL
                ) ?? saveURL

                revealItemURL = fileManager.fileExists(atPath: parentFolderURL.path)
                    ? parentFolderURL
                    : saveURL
                openItemURL = nil
            }
        } else {
            let commonAncestor = commonAncestorURL(
                for: payload.managedFileURLs,
                boundary: saveURL
            ) ?? saveURL

            revealItemURL = fileManager.fileExists(atPath: commonAncestor.path)
                ? commonAncestor
                : saveURL
            openItemURL = nil
        }

        return ManagedTorrentLocation(
            saveURL: saveURL,
            openItemURL: openItemURL,
            revealItemURL: revealItemURL
        )
    }

    private func resolvedSaveURL(for record: TorrentRecord) async -> URL? {
        await bookmarkStore.resolveURL(
            for: record.id,
            fallbackPath: record.canonicalSavePath
        )
    }

    private func archivePath(for record: TorrentRecord) async -> String {
        let archiveURL = await archiveStore.resolveArchiveURL(
            relativePath: archiveStore.relativeArchivePath(for: record.id)
        )
        return archiveURL.path
    }

    private func commonAncestorURL(for fileURLs: [URL], boundary: URL) -> URL? {
        guard let firstURL = fileURLs.first else { return nil }

        let boundaryComponents = boundary.standardizedFileURL.pathComponents
        var commonComponents = firstURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .pathComponents

        for fileURL in fileURLs.dropFirst() {
            let components = fileURL
                .deletingLastPathComponent()
                .standardizedFileURL
                .pathComponents
            let sharedCount = zip(commonComponents, components)
                .prefix { $0 == $1 }
                .count
            commonComponents = Array(commonComponents.prefix(sharedCount))
        }

        guard commonComponents.count >= boundaryComponents.count else {
            return nil
        }

        let clampedComponents: [String]
        if Array(commonComponents.prefix(boundaryComponents.count)) == boundaryComponents {
            clampedComponents = commonComponents
        } else {
            clampedComponents = boundaryComponents
        }

        guard let path = NSString.path(withComponents: clampedComponents) as String?,
              !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func managedPayloadFromStoredManifest(
        for record: TorrentRecord,
        saveURL: URL
    ) -> ManagedTorrentPayload? {
        let managedFiles = TorrentPathSafety.normalizedRelativePaths(record.selectedFileRelativePaths)
            .map {
                ManagedTorrentFile(
                    relativePath: $0,
                    fileURL: saveURL.appendingPathComponent($0, isDirectory: false)
                )
            }
            .filter { isDescendant($0.fileURL, of: saveURL) }

        guard !managedFiles.isEmpty else { return nil }

        return ManagedTorrentPayload(
            saveURL: saveURL,
            managedFiles: managedFiles,
            source: .storedManifest
        )
    }

    private func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents

        guard candidateComponents.count > ancestorComponents.count else {
            return false
        }

        return Array(candidateComponents.prefix(ancestorComponents.count)) == ancestorComponents
    }
}
