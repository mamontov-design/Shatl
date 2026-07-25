// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

final class ShatlFileLoggerTests: XCTestCase {
    func testDisabledLoggerDoesNotCreateLogFile() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShatlFileLogger-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let logger = ShatlFileLogger(
            directoryURL: rootURL,
            fileName: "Shatl.log",
            maxFileSizeBytes: 1_024,
            initiallyEnabled: false
        )

        logger.write(level: .notice, category: "Tests", message: "disabled")
        logger.flushForTests()

        let fileURL = rootURL.appendingPathComponent("Shatl.log", isDirectory: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testEnabledLoggerWritesToConfiguredFile() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShatlFileLogger-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let logger = ShatlFileLogger(
            directoryURL: rootURL,
            fileName: "Shatl.log",
            maxFileSizeBytes: 1_024,
            initiallyEnabled: true
        )

        logger.write(level: .notice, category: "Tests", message: "hello world")
        logger.flushForTests()

        let fileURL = rootURL.appendingPathComponent("Shatl.log", isDirectory: false)
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(contents.contains("[Tests] [NOTICE] hello world"))
    }

    func testDefaultLogsDirectoryUsesDownloadsInAppRuntime() {
        let directoryURL = AppPreferences.defaultLogsDirectoryURL(
            processInfo: TestProcessInfo(environment: [:]),
            fileManager: .default
        )

        XCTAssertTrue(directoryURL.path.hasSuffix("/Downloads/Shatl Logs"))
    }

    func testAddTorrentReviewDiagnosticsWriteStructuredEvent() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShatlFileLogger-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let logger = ShatlFileLogger(
            directoryURL: rootURL,
            fileName: "Shatl Add Torrent Review Diagnostics.log",
            maxFileSizeBytes: 1_024,
            initiallyEnabled: true
        )

        logger.write(
            level: .notice,
            category: "AddTorrentReview",
            message: "event=folder.toggle action=collapse rows=17",
            flush: true
        )

        let fileURL = rootURL.appendingPathComponent(
            "Shatl Add Torrent Review Diagnostics.log",
            isDirectory: false
        )
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(contents.contains("event=folder.toggle action=collapse rows=17"))
    }
}

private struct TestProcessInfo: _AppPreferencesProcessInfoProviding {
    let environment: [String: String]
}
