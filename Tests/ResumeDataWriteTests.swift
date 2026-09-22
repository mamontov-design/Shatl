// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

final class ResumeDataWriteTests: XCTestCase {
    func testResumeDataWriteReplacesFileWithoutLeftovers() throws {
        let directoryURL = try makeTemporaryDirectory(named: "Replace")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("\(UUID().uuidString).fastresume")
        try Data("previous checkpoint".utf8).write(to: fileURL)

        try LibtorrentSessionBridge.writeResumeData(Data("fresh checkpoint".utf8), toFileURL: fileURL)

        XCTAssertEqual(try Data(contentsOf: fileURL), Data("fresh checkpoint".utf8))
        XCTAssertEqual(try directoryItemNames(at: directoryURL), [fileURL.lastPathComponent])
    }

    func testFailedResumeDataWriteKeepsPreviousFile() throws {
        let directoryURL = try makeTemporaryDirectory(named: "Unwritable")
        let fileURL = directoryURL.appendingPathComponent("\(UUID().uuidString).fastresume")
        let previousData = Data("previous checkpoint".utf8)
        try previousData.write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directoryURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directoryURL.path)
            try? FileManager.default.removeItem(at: directoryURL)
        }

        XCTAssertThrowsError(
            try LibtorrentSessionBridge.writeResumeData(Data("fresh checkpoint".utf8), toFileURL: fileURL)
        )

        XCTAssertEqual(try Data(contentsOf: fileURL), previousData)
        XCTAssertEqual(try directoryItemNames(at: directoryURL), [fileURL.lastPathComponent])
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResumeDataWrite-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func directoryItemNames(at url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }
}
