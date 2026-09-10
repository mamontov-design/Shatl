// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Darwin
import Foundation

nonisolated enum TorrentPayloadDeletionSafetyReason: String, Sendable, Equatable {
    case rootUnavailable = "root-unavailable"
    case safetyContractUnavailable = "safety-contract-unavailable"
    case symlinkComponent = "symlink-component"
    case pathComponentNotDirectory = "path-component-not-directory"
    case objectTypeMismatch = "object-type-mismatch"
    case objectChanged = "object-changed"
    case invalidManifest = "invalid-manifest"
    case filesystemFailure = "filesystem-failure"
}

nonisolated enum TorrentPayloadFileSystemObjectType: String, Sendable, Equatable {
    case regularFile = "regular-file"
    case directory
    case symbolicLink = "symbolic-link"
    case other
}

nonisolated struct TorrentPayloadDeletionSafetyIssue: Sendable, Equatable {
    var relativePath: String
    var reason: TorrentPayloadDeletionSafetyReason
    var actualType: TorrentPayloadFileSystemObjectType?
    var errorCode: Int32?
}

nonisolated struct TorrentPayloadDeletionSafetyFailure: Sendable, Equatable {
    var issues: [TorrentPayloadDeletionSafetyIssue]
}

nonisolated enum SecureTorrentPayloadFileSystemEvent: Sendable, Equatable {
    case didCompletePreflight
    case willDeleteFile(String)
    case willDeleteSidecar(String)
    case willRemoveDirectory(String)
}

nonisolated struct SecureTorrentPayloadFileSystemReport: Sendable, Equatable {
    var deletedFilePaths: [String] = []
    var missingFilePaths: [String] = []
    var failedFileIssues: [TorrentPayloadDeletionSafetyIssue] = []
    var unsafeFileIssues: [TorrentPayloadDeletionSafetyIssue] = []
    var deletedDirectoryCount: Int = 0
    var deletedSidecarCount: Int = 0
    var failedDirectoryCleanupCount: Int = 0
    var unsafeCleanupIssues: [TorrentPayloadDeletionSafetyIssue] = []
}

nonisolated enum SecureTorrentPayloadFileSystemOutcome: Sendable, Equatable {
    case completed(SecureTorrentPayloadFileSystemReport)
    case refused(TorrentPayloadDeletionSafetyFailure)
}

/// Executes destructive payload operations relative to one opened save-root.
/// No payload path is ever passed to a recursive Foundation removal API.
/// Device/inode rechecks detect ordinary replacement races. The final unlink is
/// still name-based, so the kernel and callers with equal filesystem privileges
/// remain part of the trusted boundary.
nonisolated struct SecureTorrentPayloadFileSystem: Sendable {
    typealias EventHook = @Sendable (SecureTorrentPayloadFileSystemEvent) -> Void

    private struct FileIdentity: Equatable {
        var device: UInt64
        var inode: UInt64
    }

    private struct InspectedObject {
        var identity: FileIdentity
        var type: TorrentPayloadFileSystemObjectType
    }

    private enum InspectionOutcome {
        case object(InspectedObject)
        case missing
        case issue(TorrentPayloadDeletionSafetyIssue)
    }

    private enum DirectoryContentsOutcome {
        case contents([String])
        case missing
        case issue(TorrentPayloadDeletionSafetyIssue)
    }

    private let eventHook: EventHook?

    init(eventHook: EventHook? = nil) {
        self.eventHook = eventHook
    }

    func delete(
        saveURL: URL,
        managedFiles: [ManagedTorrentFile]
    ) -> SecureTorrentPayloadFileSystemOutcome {
        let manifestIssues = validateManifest(managedFiles)
        guard manifestIssues.isEmpty else {
            return .refused(TorrentPayloadDeletionSafetyFailure(issues: manifestIssues))
        }

        let rootDescriptor = openRootDirectory(at: saveURL)
        guard rootDescriptor >= 0 else {
            return .refused(
                TorrentPayloadDeletionSafetyFailure(
                    issues: [
                        TorrentPayloadDeletionSafetyIssue(
                            relativePath: "",
                            reason: .rootUnavailable,
                            actualType: nil,
                            errorCode: errno
                        )
                    ]
                )
            )
        }
        defer { Darwin.close(rootDescriptor) }

        let sortedFiles = managedFiles.sorted {
            if $0.relativePathComponents.count != $1.relativePathComponents.count {
                return $0.relativePathComponents.count > $1.relativePathComponents.count
            }
            return $0.relativePath > $1.relativePath
        }

        var preflightIdentities: [String: FileIdentity] = [:]
        var preflightMissingPaths: Set<String> = []
        var preflightIssues: [TorrentPayloadDeletionSafetyIssue] = []

        for managedFile in sortedFiles {
            switch inspect(relativePath: managedFile.relativePath, rootDescriptor: rootDescriptor) {
            case .object(let object) where object.type == .regularFile:
                preflightIdentities[managedFile.relativePath] = object.identity
            case .object(let object):
                preflightIssues.append(
                    typeMismatchIssue(relativePath: managedFile.relativePath, actualType: object.type)
                )
            case .missing:
                preflightMissingPaths.insert(managedFile.relativePath)
            case .issue(let issue):
                preflightIssues.append(issue)
            }
        }

        guard preflightIssues.isEmpty else {
            return .refused(TorrentPayloadDeletionSafetyFailure(issues: preflightIssues))
        }

        eventHook?(.didCompletePreflight)

        var report = SecureTorrentPayloadFileSystemReport(
            missingFilePaths: preflightMissingPaths.sorted()
        )

        for managedFile in sortedFiles where !preflightMissingPaths.contains(managedFile.relativePath) {
            let relativePath = managedFile.relativePath
            eventHook?(.willDeleteFile(relativePath))

            switch inspect(relativePath: relativePath, rootDescriptor: rootDescriptor) {
            case .object(let object) where object.type == .regularFile:
                guard object.identity == preflightIdentities[relativePath] else {
                    report.unsafeFileIssues.append(
                        TorrentPayloadDeletionSafetyIssue(
                            relativePath: relativePath,
                            reason: .objectChanged,
                            actualType: object.type,
                            errorCode: nil
                        )
                    )
                    continue
                }

                let unlinkResult = withRelativeFileSystemPath(relativePath) { path in
                    Darwin.unlinkat(rootDescriptor, path, safeLookupFlags)
                }
                if unlinkResult == 0 {
                    report.deletedFilePaths.append(relativePath)
                } else if errno == ENOENT {
                    report.missingFilePaths.append(relativePath)
                } else {
                    report.failedFileIssues.append(
                        issueForErrno(relativePath: relativePath, errorCode: errno)
                    )
                }
            case .object(let object):
                report.unsafeFileIssues.append(
                    typeMismatchIssue(relativePath: relativePath, actualType: object.type)
                )
            case .missing:
                report.missingFilePaths.append(relativePath)
            case .issue(let issue):
                report.unsafeFileIssues.append(issue)
            }
        }

        guard report.failedFileIssues.isEmpty, report.unsafeFileIssues.isEmpty else {
            report.missingFilePaths = Array(Set(report.missingFilePaths)).sorted()
            return .completed(report)
        }

        let candidateDirectories = directoryCandidates(for: sortedFiles)
        for relativeDirectoryPath in candidateDirectories {
            cleanupDirectory(
                relativePath: relativeDirectoryPath,
                rootDescriptor: rootDescriptor,
                report: &report
            )
        }

        report.missingFilePaths = Array(Set(report.missingFilePaths)).sorted()
        return .completed(report)
    }

    private var safeLookupFlags: Int32 {
        Int32(AT_SYMLINK_NOFOLLOW_ANY | AT_RESOLVE_BENEATH)
    }

    private func validateManifest(
        _ managedFiles: [ManagedTorrentFile]
    ) -> [TorrentPayloadDeletionSafetyIssue] {
        var issues: [TorrentPayloadDeletionSafetyIssue] = []
        var seenPaths = Set<String>()
        var componentPaths: [[String]] = []

        for managedFile in managedFiles {
            guard let normalizedComponents = TorrentPathSafety.normalizedRelativePathComponents(
                managedFile.relativePath
            ), normalizedComponents == managedFile.relativePathComponents,
               normalizedComponents.joined(separator: "/") == managedFile.relativePath,
               seenPaths.insert(managedFile.relativePath).inserted else {
                issues.append(invalidManifestIssue(relativePath: managedFile.relativePath))
                continue
            }
            componentPaths.append(normalizedComponents)
        }

        let validPaths = Set(componentPaths.map { $0.joined(separator: "/") })
        for components in componentPaths where components.count > 1 {
            for prefixLength in 1..<components.count {
                let prefix = components.prefix(prefixLength).joined(separator: "/")
                if validPaths.contains(prefix) {
                    issues.append(
                        invalidManifestIssue(relativePath: components.joined(separator: "/"))
                    )
                    break
                }
            }
        }

        return issues
    }

    private func invalidManifestIssue(relativePath: String) -> TorrentPayloadDeletionSafetyIssue {
        TorrentPayloadDeletionSafetyIssue(
            relativePath: relativePath,
            reason: .invalidManifest,
            actualType: nil,
            errorCode: nil
        )
    }

    private func openRootDirectory(at url: URL) -> Int32 {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
    }

    private func inspect(relativePath: String, rootDescriptor: Int32) -> InspectionOutcome {
        var status = stat()
        let result = withRelativeFileSystemPath(relativePath) { path in
            Darwin.fstatat(rootDescriptor, path, &status, safeLookupFlags)
        }

        guard result == 0 else {
            let errorCode = errno
            if errorCode == ENOENT {
                return .missing
            }
            return .issue(issueForErrno(relativePath: relativePath, errorCode: errorCode))
        }

        return .object(
            InspectedObject(
                identity: FileIdentity(
                    device: UInt64(status.st_dev),
                    inode: UInt64(status.st_ino)
                ),
                type: objectType(for: status.st_mode)
            )
        )
    }

    private func objectType(for mode: mode_t) -> TorrentPayloadFileSystemObjectType {
        switch mode & S_IFMT {
        case S_IFREG:
            .regularFile
        case S_IFDIR:
            .directory
        case S_IFLNK:
            .symbolicLink
        default:
            .other
        }
    }

    private func typeMismatchIssue(
        relativePath: String,
        actualType: TorrentPayloadFileSystemObjectType
    ) -> TorrentPayloadDeletionSafetyIssue {
        TorrentPayloadDeletionSafetyIssue(
            relativePath: relativePath,
            reason: .objectTypeMismatch,
            actualType: actualType,
            errorCode: nil
        )
    }

    private func issueForErrno(
        relativePath: String,
        errorCode: Int32
    ) -> TorrentPayloadDeletionSafetyIssue {
        let reason: TorrentPayloadDeletionSafetyReason
        switch errorCode {
        case ELOOP:
            reason = .symlinkComponent
        case ENOTDIR:
            reason = .pathComponentNotDirectory
        case EINVAL:
            reason = .safetyContractUnavailable
        default:
            reason = .filesystemFailure
        }

        return TorrentPayloadDeletionSafetyIssue(
            relativePath: relativePath,
            reason: reason,
            actualType: nil,
            errorCode: errorCode
        )
    }

    private func directoryCandidates(for managedFiles: [ManagedTorrentFile]) -> [String] {
        var candidates = Set<String>()

        for managedFile in managedFiles where managedFile.relativePathComponents.count > 1 {
            for componentCount in 1..<managedFile.relativePathComponents.count {
                candidates.insert(
                    managedFile.relativePathComponents.prefix(componentCount).joined(separator: "/")
                )
            }
        }

        return candidates.sorted {
            let leftDepth = $0.split(separator: "/").count
            let rightDepth = $1.split(separator: "/").count
            return leftDepth == rightDepth ? $0 > $1 : leftDepth > rightDepth
        }
    }

    private func cleanupDirectory(
        relativePath: String,
        rootDescriptor: Int32,
        report: inout SecureTorrentPayloadFileSystemReport
    ) {
        let directoryIdentity: FileIdentity
        switch inspect(relativePath: relativePath, rootDescriptor: rootDescriptor) {
        case .object(let object) where object.type == .directory:
            directoryIdentity = object.identity
        case .object(let object):
            report.unsafeCleanupIssues.append(
                typeMismatchIssue(relativePath: relativePath, actualType: object.type)
            )
            return
        case .missing:
            return
        case .issue(let issue):
            report.unsafeCleanupIssues.append(issue)
            return
        }

        let contents: [String]
        switch directoryContents(relativePath: relativePath, rootDescriptor: rootDescriptor) {
        case .contents(let names):
            contents = names
        case .missing:
            return
        case .issue(let issue):
            report.failedDirectoryCleanupCount += 1
            report.unsafeCleanupIssues.append(issue)
            return
        }

        let sidecarNames = contents.filter(isIgnorableSystemSidecar)
        guard contents.count == sidecarNames.count else { return }

        var sidecarIdentities: [String: FileIdentity] = [:]
        var sidecarIssues: [TorrentPayloadDeletionSafetyIssue] = []
        for sidecarName in sidecarNames {
            let sidecarPath = relativePath + "/" + sidecarName
            switch inspect(relativePath: sidecarPath, rootDescriptor: rootDescriptor) {
            case .object(let object) where object.type == .regularFile:
                sidecarIdentities[sidecarPath] = object.identity
            case .object(let object):
                sidecarIssues.append(typeMismatchIssue(relativePath: sidecarPath, actualType: object.type))
            case .missing:
                break
            case .issue(let issue):
                sidecarIssues.append(issue)
            }
        }

        guard sidecarIssues.isEmpty else {
            report.unsafeCleanupIssues.append(contentsOf: sidecarIssues)
            return
        }

        for sidecarName in sidecarNames {
            let sidecarPath = relativePath + "/" + sidecarName
            guard let expectedIdentity = sidecarIdentities[sidecarPath] else { continue }
            eventHook?(.willDeleteSidecar(sidecarPath))

            switch inspect(relativePath: sidecarPath, rootDescriptor: rootDescriptor) {
            case .object(let object) where object.type == .regularFile && object.identity == expectedIdentity:
                let result = withRelativeFileSystemPath(sidecarPath) { path in
                    Darwin.unlinkat(rootDescriptor, path, safeLookupFlags)
                }
                if result == 0 {
                    report.deletedSidecarCount += 1
                } else if errno != ENOENT {
                    report.failedDirectoryCleanupCount += 1
                    report.unsafeCleanupIssues.append(
                        issueForErrno(relativePath: sidecarPath, errorCode: errno)
                    )
                    return
                }
            case .object(let object):
                report.unsafeCleanupIssues.append(
                    TorrentPayloadDeletionSafetyIssue(
                        relativePath: sidecarPath,
                        reason: .objectChanged,
                        actualType: object.type,
                        errorCode: nil
                    )
                )
                return
            case .missing:
                continue
            case .issue(let issue):
                report.unsafeCleanupIssues.append(issue)
                return
            }
        }

        switch inspect(relativePath: relativePath, rootDescriptor: rootDescriptor) {
        case .object(let object) where object.type == .directory && object.identity == directoryIdentity:
            break
        case .object(let object):
            report.unsafeCleanupIssues.append(
                TorrentPayloadDeletionSafetyIssue(
                    relativePath: relativePath,
                    reason: .objectChanged,
                    actualType: object.type,
                    errorCode: nil
                )
            )
            return
        case .missing:
            return
        case .issue(let issue):
            report.unsafeCleanupIssues.append(issue)
            return
        }

        eventHook?(.willRemoveDirectory(relativePath))
        let removeFlags = safeLookupFlags | Int32(AT_REMOVEDIR)
        let result = withRelativeFileSystemPath(relativePath) { path in
            Darwin.unlinkat(rootDescriptor, path, removeFlags)
        }
        if result == 0 {
            report.deletedDirectoryCount += 1
        } else if errno != ENOENT && errno != ENOTEMPTY {
            report.failedDirectoryCleanupCount += 1
            report.unsafeCleanupIssues.append(
                issueForErrno(relativePath: relativePath, errorCode: errno)
            )
        }
    }

    private func directoryContents(
        relativePath: String,
        rootDescriptor: Int32
    ) -> DirectoryContentsOutcome {
        let descriptor = withRelativeFileSystemPath(relativePath) { path in
            Darwin.openat(
                rootDescriptor,
                path,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW_ANY | O_RESOLVE_BENEATH
            )
        }
        guard descriptor >= 0 else {
            let errorCode = errno
            if errorCode == ENOENT {
                return .missing
            }
            return .issue(issueForErrno(relativePath: relativePath, errorCode: errorCode))
        }

        guard let directory = Darwin.fdopendir(descriptor) else {
            let errorCode = errno
            Darwin.close(descriptor)
            return .issue(issueForErrno(relativePath: relativePath, errorCode: errorCode))
        }
        defer { Darwin.closedir(directory) }

        var names: [String] = []
        errno = 0
        while let entry = Darwin.readdir(directory) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." {
                names.append(name)
            }
            errno = 0
        }

        guard errno == 0 else {
            return .issue(issueForErrno(relativePath: relativePath, errorCode: errno))
        }
        return .contents(names)
    }

    private func isIgnorableSystemSidecar(_ name: String) -> Bool {
        name == ".DS_Store" || name.hasPrefix("._")
    }

    private func withRelativeFileSystemPath<Result>(
        _ relativePath: String,
        _ body: (UnsafePointer<CChar>) -> Result
    ) -> Result {
        relativePath.withCString(body)
    }
}
