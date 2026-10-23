// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Combine
import SwiftUI

@MainActor
final class ShatlAccentState: ObservableObject {
    @Published private(set) var isUsingAppAccent: Bool
    @Published private(set) var systemAccentColor: Color
    /// The user picked Graphite, the grey accent, in System Settings.
    @Published private(set) var isGraphite: Bool

    private let notificationCenter: NotificationCenter
    private let defaults: UserDefaults
    private var systemColorsObserver: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = .default, defaults: UserDefaults = .standard) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        self.isUsingAppAccent = Self.resolveIsUsingAppAccent()
        self.systemAccentColor = Self.resolveSystemAccentColor()
        self.isGraphite = Self.accentIsGraphite(in: defaults)

        systemColorsObserver = notificationCenter.addObserver(
            forName: NSColor.systemColorsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    isolated deinit {
        if let systemColorsObserver {
            notificationCenter.removeObserver(systemColorsObserver)
        }
    }

    func refresh() {
        isUsingAppAccent = Self.resolveIsUsingAppAccent()
        systemAccentColor = Self.resolveSystemAccentColor()
        isGraphite = Self.accentIsGraphite(in: defaults)
    }

    /// macOS keeps the accent picked in System Settings as a number in the
    /// global domain, and Graphite is -1. AppKit has no API that names the
    /// accent; this key has stood since macOS 10.14. Multicolor removes it.
    static func accentIsGraphite(in defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: "AppleAccentColor") as? NSNumber)?.intValue == -1
    }

    private static func resolveIsUsingAppAccent() -> Bool {
        guard let appAccent = NSColor(named: "AccentColor") else {
            return false
        }

        return colorsMatch(NSColor.controlAccentColor, appAccent)
    }

    private static func resolveSystemAccentColor() -> Color {
        Color(nsColor: NSColor.controlAccentColor)
    }

    private static func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        guard let left = rgbaComponents(for: lhs),
              let right = rgbaComponents(for: rhs) else {
            return false
        }

        let tolerance = 0.02
        return abs(left.red - right.red) <= tolerance
            && abs(left.green - right.green) <= tolerance
            && abs(left.blue - right.blue) <= tolerance
    }

    private static func rgbaComponents(for color: NSColor) -> (red: Double, green: Double, blue: Double)? {
        guard let convertedColor = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) else {
            return nil
        }

        return (
            Double(convertedColor.redComponent),
            Double(convertedColor.greenComponent),
            Double(convertedColor.blueComponent)
        )
    }
}

private struct ShatlMonochromeAppearanceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The monochrome appearance, as every window's root passes it down.
    var shatlUsesMonochromeAppearance: Bool {
        get { self[ShatlMonochromeAppearanceKey.self] }
        set { self[ShatlMonochromeAppearanceKey.self] = newValue }
    }

    /// The accent our views draw with. The asset's, which macOS replaces
    /// with the accent picked in System Settings; in the monochrome
    /// appearance the monochrome one, whatever macOS has.
    var shatlAccent: Color {
        shatlUsesMonochromeAppearance ? ShatlColor.accentMonochrome : ShatlColor.accent
    }
}

extension View {
    /// The monochrome appearance at a window's root: our views take its
    /// accent from the environment, the system's controls from the tint.
    func shatlMonochromeAppearance(_ isOn: Bool) -> some View {
        environment(\.shatlUsesMonochromeAppearance, isOn)
            .tint(isOn ? ShatlColor.accentMonochrome : nil)
    }
}
