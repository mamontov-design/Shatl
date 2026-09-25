// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated enum ManagedTorrentPayloadUnresolvedReason: String, Sendable, Equatable {
    case savePathUnresolved = "save-path-unresolved"
    case archiveMissing = "archive-missing"
    case archiveInspectFailed = "archive-inspect-failed"
    case selectedFilesUnresolved = "selected-files-unresolved"
    case unsafeManifest = "unsafe-manifest"
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
    var relativePathComponents: [String]
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
            if !record.selectedFileRelativePaths.isEmpty {
                guard let payload = managedPayloadFromStoredManifest(for: record, saveURL: saveURL) else {
                    return .unresolved(
                        resolutionFailure(
                            reason: .unsafeManifest,
                            record: record,
                            saveURL: saveURL,
                            archivePath: archiveURL.path,
                            inspectedFileCount: nil
                        )
                    )
                }

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
            if !record.selectedFileRelativePaths.isEmpty,
               let payload = managedPayloadFromStoredManifest(for: record, saveURL: saveURL) {
                Self.logger.notice(
                    "Managed payload resolved from stored manifest for torrent id=\(record.id.uuidString) reason=archive-inspect-failed fileCount=\(payload.managedFiles.count)"
                )
                return .resolved(payload)
            }

            if !record.selectedFileRelativePaths.isEmpty {
                return .unresolved(
                    resolutionFailure(
                        reason: .unsafeManifest,
                        record: record,
                        saveURL: saveURL,
                        archivePath: archiveURL.path,
                        inspectedFileCount: nil
                    )
                )
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
        let selectedContentFiles = contentFiles.filter { selectedIndices.contains($0.fileIndex) }

        guard selectedIndices.count == record.selectedFileIndices.count,
              selectedIndices.count == record.selectedFileCount,
              selectedContentFiles.count == selectedIndices.count else {
            if !record.selectedFileRelativePaths.isEmpty,
               let payload = managedPayloadFromStoredManifest(for: record, saveURL: saveURL) {
                Self.logger.notice(
                    "Managed payload resolved from stored manifest for torrent id=\(record.id.uuidString) reason=selected-files-unresolved fileCount=\(payload.managedFiles.count)"
                )
                return .resolved(payload)
            }

            if !record.selectedFileRelativePaths.isEmpty {
                return .unresolved(
                    resolutionFailure(
                        reason: .unsafeManifest,
                        record: record,
                        saveURL: saveURL,
                        archivePath: archiveURL.path,
                        inspectedFileCount: contentFiles.count
                    )
                )
            }

            return .unresolved(
                resolutionFailure(
                    reason: .selectedFilesUnresolved,
                    record: record,
                    saveURL: saveURL,
                    archivePath: archiveURL.path,
                    inspectedFileCount: contentFiles.count
                )
            )
        }

        guard let managedFiles = makeManagedFiles(
            relativePaths: selectedContentFiles.map(\.relativePath),
            saveURL: saveURL
        ) else {
            return .unresolved(
                resolutionFailure(
                    reason: .unsafeManifest,
                    record: record,
                    saveURL: saveURL,
                    archivePath: archiveURL.path,
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

    /// Every card asks this when it appears, to enable Open and Show in Finder.
    /// They need only the selected files, which the record lists from the same
    /// torrent, so the archive is parsed only for records without that list.
    /// Deletion keeps the archive as its primary manifest.
    func primaryLocation(for record: TorrentRecord) async -> ManagedTorrentLocation? {
        guard let saveURL = await resolvedSaveURL(for: record) else {
            return nil
        }

        var resolvedPayload = managedPayloadFromStoredManifest(for: record, saveURL: saveURL)
        if resolvedPayload == nil {
            resolvedPayload = await managedPayload(for: record)
        }
        guard let payload = resolvedPayload else {
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
        guard record.selectedFileRelativePaths.count == record.selectedFileCount,
              let managedFiles = makeManagedFiles(
                relativePaths: record.selectedFileRelativePaths,
                saveURL: saveURL
              ) else {
            return nil
        }

        return ManagedTorrentPayload(
            saveURL: saveURL,
            managedFiles: managedFiles,
            source: .storedManifest
        )
    }

    private func makeManagedFiles(relativePaths: [String], saveURL: URL) -> [ManagedTorrentFile]? {
        guard !relativePaths.isEmpty else { return nil }

        var normalizedPaths = Set<String>()
        var componentPaths: [[String]] = []

        for relativePath in relativePaths {
            guard let components = TorrentPathSafety.normalizedRelativePathComponents(relativePath) else {
                return nil
            }

            let normalizedPath = components.joined(separator: "/")
            guard normalizedPaths.insert(normalizedPath).inserted else { return nil }
            componentPaths.append(components)
        }

        let pathSets = Set(componentPaths.map { $0.joined(separator: "/") })
        for components in componentPaths where components.count > 1 {
            for prefixLength in 1..<components.count {
                let prefix = components.prefix(prefixLength).joined(separator: "/")
                guard !pathSets.contains(prefix) else { return nil }
            }
        }

        return componentPaths.map { components in
            let relativePath = components.joined(separator: "/")
            return ManagedTorrentFile(
                relativePath: relativePath,
                relativePathComponents: components,
                fileURL: saveURL.appendingPathComponent(relativePath, isDirectory: false)
            )
        }
    }

    private func resolutionFailure(
        reason: ManagedTorrentPayloadUnresolvedReason,
        record: TorrentRecord,
        saveURL: URL,
        archivePath: String,
        inspectedFileCount: Int?
    ) -> ManagedTorrentPayloadResolutionFailure {
        ManagedTorrentPayloadResolutionFailure(
            reason: reason,
            savePath: saveURL.path,
            archivePath: archivePath,
            selectedFileCount: record.selectedFileCount,
            totalFileCount: record.totalFileCount,
            inspectedFileCount: inspectedFileCount
        )
    }
}
