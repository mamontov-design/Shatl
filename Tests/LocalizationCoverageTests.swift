// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// A key missing from the strings files falls back to the Russian default in
/// every language, silently: VoiceOver read «Продолжить» in English and German.
final class LocalizationCoverageTests: XCTestCase {
    private let languages = ["ru", "en", "de", "es", "fr", "ja", "zh-Hans"]
    /// Plural categories depend on the language's grammar.
    private let pluralSuffixes = [".zero", ".one", ".two", ".few", ".many", ".other"]

    func testEveryLanguageHasTheSameKeys() throws {
        let russianKeys = try singularKeys(for: "ru")

        for language in languages.dropFirst() {
            let keys = try singularKeys(for: language)
            XCTAssertEqual(keys.subtracting(russianKeys), [], "\(language) has keys Russian lacks")
            XCTAssertEqual(russianKeys.subtracting(keys), [], "\(language) lacks keys Russian has")
        }
    }

    /// Reads the sources next to this file, so it runs where the repository is.
    func testEveryKeyWrittenInCodeIsTranslated() throws {
        let appURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App", isDirectory: true)
        let keysInCode = try literalKeys(under: appURL)
        XCTAssertGreaterThan(keysInCode.count, 100, "The source scan found too few keys")

        for language in languages {
            let keys = try Set(strings(for: language).keys)
            XCTAssertEqual(keysInCode.subtracting(keys), [], "Untranslated keys in \(language)")
        }
    }

    // MARK: - Helpers

    private func strings(for language: String) throws -> [String: String] {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language),
            "No Localizable.strings for \(language)"
        )
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    private func singularKeys(for language: String) throws -> Set<String> {
        Set(try strings(for: language).keys.filter { key in
            !pluralSuffixes.contains { key.hasSuffix($0) }
        })
    }

    /// Keys passed to `L10n` and to Shatl components that take a localized key.
    private func literalKeys(under directoryURL: URL) throws -> Set<String> {
        let key = #""([a-z0-9_]+(?:\.[a-z0-9_]+)+)""#
        let callPattern = try NSRegularExpression(
            pattern: #"(?:L10n\.(?:string|format)\(\s*|localizedTitle:\s*|localizedText:\s*)"# + key
        )
        let linesPattern = try NSRegularExpression(pattern: #"localizedLines:\s*\[([^\]]*)\]"#)
        let keyPattern = try NSRegularExpression(pattern: key)

        var keys: Set<String> = []
        let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in callPattern.matches(in: source, range: range) {
                keys.insert((source as NSString).substring(with: match.range(at: 1)))
            }
            for match in linesPattern.matches(in: source, range: range) {
                let list = (source as NSString).substring(with: match.range(at: 1))
                let listRange = NSRange(list.startIndex..., in: list)
                for keyMatch in keyPattern.matches(in: list, range: listRange) {
                    keys.insert((list as NSString).substring(with: keyMatch.range(at: 1)))
                }
            }
        }
        return keys
    }
}
