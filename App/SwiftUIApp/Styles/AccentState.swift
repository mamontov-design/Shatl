// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Combine
import SwiftUI

@MainActor
final class ShatlAccentState: ObservableObject {
    @Published private(set) var isUsingAppAccent: Bool
    @Published private(set) var systemAccentColor: Color

    private let notificationCenter: NotificationCenter
    private var systemColorsObserver: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        self.isUsingAppAccent = Self.resolveIsUsingAppAccent()
        self.systemAccentColor = Self.resolveSystemAccentColor()

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

    deinit {
        if let systemColorsObserver {
            notificationCenter.removeObserver(systemColorsObserver)
        }
    }

    func refresh() {
        isUsingAppAccent = Self.resolveIsUsingAppAccent()
        systemAccentColor = Self.resolveSystemAccentColor()
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
