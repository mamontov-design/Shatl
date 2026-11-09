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
/// `ShatlPalette`, and Figma has the same token in its UI collection:
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
    /// The add window's own background, under its settings, and the cover
    /// its files are shown from under: what the system draws as a window's
    /// background, white in light and #1E1E1E in dark, without the
    /// wallpaper's tint. The tint is no one colour, so nothing painted over
    /// the system's background could match it.
    static let backgroundWindow = Color(light: ShatlPalette.white, dark: ShatlPalette.windowBackgroundDark)
    /// The add window's half with the files and the summary, a step darker
    /// than the window, so the summary's white card stands out on it.
    static let backgroundAddWindow = Color(light: ShatlPalette.gray1, dark: ShatlPalette.grayDark2)

    static let buttonNeutral = Color(light: ShatlPalette.grayA3, dark: ShatlPalette.grayDarkA8)

    /// A card keeps one fill whatever happens to it; its outline answers the
    /// pointer and the selection.
    static let cardBackgroundDefault = Color(light: ShatlPalette.white, dark: ShatlPalette.grayDarkA3)
    /// A card that things pass under: the add window's summary, with the
    /// files scrolling beneath it. The dark step is what the nearly clear
    /// card looks like on the files' ground, so it looks the same and
    /// nothing shows through.
    static let cardBackgroundSolid = Color(light: ShatlPalette.white, dark: ShatlPalette.grayDark4)

    static let cardOutlineDefault = Color(light: ShatlPalette.gray6, dark: ShatlPalette.grayDarkA6)
    static let cardOutlineHover = Color(light: ShatlPalette.gray9, dark: ShatlPalette.grayDarkA9)
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
    /// See-through, as the popover's glass is: a plate's edge and the lines
    /// on a popover.
    static let outlineOnPopover = Color(light: ShatlPalette.grayA8, dark: ShatlPalette.grayDarkA8)

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
    static let statusBadgeCompletedDefault = Color(light: ShatlPalette.clear, dark: ShatlPalette.clear)
    static let statusBadgeCompletedHover = Color(light: ShatlPalette.clear, dark: ShatlPalette.clear)
    static let statusBadgeErrorDefault = Color(light: ShatlPalette.clear, dark: ShatlPalette.clear)
    static let statusBadgeErrorHover = Color(light: ShatlPalette.clear, dark: ShatlPalette.clear)

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
    static let statusBadgeOutlineCompletedDefault = Color(light: ShatlPalette.gold6, dark: ShatlPalette.goldDark7)
    static let statusBadgeOutlineCompletedHover = Color(light: ShatlPalette.gold7, dark: ShatlPalette.goldDark8)
    /// A step brighter than the other outlines, so an error reads stronger;
    /// red in the monochrome appearance too.
    static let statusBadgeOutlineErrorDefault = Color(light: ShatlPalette.red9, dark: ShatlPalette.redDark9)
    static let statusBadgeOutlineErrorHover = Color(light: ShatlPalette.red10, dark: ShatlPalette.redDark10)

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
    static let statusTextCompletedDefault = Color(light: ShatlPalette.gold9, dark: ShatlPalette.goldDark12)
    static let statusTextCompletedHover = Color(light: ShatlPalette.gold10, dark: ShatlPalette.goldDark12)
    static let statusTextErrorDefault = Color(light: ShatlPalette.red10, dark: ShatlPalette.redDark11)
    static let statusTextErrorHover = Color(light: ShatlPalette.red11, dark: ShatlPalette.redDark11)

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
    static let statusTextMonochromaticErrorDefault = Color(light: ShatlPalette.red10, dark: ShatlPalette.redDark11)
    static let statusTextMonochromaticErrorHover = Color(light: ShatlPalette.red11, dark: ShatlPalette.redDark11)

    /// A link button under the pointer wears the colours of the
    /// "Скачивается" badge, as the mockup binds them.
    static let linkButtonHoverBackground = statusBadgeDownloadingDefault
    static let linkButtonHoverLabel = statusTextDownloadingDefault
    /// A link button on a popover's glass is filled at rest too, its label
    /// inverted. The monochrome pair holds the same steps for now, so that
    /// either can be repainted alone.
    static let linkButtonOnPopoverDefault = Color(light: ShatlPalette.grayA11, dark: ShatlPalette.grayDarkA11)
    static let linkButtonOnPopoverHover = Color(light: ShatlPalette.grayA12, dark: ShatlPalette.grayDarkA12)
    static let linkButtonOnPopoverMonochromeDefault = Color(light: ShatlPalette.grayA11, dark: ShatlPalette.grayDarkA11)
    static let linkButtonOnPopoverMonochromeHover = Color(light: ShatlPalette.grayA12, dark: ShatlPalette.grayDarkA12)

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
        /// amber/8 in both themes, as Figma has it: the dark scale's step 8 is
        /// a brown, and the yellow should read the same on either preview.
        static let windowButtonMinimize = Color(light: ShatlPalette.amber8, dark: ShatlPalette.amber8)
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

extension ShatlColor {
    /// The type wordmark in the app's own accent. Its hue is one of four
    /// neighbours on the colour wheel, kept in their order so that a change
    /// of hue passes through the ones between; its step follows only the
    /// weight of its letters, thin letters solid and bold ones pale. The
    /// standard set stands on the pastel step, behind the title under it.
    enum Wordmark {
        static let iris = ShatlWordmarkHue(
            thin: Color(light: ShatlPalette.iris9, dark: ShatlPalette.irisDark10),
            standard: Color(light: ShatlPalette.iris8, dark: ShatlPalette.irisDark8),
            bold: Color(light: ShatlPalette.iris6, dark: ShatlPalette.irisDark7)
        )
        static let violet = ShatlWordmarkHue(
            thin: Color(light: ShatlPalette.violet9, dark: ShatlPalette.violetDark10),
            standard: Color(light: ShatlPalette.violet8, dark: ShatlPalette.violetDark8),
            bold: Color(light: ShatlPalette.violet6, dark: ShatlPalette.violetDark7)
        )
        static let purple = ShatlWordmarkHue(
            thin: Color(light: ShatlPalette.purple9, dark: ShatlPalette.purpleDark10),
            standard: Color(light: ShatlPalette.purple8, dark: ShatlPalette.purpleDark8),
            bold: Color(light: ShatlPalette.purple6, dark: ShatlPalette.purpleDark7)
        )
        static let plum = ShatlWordmarkHue(
            thin: Color(light: ShatlPalette.plum9, dark: ShatlPalette.plumDark10),
            standard: Color(light: ShatlPalette.plum8, dark: ShatlPalette.plumDark8),
            bold: Color(light: ShatlPalette.plum6, dark: ShatlPalette.plumDark7)
        )

        /// In the order of the colour wheel, from blue to pink.
        static let hues = [iris, violet, purple, plum]

        /// The monochrome appearance: grey at the steps of the hues.
        static let gray = ShatlWordmarkHue(
            thin: Color(light: ShatlPalette.gray9, dark: ShatlPalette.grayDark10),
            standard: Color(light: ShatlPalette.gray8, dark: ShatlPalette.grayDark8),
            bold: Color(light: ShatlPalette.gray6, dark: ShatlPalette.grayDark7)
        )

        /// The accent chosen in macOS is one colour, so the weight takes it
        /// through the steps of the hues itself, adding as much white in
        /// light and black in dark as the Radix scales add between them. The
        /// hues and grey all add the same: 40 and 70 % white from step 9 to
        /// 8 and 6, 12 and 25 % black from step 10 to 8 and 7. In light the
        /// letters get no lighter than step 6, where a light accent, yellow,
        /// would fade into the window.
        static func systemAccent(_ accent: Color, weight: Double, colorScheme: ColorScheme) -> Color {
            let place = ShatlWordmarkHue.place(of: weight)
            if colorScheme == .dark {
                let share = systemAccentShare(at: place, standard: 0.12, bold: 0.25)
                return ShatlWordmarkHue.mix(accent, ShatlPalette.black, by: share)
            }
            let share = min(
                systemAccentShare(at: place, standard: 0.40, bold: 0.70),
                whiteShareUpToLightestStep(of: accent)
            )
            return ShatlWordmarkHue.mix(accent, ShatlPalette.white, by: share)
        }

        /// The lightest the letters get in light: step 6 of the app's hue.
        static let lightestStep = ShatlPalette.violet6

        private static func systemAccentShare(at place: Double, standard: Double, bold: Double) -> Double {
            place <= 1 ? standard * place : standard + (bold - standard) * (place - 1)
        }

        /// White mixed as the eye sees it raises the lightness in proportion
        /// to the share, so the share that reaches `lightestStep` is known.
        private static func whiteShareUpToLightestStep(of accent: Color) -> Double {
            var environment = EnvironmentValues()
            environment.colorScheme = .light
            let accentLightness = ShatlOklab.lightness(of: accent.resolve(in: environment))
            let limit = ShatlOklab.lightness(of: lightestStep.resolve(in: environment))
            guard accentLightness < 1 else { return 0 }
            return max(0, (limit - accentLightness) / (1 - accentLightness))
        }

        /// The colour of letters of `weight` at `hue`, a place on `hues`
        /// that may lie between two of them. Between two steps or two hues
        /// the colours are mixed as the eye sees them, so the middle does not
        /// turn grey.
        static func color(hue: Double, weight: Double) -> Color {
            let place = min(max(hue, 0), Double(hues.count - 1))
            let lower = Int(place.rounded(.down))
            let upper = min(lower + 1, hues.count - 1)
            let lowerColor = hues[lower].color(weight: weight)
            let share = place - Double(lower)
            guard share > 0, upper != lower else { return lowerColor }
            return lowerColor.mix(with: hues[upper].color(weight: weight), by: share, in: .perceptual)
        }
    }
}

extension ShatlColor {
    /// A Settings option card's plate winks lighter after a click. In the
    /// app's own accent it takes one of the wordmark's hues, step 2 in light
    /// and A3 in dark: the dark plate is see-through white, and a solid
    /// step 2 would darken it. With the macOS accent and in the monochrome
    /// appearance it stays grey.
    enum InputCardActivationPulse {
        static let gray = ShatlColor.backgroundPrimary
        static let hues = [
            Color(light: ShatlPalette.iris2, dark: ShatlPalette.irisDarkA3),
            Color(light: ShatlPalette.violet2, dark: ShatlPalette.violetDarkA3),
            Color(light: ShatlPalette.purple2, dark: ShatlPalette.purpleDarkA3),
            Color(light: ShatlPalette.plum2, dark: ShatlPalette.plumDarkA3),
        ]
    }
}

/// Lightness as the eye sees it, in Oklab, the space `.perceptual` mixes
/// in: 0 is black, 1 white.
nonisolated enum ShatlOklab {
    static func lightness(of color: Color.Resolved) -> Double {
        let red = Double(color.linearRed)
        let green = Double(color.linearGreen)
        let blue = Double(color.linearBlue)
        let long = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
        let medium = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
        let short = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
        return 0.2104542553 * long + 0.7936177850 * medium - 0.0040720468 * short
    }
}

/// One hue of the type wordmark at the three weights it is pinned to.
struct ShatlWordmarkHue {
    /// Weight 100: step 9 in light, 10 in dark, as `accentColored`.
    let thin: Color
    /// Weight 540, the standard set: step 8 in both themes.
    let standard: Color
    /// Weight 1000: step 6 in light, 7 in dark, where step 6 turns murky.
    let bold: Color

    func color(weight: Double) -> Color {
        let place = Self.place(of: weight)
        return place <= 1
            ? Self.mix(thin, standard, by: place)
            : Self.mix(standard, bold, by: place - 1)
    }

    /// Where `weight` stands between the three weights: 0 at the thinnest,
    /// 1 at the standard one, 2 at the boldest.
    static func place(of weight: Double) -> Double {
        let weights = ShatlTypeWordmark.weights
        let standardWeight = ShatlTypeWordmark.standard.weight
        if weight <= standardWeight {
            let share = (weight - weights.lowerBound) / (standardWeight - weights.lowerBound)
            return min(max(share, 0), 1)
        }
        let share = (weight - standardWeight) / (weights.upperBound - standardWeight)
        return 1 + min(max(share, 0), 1)
    }

    static func mix(_ from: Color, _ to: Color, by share: Double) -> Color {
        let share = min(max(share, 0), 1)
        if share == 0 { return from }
        if share == 1 { return to }
        return from.mix(with: to, by: share, in: .perceptual)
    }
}

enum ShatlCornerRadius {
    static let button: CGFloat = 8
    static let tab: CGFloat = 6
    static let container: CGFloat = 20
    /// The corner of a container where its selection mark stands: rounded
    /// as a download card is, so the mark stands 10 pt in, as there.
    static let containerSelectionCorner: CGFloat = 18

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
        outline: Tone(rest: ShatlColor.statusBadgeOutlineCompletedDefault, hover: ShatlColor.statusBadgeOutlineCompletedHover),
        text: Tone(rest: ShatlColor.statusTextCompletedDefault, hover: ShatlColor.statusTextCompletedHover)
    )
    static let error = Self(
        fill: Tone(rest: ShatlColor.statusBadgeErrorDefault, hover: ShatlColor.statusBadgeErrorHover),
        outline: Tone(rest: ShatlColor.statusBadgeOutlineErrorDefault, hover: ShatlColor.statusBadgeOutlineErrorHover),
        text: Tone(rest: ShatlColor.statusTextErrorDefault, hover: ShatlColor.statusTextErrorHover)
    )

    /// The monochrome appearance: a filled grey badge for a download that
    /// works, a grey outline for one that stands or has finished, a red
    /// outline and red text for an error.
    static let monochromaticFilled = Self(
        fill: Tone(rest: ShatlColor.statusBadgeMonochromaticFilledDefault, hover: ShatlColor.statusBadgeMonochromaticFilledHover),
        outline: nil,
        text: Tone(rest: ShatlColor.statusTextMonochromaticDefault, hover: ShatlColor.statusTextMonochromaticHover)
    )
    static let monochromaticError = Self(
        fill: Tone(rest: ShatlColor.statusBadgeMonochromaticStalledDefault, hover: ShatlColor.statusBadgeMonochromaticStalledHover),
        outline: error.outline,
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

    /// Under the add window's summary card: `shadowSummary` in Figma. In
    /// light 14 % since the owner's check in November 2026 (10 % before).
    static let summary = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.14, radius: 4)
        ),
        dark: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.24, radius: 4)
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

/// A shadow cast by a shape and seen only outside it, as Figma draws a
/// frame's shadow. Laid on a view itself, a shadow comes from whatever is
/// opaque inside it: in dark a card's fill is nearly clear, and the plates
/// on it would cast shadows of their own (the owner's check on macOS 26).
private struct ShatlOutsideShadowModifier<ShadowShape: Shape>: ViewModifier {
    let token: ShatlShadowToken
    let shape: ShadowShape

    func body(content: Content) -> some View {
        content.background {
            // The fill only casts the shadow; the mask takes the shape's own
            // area away, so nothing of it shows through a clear fill.
            shape
                .fill(ShatlColor.shadowKeyColor)
                .shatlShadow(token)
                .mask {
                    ZStack {
                        Rectangle().padding(-Self.shadowReach)
                        shape.blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
        }
    }

    /// Room around the shape for the widest shadow layer to fade out.
    private static var shadowReach: CGFloat { 48 }
}

extension View {
    func shatlShadow(
        _ token: ShatlShadowToken,
        isEnabled: Bool = true
    ) -> some View {
        modifier(ShatlShadowModifier(token: token, isEnabled: isEnabled))
    }

    /// `token` cast by `shape` behind the view, seen only outside the shape.
    func shatlOutsideShadow<ShadowShape: Shape>(
        _ token: ShatlShadowToken,
        in shape: ShadowShape
    ) -> some View {
        modifier(ShatlOutsideShadowModifier(token: token, shape: shape))
    }
}
