// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
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

    /// While the assets are still in the catalog: every token in code is the
    /// colour its asset had, in both themes.
    func testEveryTokenMatchesTheAssetItReplaces() throws {
        for (name, token) in Self.tokensWithAssets {
            let asset = try XCTUnwrap(NSColor(named: name), name)
            for scheme in [ColorScheme.light, .dark] {
                let expected = try components(asset, in: scheme)
                let actual = try components(token, in: scheme)
                XCTAssertTrue(
                    zip(expected, actual).allSatisfy { abs($0 - $1) <= 1 },
                    "\(name), \(scheme): \(actual) instead of \(expected)"
                )
            }
        }
    }

    private static let tokensWithAssets: [(String, Color)] = [
        ("backgroundSecondary", ShatlColor.backgroundSecondary),
        ("backgroundTertiary", ShatlColor.backgroundTertiary),
        ("backgroundPrimary", ShatlColor.backgroundPrimary),
        ("backgroundAddWindow", ShatlColor.backgroundAddWindow),
        ("buttonNeutral", ShatlColor.buttonNeutral),
        ("cardDefault", ShatlColor.cardDefault),
        ("cardHover", ShatlColor.cardHover),
        ("errorSolidBackground", ShatlColor.errorSolidBackground),
        ("progressBarTrack", ShatlColor.progressBarTrack),
        ("speedBadgeTortoise", ShatlColor.speedBadgeTortoise),
        ("speedIconTortoise", ShatlColor.speedIconTortoise),
        ("speedLabelTortoise", ShatlColor.speedLabelTortoise),
        ("speedBadgeWalk", ShatlColor.speedBadgeWalk),
        ("speedIconWalk", ShatlColor.speedIconWalk),
        ("speedLabelWalk", ShatlColor.speedLabelWalk),
        ("speedBadgeRun", ShatlColor.speedBadgeRun),
        ("speedIconRun", ShatlColor.speedIconRun),
        ("speedLabelRun", ShatlColor.speedLabelRun),
        ("speedBadgeHare", ShatlColor.speedBadgeHare),
        ("speedIconHare", ShatlColor.speedIconHare),
        ("speedLabelHare", ShatlColor.speedLabelHare),
        ("speedBadgeBolt", ShatlColor.speedBadgeBolt),
        ("speedIconBolt", ShatlColor.speedIconBolt),
        ("speedLabelBolt", ShatlColor.speedLabelBolt),
        ("metricBackground", ShatlColor.metricBackground),
        ("metricDivider", ShatlColor.metricDivider),
        ("metricOutline", ShatlColor.metricOutline),
        ("outlinePrimary", ShatlColor.outlinePrimary),
        ("outlineSecondary", ShatlColor.outlineSecondary),
        ("outlineTertiary", ShatlColor.outlineTertiary),
        ("cerisePink", ShatlColor.cerisePink),
        ("slate", ShatlColor.slate),
        ("neonBlue", ShatlColor.neonBlue),
        ("statusBadgeCompletedDefault", ShatlColor.statusBadgeCompletedDefault),
        ("statusBadgeCompletedHover", ShatlColor.statusBadgeCompletedHover),
        ("statusBadgeDownloadingDefault", ShatlColor.statusBadgeDownloadingDefault),
        ("statusBadgeDownloadingHover", ShatlColor.statusBadgeDownloadingHover),
        ("statusBadgeErrorDefault", ShatlColor.statusBadgeErrorDefault),
        ("statusBadgeErrorHover", ShatlColor.statusBadgeErrorHover),
        ("statusBadgePausedDefault", ShatlColor.statusBadgePausedDefault),
        ("statusBadgePausedHover", ShatlColor.statusBadgePausedHover),
        ("statusBadgeSeedingDefault", ShatlColor.statusBadgeSeedingDefault),
        ("statusBadgeSeedingHover", ShatlColor.statusBadgeSeedingHover),
        ("statusTextCompletedDefault", ShatlColor.statusTextCompletedDefault),
        ("statusTextCompletedHover", ShatlColor.statusTextCompletedHover),
        ("statusTextDownloadingDefault", ShatlColor.statusTextDownloadingDefault),
        ("statusTextDownloadingHover", ShatlColor.statusTextDownloadingHover),
        ("statusTextErrorDefault", ShatlColor.statusTextErrorDefault),
        ("statusTextErrorHover", ShatlColor.statusTextErrorHover),
        ("statusTextPausedDefault", ShatlColor.statusTextPausedDefault),
        ("statusTextPausedHover", ShatlColor.statusTextPausedHover),
        ("statusTextSeedingDefault", ShatlColor.statusTextSeedingDefault),
        ("statusTextSeedingHover", ShatlColor.statusTextSeedingHover),
        ("typographyPrimary", ShatlColor.typographyPrimary),
        ("typographyPrimaryInverted", ShatlColor.typographyPrimaryInverted),
        ("typographySecondary", ShatlColor.typographySecondary),
        ("typographyTertiary", ShatlColor.typographyTertiary),
        ("lineMessageBackground", ShatlColor.lineMessageBackground),
        ("lineMessageButtonBackground", ShatlColor.lineMessageButtonBackground),
        ("lineMessageButtonLabel", ShatlColor.lineMessageButtonLabel),
        ("lineMessageCaption", ShatlColor.lineMessageCaption),
        ("lineMessageHeadline", ShatlColor.lineMessageHeadline),
        ("onboardingForeground", ShatlColor.onboardingForeground),
        ("onboardingBackground", ShatlColor.onboardingBackground),
        ("onboardingButtonText", ShatlColor.onboardingButtonText),
        ("onboardingButtonBody", ShatlColor.onboardingButtonBody),
        ("shadowKeyColor", ShatlColor.shadowKeyColor),
    ]

    /// The colour as SwiftUI draws it in a view of that scheme, in sRGB
    /// bytes. A fully transparent colour reads as zeros.
    private func components(_ color: Color, in scheme: ColorScheme) throws -> [Int] {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return try bytes(color.resolve(in: environment).cgColor)
    }

    private func components(_ color: NSColor, in scheme: ColorScheme) throws -> [Int] {
        let appearance = try XCTUnwrap(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua))
        var resolved: CGColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)?.cgColor
        }
        return try bytes(XCTUnwrap(resolved))
    }

    private func bytes(_ color: CGColor) throws -> [Int] {
        let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let converted = try XCTUnwrap(color.converted(to: srgb, intent: .defaultIntent, options: nil))
        let parts = try XCTUnwrap(converted.components)
        let rgba = parts.map { Int(($0 * 255).rounded()) }
        return rgba[3] == 0 ? [0, 0, 0, 0] : rgba
    }
}
