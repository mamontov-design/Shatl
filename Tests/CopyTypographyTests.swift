// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// Interface strings follow the typesetting rules of their language, so a
/// preposition never hangs at the end of a line. Placing non-breaking spaces
/// by hand left gaps in every file; `Scripts/typograph.sh` places them now,
/// and these tests keep a string edited by hand from slipping back.
final class CopyTypographyTests: XCTestCase {
    private let nbsp = "\u{00A0}"
    private let narrow = "\u{202F}"

    // MARK: - The strings files

    func testEveryStringIsTypeset() throws {
        var failures: [String] = []
        for language in ShatlTypograph.languages {
            for (key, value) in try strings(for: language).sorted(by: { $0.key < $1.key }) {
                let typeset = ShatlTypograph.apply(value, language: language)
                if typeset != value {
                    failures.append("\(language) \(key): «\(visible(value))» → «\(visible(typeset))»")
                }
            }
        }
        XCTAssertEqual(failures, [], "Run Scripts/typograph.sh")
    }

    /// "3 файл(ов)" reads as a form, not a sentence: counts take a plural key.
    func testCountsTakePluralFormsNotBrackets() throws {
        let brackets = try NSRegularExpression(pattern: #"\p{L}\((?:ов|а|ы|s|es|en|e|n|x)\)"#)
        var failures: [String] = []
        for language in ShatlTypograph.languages {
            for (key, value) in try strings(for: language) {
                let range = NSRange(value.startIndex..., in: value)
                if brackets.firstMatch(in: value, range: range) != nil {
                    failures.append("\(language) \(key): \(value)")
                }
            }
        }
        XCTAssertEqual(failures, [], "Use L10n.pluralKey with .one/.few/.many/.other keys")
    }

    func testNoStraightQuotesDoubleSpacesOrHyphenDashes() throws {
        var failures: [String] = []
        for language in ShatlTypograph.languages {
            for (key, value) in try strings(for: language) {
                if value.contains("\"") { failures.append("\(language) \(key): straight quote") }
                if value.contains("'") { failures.append("\(language) \(key): straight apostrophe") }
                if value.contains("  ") { failures.append("\(language) \(key): double space") }
                if value.hasPrefix(" ") || value.hasSuffix(" ") { failures.append("\(language) \(key): edge space") }
                if value.contains(" - ") { failures.append("\(language) \(key): hyphen used as a dash") }
            }
        }
        XCTAssertEqual(failures, [])
    }

    /// The app names itself only where the reader could not tell which app is
    /// meant. The pending keys still say "Shatl" as the actor; each copy stage
    /// rewrites its own and takes them off this list.
    func testAppNameOnlyWhereItSaysWhichApp() throws {
        let whichApp: Set<String> = [
            "session.load.unsupported.message",       // a list saved by another version
            "single_instance.already_running.title",  // a second copy
            "single_instance.already_running.message",
            "onboarding.data.description",            // supporting the project
            "settings.data.caption",
        ]
        let pending: Set<String> = [
            // Deferred with the folder's "Retry" button
            "torrent.error.save_path_unavailable.message",
            // Stage 5: deletion
            "remove_dialog.choice.message.list_only",
            "remove_dialog.delete_with_files.message",
            "add_torrent.cancel.message",
            "payload_deletion.engine_stop_failed.message",
            "payload_deletion.partial_failure.message.one",
            "payload_deletion.partial_failure.message.few",
            "payload_deletion.partial_failure.message.many",
            "payload_deletion.partial_failure.message.other",
            "payload_deletion.unresolved.message",
            "payload_deletion.safety_refused.message",
            "payload_deletion.cleanup_failure.message",
            // Stage 6: settings
            "settings.downloads.performance.caption.main",
            "settings.downloads.network.port_forwarding.caption",
            "settings.tab.about",
        ]
        let debugPrefixes = ["settings.debug.", "settings.localization.", "menu.debug."]

        var namingKeys: Set<String> = []
        var failures: [String] = []
        for language in ShatlTypograph.languages {
            for (key, value) in try strings(for: language) where value.contains("Shatl") {
                namingKeys.insert(key)
                let allowed = whichApp.contains(key)
                    || pending.contains(key)
                    || debugPrefixes.contains { key.hasPrefix($0) }
                if !allowed { failures.append("\(language) \(key): \(value)") }
            }
        }
        XCTAssertEqual(failures, [], "Write about the object and the result, not about Shatl")
        XCTAssertEqual(pending.subtracting(namingKeys), [], "Rewritten: take these keys off the pending list")
    }

    // MARK: - The rules

    func testRussianShortWordsStayWithTheNextWord() {
        XCTAssertEqual(
            ShatlTypograph.apply("Не удалось найти загрузку в списке или в папке", language: "ru"),
            "Не\(nbsp)удалось найти загрузку в\(nbsp)списке или\(nbsp)в\(nbsp)папке"
        )
        XCTAssertEqual(
            ShatlTypograph.apply("Отложено из-за ошибки для этой загрузки", language: "ru"),
            "Отложено из-за\(nbsp)ошибки для\(nbsp)этой загрузки"
        )
    }

    func testLatinCompoundsDoNotBreakAtTheHyphen() {
        XCTAssertEqual(
            ShatlTypograph.apply("Вставьте magnet-ссылку или выберите .torrent-файл", language: "ru"),
            "Вставьте magnet\u{2011}ссылку или\(nbsp)выберите .torrent\u{2011}файл"
        )
        XCTAssertEqual(ShatlTypograph.apply("торрент-клиент", language: "ru"), "торрент-клиент")
        XCTAssertEqual(ShatlTypograph.apply("a magnet-link", language: "en"), "a\(nbsp)magnet-link")
    }

    func testRussianParticlesStayWithTheWordBefore() {
        XCTAssertEqual(
            ShatlTypograph.apply("Файлы скачаются в ту же папку", language: "ru"),
            "Файлы скачаются в\(nbsp)ту\(nbsp)же папку"
        )
    }

    /// The "с" of "МБ/с" is a unit, not the preposition.
    func testUnitsAreNotMistakenForWords() {
        XCTAssertEqual(
            ShatlTypograph.apply("10 МБ/с может превратиться в 10,5 МБ/с", language: "ru"),
            "10\(nbsp)МБ/с может превратиться в\(nbsp)10,5\(nbsp)МБ/с"
        )
    }

    func testNumbersStayWithTheirWord() {
        XCTAssertEqual(ShatlTypograph.apply("Не удалось удалить 3 файла", language: "ru"), "Не\(nbsp)удалось удалить 3\(nbsp)файла")
        XCTAssertEqual(ShatlTypograph.apply("%lld files", language: "en"), "%lld\(nbsp)files")
        XCTAssertEqual(ShatlTypograph.apply("Всего 8 955 файлов", language: "ru"), "Всего 8\(narrow)955\(nbsp)файлов")
    }

    func testDashNeverStartsALine() {
        XCTAssertEqual(ShatlTypograph.apply("Несколько шагов — и всё", language: "ru"), "Несколько шагов\(nbsp)— и\(nbsp)всё")
        XCTAssertEqual(ShatlTypograph.apply("So sehen sie aus – jeder", language: "de"), "So sehen sie aus\(nbsp)– jeder")
        XCTAssertEqual(ShatlTypograph.apply("Halo, Orbit, or Nova—from", language: "en"), "Halo, Orbit, or Nova—from")
    }

    func testEllipsisIsOneCharacter() {
        XCTAssertEqual(ShatlTypograph.apply("Проверка...", language: "ru"), "Проверка…")
    }

    func testFrenchSpacing() {
        XCTAssertEqual(ShatlTypograph.apply("Partager ?", language: "fr"), "Partager\(narrow)?")
        XCTAssertEqual(ShatlTypograph.apply("Réglages:", language: "fr"), "Réglages\(narrow):")
        XCTAssertEqual(ShatlTypograph.apply("Cliquez sur «OK».", language: "fr"), "Cliquez sur «\(narrow)OK\(narrow)».")
        XCTAssertEqual(ShatlTypograph.apply("Le torrent « %@ »", language: "fr"), "Le torrent «\(narrow)%@\(narrow)»")
        XCTAssertEqual(ShatlTypograph.apply("commence par magnet:? et", language: "fr"), "commence par magnet:? et")
        XCTAssertEqual(ShatlTypograph.apply("à nouveau", language: "fr"), "à\(nbsp)nouveau")
    }

    func testOtherLanguagesBindTheirShortWords() {
        XCTAssertEqual(ShatlTypograph.apply("Paste a link", language: "en"), "Paste a\(nbsp)link")
        XCTAssertEqual(ShatlTypograph.apply("Elige otro o quita", language: "es"), "Elige otro o\(nbsp)quita")
        XCTAssertEqual(ShatlTypograph.apply("Prüfen Sie oder entfernen", language: "de"), "Prüfen Sie oder entfernen")
    }

    func testTypesettingTwiceChangesNothing() {
        for language in ShatlTypograph.languages {
            let sample = "Не удалось — 3 файла в списке... Partager ? « %@ » a link"
            let once = ShatlTypograph.apply(sample, language: language)
            XCTAssertEqual(ShatlTypograph.apply(once, language: language), once, language)
        }
    }

    // MARK: - Plural forms

    func testPluralKeysFollowEachLanguage() {
        let base = "payload_deletion.partial_failure.message"
        XCTAssertEqual(L10n.pluralKey(base, count: 1, localeOverride: .russian), base + ".one")
        XCTAssertEqual(L10n.pluralKey(base, count: 3, localeOverride: .russian), base + ".few")
        XCTAssertEqual(L10n.pluralKey(base, count: 6, localeOverride: .russian), base + ".many")
        XCTAssertEqual(L10n.pluralKey(base, count: 21, localeOverride: .russian), base + ".one")
        XCTAssertEqual(L10n.pluralKey(base, count: 1, localeOverride: .english), base + ".one")
        XCTAssertEqual(L10n.pluralKey(base, count: 2, localeOverride: .english), base + ".other")
        XCTAssertEqual(L10n.pluralKey(base, count: 2, localeOverride: .japanese), base + ".other")
    }

    func testPartialDeletionNamesTheCountInWords() {
        let base = "payload_deletion.partial_failure.message"
        for (count, word) in [(1, "файл"), (3, "файла"), (6, "файлов"), (21, "файл")] {
            let message = L10n.format(
                L10n.pluralKey(base, count: count, localeOverride: .russian),
                localeOverride: .russian,
                defaultValue: "",
                count
            )
            XCTAssertTrue(message.contains("\(count)\(nbsp)\(word) "), message)
        }
        for language in [AppLocaleOverride.english, .german, .spanish, .french, .japanese, .simplifiedChinese] {
            for count in [1, 2] {
                let key = L10n.pluralKey(base, count: count, localeOverride: language)
                XCTAssertNotEqual(L10n.string(key, localeOverride: language, defaultValue: ""), "", "\(language) \(key)")
            }
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

    private func visible(_ text: String) -> String {
        text
            .replacingOccurrences(of: nbsp, with: "⍽")
            .replacingOccurrences(of: narrow, with: "⌴")
    }
}
