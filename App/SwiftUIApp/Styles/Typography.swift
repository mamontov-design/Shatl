// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

enum ShatlTypographyProfile {
    case standard
    case cjk
}

struct ShatlTextStyleVariant {
    let size: CGFloat
    let lineHeight: CGFloat
    let weight: Font.Weight

    var font: Font {
        .system(size: size, weight: weight)
    }
}

struct ShatlTextStyle {
    let standard: ShatlTextStyleVariant
    let cjk: ShatlTextStyleVariant

    func variant(for profile: ShatlTypographyProfile) -> ShatlTextStyleVariant {
        switch profile {
        case .standard:
            standard
        case .cjk:
            cjk
        }
    }
}

enum ShatlTypography {
    static let headlineSemibold = ShatlTextStyle(
        standard: ShatlTextStyleVariant(size: 20, lineHeight: 22, weight: .semibold),
        cjk: ShatlTextStyleVariant(size: 24, lineHeight: 26, weight: .medium)
    )
    static let subheadlineBold = ShatlTextStyle(
        standard: ShatlTextStyleVariant(size: 18, lineHeight: 20, weight: .semibold),
        cjk: ShatlTextStyleVariant(size: 22, lineHeight: 24, weight: .medium)
    )
    static let bodySemibold = ShatlTextStyle(
        standard: ShatlTextStyleVariant(size: 13, lineHeight: 16, weight: .medium),
        cjk: ShatlTextStyleVariant(size: 15, lineHeight: 18, weight: .regular)
    )
    static let bodyMedium = ShatlTextStyle(
        standard: ShatlTextStyleVariant(size: 13, lineHeight: 16, weight: .regular),
        cjk: ShatlTextStyleVariant(size: 15, lineHeight: 18, weight: .light)
    )
    static let bodyRegular = ShatlTextStyle(
        standard: ShatlTextStyleVariant(size: 13, lineHeight: 16, weight: .regular),
        cjk: ShatlTextStyleVariant(size: 15, lineHeight: 18, weight: .light)
    )
    static let metricSemibold = ShatlTextStyle(
        standard: ShatlTextStyleVariant(size: 12, lineHeight: 15, weight: .medium),
        cjk: ShatlTextStyleVariant(size: 14, lineHeight: 16, weight: .regular)
    )
    static let captionRegular = ShatlTextStyle(
        standard: ShatlTextStyleVariant(size: 11, lineHeight: 14, weight: .regular),
        cjk: ShatlTextStyleVariant(size: 14, lineHeight: 18, weight: .light)
    )
    static let groupSemibold = ShatlTextStyle(
        standard: ShatlTextStyleVariant(size: 10, lineHeight: 13, weight: .medium),
        cjk: ShatlTextStyleVariant(size: 12, lineHeight: 15, weight: .light)
    )
}

extension AppLocaleOverride {
    func shatlTypographyProfile(backingScaleFactor: CGFloat) -> ShatlTypographyProfile {
        guard usesCJKTypographyScript, backingScaleFactor < 2 else {
            return .standard
        }

        return .cjk
    }
}

private extension AppLocaleOverride {
    var usesCJKTypographyScript: Bool {
        switch self {
        case .japanese, .simplifiedChinese:
            true
        case .system:
            Self.isCJKLocale(.autoupdatingCurrent)
        default:
            false
        }
    }

    static func isCJKLocale(_ locale: Locale) -> Bool {
        switch locale.language.languageCode?.identifier {
        case "ja", "zh":
            true
        default:
            false
        }
    }
}

private struct ShatlTypographyProfileEnvironmentKey: EnvironmentKey {
    static let defaultValue = ShatlTypographyProfile.standard
}

extension EnvironmentValues {
    var shatlTypographyProfile: ShatlTypographyProfile {
        get { self[ShatlTypographyProfileEnvironmentKey.self] }
        set { self[ShatlTypographyProfileEnvironmentKey.self] = newValue }
    }
}

private struct ShatlTextStyleModifier: ViewModifier {
    @Environment(\.shatlTypographyProfile) private var typographyProfile

    let style: ShatlTextStyle

    func body(content: Content) -> some View {
        content
            .font(style.variant(for: typographyProfile).font)
    }
}

extension View {
    func shatlTypography(_ style: ShatlTextStyle) -> some View {
        modifier(ShatlTextStyleModifier(style: style))
    }

    func shatlTypographyProfile(localeOverride: AppLocaleOverride) -> some View {
        modifier(ShatlTypographyProfileModifier(localeOverride: localeOverride))
    }
}

private struct ShatlTypographyProfileModifier: ViewModifier {
    let localeOverride: AppLocaleOverride

    @State private var backingScaleFactor = NSScreen.main?.backingScaleFactor ?? 2

    func body(content: Content) -> some View {
        content
            .environment(
                \.shatlTypographyProfile,
                localeOverride.shatlTypographyProfile(backingScaleFactor: backingScaleFactor)
            )
            .background {
                ShatlWindowBackingScaleReader(backingScaleFactor: $backingScaleFactor)
                    .frame(width: 0, height: 0)
            }
    }
}

private struct ShatlWindowBackingScaleReader: NSViewRepresentable {
    @Binding var backingScaleFactor: CGFloat

    func makeNSView(context: Context) -> ShatlWindowBackingScaleView {
        let view = ShatlWindowBackingScaleView()
        view.onScaleChange = { backingScaleFactor = $0 }
        return view
    }

    func updateNSView(_ nsView: ShatlWindowBackingScaleView, context: Context) {
        nsView.onScaleChange = { backingScaleFactor = $0 }
    }
}

private final class ShatlWindowBackingScaleView: NSView {
    var onScaleChange: ((CGFloat) -> Void)?

    private var observations: [NSObjectProtocol] = []
    private var deliveredScale: CGFloat?
    private var isDeliveryScheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowObservers()
        reportBackingScaleFactor()
    }

    isolated deinit {
        removeWindowObservers()
    }

    /// Hands the scale over once the view update under way is done, and
    /// only when it changed: SwiftUI forbids changing its state while it
    /// draws, and the scale changes only with the screen.
    private func reportBackingScaleFactor() {
        guard !isDeliveryScheduled else { return }

        isDeliveryScheduled = true
        Task { @MainActor [weak self] in
            self?.deliverBackingScaleFactor()
        }
    }

    private func deliverBackingScaleFactor() {
        isDeliveryScheduled = false
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard scale != deliveredScale else { return }

        deliveredScale = scale
        onScaleChange?(scale)
    }

    private func updateWindowObservers() {
        removeWindowObservers()

        guard let window else { return }

        let notificationCenter = NotificationCenter.default
        observations = [
            notificationCenter.addObserver(
                forName: NSWindow.didChangeBackingPropertiesNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportBackingScaleFactor() }
            },
            notificationCenter.addObserver(
                forName: NSWindow.didChangeScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportBackingScaleFactor() }
            }
        ]
    }

    private func removeWindowObservers() {
        observations.forEach(NotificationCenter.default.removeObserver)
        observations = []
    }
}
