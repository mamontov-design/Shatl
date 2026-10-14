// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XCTest
@testable import Shatl

/// The foot of "О программе": where its links lead and that it stays as
/// low as it is drawn. Settings never scroll, so a second line there would
/// make the window taller in that language alone.
@MainActor
final class AboutLinksTests: XCTestCase {
    private let languages = AppLocaleOverride.allCases.filter { $0 != .system }
    private let site = "https://mamontov-design.github.io/Shatl/"
    /// The 440 pt window less its 16 pt sides.
    private let contentWidth: CGFloat = 440 - 16 * 2

    func testWebsiteLinkLeavesTheLanguageToTheSite() {
        for language in languages {
            XCTAssertEqual(AboutLink.website.url(localeOverride: language).absoluteString, site)
        }
    }

    /// The site has the privacy policy and the terms in Russian and English
    /// only; any other address there is "not found".
    func testLegalPagesAreRussianInRussianAndEnglishElsewhere() {
        XCTAssertEqual(AboutLink.privacy.url(localeOverride: .russian).absoluteString, site + "ru/privacy/")
        XCTAssertEqual(AboutLink.terms.url(localeOverride: .russian).absoluteString, site + "ru/terms/")

        for language in languages where language != .russian {
            XCTAssertEqual(
                AboutLink.privacy.url(localeOverride: language).absoluteString,
                site + "en/privacy/",
                language.rawValue
            )
            XCTAssertEqual(
                AboutLink.terms.url(localeOverride: language).absoluteString,
                site + "en/terms/",
                language.rawValue
            )
        }
    }

    func testLegalLanguageFollowsTheLanguageNotTheRegion() {
        XCTAssertEqual(ShatlLinks.legalLanguage(forInterfaceLanguage: "ru"), "ru")
        XCTAssertEqual(ShatlLinks.legalLanguage(forInterfaceLanguage: "ru-KZ"), "ru")
        XCTAssertEqual(ShatlLinks.legalLanguage(forInterfaceLanguage: "en-GB"), "en")
        XCTAssertEqual(ShatlLinks.legalLanguage(forInterfaceLanguage: "zh-Hans"), "en")
        XCTAssertEqual(ShatlLinks.legalLanguage(forInterfaceLanguage: "uk"), "en")
        XCTAssertEqual(ShatlLinks.legalLanguage(forInterfaceLanguage: nil), "en")
    }

    func testEveryLinkIsTranslated() {
        for language in languages {
            for link in AboutLink.allCases {
                XCTAssertNotEqual(
                    L10n.string(link.titleKey, localeOverride: language),
                    link.titleKey,
                    "\(language.rawValue) \(link.titleKey)"
                )
            }
        }
    }

    func testLinksFitOneLineInEveryLanguage() {
        for language in languages {
            let row = HStack(spacing: AboutSettingsFooter.linkSpacing) {
                ForEach(AboutLink.allCases) { link in
                    ShatlLinkButton(
                        title: L10n.string(link.titleKey, localeOverride: language),
                        url: link.url(localeOverride: language)
                    )
                }
            }
            .fixedSize()
            .shatlTypographyProfile(localeOverride: language)
            let width = NSHostingView(rootView: row).fittingSize.width
            XCTAssertLessThanOrEqual(width, contentWidth, language.rawValue)
        }
    }

    func testSignatureFitsOneLineInEveryLanguage() {
        for language in languages {
            let signature = L10n.string("settings.about.footer", localeOverride: language)
            let line = Text(signature)
                .shatlTypography(ShatlTypography.captionRegular)
                .fixedSize()
                .shatlTypographyProfile(localeOverride: language)
            let width = NSHostingView(rootView: line).fittingSize.width
            XCTAssertLessThanOrEqual(width, contentWidth, "\(language.rawValue): \(signature)")
        }
    }
}
