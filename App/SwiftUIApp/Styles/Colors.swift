// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

enum ShatlColor {
    static let accent = Color.accentColor

    static let backgroundSecondary = Color("backgroundSecondary")
    static let backgroundTertiary = Color("backgroundTertiary")
    static let backgroundPrimary = Color("backgroundPrimary")
    static let backgroundFiles = Color("backgroundFiles")

    static let buttonNeutral = Color("buttonNeutral")

    static let cardDefault = Color("cardDefault")
    static let cardHover = Color("cardHover")
    static let cardSelectedError = Color("cardSelectedError")

    /// `backgroundTertiary` in light; 20% black in dark, so the empty part of
    /// the bar does not read as a hole in the card.
    static let progressBarTrack = Color("progressBarTrack")

    static let speedBadgeTortoise = Color("speedBadgeTortoise")
    static let speedIconTortoise = Color("speedIconTortoise")
    static let speedLabelTortoise = Color("speedLabelTortoise")
    static let speedBadgeWalk = Color("speedBadgeWalk")
    static let speedIconWalk = Color("speedIconWalk")
    static let speedLabelWalk = Color("speedLabelWalk")
    static let speedBadgeRun = Color("speedBadgeRun")
    static let speedIconRun = Color("speedIconRun")
    static let speedLabelRun = Color("speedLabelRun")
    static let speedBadgeHare = Color("speedBadgeHare")
    static let speedIconHare = Color("speedIconHare")
    static let speedLabelHare = Color("speedLabelHare")
    static let speedBadgeBolt = Color("speedBadgeBolt")
    static let speedIconBolt = Color("speedIconBolt")
    static let speedLabelBolt = Color("speedLabelBolt")

    /// The port status dot in Settings → Downloads → Network, the same in
    /// both themes: #71717A while the router is asked, #22C55E open, #EF4444 closed.
    static let portStatusChecking = Color(red: 113.0 / 255.0, green: 113.0 / 255.0, blue: 122.0 / 255.0)
    static let portStatusOpen = Color(red: 34.0 / 255.0, green: 197.0 / 255.0, blue: 94.0 / 255.0)
    static let portStatusClosed = Color(red: 239.0 / 255.0, green: 68.0 / 255.0, blue: 68.0 / 255.0)

    static let metricBackground = Color("metricBackground")
    static let metricDivider = Color("metricDivider")
    static let metricOutline = Color("metricOutline")
    static let metricPulseHighlight = Color(
        red: 249.0 / 255.0,
        green: 115.0 / 255.0,
        blue: 22.0 / 255.0
    )

    static let outlinePrimary = Color("outlinePrimary")
    static let outlineSecondary = Color("outlineSecondary")
    static let outlineTertiary = Color("outlineTertiary")

    static let cerisePink = Color("cerisePink")
    static let mangoTango = Color("mangoTango")
    static let pictonBlue = Color("pictonBlue")
    static let slate = Color("slate")
    static let neonBlue = Color("neonBlue")

    static let statusBadgeCompletedDefault = Color("statusBadgeCompletedDefault")
    static let statusBadgeCompletedHover = Color("statusBadgeCompletedHover")
    static let statusBadgeDownloadingDefault = Color("statusBadgeDownloadingDefault")
    static let statusBadgeDownloadingHover = Color("statusBadgeDownloadingHover")
    static let statusBadgeErrorDefault = Color("statusBadgeErrorDefault")
    static let statusBadgeErrorHover = Color("statusBadgeErrorHover")
    static let statusBadgePausedDefault = Color("statusBadgePausedDefault")
    static let statusBadgePausedHover = Color("statusBadgePausedHover")
    static let statusBadgeSeedingDefault = Color("statusBadgeSeedingDefault")
    static let statusBadgeSeedingHover = Color("statusBadgeSeedingHover")

    static let statusTextCompletedDefault = Color("statusTextCompletedDefault")
    static let statusTextCompletedHover = Color("statusTextCompletedHover")
    static let statusTextDownloadingDefault = Color("statusTextDownloadingDefault")
    static let statusTextDownloadingHover = Color("statusTextDownloadingHover")
    static let statusTextErrorDefault = Color("statusTextErrorDefault")
    static let statusTextErrorHover = Color("statusTextErrorHover")
    static let statusTextPausedDefault = Color("statusTextPausedDefault")
    static let statusTextPausedHover = Color("statusTextPausedHover")
    static let statusTextSeedingDefault = Color("statusTextSeedingDefault")
    static let statusTextSeedingHover = Color("statusTextSeedingHover")

    static let typographyPrimary = Color("typographyPrimary")
    static let typographyPrimaryInverted = Color("typographyPrimaryInverted")
    static let typographySecondary = Color("typographySecondary")
    static let typographyTertiary = Color("typographyTertiary")

    static let lineMessageBackground = Color("lineMessageBackground")
    static let lineMessageButtonBackground = Color("lineMessageButtonBackground")
    static let lineMessageButtonLabel = Color("lineMessageButtonLabel")
    static let lineMessageCaption = Color("lineMessageCaption")
    static let lineMessageHeadline = Color("lineMessageHeadline")

    static let onboardingForeground = Color("onboardingForeground")
    static let onboardingBackground = Color("onboardingBackground")
    static let onboardingOutline = Color("onboardingOutline")
    static let onboardingButtonText = Color("onboardingButtonText")
    static let onboardingButtonBody = Color("onboardingButtonBody")

    static func onboardingPresentationGradient(colorScheme: ColorScheme) -> LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [
                Color(red: 63.0 / 255.0, green: 63.0 / 255.0, blue: 70.0 / 255.0),
                Color.black.opacity(0),
            ]
            : [
                Color(red: 244.0 / 255.0, green: 244.0 / 255.0, blue: 245.0 / 255.0),
                Color.white,
            ]

        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

}

enum ShatlCornerRadius {
    static let button: CGFloat = 8
    static let tab: CGFloat = 6
    static let tabsContainer: CGFloat = 8
    static let container: CGFloat = 20
    static let expandButton: CGFloat = 5.5
}

enum ShatlGlassTint {
    static var subtleOpacity: Double {
        if #available(macOS 27.0, *) {
            return 0.02
        }

        return 0.00
    }
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
    /// Shadow for the active tab in the add-torrent review window.
    static let activeTab = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.45, radius: 1),
            secondary: ShatlShadowLayer(opacity: 0.24, radius: 4, y: 2)
        ),
        dark: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.45, radius: 1),
            secondary: ShatlShadowLayer(opacity: 0.24, radius: 4, y: 2)
        )
    )

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

    /// Animated metric-set shadow used while its icon changes.
    static let metricBounce = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.12, radius: 5.5)
        ),
        dark: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.32, radius: 5.5)
        )
    )

    /// Shadow for the pinned folder row in the add-torrent file tree.
    static let addTorrentStickyRow = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.04, radius: 2, y: 2)
        ),
        dark: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.50, radius: 2, y: 2)
        )
    )

    /// Inner shadow of the logomark background shape in the light theme.
    static let logomarkInner = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.08, radius: 0.5),
            secondary: ShatlShadowLayer(opacity: 0.08, radius: 3)
        ),
        dark: nil
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
    static let shadowKeyColor = Color("shadowKeyColor")
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
