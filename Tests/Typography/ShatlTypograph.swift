// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Typesetting rules for interface strings, one set per language. The tests
/// check that every string is already typeset; `Scripts/typograph.sh` applies
/// the same rules to the strings files, so nobody places non-breaking spaces
/// by hand. The rules only add non-breaking spaces and replace characters:
/// a non-breaking space placed by hand is never removed.
///
/// Plain Foundation and no app types: the script compiles this file on its own.
nonisolated enum ShatlTypograph {
    static let languages = ["ru", "en", "de", "es", "fr", "ja", "zh-Hans"]

    static let noBreakSpace = "\u{00A0}"
    static let narrowNoBreakSpace = "\u{202F}"

    /// Short Russian prepositions, conjunctions and particles that must not
    /// end a line: every word of one or two letters, plus a few of three.
    static let russianLeadingWords = [
        "в", "во", "к", "ко", "с", "со", "у", "о", "об", "а", "и", "я",
        "на", "по", "за", "из", "от", "до", "не", "ни", "но", "да", "же",
        "их", "её", "ей", "ею", "ее", "мы", "вы", "он", "ты", "то", "ну",
        "для", "или", "без", "при", "про", "под", "над", "обо", "изо", "ото",
        "из-за", "из-под",
    ]

    /// Particles that lean on the word before them.
    static let russianTrailingWords = ["же", "ли", "бы", "ль"]

    static func apply(_ text: String, language: String) -> String {
        var result = text.replacingOccurrences(of: "...", with: "…")
        result = bindDashes(result)
        result = bindNumbers(result)

        switch language {
        case "ru":
            result = bindTrailing(result, words: russianTrailingWords)
            result = bindLeading(result, words: russianLeadingWords.filter { !russianTrailingWords.contains($0) })
        case "en":
            result = bindLeading(result, words: ["a", "an"])
        case "es":
            result = bindLeading(result, words: ["a", "e", "o", "u", "y"])
        case "fr":
            result = bindLeading(result, words: ["à", "au", "aux"])
            result = frenchSpacing(result)
        default:
            break
        }

        return result
    }

    // MARK: - Rules

    /// A dash never starts a line: the space before it does not break.
    private static func bindDashes(_ text: String) -> String {
        replace(#" (?=—)| (?=– )"#, in: text, with: noBreakSpace)
    }

    /// A number stays with the word or unit after it ("3 файла", "10 МБ/с"),
    /// and thousands are grouped with a narrow space ("8 955").
    private static func bindNumbers(_ text: String) -> String {
        let grouped = replace(#"(?<=\d) (?=\d{3}(?!\d))"#, in: text, with: narrowNoBreakSpace)
        return replace(#"(?<=\d|%l{0,2}[dui]|%\d\$l{0,2}[dui]) (?=[\p{L}%])"#, in: grouped, with: noBreakSpace)
    }

    /// The space after a short word does not break, so the word starts the
    /// next line together with what it belongs to.
    private static func bindLeading(_ text: String, words: [String]) -> String {
        // Not after a slash or a dot: the "с" of "МБ/с" is a unit, not a word.
        let pattern = #"(?<![\p{L}\p{N}\-’'/.])("# + alternation(words) + ") "
        return replace(pattern, in: text, with: "$1" + noBreakSpace, caseInsensitive: true)
    }

    /// The space before a particle does not break.
    private static func bindTrailing(_ text: String, words: [String]) -> String {
        let pattern = " (" + alternation(words) + #")(?![\p{L}\p{N}\-])"#
        return replace(pattern, in: text, with: noBreakSpace + "$1", caseInsensitive: true)
    }

    /// French puts a narrow non-breaking space before ; : ? ! and inside « ».
    private static func frenchSpacing(_ text: String) -> String {
        var result = replace(#"[  ](?=[;:?!])"#, in: text, with: narrowNoBreakSpace)
        result = replace(#"(?<=[\p{L}\p{N}»)…])(?=[;:?!](?:\s|$|»))"#, in: result, with: narrowNoBreakSpace)
        result = replace(#"«(?:[  ]|(?=[^ ]))"#, in: result, with: "«" + narrowNoBreakSpace)
        result = replace(#"(?:[  ]|(?<=[^ ]))»"#, in: result, with: narrowNoBreakSpace + "»")
        return result
    }

    // MARK: - Helpers

    private static func alternation(_ words: [String]) -> String {
        words
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
    }

    private static func replace(
        _ pattern: String,
        in text: String,
        with template: String,
        caseInsensitive: Bool = false
    ) -> String {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            preconditionFailure("Bad typograph pattern: \(pattern)")
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
