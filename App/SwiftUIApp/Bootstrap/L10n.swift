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
