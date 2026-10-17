// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

extension Color {
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
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private extension NSColor {
    convenience init(rgba: UInt32) {
        self.init(
            srgbRed: CGFloat(rgba >> 24 & 0xFF) / 255,
            green: CGFloat(rgba >> 16 & 0xFF) / 255,
            blue: CGFloat(rgba >> 8 & 0xFF) / 255,
            alpha: CGFloat(rgba & 0xFF) / 255
        )
    }
}

enum ShatlColor {
    static let accent = Color.accentColor

    static let backgroundSecondary = Color(light: Color(rgb: 0xF4F4F5), dark: Color(rgba: 0xFFFFFF0F))
    static let backgroundTertiary = Color(light: Color(rgb: 0xFFFFFF), dark: Color(rgb: 0x000000))
    static let backgroundPrimary = Color(light: Color(rgb: 0xF1F1F3), dark: Color(rgba: 0xFFFFFF1A))
    /// The add window's own background, and the cover its files are shown
    /// from under: what the system draws as a window's background, white in
    /// light and #1E1E1E in dark, without the wallpaper's tint. The tint is
    /// no one colour, so nothing painted over the system's background could
    /// match it.
    static let backgroundAddWindow = Color(light: Color(rgb: 0xFFFFFF), dark: Color(rgb: 0x1E1E1E))

    static let buttonNeutral = Color(light: Color(rgba: 0x09090B0F), dark: Color(rgba: 0xFFFFFF4C))

    static let cardDefault = Color(light: Color(rgb: 0xFAFAFA), dark: Color(rgba: 0xFFFFFF14))
    static let cardHover = Color(light: Color(rgb: 0xF5F5F5), dark: Color(rgba: 0xFFFFFF1F))
    /// The fill of a message that needs attention now, under white text:
    /// no room for a download in the add window.
    static let errorSolidBackground = Color(light: Color(rgb: 0xEF4444), dark: Color(rgb: 0xEF4444))

    /// `backgroundTertiary` in light; 20% black in dark, so the empty part of
    /// the bar does not read as a hole in the card.
    static let progressBarTrack = Color(light: Color(rgb: 0xFFFFFF), dark: Color(rgba: 0x00000033))

    static let speedBadgeTortoise = Color(light: Color(rgb: 0xE2E8F0), dark: Color(rgba: 0x64748B4C))
    static let speedIconTortoise = Color(light: Color(rgb: 0x64748B), dark: Color(rgb: 0xCBD5E1))
    static let speedLabelTortoise = Color(light: Color(rgb: 0x1E293B), dark: Color(rgb: 0xF1F5F9))
    static let speedBadgeWalk = Color(light: Color(rgb: 0x99F6E4), dark: Color(rgba: 0x14B8A64C))
    static let speedIconWalk = Color(light: Color(rgb: 0x0D9488), dark: Color(rgb: 0x2DD4BF))
    static let speedLabelWalk = Color(light: Color(rgb: 0x134E4A), dark: Color(rgb: 0xCCFBF1))
    static let speedBadgeRun = Color(light: Color(rgb: 0xD9F99D), dark: Color(rgba: 0x84CC164C))
    static let speedIconRun = Color(light: Color(rgb: 0x65A30D), dark: Color(rgb: 0xA3E635))
    static let speedLabelRun = Color(light: Color(rgb: 0x365314), dark: Color(rgb: 0xECFCCB))
    static let speedBadgeHare = Color(light: Color(rgb: 0xFED7AA), dark: Color(rgba: 0xF973164C))
    static let speedIconHare = Color(light: Color(rgb: 0xEA580C), dark: Color(rgb: 0xFB923C))
    static let speedLabelHare = Color(light: Color(rgb: 0x7C2D12), dark: Color(rgb: 0xFFEDD5))
    static let speedBadgeBolt = Color(light: Color(rgb: 0xFECDD3), dark: Color(rgba: 0xF43F5E4C))
    static let speedIconBolt = Color(light: Color(rgb: 0xE11D48), dark: Color(rgb: 0xFB7185))
    static let speedLabelBolt = Color(light: Color(rgb: 0x881337), dark: Color(rgb: 0xFFE4E6))

    static let metricBackground = Color(light: Color(rgb: 0xFFFFFF), dark: Color(rgba: 0x49494900))
    static let metricDivider = Color(light: Color(rgb: 0xF4F4F5), dark: Color(rgba: 0xFFFFFF14))
    static let metricOutline = Color(light: Color(rgb: 0xD4D4D8), dark: Color(rgba: 0xFFFFFF29))
    static let metricPulseHighlight = Color(
        red: 249.0 / 255.0,
        green: 115.0 / 255.0,
        blue: 22.0 / 255.0
    )

    static let outlinePrimary = Color(light: Color(rgb: 0xD4D4D8), dark: Color(rgba: 0xFFFFFF66))
    static let outlineSecondary = Color(light: Color(rgba: 0x71717A14), dark: Color(rgba: 0xFFFFFF14))
    static let outlineTertiary = Color(light: Color(rgb: 0xEDEDEF), dark: Color(rgba: 0xFFFFFF14))

    static let cerisePink = Color(light: Color(rgb: 0xF43E75), dark: Color(rgb: 0xF55586))
    static let slate = Color(light: Color(rgb: 0x64748B), dark: Color(rgb: 0x778599))
    static let neonBlue = Color(light: Color(rgb: 0x7548F3), dark: Color(rgb: 0x6C6FFD))

    static let statusBadgeCompletedDefault = Color(light: Color(rgb: 0xE8E4E3), dark: Color(rgb: 0x5B4C49))
    static let statusBadgeCompletedHover = Color(light: Color(rgb: 0xD8D2D0), dark: Color(rgb: 0x8B7A74))
    static let statusBadgeDownloadingDefault = Color(light: Color(rgb: 0xDDD6FE), dark: Color(rgb: 0x6D2AD5))
    static let statusBadgeDownloadingHover = Color(light: Color(rgb: 0xC4B5FD), dark: Color(rgb: 0x7B3CDD))
    static let statusBadgeErrorDefault = Color(light: Color(rgb: 0xFECDD3), dark: Color(rgb: 0x9D163F))
    static let statusBadgeErrorHover = Color(light: Color(rgb: 0xFDA4AF), dark: Color(rgb: 0xB71542))
    static let statusBadgePausedDefault = Color(light: Color(rgb: 0xFDE68A), dark: Color(rgb: 0x8D3E12))
    static let statusBadgePausedHover = Color(light: Color(rgb: 0xFCD34D), dark: Color(rgb: 0xCC5E0A))
    static let statusBadgeSeedingDefault = Color(light: Color(rgb: 0xBAE6FD), dark: Color(rgb: 0x0F5A85))
    static let statusBadgeSeedingHover = Color(light: Color(rgb: 0x7DD3FC), dark: Color(rgb: 0x0379B9))

    static let statusTextCompletedDefault = Color(light: Color(rgb: 0x5B4F4B), dark: Color(rgb: 0xF3F1F1))
    static let statusTextCompletedHover = Color(light: Color(rgb: 0x473C39), dark: Color(rgb: 0xFBFAF9))
    static let statusTextDownloadingDefault = Color(light: Color(rgb: 0x3730A3), dark: Color(rgb: 0xE0E7FF))
    static let statusTextDownloadingHover = Color(light: Color(rgb: 0x312E81), dark: Color(rgb: 0xEEF2FF))
    static let statusTextErrorDefault = Color(light: Color(rgb: 0x9F1239), dark: Color(rgb: 0xFFE4E6))
    static let statusTextErrorHover = Color(light: Color(rgb: 0x881337), dark: Color(rgb: 0xFFF1F2))
    static let statusTextPausedDefault = Color(light: Color(rgb: 0x92400E), dark: Color(rgb: 0xFEF3C7))
    static let statusTextPausedHover = Color(light: Color(rgb: 0x78350F), dark: Color(rgb: 0xFFFBEB))
    static let statusTextSeedingDefault = Color(light: Color(rgb: 0x075985), dark: Color(rgb: 0xE0F2FE))
    static let statusTextSeedingHover = Color(light: Color(rgb: 0x0C4A6E), dark: Color(rgb: 0xF0F9FF))

    /// A link button under the pointer wears the colours of the
    /// "Скачивается" badge, as the mockup binds them.
    static let linkButtonHoverBackground = statusBadgeDownloadingDefault
    static let linkButtonHoverLabel = statusTextDownloadingDefault

    static let typographyPrimary = Color(light: Color(rgb: 0x09090B), dark: Color(rgba: 0xFFFFFFF2))
    static let typographyPrimaryInverted = Color(light: Color(rgb: 0xFFFFFF), dark: Color(rgb: 0x030712))
    static let typographySecondary = Color(light: Color(rgb: 0x71717A), dark: Color(rgba: 0xFFFFFFA6))
    static let typographyTertiary = Color(light: Color(rgb: 0xA1A1AA), dark: Color(rgba: 0xFFFFFF59))

    static let lineMessageBackground = Color(light: Color(rgb: 0x27272A), dark: Color(rgb: 0xE4E4E7))
    static let lineMessageButtonBackground = Color(light: Color(rgb: 0x52525B), dark: Color(rgb: 0xBCBCC2))
    static let lineMessageButtonLabel = Color(light: Color(rgb: 0xFFFFFF), dark: Color(rgb: 0x09090B))
    static let lineMessageCaption = Color(light: Color(rgb: 0xA1A1AA), dark: Color(rgb: 0x52525B))
    static let lineMessageHeadline = Color(light: Color(rgb: 0xFAFAFA), dark: Color(rgb: 0x09090B))

    static let onboardingForeground = Color(light: Color(rgb: 0xFFFFFF), dark: Color(rgb: 0x374151))
    static let onboardingBackground = Color(light: Color(rgb: 0xF3F4F6), dark: Color(rgb: 0x111827))
    static let onboardingButtonText = Color(light: Color(rgb: 0xFFFFFF), dark: Color(rgb: 0x030712))
    static let onboardingButtonBody = Color(light: Color(rgb: 0x030712), dark: Color(rgb: 0xF5F5F5))

}

extension ShatlColor {
    /// Colours of small, rare elements, kept apart so they do not crowd the
    /// main tokens; `extra/…` in Figma.
    enum Extra {
        /// The port status dot in Settings → Downloads → Network.
        static let portStatusChecking = Color(light: Color(rgb: 0x71717A), dark: Color(rgb: 0x71717A))
        static let portStatusOpen = Color(light: Color(rgb: 0x22C55E), dark: Color(rgb: 0x22C55E))
        static let portStatusClosed = Color(light: Color(rgb: 0xEF4444), dark: Color(rgb: 0xEF4444))

        /// The empty part of a performance mode's speedometer.
        static let speedometerTrack = Color(light: Color(rgba: 0x3F3F4614), dark: Color(rgba: 0xFFFFFF29))
        /// The two ends of the speedometer's gradient, at its start and end
        /// angle.
        static let speedometerGradientStart = Color(light: Color(rgb: 0xBE9AFF), dark: Color(rgb: 0x885FFF))
        static let speedometerGradientEnd = Color(light: Color(rgb: 0x885FFF), dark: Color(rgb: 0xBE9AFF))

        /// The window buttons on the theme previews in Settings while the
        /// app's own accent is on.
        static let windowButtonClose = Color(light: Color(rgb: 0xF43F5E), dark: Color(rgb: 0xF43F5E))
        static let windowButtonMinimize = Color(light: Color(rgb: 0xEAB308), dark: Color(rgb: 0xEAB308))
        static let windowButtonZoom = Color(light: Color(rgb: 0x22C55E), dark: Color(rgb: 0x22C55E))
        /// The same buttons, grey, on a light and on a dark preview while the
        /// accent comes from the system.
        static let themePreviewWindowButtonLight = Color(light: Color(rgb: 0xD4D4D8), dark: Color(rgb: 0xD4D4D8))
        static let themePreviewWindowButtonDark = Color(light: Color(rgb: 0x71717A), dark: Color(rgb: 0x71717A))

        /// The backdrop of an onboarding step's demonstration, top to bottom.
        static let onboardingGradientTop = Color(light: Color(rgb: 0xF4F4F5), dark: Color(rgb: 0x3F3F46))
        static let onboardingGradientBottom = Color(light: Color(rgb: 0xFFFFFF), dark: Color(rgba: 0x00000000))
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
    static let shadowKeyColor = Color(light: Color(rgb: 0x71717A), dark: Color(rgb: 0x000000))
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
