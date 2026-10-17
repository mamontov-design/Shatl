// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XCTest
@testable import Shatl

/// Colours live in code as light and dark pairs. The system has to pick the
/// right one for a view the way it did for asset colours.
@MainActor
final class ColorTokenTests: XCTestCase {
    func testATokenTakesItsDarkColourInADarkView() throws {
        let token = Color(light: Color(rgb: 0x112233), dark: Color(rgba: 0xDDEEFF80))

        XCTAssertEqual(try components(token, in: .light), [0x11, 0x22, 0x33, 0xFF])
        XCTAssertEqual(try components(token, in: .dark), [0xDD, 0xEE, 0xFF, 0x80])
    }

    /// Colours are written in Palette.swift and named in Colors.swift, after
    /// Figma's Palette and Tokens. A colour written into a view by hand
    /// follows neither the mockup nor, often, the theme.
    func testNoViewWritesAColourByHand() throws {
        let appURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App", isDirectory: true)
        let literal = try NSRegularExpression(pattern: #"Color\(\s*(red|rgb|rgba|white|hue|light):"#)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: appURL, includingPropertiesForKeys: nil))
        var scanned = 0
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            guard !["Colors.swift", "Palette.swift"].contains(url.lastPathComponent) else { continue }
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in literal.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let prefix = text[..<String.Index(utf16Offset: match.range.location, in: text)]
                offenders.append("\(url.lastPathComponent):\(prefix.filter { $0 == "\n" }.count + 1)")
            }
        }
        XCTAssertGreaterThan(scanned, 20, "The source scan found too few files")
        XCTAssertEqual(offenders, [], "Colours written by hand")
    }

    /// The colour as SwiftUI draws it in a view of that scheme, in sRGB
    /// bytes. A fully transparent colour reads as zeros.
    private func components(_ color: Color, in scheme: ColorScheme) throws -> [Int] {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return try bytes(color.resolve(in: environment).cgColor)
    }

    private func bytes(_ color: CGColor) throws -> [Int] {
        let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let converted = try XCTUnwrap(color.converted(to: srgb, intent: .defaultIntent, options: nil))
        let parts = try XCTUnwrap(converted.components)
        let rgba = parts.map { Int(($0 * 255).rounded()) }
        return rgba[3] == 0 ? [0, 0, 0, 0] : rgba
    }
}
