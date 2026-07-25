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

    static let onboardingForeground = Color("onboardingForeground")
    static let onboardingBackground = Color("onboardingBackground")
    static let onboardingOutline = Color("onboardingOutline")
    static let onboardingButtonText = Color("onboardingButtonText")
    static let onboardingButtonBody = Color("onboardingButtonBody")

    static func onboardingPresentationGradient(colorScheme: ColorScheme) -> LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [
                Color(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 39.0 / 255.0),
                Color(red: 55.0 / 255.0, green: 65.0 / 255.0, blue: 81.0 / 255.0),
            ]
            : [
                Color(red: 229.0 / 255.0, green: 231.0 / 255.0, blue: 235.0 / 255.0),
                Color.white,
            ]

        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    /// Shared gauge color scale for performance modes.
    static let performanceSpeedometerGradient = AngularGradient(
        gradient: Gradient(stops: [
            Gradient.Stop(
                color: Color(red: 56.0 / 255.0, green: 189.0 / 255.0, blue: 248.0 / 255.0),
                location: 0.08
            ),
            Gradient.Stop(
                color: Color(red: 251.0 / 255.0, green: 191.0 / 255.0, blue: 36.0 / 255.0),
                location: 0.50
            ),
            Gradient.Stop(
                color: Color(red: 248.0 / 255.0, green: 113.0 / 255.0, blue: 113.0 / 255.0),
                location: 0.92
            ),
        ]),
        center: .center,
        startAngle: .degrees(135),
        endAngle: .degrees(405)
    )
}

enum ShatlCornerRadius {
    static let button: CGFloat = 8
    static let tab: CGFloat = 6
    static let tabsContainer: CGFloat = 8
    static let container: CGFloat = 20
    static let expandButton: CGFloat = 5.5
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

    /// Animated metric-set shadow used while its icon changes.
    static let metricBounce = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.12, radius: 5.5)
        ),
        dark: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.32, radius: 5.5)
        )
    )

    /// Inner shadow of the main torrent card in the light theme.
    static let torrentCardInner = ShatlShadowToken(
        light: ShatlShadowAppearance(
            primary: ShatlShadowLayer(opacity: 0.08, radius: 0.5),
            secondary: ShatlShadowLayer(opacity: 0.08, radius: 3)
        ),
        dark: nil
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
