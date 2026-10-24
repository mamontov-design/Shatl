// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// Off the main actor: AppKit and Core Animation resolve a colour on their own
/// threads, as when a gradient is drawn, and every colour here is a constant.
nonisolated extension Color {
    /// An sRGB colour written as Figma shows it: `Color(rgb: 0xF0F0F0)`.
    init(rgb: UInt32) {
        self.init(nsColor: NSColor(rgba: rgb << 8 | 0xFF))
    }

    /// An sRGB colour with its opacity in the last byte, as Radix writes
    /// transparent steps: `Color(rgba: 0xFFFFFF12)`.
    init(rgba: UInt32) {
        self.init(nsColor: NSColor(rgba: rgba))
    }

    /// A colour that is `light` in the light appearance and `dark` in the
    /// dark one. The system picks between them the way it does for an asset
    /// colour, so a window follows the theme set in Settings by itself.
    init(light: Color, dark: Color) {
        let light = NSColor(light)
        let dark = NSColor(dark)
        self.init(nsColor: NSColor(name: nil) { @Sendable appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private nonisolated extension NSColor {
    convenience init(rgba: UInt32) {
        self.init(
            srgbRed: CGFloat(rgba >> 24 & 0xFF) / 255,
            green: CGFloat(rgba >> 16 & 0xFF) / 255,
            blue: CGFloat(rgba >> 8 & 0xFF) / 255,
            alpha: CGFloat(rgba & 0xFF) / 255
        )
    }
}

/// Tokens: what a colour is for. Each names its light and dark colour in
/// `ShatlPalette`, and Figma has the same token in its Tokens collection:
/// `line-message/background` there is `lineMessageBackground` here. Views
/// use only these.
enum ShatlColor {
    /// The app's accent: the `AccentColor` asset (gray 12 in light, gray-dark
    /// 12 in dark) unless the user picked an accent in System Settings.
    static let accent = Color.accentColor
    /// The coloured accent: the check marks beside what is sent, the flash
    /// of a metric on the card previews.
    static let accentColored = Color(light: ShatlPalette.violet9, dark: ShatlPalette.violetDark10)
    /// The accent of the monochrome appearance, in place of the asset and
    /// of the accent chosen in macOS: black in light, white in dark.
    static let accentMonochrome = Color(light: ShatlPalette.gray12, dark: ShatlPalette.grayDark12)

    static let backgroundPrimary = Color(light: ShatlPalette.gray2, dark: ShatlPalette.grayDarkA4)
    static let backgroundSecondary = Color(light: ShatlPalette.gray3, dark: ShatlPalette.grayDarkA3)
    static let backgroundTertiary = Color(light: ShatlPalette.white, dark: ShatlPalette.black)
    /// The add window's own background, and the cover its files are shown
    /// from under: what the system draws as a window's background, white in
    /// light and #1E1E1E in dark, without the wallpaper's tint. The tint is
    /// no one colour, so nothing painted over the system's background could
    /// match it.
    static let backgroundAddWindow = Color(light: ShatlPalette.white, dark: ShatlPalette.windowBackgroundDark)

    static let buttonNeutral = Color(light: ShatlPalette.grayA3, dark: ShatlPalette.grayDarkA8)

    /// A card keeps one fill whatever happens to it; its outline answers the
    /// pointer and the selection.
    static let cardBackgroundDefault = Color(light: ShatlPalette.white, dark: ShatlPalette.grayDarkA3)

    static let cardOutlineDefault = Color(light: ShatlPalette.gray6, dark: ShatlPalette.grayDarkA6)
    static let cardOutlineHover = Color(light: ShatlPalette.gray8, dark: ShatlPalette.grayDarkA8)
    /// Three quarters of the accent, which follows the one the user picked.
    static let cardOutlineSelected = accent.opacity(0.75)
    /// The same in the monochrome appearance.
    static let cardOutlineSelectedMonochrome = accentMonochrome.opacity(0.75)
    static let cardOutlineError = Color(light: ShatlPalette.red8, dark: ShatlPalette.redDarkA8)

    /// The fill of a message that needs attention now, under white text:
    /// no room for a download in the add window.
    static let errorSolidBackground = Color(light: ShatlPalette.red9, dark: ShatlPalette.redDark9)

    /// The line message under the toolbar is inverted: in light it takes
    /// the dark scale, in dark the light one.
    static let lineMessageBackground = Color(light: ShatlPalette.grayDark3, dark: ShatlPalette.gray3)
    static let lineMessageHeadline = Color(light: ShatlPalette.grayDark12, dark: ShatlPalette.gray12)
    static let lineMessageCaption = Color(light: ShatlPalette.grayDark11, dark: ShatlPalette.gray11)
    static let lineMessageButtonBackground = Color(light: ShatlPalette.grayDark8, dark: ShatlPalette.gray7)
    static let lineMessageButtonLabel = Color(light: ShatlPalette.white, dark: ShatlPalette.gray12)

    static let metricBackground = Color(light: ShatlPalette.white, dark: ShatlPalette.clear)
    static let metricDivider = Color(light: ShatlPalette.gray3, dark: ShatlPalette.grayDarkA3)
    static let metricOutline = Color(light: ShatlPalette.gray6, dark: ShatlPalette.grayDarkA6)
    /// The expanded metrics sit on a filled plate with no outline or
    /// shadow; the speed and the time left keep the outlined plate.
    static let metricBackgroundMuted = Color(light: ShatlPalette.gray3, dark: ShatlPalette.grayDark3)
    static let metricDividerMuted = Color(light: ShatlPalette.gray6, dark: ShatlPalette.grayDark6)

    static let onboardingBackground = Color(light: ShatlPalette.gray3, dark: ShatlPalette.grayDark2)
    static let onboardingForeground = Color(light: ShatlPalette.white, dark: ShatlPalette.grayDark6)

    static let outlinePrimary = Color(light: ShatlPalette.gray6, dark: ShatlPalette.grayDarkA8)
    static let outlineSecondary = Color(light: ShatlPalette.grayA3, dark: ShatlPalette.grayDarkA3)
    static let outlineTertiary = Color(light: ShatlPalette.gray4, dark: ShatlPalette.grayDarkA3)

    /// `backgroundTertiary` in light; 20% black in dark, so the empty part of
    /// the bar does not read as a hole in the card.
    static let progressBarTrack = Color(light: ShatlPalette.white, dark: ShatlPalette.blackA4)

    static let speedBadgeTortoise = Color(light: ShatlPalette.slate3, dark: ShatlPalette.slateDark4)
    static let speedBadgeWalk = Color(light: ShatlPalette.teal3, dark: ShatlPalette.tealDark4)
    static let speedBadgeRun = Color(light: ShatlPalette.grass3, dark: ShatlPalette.grassDark4)
    static let speedBadgeHare = Color(light: ShatlPalette.orange3, dark: ShatlPalette.orangeDark4)
    static let speedBadgeBolt = Color(light: ShatlPalette.ruby3, dark: ShatlPalette.rubyDark4)
    /// The monochrome appearance leaves the speed without a plate.
    static let speedBadgeMonochromatic = Color(light: ShatlPalette.clear, dark: ShatlPalette.clear)
    static let speedIconTortoise = Color(light: ShatlPalette.slate9, dark: ShatlPalette.slateDark9)
    static let speedIconWalk = Color(light: ShatlPalette.teal9, dark: ShatlPalette.tealDark9)
    static let speedIconRun = Color(light: ShatlPalette.grass9, dark: ShatlPalette.grassDark9)
    static let speedIconHare = Color(light: ShatlPalette.orange9, dark: ShatlPalette.orangeDark9)
    static let speedIconBolt = Color(light: ShatlPalette.ruby9, dark: ShatlPalette.rubyDark9)
    static let speedLabelTortoise = Color(light: ShatlPalette.slate11, dark: ShatlPalette.slateDark12)
    static let speedLabelWalk = Color(light: ShatlPalette.teal11, dark: ShatlPalette.tealDark12)
    static let speedLabelRun = Color(light: ShatlPalette.grass11, dark: ShatlPalette.grassDark12)
    static let speedLabelHare = Color(light: ShatlPalette.orange11, dark: ShatlPalette.orangeDark12)
    static let speedLabelBolt = Color(light: ShatlPalette.ruby11, dark: ShatlPalette.rubyDark12)

    /// A filled badge says the download is doing something; an outlined one
    /// says it stands: idle, paused, being added or saved. "Скачана" and
    /// "Ошибка" keep their fill. Its text and icon are a step lighter at
    /// rest and darken under the pointer.
    static let statusBadgeDownloadingDefault = Color(light: ShatlPalette.purple3, dark: ShatlPalette.purpleDark7)
    static let statusBadgeDownloadingHover = Color(light: ShatlPalette.purple4, dark: ShatlPalette.purpleDark8)
    static let statusBadgeDownloadingStalledDefault = Color(light: ShatlPalette.clear, dark: ShatlPalette.clear)
    static let statusBadgeDownloadingStalledHover = Color(light: ShatlPalette.clear, dark: ShatlPalette.clear)
    static let statusBadgePausedDefault = Color(light: ShatlPalette.clear, dark: ShatlPalette.clear)
    static let statusBadgePausedHover = Color(light: ShatlPalette.clear, dark: ShatlPalette.clear)
    static let statusBadgeSeedingDefault = Color(light: ShatlPalette.sky3, dark: ShatlPalette.skyDark6)
    static let statusBadgeSeedingHover = Color(light: ShatlPalette.sky4, dark: ShatlPalette.skyDark7)
    static let statusBadgeSeedingStalledDefault = Color(light: ShatlPalette.clear, dark: ShatlPalette.clear)
    static let statusBadgeSeedingStalledHover = Color(light: ShatlPalette.clear, dark: ShatlPalette.clear)
    static let statusBadgeCompletedDefault = Color(light: ShatlPalette.gold3, dark: ShatlPalette.goldDark6)
    static let statusBadgeCompletedHover = Color(light: ShatlPalette.gold4, dark: ShatlPalette.goldDark7)
    static let statusBadgeErrorDefault = Color(light: ShatlPalette.red3, dark: ShatlPalette.redDark6)
    static let statusBadgeErrorHover = Color(light: ShatlPalette.red4, dark: ShatlPalette.redDark7)

    /// The outline of a standing badge, 1 pt inside. A saved download's is
    /// dashed and a step darker, so that the dashes hold.
    static let statusBadgeOutlineDownloadingStalledDefault = Color(light: ShatlPalette.purple6, dark: ShatlPalette.purpleDark7)
    static let statusBadgeOutlineDownloadingStalledHover = Color(light: ShatlPalette.purple7, dark: ShatlPalette.purpleDark8)
    static let statusBadgeOutlineDownloadingStalledDashedDefault = Color(light: ShatlPalette.purple7, dark: ShatlPalette.purpleDark8)
    static let statusBadgeOutlineDownloadingStalledDashedHover = Color(light: ShatlPalette.purple8, dark: ShatlPalette.purpleDark9)
    static let statusBadgeOutlinePausedDefault = Color(light: ShatlPalette.purple6, dark: ShatlPalette.purpleDark7)
    static let statusBadgeOutlinePausedHover = Color(light: ShatlPalette.purple7, dark: ShatlPalette.purpleDark8)
    static let statusBadgeOutlineSeedingStalledDefault = Color(light: ShatlPalette.sky6, dark: ShatlPalette.skyDark7)
    static let statusBadgeOutlineSeedingStalledHover = Color(light: ShatlPalette.sky7, dark: ShatlPalette.skyDark8)

    static let statusTextDownloadingDefault = Color(light: ShatlPalette.violet10, dark: ShatlPalette.violetDark12)
    static let statusTextDownloadingHover = Color(light: ShatlPalette.violet11, dark: ShatlPalette.violetDark12)
    static let statusTextDownloadingStalledDefault = Color(light: ShatlPalette.violet9, dark: ShatlPalette.violetDark12)
    static let statusTextDownloadingStalledHover = Color(light: ShatlPalette.violet10, dark: ShatlPalette.violetDark12)
    static let statusTextPausedDefault = Color(light: ShatlPalette.violet9, dark: ShatlPalette.violetDark12)
    static let statusTextPausedHover = Color(light: ShatlPalette.violet10, dark: ShatlPalette.violetDark12)
    static let statusTextSeedingDefault = Color(light: ShatlPalette.blue10, dark: ShatlPalette.blueDarkA12)
    static let statusTextSeedingHover = Color(light: ShatlPalette.blue11, dark: ShatlPalette.blueDarkA12)
    static let statusTextSeedingStalledDefault = Color(light: ShatlPalette.blue9, dark: ShatlPalette.blueDarkA12)
    static let statusTextSeedingStalledHover = Color(light: ShatlPalette.blue10, dark: ShatlPalette.blueDarkA12)
    static let statusTextCompletedDefault = Color(light: ShatlPalette.gold10, dark: ShatlPalette.goldDark12)
    static let statusTextCompletedHover = Color(light: ShatlPalette.gold11, dark: ShatlPalette.goldDark12)
    static let statusTextErrorDefault = Color(light: ShatlPalette.red10, dark: ShatlPalette.redDark12)
    static let statusTextErrorHover = Color(light: ShatlPalette.red11, dark: ShatlPalette.redDark12)

    /// The monochrome appearance: a fill and an outline keep their meaning in
    /// greys, and "Ошибка" is the one status left in colour.
    static let statusBadgeMonochromaticFilledDefault = Color(light: ShatlPalette.gray3, dark: ShatlPalette.grayDark7)
    static let statusBadgeMonochromaticFilledHover = Color(light: ShatlPalette.gray4, dark: ShatlPalette.grayDark8)
    static let statusBadgeMonochromaticStalledDefault = Color(light: ShatlPalette.clear, dark: ShatlPalette.clear)
    static let statusBadgeMonochromaticStalledHover = Color(light: ShatlPalette.clear, dark: ShatlPalette.clear)
    static let statusBadgeOutlineMonochromaticStalledDefault = Color(light: ShatlPalette.gray6, dark: ShatlPalette.grayDark7)
    static let statusBadgeOutlineMonochromaticStalledHover = Color(light: ShatlPalette.gray7, dark: ShatlPalette.grayDark8)
    static let statusBadgeOutlineMonochromaticStalledDashedDefault = Color(light: ShatlPalette.gray7, dark: ShatlPalette.grayDark8)
    static let statusBadgeOutlineMonochromaticStalledDashedHover = Color(light: ShatlPalette.gray8, dark: ShatlPalette.grayDark9)
    static let statusTextMonochromaticDefault = Color(light: ShatlPalette.gray12, dark: ShatlPalette.grayDark12)
    static let statusTextMonochromaticHover = Color(light: ShatlPalette.gray12, dark: ShatlPalette.grayDark12)
    static let statusTextMonochromaticErrorDefault = Color(light: ShatlPalette.red10, dark: ShatlPalette.redDark9)
    static let statusTextMonochromaticErrorHover = Color(light: ShatlPalette.red11, dark: ShatlPalette.redDark10)

    /// A link button under the pointer wears the colours of the
    /// "Скачивается" badge, as the mockup binds them.
    static let linkButtonHoverBackground = statusBadgeDownloadingDefault
    static let linkButtonHoverLabel = statusTextDownloadingDefault

    static let typographyPrimary = Color(light: ShatlPalette.gray12, dark: ShatlPalette.grayDark12)
    static let typographyPrimaryInverted = Color(light: ShatlPalette.white, dark: ShatlPalette.gray12)
    static let typographySecondary = Color(light: ShatlPalette.gray11, dark: ShatlPalette.grayDark11)
    static let typographyTertiary = Color(light: ShatlPalette.gray9, dark: ShatlPalette.grayDark9)
}

extension ShatlColor {
    /// Colours of small, rare elements, kept apart so they do not crowd the
    /// main tokens; `extra/…` in Figma.
    enum Extra {
        /// The crosses beside what is not sent, in Settings → Data and in
        /// onboarding, while the accent comes from the system.
        static let dataCollectionCross = Color(light: ShatlPalette.gray11, dark: ShatlPalette.grayDark10)

        /// The main window's ground in light, under the list's white cards;
        /// the empty list keeps the system's background. In dark the window
        /// keeps the system's background, tinted by the wallpaper, and this
        /// value only names it.
        static let macosWindowBackground = Color(light: ShatlPalette.gray2, dark: ShatlPalette.windowBackgroundDark)

        /// The empty part of a performance mode's speedometer.
        static let speedometerTrack = Color(light: ShatlPalette.grayA3, dark: ShatlPalette.grayDarkA6)
        /// In the monochrome appearance: its accent at 16 %.
        static let speedometerMonochromeTrack = ShatlColor.accentMonochrome.opacity(0.16)
        /// The two ends of the speedometer's gradient, at its start and end
        /// angle.
        static let speedometerGradientStart = Color(light: ShatlPalette.purple6, dark: ShatlPalette.violetDark10)
        static let speedometerGradientEnd = Color(light: ShatlPalette.violet9, dark: ShatlPalette.violetDark11)

        /// The window buttons on the theme previews in Settings while the
        /// app's own accent is on.
        static let windowButtonClose = Color(light: ShatlPalette.red9, dark: ShatlPalette.redDark9)
        static let windowButtonMinimize = Color(light: ShatlPalette.amber8, dark: ShatlPalette.amberDark9)
        static let windowButtonZoom = Color(light: ShatlPalette.grass9, dark: ShatlPalette.grassDark9)

        /// The same buttons, grey, on a light and on a dark preview while the
        /// accent comes from the system; one colour in both themes of the app.
        static let themePreviewWindowButtonLight = Color(light: ShatlPalette.gray7, dark: ShatlPalette.gray7)
        static let themePreviewWindowButtonDark = Color(light: ShatlPalette.grayDark9, dark: ShatlPalette.grayDark9)

        /// The port status dot in Settings → Downloads → Network. In the
        /// monochrome appearance an open port is the accent's, and a closed
        /// one stays red.
        static let indicatorStatusChecking = Color(light: ShatlPalette.gray10, dark: ShatlPalette.grayDark10)
        static let indicatorStatusSuccess = Color(light: ShatlPalette.grass9, dark: ShatlPalette.grassDark10)
        static let indicatorStatusFailure = Color(light: ShatlPalette.red9, dark: ShatlPalette.redDark10)

        /// The backdrop of an onboarding step's demonstration, top to bottom.
        static let onboardingGradientTop = Color(light: ShatlPalette.gray3, dark: ShatlPalette.grayDark6)
        static let onboardingGradientBottom = Color(light: ShatlPalette.white, dark: ShatlPalette.windowBackgroundDark)
    }
}

enum ShatlCornerRadius {
    static let button: CGFloat = 8
    static let tab: CGFloat = 6
    static let container: CGFloat = 20

    /// A window's corner as macOS rounds it: 16 pt, and 26 pt on macOS 26.
    static var window: CGFloat {
        if #available(macOS 27.0, *) { 16 } else { 26 }
    }

    /// The corner of a shape nested in a rounder one. The gap between the two
    /// stays the same all the way round the corner when the outer radius is
    /// the inner one plus the distance between the shapes.
    static func nested(in outerRadius: CGFloat, inset: CGFloat) -> CGFloat {
        max(outerRadius - inset, 0)
    }
}

enum ShatlGlassTint {
    static var subtleOpacity: Double {
        if #available(macOS 27.0, *) {
            return 0.02
        }

        return 0.00
    }
}

/// The colours of a torrent's status badge, each at rest and under the
/// pointer.
struct ShatlStatusBadgePalette {
    struct Tone {
        let rest: Color
        let hover: Color
    }

    let fill: Tone
    /// Nil for a filled badge.
    let outline: Tone?
    let text: Tone

    static let downloading = Self(
        fill: Tone(rest: ShatlColor.statusBadgeDownloadingDefault, hover: ShatlColor.statusBadgeDownloadingHover),
        outline: nil,
        text: Tone(rest: ShatlColor.statusTextDownloadingDefault, hover: ShatlColor.statusTextDownloadingHover)
    )
    /// A download with no speed, one being added, and a saved one.
    static let downloadingStalled = Self(
        fill: Tone(rest: ShatlColor.statusBadgeDownloadingStalledDefault, hover: ShatlColor.statusBadgeDownloadingStalledHover),
        outline: Tone(rest: ShatlColor.statusBadgeOutlineDownloadingStalledDefault, hover: ShatlColor.statusBadgeOutlineDownloadingStalledHover),
        text: Tone(rest: ShatlColor.statusTextDownloadingStalledDefault, hover: ShatlColor.statusTextDownloadingStalledHover)
    )
    static let saved = Self(
        fill: downloadingStalled.fill,
        outline: Tone(rest: ShatlColor.statusBadgeOutlineDownloadingStalledDashedDefault, hover: ShatlColor.statusBadgeOutlineDownloadingStalledDashedHover),
        text: downloadingStalled.text
    )
    static let paused = Self(
        fill: Tone(rest: ShatlColor.statusBadgePausedDefault, hover: ShatlColor.statusBadgePausedHover),
        outline: Tone(rest: ShatlColor.statusBadgeOutlinePausedDefault, hover: ShatlColor.statusBadgeOutlinePausedHover),
        text: Tone(rest: ShatlColor.statusTextPausedDefault, hover: ShatlColor.statusTextPausedHover)
    )
    static let seeding = Self(
        fill: Tone(rest: ShatlColor.statusBadgeSeedingDefault, hover: ShatlColor.statusBadgeSeedingHover),
        outline: nil,
        text: Tone(rest: ShatlColor.statusTextSeedingDefault, hover: ShatlColor.statusTextSeedingHover)
    )
    static let seedingStalled = Self(
        fill: Tone(rest: ShatlColor.statusBadgeSeedingStalledDefault, hover: ShatlColor.statusBadgeSeedingStalledHover),
        outline: Tone(rest: ShatlColor.statusBadgeOutlineSeedingStalledDefault, hover: ShatlColor.statusBadgeOutlineSeedingStalledHover),
        text: Tone(rest: ShatlColor.statusTextSeedingStalledDefault, hover: ShatlColor.statusTextSeedingStalledHover)
    )
    static let completed = Self(
        fill: Tone(rest: ShatlColor.statusBadgeCompletedDefault, hover: ShatlColor.statusBadgeCompletedHover),
        outline: nil,
        text: Tone(rest: ShatlColor.statusTextCompletedDefault, hover: ShatlColor.statusTextCompletedHover)
    )
    static let error = Self(
        fill: Tone(rest: ShatlColor.statusBadgeErrorDefault, hover: ShatlColor.statusBadgeErrorHover),
        outline: nil,
        text: Tone(rest: ShatlColor.statusTextErrorDefault, hover: ShatlColor.statusTextErrorHover)
    )

    /// The monochrome appearance: a filled grey badge for a download that
    /// works, a grey outline for one that stands, red text for an error.
    static let monochromaticFilled = Self(
        fill: Tone(rest: ShatlColor.statusBadgeMonochromaticFilledDefault, hover: ShatlColor.statusBadgeMonochromaticFilledHover),
        outline: nil,
        text: Tone(rest: ShatlColor.statusTextMonochromaticDefault, hover: ShatlColor.statusTextMonochromaticHover)
    )
    static let monochromaticError = Self(
        fill: monochromaticFilled.fill,
        outline: nil,
        text: Tone(rest: ShatlColor.statusTextMonochromaticErrorDefault, hover: ShatlColor.statusTextMonochromaticErrorHover)
    )
    static let monochromaticStalled = Self(
        fill: Tone(rest: ShatlColor.statusBadgeMonochromaticStalledDefault, hover: ShatlColor.statusBadgeMonochromaticStalledHover),
        outline: Tone(rest: ShatlColor.statusBadgeOutlineMonochromaticStalledDefault, hover: ShatlColor.statusBadgeOutlineMonochromaticStalledHover),
        text: monochromaticFilled.text
    )
    static let monochromaticSaved = Self(
        fill: monochromaticStalled.fill,
        outline: Tone(rest: ShatlColor.statusBadgeOutlineMonochromaticStalledDashedDefault, hover: ShatlColor.statusBadgeOutlineMonochromaticStalledDashedHover),
        text: monochromaticFilled.text
    )
}

struct ShatlSpeedMetricPalette: Equatable {
    let badge: Color
    let icon: Color
    let label: Color

    static func downloadSymbol(_ symbol: String?) -> Self? {
        switch symbol {
        case "tortoise.fill":
            Self(badge: ShatlColor.speedBadgeTortoise, icon: ShatlColor.speedIconTortoise, label: ShatlColor.speedLabelTortoise)
        case "figure.walk":
            Self(badge: ShatlColor.speedBadgeWalk, icon: ShatlColor.speedIconWalk, label: ShatlColor.speedLabelWalk)
        case "figure.run":
            Self(badge: ShatlColor.speedBadgeRun, icon: ShatlColor.speedIconRun, label: ShatlColor.speedLabelRun)
        case "hare.fill":
            Self(badge: ShatlColor.speedBadgeHare, icon: ShatlColor.speedIconHare, label: ShatlColor.speedLabelHare)
        case "bolt.fill":
            Self(badge: ShatlColor.speedBadgeBolt, icon: ShatlColor.speedIconBolt, label: ShatlColor.speedLabelBolt)
        default:
            nil
        }
    }
}

struct ShatlShadowLayer: Sendable {
    let opacity: Double
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    init(
        opacity: Double,
        radius: CGFloat,
        x: CGFloat = 0,
        y: CGFloat = 0
    ) {
        self.opacity = opacity
        self.radius = radius
        self.x = x
        self.y = y
    }
}

struct ShatlShadowAppearance {
    let primary: ShatlShadowLayer
    let secondary: ShatlShadowLayer?

    init(
        primary: ShatlShadowLayer,
        secondary: ShatlShadowLayer? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
    }
}

struct ShatlShadowToken {
    let light: ShatlShadowAppearance?
    let dark: ShatlShadowAppearance?

    func appearance(for colorScheme: ColorScheme) -> ShatlShadowAppearance? {
        switch colorScheme {
        case .dark:
            dark
        default:
            light
        }
    }
}

enum ShatlShadow {

    /// Shadow for the add-torrent error message overlay.
    static let messageBlock = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.16, radius: 5),
            secondary: ShatlShadowLayer(opacity: 0.32, radius: 20, y: 4)
        ),
        dark: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.50, radius: 5),
            secondary: ShatlShadowLayer(opacity: 1.00, radius: 20, y: 4)
        )
    )

    /// Shadow for demonstration cards in onboarding steps.
    static let onboardingCard = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.24, radius: 1),
            secondary: ShatlShadowLayer(opacity: 0.18, radius: 17)
        ),
        dark: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.24, radius: 1),
            secondary: ShatlShadowLayer(opacity: 0.18, radius: 17)
        )
    )

    /// Shadow for the sample torrent card in Appearance settings.
    static let settingsTorrentPreview = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.24, radius: 18, y: 8)
        ),
        dark: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.50, radius: 18, y: 4)
        )
    )

    /// Shadow for system, light, and dark theme previews in Settings.
    static let themePreview = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.06, radius: 6, y: 2),
            secondary: ShatlShadowLayer(opacity: 0.25, radius: 14, y: 4)
        ),
        dark: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.16, radius: 6, y: 2),
            secondary: ShatlShadowLayer(opacity: 0.40, radius: 14, y: 4)
        )
    )

    /// Resting shadow for metrics that do not have a colored speed badge.
    static let metricRest = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.06, radius: 1.5, y: 1)
        ),
        dark: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.06, radius: 1.5, y: 1)
        )
    )

    /// Drop shadow of the add box on the empty main window.
    static let addTorrentEmptyStateBox = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.24, radius: 2),
            secondary: ShatlShadowLayer(opacity: 0.12, radius: 16, y: 4)
        ),
        dark: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.24, radius: 2),
            secondary: ShatlShadowLayer(opacity: 0.12, radius: 16, y: 4)
        )
    )

    /// Shadow for performance gauge needles in Settings.
    static let speedometerArrow = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.45, radius: 2, y: 1),
            secondary: ShatlShadowLayer(opacity: 0.50, radius: 6, y: 1)
        ),
        dark: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.45, radius: 2, y: 1),
            secondary: ShatlShadowLayer(opacity: 0.50, radius: 6, y: 1)
        )
    )
}

extension ShatlColor {
    /// Adaptive key color shared by interface shadows.
    static let shadowKeyColor = Color(light: ShatlPalette.gray10, dark: ShatlPalette.black)
}

private struct ShatlShadowModifier: ViewModifier {
    let token: ShatlShadowToken
    let isEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled, let appearance = token.appearance(for: colorScheme) {
            if let secondary = appearance.secondary {
                content
                    .shadow(
                        color: ShatlColor.shadowKeyColor.opacity(appearance.primary.opacity),
                        radius: appearance.primary.radius,
                        x: appearance.primary.x,
                        y: appearance.primary.y
                    )
                    .shadow(
                        color: ShatlColor.shadowKeyColor.opacity(secondary.opacity),
                        radius: secondary.radius,
                        x: secondary.x,
                        y: secondary.y
                    )
            } else {
                content
                    .shadow(
                        color: ShatlColor.shadowKeyColor.opacity(appearance.primary.opacity),
                        radius: appearance.primary.radius,
                        x: appearance.primary.x,
                        y: appearance.primary.y
                    )
            }
        } else {
            content
        }
    }
}

extension View {
    func shatlShadow(
        _ token: ShatlShadowToken,
        isEnabled: Bool = true
    ) -> some View {
        modifier(ShatlShadowModifier(token: token, isEnabled: isEnabled))
    }
}
