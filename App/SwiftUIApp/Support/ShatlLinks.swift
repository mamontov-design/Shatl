// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

enum ShatlLinks {
    /// The site with the latest version for download. It picks its own
    /// language.
    static let website = URL(string: "https://mamontov-design.github.io/Shatl/")!

    static func privacy(localeOverride: AppLocaleOverride = .system) -> URL {
        legalPage("privacy", localeOverride: localeOverride)
    }

    static func terms(localeOverride: AppLocaleOverride = .system) -> URL {
        legalPage("terms", localeOverride: localeOverride)
    }

    /// The privacy policy and the terms exist on the site in Russian and in
    /// English only, and have no address without a language: every other
    /// interface language reads the English page, as the site's footer does.
    nonisolated static func legalLanguage(forInterfaceLanguage language: String?) -> String {
        guard let language else { return "en" }
        return Locale(identifier: language).language.languageCode == .russian ? "ru" : "en"
    }

    private static func legalPage(_ name: String, localeOverride: AppLocaleOverride) -> URL {
        let interfaceLanguage = localeOverride.localeIdentifier ?? Bundle.main.preferredLocalizations.first
        return website
            .appendingPathComponent(legalLanguage(forInterfaceLanguage: interfaceLanguage), isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }
}
