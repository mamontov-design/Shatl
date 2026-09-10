// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

final class TorrentPathSafetyTests: XCTestCase {
    func testAcceptsNormalizedRelativePaths() {
        XCTAssertEqual(
            TorrentPathSafety.normalizedRelativePathComponents("Show/Season 1/E01.mkv"),
            ["Show", "Season 1", "E01.mkv"]
        )
        XCTAssertEqual(
            TorrentPathSafety.normalizedRelativePathComponents("Сериал/серия 🎬.mkv"),
            ["Сериал", "серия 🎬.mkv"]
        )
        XCTAssertEqual(TorrentPathSafety.normalizedRelativePath("Show\\E01.mkv"), "Show/E01.mkv")
    }

    func testRejectsAbsoluteAndTraversalPaths() {
        let unsafePaths = [
            "/movie.bin",
            "../movie.bin",
            "Show/../movie.bin",
            "./movie.bin",
            "Show/./movie.bin",
        ]

        for path in unsafePaths {
            XCTAssertNil(TorrentPathSafety.normalizedRelativePathComponents(path), path)
        }
    }

    func testRejectsEmptyComponentsInsteadOfSilentlyRewritingManifest() {
        let ambiguousPaths = ["", "/", "Show//movie.bin", "Show/movie.bin/"]

        for path in ambiguousPaths {
            XCTAssertNil(TorrentPathSafety.normalizedRelativePathComponents(path), path)
        }
    }

    func testRejectsEmbeddedNullByte() {
        XCTAssertNil(TorrentPathSafety.normalizedRelativePathComponents("movie\0.bin"))
    }
}
