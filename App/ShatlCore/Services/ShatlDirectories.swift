// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Centralizes system directory resolution so paths are not scattered
/// throughout the project or tied to Xcode's local sandbox.
nonisolated struct ShatlDirectories: Sendable {
    private let customApplicationSupportURL: URL?
    private let customCachesURL: URL?

    init(applicationSupportURL: URL? = nil, cachesURL: URL? = nil) {
        self.customApplicationSupportURL = applicationSupportURL
        self.customCachesURL = cachesURL
    }

    nonisolated var applicationSupportURL: URL {
        if let customApplicationSupportURL {
            return customApplicationSupportURL
        }

        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL.appendingPathComponent("Shatl", isDirectory: true)
    }

    nonisolated var cachesURL: URL {
        if let customCachesURL {
            return customCachesURL
        }

        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
        return baseURL.appendingPathComponent("Shatl", isDirectory: true)
    }

    nonisolated var sessionDirectoryURL: URL {
        applicationSupportURL.appendingPathComponent("Session", isDirectory: true)
    }

    nonisolated var sessionSnapshotURL: URL {
        sessionDirectoryURL.appendingPathComponent("session.json", isDirectory: false)
    }

    nonisolated var archivedTorrentsDirectoryURL: URL {
        sessionDirectoryURL.appendingPathComponent("Torrents", isDirectory: true)
    }

    nonisolated var bookmarksDirectoryURL: URL {
        sessionDirectoryURL.appendingPathComponent("Bookmarks", isDirectory: true)
    }

    nonisolated var resumeDataDirectoryURL: URL {
        sessionDirectoryURL.appendingPathComponent("ResumeData", isDirectory: true)
    }

    nonisolated var telemetryDirectoryURL: URL {
        applicationSupportURL.appendingPathComponent("Telemetry", isDirectory: true)
    }

    nonisolated var usageTelemetryStateURL: URL {
        telemetryDirectoryURL.appendingPathComponent("usage-telemetry-state.json", isDirectory: false)
    }

    nonisolated var usageTelemetryPayloadURL: URL {
        telemetryDirectoryURL.appendingPathComponent("weekly-launch-payload.json", isDirectory: false)
    }

    nonisolated func ensureSessionDirectories() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: sessionDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: archivedTorrentsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: bookmarksDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: resumeDataDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }
}
