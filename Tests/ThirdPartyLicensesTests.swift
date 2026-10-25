// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// The licences travel with the app, not only with its source: Shatl's GPL,
/// the notices and every component's licence text are in its Resources, and
/// the popover in About names the same components the notices list.
final class ThirdPartyLicensesTests: XCTestCase {
    private var resources: URL {
        get throws { try XCTUnwrap(Bundle.main.resourceURL) }
    }

    private func text(_ path: String) throws -> String {
        try String(contentsOf: resources.appendingPathComponent(path), encoding: .utf8)
    }

    func testTheAppCarriesItsLicenceAndTheNotices() throws {
        XCTAssertTrue(try text("LICENSE").contains("GNU GENERAL PUBLIC LICENSE"))
        XCTAssertTrue(try text("THIRD-PARTY-NOTICES.md").contains("Third-Party Notices"))
    }

    /// One text per component, and no text for a component the popover
    /// does not name.
    func testEveryComponentHasItsLicenceTextInTheApp() throws {
        let folder = try resources.appendingPathComponent("Licenses", isDirectory: true)
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        XCTAssertEqual(files, Set(ShatlThirdPartyComponent.allCases.map(\.licenseFileName)))
        for component in ShatlThirdPartyComponent.allCases {
            let license = try text("Licenses/\(component.licenseFileName)")
            XCTAssertGreaterThan(license.count, 500, component.name)
        }
    }

    /// The popover and the notices list the same components, at the same
    /// versions: a library updated in one place and not the other fails here.
    func testThePopoverNamesWhatTheNoticesList() throws {
        let notices = try text("THIRD-PARTY-NOTICES.md")
        let entries = notices.split(separator: "\n").filter { $0.hasPrefix("- ") }
        XCTAssertEqual(entries.count, ShatlThirdPartyComponent.allCases.count, "\(entries)")
        for component in ShatlThirdPartyComponent.allCases {
            let named = [component.name, component.version].compactMap { $0 }.joined(separator: " ")
            XCTAssertTrue(entries.contains { $0.hasPrefix("- \(named)") }, "\(named) is not in the notices")
            XCTAssertEqual(component.licenseURL.scheme, "https", component.name)
        }
    }
}
