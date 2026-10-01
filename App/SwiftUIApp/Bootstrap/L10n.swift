// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated enum L10n {
    nonisolated static func string(
        _ key: String,
        localeOverride: AppLocaleOverride = .system,
        defaultValue: String? = nil
    ) -> String {
        localizedBundle(for: localeOverride)
            .localizedString(forKey: key, value: defaultValue, table: nil)
    }

    nonisolated static func format(
        _ key: String,
        localeOverride: AppLocaleOverride = .system,
        defaultValue: String,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(key, localeOverride: localeOverride, defaultValue: defaultValue),
            locale: locale(for: localeOverride),
            arguments: arguments
        )
    }

    /// The key of the plural form `count` takes in the interface language, as
    /// the strings files spell it: `base.one`, `base.few`, `base.many`,
    /// `base.other`. A count never sits beside "(s)" or "(ов)".
    nonisolated static func pluralKey(
        _ baseKey: String,
        count: Int,
        localeOverride: AppLocaleOverride = .system
    ) -> String {
        "\(baseKey).\(L10nPluralCategory.resolve(count: count, localeOverride: localeOverride).rawValue)"
    }

    nonisolated static func locale(for localeOverride: AppLocaleOverride = .system) -> Locale {
        guard let localeIdentifier = localeOverride.localeIdentifier else {
            return .autoupdatingCurrent
        }

        return Locale(identifier: localeIdentifier)
    }

    private nonisolated static func localizedBundle(for localeOverride: AppLocaleOverride) -> Bundle {
        guard let localeIdentifier = localeOverride.localeIdentifier,
              let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return .main
        }

        return bundle
    }
}

/// Plural categories as each interface language needs them.
nonisolated enum L10nPluralCategory: String {
    case one
    case few
    case many
    case other

    static func resolve(count: Int, localeOverride: AppLocaleOverride) -> Self {
        // The language the strings come from, which for the system setting is
        // the bundle's choice rather than the region's.
        let identifier = localeOverride.localeIdentifier
            ?? Bundle.main.preferredLocalizations.first
            ?? "en"
        let languageCode = Locale(identifier: identifier).language.languageCode?.identifier

        switch languageCode {
        case "ru":
            let modulo10 = count % 10
            let modulo100 = count % 100
            if modulo10 == 1, modulo100 != 11 {
                return .one
            }
            if (2...4).contains(modulo10), !(12...14).contains(modulo100) {
                return .few
            }
            return .many
        case "en", "de", "es":
            return count == 1 ? .one : .other
        case "fr":
            return count == 0 || count == 1 ? .one : .other
        default:
            return .other
        }
    }
}
