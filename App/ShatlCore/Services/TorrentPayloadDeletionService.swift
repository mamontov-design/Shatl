// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated enum TorrentPayloadDeletionOutcome: Sendable, Equatable {
    case deleted(TorrentPayloadDeletionResult)
    case unresolved(ManagedTorrentPayloadResolutionFailure)
    case unsafe(TorrentPayloadDeletionSafetyFailure)
}

nonisolated struct TorrentPayloadDeletionResult: Sendable, Equatable {
    var payloadSource: ManagedTorrentPayloadSource = .archive
    var deletedManagedFileCount: Int = 0
    var missingManagedFileCount: Int = 0
    var failedManagedFileCount: Int = 0
    var unsafeManagedFileCount: Int = 0
    var deletedDirectoryCount: Int = 0
    var deletedSystemSidecarCount: Int = 0
    var failedDirectoryCleanupCount: Int = 0
    var unsafeCleanupItemCount: Int = 0
}

/// Keeps payload deletion separate from the engine so Shatl controls
/// partial selections, nested folders, and safe cleanup of empty directories.
actor TorrentPayloadDeletionService {
    private let payloadLocator: TorrentPayloadLocator
    private let secureFileSystem: SecureTorrentPayloadFileSystem

    init(
        payloadLocator: TorrentPayloadLocator,
        secureFileSystem: SecureTorrentPayloadFileSystem = SecureTorrentPayloadFileSystem()
    ) {
        self.payloadLocator = payloadLocator
        self.secureFileSystem = secureFileSystem
    }

    func deletePayload(for record: TorrentRecord) async -> TorrentPayloadDeletionOutcome {
        let payload: ManagedTorrentPayload
        switch await payloadLocator.managedPayloadResolution(for: record) {
        case .resolved(let resolvedPayload):
            payload = resolvedPayload
        case .unresolved(let failure):
            return .unresolved(failure)
        }

        switch secureFileSystem.delete(saveURL: payload.saveURL, managedFiles: payload.managedFiles) {
        case .refused(let failure):
            logSafetyIssues(failure.issues, record: record, payload: payload, phase: "preflight")
            return .unsafe(failure)
        case .completed(let report):
            var result = TorrentPayloadDeletionResult(payloadSource: payload.source)
            result.deletedManagedFileCount = report.deletedFilePaths.count
            result.missingManagedFileCount = report.missingFilePaths.count
            result.failedManagedFileCount = report.failedFileIssues.count
            result.unsafeManagedFileCount = report.unsafeFileIssues.count
            result.deletedDirectoryCount = report.deletedDirectoryCount
            result.deletedSystemSidecarCount = report.deletedSidecarCount
            result.failedDirectoryCleanupCount = report.failedDirectoryCleanupCount
            result.unsafeCleanupItemCount = report.unsafeCleanupIssues.count

            logCompletedReport(report, record: record, payload: payload)
            return .deleted(result)
        }
    }

    private func logFileDeletionEvent(
        _ event: String,
        record: TorrentRecord,
        payload: ManagedTorrentPayload,
        managedFile: ManagedTorrentFile,
        reason: String? = nil
    ) {
        guard ShatlDiskDiagnosticsLog.isEnabled else { return }

        var fields: [String: String] = [
            "torrentID": record.id.uuidString,
            "source": payload.source.rawValue,
            "relativePath": managedFile.relativePath,
            "path": managedFile.fileURL.path
        ]

        if let reason {
            fields["reason"] = reason
        }

        ShatlDiskDiagnosticsLog.event(event, fields: fields)
    }

    private func logCompletedReport(
        _ report: SecureTorrentPayloadFileSystemReport,
        record: TorrentRecord,
        payload: ManagedTorrentPayload
    ) {
        let managedFilesByPath = Dictionary(
            uniqueKeysWithValues: payload.managedFiles.map { ($0.relativePath, $0) }
        )

        for relativePath in report.deletedFilePaths {
            if let managedFile = managedFilesByPath[relativePath] {
                logFileDeletionEvent(
                    "payload.delete.file.deleted",
                    record: record,
                    payload: payload,
                    managedFile: managedFile
                )
            }
        }
        for relativePath in report.missingFilePaths {
            if let managedFile = managedFilesByPath[relativePath] {
                logFileDeletionEvent(
                    "payload.delete.file.missing",
                    record: record,
                    payload: payload,
                    managedFile: managedFile
                )
            }
        }

        for issue in report.failedFileIssues {
            logSafetyIssues([issue], record: record, payload: payload, phase: "delete-failed")
        }
        for issue in report.unsafeFileIssues {
            logSafetyIssues([issue], record: record, payload: payload, phase: "delete-unsafe")
        }
        for issue in report.unsafeCleanupIssues {
            logSafetyIssues([issue], record: record, payload: payload, phase: "cleanup-unsafe")
        }
    }

    private func logSafetyIssues(
        _ issues: [TorrentPayloadDeletionSafetyIssue],
        record: TorrentRecord,
        payload: ManagedTorrentPayload,
        phase: String
    ) {
        for issue in issues {
            let actualType = issue.actualType?.rawValue ?? "-"
            let errorCode = issue.errorCode.map(String.init) ?? "-"
            ShatlDiskDiagnosticsLog.event(
                "payload.delete.safety-refused",
                fields: [
                    "torrentID": record.id.uuidString,
                    "source": payload.source.rawValue,
                    "phase": phase,
                    "savePath": payload.saveURL.path,
                    "relativePath": issue.relativePath,
                    "reason": issue.reason.rawValue,
                    "actualType": actualType,
                    "errno": errorCode
                ]
            )
        }
    }
}
