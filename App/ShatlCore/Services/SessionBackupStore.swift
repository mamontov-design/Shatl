// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import CryptoKit
import Foundation

nonisolated struct SessionBackupConfiguration: Equatable, Sendable {
    var isEnabled: Bool
    var parentDirectoryPath: String
    var parentDirectoryBookmarkData: Data?
}

nonisolated struct SessionBackupDetails: Codable, Equatable, Sendable {
    var createdAt: Date
    var sessionSavedAt: Date
    var torrentCount: Int
    var parentDirectoryPath: String
}

nonisolated enum SessionBackupIssue: String, Codable, Equatable, Sendable {
    case outOfDate
    case folderUnavailable
    case permissionDenied
    case insufficientSpace
    case invalidBackup
    case unknown
}

nonisolated enum SessionBackupStatus: Equatable, Sendable {
    case disabled
    case notCreated
    case current(SessionBackupDetails)
    case stale(lastSuccessful: SessionBackupDetails?, issue: SessionBackupIssue)

    var details: SessionBackupDetails? {
        switch self {
        case .current(let details):
            details
        case .stale(let details, _):
            details
        case .disabled, .notCreated:
            nil
        }
    }
}

nonisolated enum SessionBackupRestoreOutcome: Sendable {
    case restored(SessionSnapshot)
    case unavailable(SessionBackupIssue)
}

private nonisolated struct SessionBackupManifest: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var createdAt: Date
    var sessionSavedAt: Date
    var torrentCount: Int
    var files: [String: String]
}

/// Maintains one verified copy of the complete restore bundle outside Application Support.
actor SessionBackupStore {
    static let directoryName = ".shatl-app-session-backup"

    private let sourceDirectories: ShatlDirectories
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var configuration: SessionBackupConfiguration
    private var currentStatus: SessionBackupStatus

    init(
        sourceDirectories: ShatlDirectories,
        configuration: SessionBackupConfiguration,
        fileManager: FileManager = .default
    ) {
        self.sourceDirectories = sourceDirectories
        self.configuration = configuration
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
        self.currentStatus = configuration.isEnabled ? .notCreated : .disabled
    }

    func status() -> SessionBackupStatus {
        currentStatus
    }

    func configure(_ configuration: SessionBackupConfiguration) async -> SessionBackupStatus {
        self.configuration = configuration
        guard configuration.isEnabled else {
            currentStatus = .disabled
            return currentStatus
        }
        return await inspect()
    }

    func inspect() async -> SessionBackupStatus {
        guard configuration.isEnabled else {
            currentStatus = .disabled
            return currentStatus
        }

        do {
            let (parentURL, didStartAccessing) = try resolveParentDirectory()
            defer {
                if didStartAccessing {
                    parentURL.stopAccessingSecurityScopedResource()
                }
            }

            let backupURL = parentURL.appendingPathComponent(Self.directoryName, isDirectory: true)
            guard fileManager.fileExists(atPath: backupURL.path) else {
                currentStatus = .notCreated
                return currentStatus
            }

            let validation = try validateBackup(at: backupURL, parentDirectoryPath: parentURL.path)
            let primarySavedAt = try? readPrimarySnapshot().savedAt
            if let primarySavedAt, primarySavedAt != validation.snapshot.savedAt {
                currentStatus = .stale(lastSuccessful: validation.details, issue: .outOfDate)
            } else {
                currentStatus = .current(validation.details)
            }
        } catch {
            currentStatus = .stale(
                lastSuccessful: currentStatus.details,
                issue: issue(for: error)
            )
        }
        return currentStatus
    }

    func createBackup() async -> SessionBackupStatus {
        guard configuration.isEnabled else {
            currentStatus = .disabled
            return currentStatus
        }

        do {
            let snapshot = try readPrimarySnapshot()
            let (parentURL, didStartAccessing) = try resolveParentDirectory()
            defer {
                if didStartAccessing {
                    parentURL.stopAccessingSecurityScopedResource()
                }
            }

            try ensureExistingDirectory(parentURL)
            try removeAbandonedStagingDirectories(in: parentURL)

            let stagingURL = parentURL.appendingPathComponent(
                "\(Self.directoryName).staging-\(UUID().uuidString)",
                isDirectory: true
            )
            let destinationURL = parentURL.appendingPathComponent(Self.directoryName, isDirectory: true)

            do {
                try buildStagingBackup(
                    at: stagingURL,
                    snapshot: snapshot,
                    parentDirectoryPath: parentURL.path
                )
                _ = try validateBackup(at: stagingURL, parentDirectoryPath: parentURL.path)
                try replaceBackup(at: destinationURL, with: stagingURL)
            } catch {
                try? fileManager.removeItem(at: stagingURL)
                throw error
            }

            let validation = try validateBackup(at: destinationURL, parentDirectoryPath: parentURL.path)
            currentStatus = .current(validation.details)
        } catch {
            currentStatus = .stale(
                lastSuccessful: currentStatus.details,
                issue: issue(for: error)
            )
        }
        return currentStatus
    }

    func restoreBackup() async -> SessionBackupRestoreOutcome {
        guard configuration.isEnabled else {
            return .unavailable(.folderUnavailable)
        }

        do {
            let (parentURL, didStartAccessing) = try resolveParentDirectory()
            defer {
                if didStartAccessing {
                    parentURL.stopAccessingSecurityScopedResource()
                }
            }

            let backupURL = parentURL.appendingPathComponent(Self.directoryName, isDirectory: true)
            let validation = try validateBackup(at: backupURL, parentDirectoryPath: parentURL.path)
            let applicationSupportURL = sourceDirectories.applicationSupportURL
            try fileManager.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let stagingURL = applicationSupportURL.appendingPathComponent(
                "Session.restore-staging-\(UUID().uuidString)",
                isDirectory: true
            )
            do {
                try copyRestoreBundle(from: backupURL, to: stagingURL)
                try replaceBackup(at: sourceDirectories.sessionDirectoryURL, with: stagingURL)
            } catch {
                try? fileManager.removeItem(at: stagingURL)
                throw error
            }
            return .restored(validation.snapshot)
        } catch {
            return .unavailable(issue(for: error))
        }
    }

    private func readPrimarySnapshot() throws -> SessionSnapshot {
        let data = try Data(contentsOf: sourceDirectories.sessionSnapshotURL)
        let snapshot = try decoder.decode(SessionSnapshot.self, from: data)
        let supportedVersions = SessionSnapshot.oldestSupportedSchemaVersion...SessionSnapshot.currentSchemaVersion
        guard supportedVersions.contains(snapshot.schemaVersion) else {
            throw SessionBackupError.invalidBackup
        }
        return snapshot
    }

    private func resolveParentDirectory() throws -> (URL, Bool) {
        if let bookmarkData = configuration.parentDirectoryBookmarkData {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return (url, url.startAccessingSecurityScopedResource())
        }

        return (
            URL(fileURLWithPath: configuration.parentDirectoryPath, isDirectory: true),
            false
        )
    }

    private func ensureExistingDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SessionBackupError.folderUnavailable
        }
    }

    private func buildStagingBackup(
        at stagingURL: URL,
        snapshot: SessionSnapshot,
        parentDirectoryPath: String
    ) throws {
        try copyRestoreBundle(from: sourceDirectories.sessionDirectoryURL, to: stagingURL)
        let files = try checksums(in: stagingURL, excludingManifest: true)
        let manifest = SessionBackupManifest(
            schemaVersion: SessionBackupManifest.currentSchemaVersion,
            createdAt: Date(),
            sessionSavedAt: snapshot.savedAt,
            torrentCount: snapshot.torrents.count,
            files: files
        )
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(
            to: stagingURL.appendingPathComponent("manifest.json", isDirectory: false),
            options: .atomic
        )
    }

    private func copyRestoreBundle(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        for name in ["session.json", "Torrents", "Bookmarks", "ResumeData"] {
            let sourceItemURL = sourceURL.appendingPathComponent(name)
            let destinationItemURL = destinationURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: sourceItemURL.path) {
                try fileManager.copyItem(at: sourceItemURL, to: destinationItemURL)
            } else if name != "session.json" {
                try fileManager.createDirectory(
                    at: destinationItemURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } else {
                throw SessionBackupError.invalidBackup
            }
        }
    }

    private func replaceBackup(at destinationURL: URL, with stagingURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: stagingURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        }
    }

    private func validateBackup(
        at backupURL: URL,
        parentDirectoryPath: String
    ) throws -> (snapshot: SessionSnapshot, details: SessionBackupDetails) {
        let manifestURL = backupURL.appendingPathComponent("manifest.json", isDirectory: false)
        let manifest = try decoder.decode(
            SessionBackupManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.schemaVersion == SessionBackupManifest.currentSchemaVersion else {
            throw SessionBackupError.invalidBackup
        }

        let actualChecksums = try checksums(in: backupURL, excludingManifest: true)
        guard actualChecksums == manifest.files,
              let expectedSessionChecksum = manifest.files["session.json"] else {
            throw SessionBackupError.checksumMismatch
        }

        let sessionURL = backupURL.appendingPathComponent("session.json", isDirectory: false)
        let sessionData = try Data(contentsOf: sessionURL)
        guard Self.sha256Hex(sessionData) == expectedSessionChecksum else {
            throw SessionBackupError.invalidBackup
        }

        let snapshot = try decoder.decode(SessionSnapshot.self, from: sessionData)
        let supportedVersions = SessionSnapshot.oldestSupportedSchemaVersion...SessionSnapshot.currentSchemaVersion
        guard supportedVersions.contains(snapshot.schemaVersion),
              snapshot.torrents.count == manifest.torrentCount,
              snapshot.savedAt == manifest.sessionSavedAt else {
            throw SessionBackupError.sessionMismatch
        }

        return (
            snapshot,
            SessionBackupDetails(
                createdAt: manifest.createdAt,
                sessionSavedAt: manifest.sessionSavedAt,
                torrentCount: manifest.torrentCount,
                parentDirectoryPath: parentDirectoryPath
            )
        )
    }

    private func checksums(in rootURL: URL, excludingManifest: Bool) throws -> [String: String] {
        let canonicalRootURL = rootURL.resolvingSymlinksInPath()
        guard let enumerator = fileManager.enumerator(
            at: canonicalRootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw SessionBackupError.invalidBackup
        }

        var result: [String: String] = [:]
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw SessionBackupError.invalidBackup
            }
            guard values.isRegularFile == true else { continue }

            let rootComponents = canonicalRootURL.pathComponents
            let fileComponents = fileURL.resolvingSymlinksInPath().pathComponents
            guard fileComponents.count > rootComponents.count,
                  Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
                throw SessionBackupError.invalidBackup
            }
            let relativePath = fileComponents
                .dropFirst(rootComponents.count)
                .joined(separator: "/")
            if excludingManifest, relativePath == "manifest.json" { continue }
            result[relativePath] = Self.sha256Hex(try Data(contentsOf: fileURL))
        }
        return result
    }

    private func removeAbandonedStagingDirectories(in parentURL: URL) throws {
        let items = try fileManager.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: nil
        )
        let prefix = "\(Self.directoryName).staging-"
        for item in items where item.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: item)
        }
    }

    private func issue(for error: Error) -> SessionBackupIssue {
        if let backupError = error as? SessionBackupError {
            switch backupError {
            case .folderUnavailable:
                return .folderUnavailable
            case .invalidBackup:
                return .invalidBackup
            case .checksumMismatch:
                return .invalidBackup
            case .sessionMismatch:
                return .invalidBackup
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return .folderUnavailable
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return .permissionDenied
            case NSFileWriteVolumeReadOnlyError:
                return .permissionDenied
            case NSFileWriteOutOfSpaceError:
                return .insufficientSpace
            default:
                break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain {
            switch POSIXErrorCode(rawValue: Int32(nsError.code)) {
            case .ENOENT, .ENXIO:
                return .folderUnavailable
            case .EACCES, .EPERM, .EROFS:
                return .permissionDenied
            case .ENOSPC, .EDQUOT:
                return .insufficientSpace
            default:
                break
            }
        }
        return .unknown
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private nonisolated enum SessionBackupError: Error {
    case folderUnavailable
    case invalidBackup
    case checksumMismatch
    case sessionMismatch
}
