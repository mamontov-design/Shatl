// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// Reads the built host app, so the checks cover the generated Info.plist.
final class InfoPlistTests: XCTestCase {
    /// The standard About window shows it under the version.
    func testAboutWindowHasACopyright() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)

        XCTAssertEqual(info["NSHumanReadableCopyright"] as? String, "© 2026 Mamontov Design")
    }

    /// Shatl opens `.torrent` files it imports as `org.bittorrent.torrent`
    /// and exports no type of its own.
    func testTorrentFilesAreImportedWithoutEmptyLeftovers() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)

        XCTAssertNil(info["UTExportedTypeDeclarations"])
        let imported = try XCTUnwrap(info["UTImportedTypeDeclarations"] as? [[String: Any]])
        XCTAssertEqual(imported.compactMap { $0["UTTypeIdentifier"] as? String }, ["org.bittorrent.torrent"])

        let documentTypes = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        XCTAssertEqual(documentTypes.count, 1)
        XCTAssertEqual(documentTypes.first?["LSItemContentTypes"] as? [String], ["org.bittorrent.torrent"])
        XCTAssertNil(documentTypes.first?["NSDocumentClass"])
    }
}
