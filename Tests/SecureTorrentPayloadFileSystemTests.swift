// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

final class SecureTorrentPayloadFileSystemTests: XCTestCase {
    func testInvalidManifestCannotInfluenceDirectoryCleanup() throws {
        let rootURL = try makeTemporaryDirectory(named: "InvalidManifest")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let payloadURL = rootURL.appendingPathComponent("movie.bin")
        let unrelatedDirectoryURL = rootURL.appendingPathComponent("Personal", isDirectory: true)
        try Data("torrent payload".utf8).write(to: payloadURL)
        try FileManager.default.createDirectory(
            at: unrelatedDirectoryURL,
            withIntermediateDirectories: true
        )

        let inconsistentFile = ManagedTorrentFile(
            relativePath: "movie.bin",
            relativePathComponents: ["Personal", "invented.bin"],
            fileURL: payloadURL
        )
        let outcome = SecureTorrentPayloadFileSystem().delete(
            saveURL: rootURL,
            managedFiles: [inconsistentFile]
        )

        guard case .refused(let failure) = outcome else {
            return XCTFail("Expected invalid manifest refusal")
        }
        XCTAssertEqual(failure.issues.map(\.reason), [.invalidManifest])
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedDirectoryURL.path))
    }

    func testDuplicateManifestCannotDeleteSharedPath() throws {
        let rootURL = try makeTemporaryDirectory(named: "DuplicateManifest")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let payloadURL = rootURL.appendingPathComponent("movie.bin")
        try Data("torrent payload".utf8).write(to: payloadURL)
        let file = managedFile("movie.bin", rootURL: rootURL)

        let outcome = SecureTorrentPayloadFileSystem().delete(
            saveURL: rootURL,
            managedFiles: [file, file]
        )

        guard case .refused(let failure) = outcome else {
            return XCTFail("Expected duplicate manifest refusal")
        }
        XCTAssertEqual(failure.issues.map(\.reason), [.invalidManifest])
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadURL.path))
    }

    func testMissingSaveRootRefusesEntireOperation() {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecurePayload-MissingRoot-\(UUID().uuidString)", isDirectory: true)

        let outcome = SecureTorrentPayloadFileSystem().delete(
            saveURL: rootURL,
            managedFiles: [managedFile("movie.bin", rootURL: rootURL)]
        )

        guard case .refused(let failure) = outcome else {
            return XCTFail("Expected missing root refusal")
        }
        XCTAssertEqual(failure.issues.map(\.reason), [.rootUnavailable])
    }

    func testSymlinkParentIsRejectedEvenWhenTargetStaysInsideRoot() throws {
        let rootURL = try makeTemporaryDirectory(named: "InternalSymlink")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let actualFolderURL = rootURL.appendingPathComponent("Actual", isDirectory: true)
        let linkedFolderURL = rootURL.appendingPathComponent("Linked", isDirectory: true)
        try FileManager.default.createDirectory(at: actualFolderURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedFolderURL, withDestinationURL: actualFolderURL)
        let payloadURL = actualFolderURL.appendingPathComponent("movie.bin")
        try Data("torrent payload".utf8).write(to: payloadURL)

        let outcome = SecureTorrentPayloadFileSystem().delete(
            saveURL: rootURL,
            managedFiles: [managedFile("Linked/movie.bin", rootURL: rootURL)]
        )

        guard case .refused(let failure) = outcome else {
            return XCTFail("Expected symlink refusal")
        }
        XCTAssertEqual(failure.issues.map(\.reason), [.symlinkComponent])
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadURL.path))
    }

    func testRegularFileReplacementAfterPreflightIsPreserved() throws {
        let rootURL = try makeTemporaryDirectory(named: "RegularReplacement")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("movie.bin")
        try Data("torrent payload".utf8).write(to: fileURL)

        let fileSystem = SecureTorrentPayloadFileSystem { event in
            guard event == .willDeleteFile("movie.bin") else { return }
            try? FileManager.default.removeItem(at: fileURL)
            try? Data("personal replacement".utf8).write(to: fileURL)
        }

        let outcome = fileSystem.delete(
            saveURL: rootURL,
            managedFiles: [managedFile("movie.bin", rootURL: rootURL)]
        )

        guard case .completed(let report) = outcome else {
            return XCTFail("Expected a completed safe refusal")
        }
        XCTAssertEqual(report.unsafeFileIssues.map(\.reason), [.objectChanged])
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("personal replacement".utf8))
    }

    func testDirectoryReplacementAfterPreflightIsNeverRecursivelyDeleted() throws {
        let rootURL = try makeTemporaryDirectory(named: "DirectoryReplacement")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("movie.bin")
        let victimURL = fileURL.appendingPathComponent("personal.txt")
        try Data("torrent payload".utf8).write(to: fileURL)

        let fileSystem = SecureTorrentPayloadFileSystem { event in
            guard event == .willDeleteFile("movie.bin") else { return }
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
            try? Data("personal replacement".utf8).write(to: victimURL)
        }

        let outcome = fileSystem.delete(
            saveURL: rootURL,
            managedFiles: [managedFile("movie.bin", rootURL: rootURL)]
        )

        guard case .completed(let report) = outcome else {
            return XCTFail("Expected a completed safe refusal")
        }
        XCTAssertEqual(report.unsafeFileIssues.first?.actualType, .directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: victimURL.path))
    }

    func testParentReplacementWithSymlinkAfterPreflightCannotEscapeRoot() throws {
        let rootURL = try makeTemporaryDirectory(named: "ParentSymlinkRace")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let showURL = rootURL.appendingPathComponent("Show", isDirectory: true)
        let originalShowURL = rootURL.appendingPathComponent("Original Show", isDirectory: true)
        let outsideURL = rootURL.appendingPathComponent("Personal", isDirectory: true)
        try FileManager.default.createDirectory(at: showURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        let originalPayloadURL = showURL.appendingPathComponent("movie.bin")
        let outsideVictimURL = outsideURL.appendingPathComponent("movie.bin")
        try Data("torrent payload".utf8).write(to: originalPayloadURL)
        try Data("personal data".utf8).write(to: outsideVictimURL)

        let fileSystem = SecureTorrentPayloadFileSystem { event in
            guard event == .willDeleteFile("Show/movie.bin") else { return }
            try? FileManager.default.moveItem(at: showURL, to: originalShowURL)
            try? FileManager.default.createSymbolicLink(at: showURL, withDestinationURL: outsideURL)
        }

        let outcome = fileSystem.delete(
            saveURL: rootURL,
            managedFiles: [managedFile("Show/movie.bin", rootURL: rootURL)]
        )

        guard case .completed(let report) = outcome else {
            return XCTFail("Expected a completed safe refusal")
        }
        XCTAssertEqual(report.unsafeFileIssues.map(\.reason), [.symlinkComponent])
        XCTAssertEqual(try Data(contentsOf: outsideVictimURL), Data("personal data".utf8))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: originalShowURL.appendingPathComponent("movie.bin").path
        ))
    }

    func testFileCreatedAfterMissingPreflightIsNotDeleted() throws {
        let rootURL = try makeTemporaryDirectory(named: "MissingRace")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("movie.bin")

        let fileSystem = SecureTorrentPayloadFileSystem { event in
            guard event == .didCompletePreflight else { return }
            try? Data("late personal file".utf8).write(to: fileURL)
        }

        let outcome = fileSystem.delete(
            saveURL: rootURL,
            managedFiles: [managedFile("movie.bin", rootURL: rootURL)]
        )

        guard case .completed(let report) = outcome else {
            return XCTFail("Expected completed deletion")
        }
        XCTAssertEqual(report.missingFilePaths, ["movie.bin"])
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("late personal file".utf8))
    }

    func testDirectoryReplacementWithSymlinkImmediatelyBeforeRmdirIsPreserved() throws {
        let rootURL = try makeTemporaryDirectory(named: "DirectoryRmdirRace")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let folderURL = rootURL.appendingPathComponent("Show", isDirectory: true)
        let movedFolderURL = rootURL.appendingPathComponent("Original Show", isDirectory: true)
        let outsideURL = rootURL.appendingPathComponent("Personal", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try Data("torrent payload".utf8).write(to: folderURL.appendingPathComponent("movie.bin"))
        let outsideVictimURL = outsideURL.appendingPathComponent("personal.txt")
        try Data("personal data".utf8).write(to: outsideVictimURL)

        let fileSystem = SecureTorrentPayloadFileSystem { event in
            guard event == .willRemoveDirectory("Show") else { return }
            try? FileManager.default.moveItem(at: folderURL, to: movedFolderURL)
            try? FileManager.default.createSymbolicLink(at: folderURL, withDestinationURL: outsideURL)
        }

        let outcome = fileSystem.delete(
            saveURL: rootURL,
            managedFiles: [managedFile("Show/movie.bin", rootURL: rootURL)]
        )

        guard case .completed(let report) = outcome else {
            return XCTFail("Expected completed payload deletion")
        }
        XCTAssertEqual(report.deletedFilePaths, ["Show/movie.bin"])
        XCTAssertEqual(report.deletedDirectoryCount, 0)
        XCTAssertEqual(report.failedDirectoryCleanupCount, 1)
        XCTAssertEqual(try Data(contentsOf: outsideVictimURL), Data("personal data".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.path))
    }

    func testSidecarSymlinkIsPreservedWithItsTarget() throws {
        let rootURL = try makeTemporaryDirectory(named: "SidecarSymlink")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let folderURL = rootURL.appendingPathComponent("Show", isDirectory: true)
        let outsideURL = rootURL.appendingPathComponent("Personal", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try Data("torrent payload".utf8).write(to: folderURL.appendingPathComponent("movie.bin"))
        let victimURL = outsideURL.appendingPathComponent("metadata.bin")
        let sidecarURL = folderURL.appendingPathComponent(".DS_Store")
        try Data("personal data".utf8).write(to: victimURL)
        try FileManager.default.createSymbolicLink(at: sidecarURL, withDestinationURL: victimURL)

        let outcome = SecureTorrentPayloadFileSystem().delete(
            saveURL: rootURL,
            managedFiles: [managedFile("Show/movie.bin", rootURL: rootURL)]
        )

        guard case .completed(let report) = outcome else {
            return XCTFail("Expected completed payload deletion")
        }
        XCTAssertEqual(report.deletedFilePaths, ["Show/movie.bin"])
        XCTAssertEqual(report.deletedSidecarCount, 0)
        XCTAssertEqual(report.unsafeCleanupIssues.first?.actualType, .symbolicLink)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))
        XCTAssertEqual(try Data(contentsOf: victimURL), Data("personal data".utf8))
    }

    func testSidecarDirectoryReplacementDuringCleanupIsPreserved() throws {
        let rootURL = try makeTemporaryDirectory(named: "SidecarDirectoryRace")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let folderURL = rootURL.appendingPathComponent("Show", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data("torrent payload".utf8).write(to: folderURL.appendingPathComponent("movie.bin"))
        let sidecarURL = folderURL.appendingPathComponent(".DS_Store")
        let victimURL = sidecarURL.appendingPathComponent("personal.txt")
        try Data("system metadata".utf8).write(to: sidecarURL)

        let fileSystem = SecureTorrentPayloadFileSystem { event in
            guard event == .willDeleteSidecar("Show/.DS_Store") else { return }
            try? FileManager.default.removeItem(at: sidecarURL)
            try? FileManager.default.createDirectory(at: sidecarURL, withIntermediateDirectories: true)
            try? Data("personal replacement".utf8).write(to: victimURL)
        }

        let outcome = fileSystem.delete(
            saveURL: rootURL,
            managedFiles: [managedFile("Show/movie.bin", rootURL: rootURL)]
        )

        guard case .completed(let report) = outcome else {
            return XCTFail("Expected completed payload deletion")
        }
        XCTAssertEqual(report.deletedSidecarCount, 0)
        XCTAssertEqual(report.unsafeCleanupIssues.map(\.reason), [.objectChanged])
        XCTAssertTrue(FileManager.default.fileExists(atPath: victimURL.path))
    }

    func testSidecarsAreNotDeletedWhenUnmanagedFileKeepsDirectoryAlive() throws {
        let rootURL = try makeTemporaryDirectory(named: "UnmanagedWithSidecar")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let folderURL = rootURL.appendingPathComponent("Show", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let payloadURL = folderURL.appendingPathComponent("movie.bin")
        let personalURL = folderURL.appendingPathComponent("personal.txt")
        let sidecarURL = folderURL.appendingPathComponent(".DS_Store")
        try Data("torrent payload".utf8).write(to: payloadURL)
        try Data("personal data".utf8).write(to: personalURL)
        try Data("system metadata".utf8).write(to: sidecarURL)

        let outcome = SecureTorrentPayloadFileSystem().delete(
            saveURL: rootURL,
            managedFiles: [managedFile("Show/movie.bin", rootURL: rootURL)]
        )

        guard case .completed(let report) = outcome else {
            return XCTFail("Expected completed payload deletion")
        }
        XCTAssertEqual(report.deletedFilePaths, ["Show/movie.bin"])
        XCTAssertEqual(report.deletedSidecarCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: personalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))
    }

    func testSaveRootSymlinkIsAllowedButBecomesTheDescriptorBoundary() throws {
        let containerURL = try makeTemporaryDirectory(named: "RootSymlink")
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let actualRootURL = containerURL.appendingPathComponent("Actual Downloads", isDirectory: true)
        let linkedRootURL = containerURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: actualRootURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedRootURL, withDestinationURL: actualRootURL)
        let payloadURL = actualRootURL.appendingPathComponent("movie.bin")
        try Data("torrent payload".utf8).write(to: payloadURL)

        let outcome = SecureTorrentPayloadFileSystem().delete(
            saveURL: linkedRootURL,
            managedFiles: [managedFile("movie.bin", rootURL: linkedRootURL)]
        )

        guard case .completed(let report) = outcome else {
            return XCTFail("Expected completed deletion")
        }
        XCTAssertEqual(report.deletedFilePaths, ["movie.bin"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkedRootURL.path))
    }

    func testDeletingOneHardLinkPreservesTheOtherLinkAndItsData() throws {
        let rootURL = try makeTemporaryDirectory(named: "HardLink")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let payloadURL = rootURL.appendingPathComponent("movie.bin")
        let otherLinkURL = rootURL.appendingPathComponent("personal-copy.bin")
        try Data("shared data".utf8).write(to: payloadURL)
        try FileManager.default.linkItem(at: payloadURL, to: otherLinkURL)

        let outcome = SecureTorrentPayloadFileSystem().delete(
            saveURL: rootURL,
            managedFiles: [managedFile("movie.bin", rootURL: rootURL)]
        )

        guard case .completed(let report) = outcome else {
            return XCTFail("Expected completed deletion")
        }
        XCTAssertEqual(report.deletedFilePaths, ["movie.bin"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
        XCTAssertEqual(try Data(contentsOf: otherLinkURL), Data("shared data".utf8))
    }

    func testUnicodeNestedPayloadUsesRelativeDescriptorOperations() throws {
        let rootURL = try makeTemporaryDirectory(named: "Unicode")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let relativePath = "Сериал/Сезон 1/серия 🎬.mkv"
        let payloadURL = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("torrent payload".utf8).write(to: payloadURL)

        let outcome = SecureTorrentPayloadFileSystem().delete(
            saveURL: rootURL,
            managedFiles: [managedFile(relativePath, rootURL: rootURL)]
        )

        guard case .completed(let report) = outcome else {
            return XCTFail("Expected completed deletion")
        }
        XCTAssertEqual(report.deletedFilePaths, [relativePath])
        XCTAssertEqual(report.deletedDirectoryCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.path))
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecurePayload-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func managedFile(_ relativePath: String, rootURL: URL) -> ManagedTorrentFile {
        let components = TorrentPathSafety.normalizedRelativePathComponents(relativePath)!
        return ManagedTorrentFile(
            relativePath: components.joined(separator: "/"),
            relativePathComponents: components,
            fileURL: rootURL.appendingPathComponent(relativePath)
        )
    }
}
