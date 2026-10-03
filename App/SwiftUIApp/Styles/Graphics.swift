// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Combine
import SwiftUI

enum ShatlBrandRenderingMode {
    case glass
    case flat
}

struct ShatlWordmark: View {
    let renderingMode: ShatlBrandRenderingMode
    let artworkAlignment: Alignment
    let isInteractive: Bool

    private let selection: Binding<ShatlBrandMark>?

    @StateObject private var wordmarkAnimationState = ShatlBrandAnimationState(
        originalStrokeWidth: ShatlBrandAnimation.wordmarkOriginalStrokeWidth,
        strokeWidths: ShatlBrandAnimation.wordmarkStrokeWidths
    )
    @StateObject private var logomarkAnimationState = ShatlBrandAnimationState(
        originalStrokeWidth: ShatlBrandAnimation.logomarkOriginalStrokeWidth,
        strokeWidths: ShatlBrandAnimation.logomarkStrokeWidths
    )
    @State private var interactionScale: CGFloat = 1
    @State private var localSelection: ShatlBrandMark
    @State private var logomarkProgress: CGFloat
    @State private var isHovering = false
    @State private var bounceTask: Task<Void, Never>?

    init(
        renderingMode: ShatlBrandRenderingMode,
        selection: Binding<ShatlBrandMark>,
        artworkAlignment: Alignment = .center,
        isInteractive: Bool = true
    ) {
        self.renderingMode = renderingMode
        self.artworkAlignment = artworkAlignment
        self.isInteractive = isInteractive
        self.selection = selection

        let initialSelection = selection.wrappedValue
        _localSelection = State(initialValue: initialSelection)
        _logomarkProgress = State(
            initialValue: initialSelection == .logomark ? 1 : 0
        )
    }

    init(
        renderingMode: ShatlBrandRenderingMode,
        initialSelection: ShatlBrandMark = .wordmark,
        artworkAlignment: Alignment = .center,
        isInteractive: Bool = true
    ) {
        self.renderingMode = renderingMode
        self.artworkAlignment = artworkAlignment
        self.isInteractive = isInteractive
        selection = nil
        _localSelection = State(initialValue: initialSelection)
        _logomarkProgress = State(
            initialValue: initialSelection == .logomark ? 1 : 0
        )
    }

    private var selectedBrandMark: ShatlBrandMark {
        selection?.wrappedValue ?? localSelection
    }

    private var effectiveRenderingMode: ShatlBrandRenderingMode {
        if #available(macOS 27.0, *) {
            renderingMode
        } else {
            .flat
        }
    }

    var body: some View {
        ZStack(alignment: artworkAlignment) {
            ShatlWordmarkArtwork(
                animationPhase: wordmarkAnimationState.phase,
                renderingMode: effectiveRenderingMode
            )
                .compositingGroup()
                .opacity(Double(1 - logomarkProgress))
                .blur(radius: logomarkProgress * ShatlBrandTransition.blurRadius)
                .zIndex(selectedBrandMark == .logomark ? 0 : 1)

            ShatlLogomarkArtwork(
                animationPhase: logomarkAnimationState.phase,
                renderingMode: effectiveRenderingMode
            )
                .frame(width: 84, height: 84)
                .compositingGroup()
                .opacity(Double(logomarkProgress))
                .blur(radius: (1 - logomarkProgress) * ShatlBrandTransition.blurRadius)
                .zIndex(selectedBrandMark == .logomark ? 1 : 0)
        }
        .frame(width: 214, height: 85, alignment: .top)
        .scaleEffect(interactionScale)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isInteractive else { return }
            toggleBrandMark()
        }
        .onChange(of: selectedBrandMark) { _, brandMark in
            resetAnimation(for: brandMark)

            withAnimation(ShatlBrandTransition.artworkChange) {
                logomarkProgress = brandMark == .logomark ? 1 : 0
            }
        }
        .onHover { hovering in
            guard isInteractive else {
                updateCursor(isHovering: false)
                return
            }
            updateCursor(isHovering: hovering)
        }
        .onDisappear {
            resetInteractionState()
        }
        .task(id: selectedBrandMark) {
            resetAnimation(for: selectedBrandMark)
            await runAnimation(for: selectedBrandMark)
        }
    }

    private func toggleBrandMark() {
        let newSelection: ShatlBrandMark = selectedBrandMark == .wordmark
            ? .logomark
            : .wordmark

        if let selection {
            selection.wrappedValue = newSelection
        } else {
            localSelection = newSelection
        }

        bounceBrandMark()
    }

    private func resetAnimation(for brandMark: ShatlBrandMark) {
        switch brandMark {
        case .wordmark:
            wordmarkAnimationState.resetToOriginal()
        case .logomark:
            logomarkAnimationState.resetToOriginal()
        }
    }

    private func runAnimation(for brandMark: ShatlBrandMark) async {
        switch brandMark {
        case .wordmark:
            await wordmarkAnimationState.run()
        case .logomark:
            await logomarkAnimationState.run()
        }
    }

    private func bounceBrandMark() {
        bounceTask?.cancel()

        bounceTask = Task { @MainActor in
            withAnimation(.spring(response: 0.18, dampingFraction: 0.62)) {
                interactionScale = 1.045
            }

            do {
                try await Task.sleep(nanoseconds: 130_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                interactionScale = 1
            }
        }
    }

    private func updateCursor(isHovering: Bool) {
        guard self.isHovering != isHovering else { return }

        self.isHovering = isHovering

        if isHovering {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }

    private func resetInteractionState() {
        if isHovering {
            NSCursor.pop()
            isHovering = false
        }

        bounceTask?.cancel()
        bounceTask = nil
        interactionScale = 1
    }
}

private struct ShatlWordmarkArtwork: View {
    @EnvironmentObject private var accentState: ShatlAccentState

    let animationPhase: CGFloat
    let renderingMode: ShatlBrandRenderingMode

    private var strokeWidth: CGFloat {
        ShatlBrandAnimation.strokeWidth(
            for: animationPhase,
            in: ShatlBrandAnimation.wordmarkStrokeWidths
        )
    }

    private var strokeOpacity: Double {
        guard renderingMode == .glass else { return 1 }

        return ShatlBrandAnimation.interpolatedOpacity(
            phase: animationPhase,
            from: ShatlWordmarkOpacity.strokeAtMinimumWidth,
            to: ShatlWordmarkOpacity.strokeAtMaximumWidth
        )
    }

    private var starOpacity: Double {
        guard renderingMode == .glass else { return 1 }

        return ShatlBrandAnimation.interpolatedOpacity(
            phase: animationPhase,
            from: ShatlWordmarkOpacity.starAtMinimumWidth,
            to: ShatlWordmarkOpacity.starAtMaximumWidth
        )
    }

    private var strokeColor: Color {
        if accentState.isUsingAppAccent {
            ShatlColor.neonBlue.opacity(strokeOpacity)
        } else {
            accentState.systemAccentColor.opacity(strokeOpacity)
        }
    }

    private var starColor: Color {
        if accentState.isUsingAppAccent {
            ShatlColor.accent.opacity(starOpacity)
        } else {
            ShatlColor.typographyPrimary.opacity(starOpacity)
        }
    }

    var body: some View {
        ZStack {
            strokeLayer
            starLayer
        }
        .frame(width: 214, height: 85)
    }

    @ViewBuilder
    private var strokeLayer: some View {
        switch renderingMode {
        case .glass:
            ShatlWordmarkStrokeShape()
                .stroke(
                    strokeColor,
                    style: StrokeStyle(lineWidth: strokeWidth)
                )
                .glassEffect(
                    .clear.tint(strokeColor),
                    in: ShatlWordmarkStrokeGlassShape(lineWidth: strokeWidth)
                )
        case .flat:
            ShatlWordmarkStrokeShape()
                .stroke(
                    strokeColor,
                    style: StrokeStyle(lineWidth: strokeWidth)
                )
        }
    }

    @ViewBuilder
    private var starLayer: some View {
        switch renderingMode {
        case .glass:
            ShatlWordmarkStarMorphShape(progress: animationPhase)
                .glassEffect(
                    .clear.tint(starColor),
                    in: ShatlWordmarkStarMorphShape(progress: animationPhase)
                )
        case .flat:
            ShatlWordmarkStarMorphShape(progress: animationPhase)
                .fill(starColor)
        }
    }
}

@MainActor
private final class ShatlBrandAnimationState: ObservableObject {
    @Published private(set) var phase: CGFloat

    private let originalPhase: CGFloat

    init(originalStrokeWidth: CGFloat, strokeWidths: ClosedRange<CGFloat>) {
        let originalPhase = ShatlBrandAnimation.phase(
            forStrokeWidth: originalStrokeWidth,
            in: strokeWidths
        )
        self.originalPhase = originalPhase
        phase = originalPhase
    }

    func resetToOriginal() {
        withAnimation(nil) {
            phase = originalPhase
        }
    }

    func run() async {
        while !Task.isCancelled {
            let nextPhase = ShatlBrandAnimation.randomPhase(
                excluding: phase,
                originalPhase: originalPhase
            )

            guard await sleep(for: ShatlBrandAnimation.pauseDuration) else { return }

            withAnimation(ShatlBrandAnimation.timing(duration: ShatlBrandAnimation.fullDuration)) {
                phase = nextPhase
            }

            guard await sleep(for: ShatlBrandAnimation.fullDuration) else { return }
        }
    }

    private func sleep(for duration: TimeInterval) async -> Bool {
        let nanoseconds = UInt64(duration * 1_000_000_000)

        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

/// Both marks breathe through one shared phase, which also morphs the star and
/// fades the glass; each mark turns it into its own stroke widths. The
/// compact letter of the logomark closes up above 8 pt, so it stays at 4–8
/// and rests at its thickest.
enum ShatlBrandAnimation {
    static let fullDuration: TimeInterval = 2.2
    static let pauseDuration: TimeInterval = 2.0
    static let wordmarkStrokeWidths: ClosedRange<CGFloat> = 4...12
    static let logomarkStrokeWidths: ClosedRange<CGFloat> = 4...8
    static let wordmarkOriginalStrokeWidth: CGFloat = 8
    static let logomarkOriginalStrokeWidth: CGFloat = 8

    static let phases: [CGFloat] = [0, 0.25, 0.5, 0.75, 1.0]
    private static let commonRangeProbability = 0.9
    private static let phaseComparisonTolerance: CGFloat = 0.001

    static func randomPhase(
        excluding currentPhase: CGFloat,
        originalPhase: CGFloat
    ) -> CGFloat {
        let availablePhases = phases.filter {
            abs($0 - currentPhase) > phaseComparisonTolerance
        }
        let usesCommonRange = Double.random(in: 0..<1) < commonRangeProbability
        let preferredPhases = availablePhases.filter { phase in
            if usesCommonRange {
                return phase <= originalPhase + phaseComparisonTolerance
            }

            return phase > originalPhase + phaseComparisonTolerance
        }

        return preferredPhases.randomElement()
            ?? availablePhases.randomElement()
            ?? originalPhase
    }

    static func strokeWidth(for phase: CGFloat, in strokeWidths: ClosedRange<CGFloat>) -> CGFloat {
        strokeWidths.lowerBound + phase * (strokeWidths.upperBound - strokeWidths.lowerBound)
    }

    static func phase(
        forStrokeWidth strokeWidth: CGFloat,
        in strokeWidths: ClosedRange<CGFloat>
    ) -> CGFloat {
        let clampedStrokeWidth = min(
            max(strokeWidth, strokeWidths.lowerBound),
            strokeWidths.upperBound
        )
        return (clampedStrokeWidth - strokeWidths.lowerBound)
            / (strokeWidths.upperBound - strokeWidths.lowerBound)
    }

    static func interpolatedOpacity(
        phase: CGFloat,
        from startOpacity: Double,
        to endOpacity: Double
    ) -> Double {
        let clampedPhase = min(max(Double(phase), 0), 1)
        return startOpacity + (endOpacity - startOpacity) * clampedPhase
    }

    static func timing(duration: TimeInterval) -> Animation {
        .timingCurve(0.85, 0.0, 0.55, 1.0, duration: duration)
    }
}

private enum ShatlBrandTransition {
    static let blurRadius: CGFloat = 7
    static let artworkChange = Animation.smooth(duration: 0.38)
}

private enum ShatlWordmarkOpacity {
    static let strokeAtMinimumWidth = 1.0
    static let strokeAtMaximumWidth = 0.85
    static let starAtMinimumWidth = 0.75
    static let starAtMaximumWidth = 0.55
}

private enum ShatlLogomarkOpacity {
    static let aShapeAtMinimumWidth = 1.0
    static let aShapeAtMaximumWidth = 0.75
    static let starAtMinimumWidth = 1.0
    static let starAtMaximumWidth = 0.85
}

private enum ShatlWordmarkMetrics {
    static let viewport = CGSize(width: 214, height: 85)
}

private struct ShatlMorphCubicSegment {
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint
}

private struct ShatlWordmarkStarMorphShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: mapped(interpolated(thinStart, boldStart), in: rect))

        for index in thinSegments.indices {
            let thin = thinSegments[index]
            let bold = boldSegments[index]
            path.addCurve(
                to: mapped(interpolated(thin.end, bold.end), in: rect),
                control1: mapped(interpolated(thin.control1, bold.control1), in: rect),
                control2: mapped(interpolated(thin.control2, bold.control2), in: rect)
            )
        }

        path.closeSubpath()
        return path
    }

    private func interpolated(_ thin: CGPoint, _ bold: CGPoint) -> CGPoint {
        CGPoint(
            x: thin.x + (bold.x - thin.x) * progress,
            y: thin.y + (bold.y - thin.y) * progress
        )
    }

    private func mapped(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width / ShatlWordmarkMetrics.viewport.width,
            y: rect.minY + point.y * rect.height / ShatlWordmarkMetrics.viewport.height
        )
    }

    private let thinStart = CGPoint(x: 90, y: 37.0015)
    private let boldStart = CGPoint(x: 90.9999, y: 30.0015)

    private let thinSegments = [
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 90.2969, y: 37.0015),
            control2: CGPoint(x: 90.412, y: 37.3224),
            end: CGPoint(x: 90.5, y: 37.8726)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 91, y: 41),
            control2: CGPoint(x: 92, y: 42),
            end: CGPoint(x: 95.1282, y: 42.5)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 95.6788, y: 42.588),
            control2: CGPoint(x: 96, y: 42.6972),
            end: CGPoint(x: 96, y: 43.0009)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 96, y: 43.3047),
            control2: CGPoint(x: 95.6788, y: 43.412),
            end: CGPoint(x: 95.1282, y: 43.5)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 92, y: 44),
            control2: CGPoint(x: 91, y: 45),
            end: CGPoint(x: 90.5, y: 48.1304)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 90.4121, y: 48.6805),
            control2: CGPoint(x: 90.3047, y: 49.0015),
            end: CGPoint(x: 90, y: 49.0015)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 89.6953, y: 49.0015),
            control2: CGPoint(x: 89.5879, y: 48.6805),
            end: CGPoint(x: 89.5, y: 48.1304)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 89, y: 45),
            control2: CGPoint(x: 88, y: 44),
            end: CGPoint(x: 84.8718, y: 43.5)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 84.3212, y: 43.412),
            control2: CGPoint(x: 84, y: 43.2969),
            end: CGPoint(x: 84, y: 43.0009)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 84, y: 42.705),
            control2: CGPoint(x: 84.3212, y: 42.588),
            end: CGPoint(x: 84.8718, y: 42.5)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 88, y: 42),
            control2: CGPoint(x: 89, y: 41),
            end: CGPoint(x: 89.5, y: 37.8726)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 89.588, y: 37.3224),
            control2: CGPoint(x: 89.7031, y: 37.0015),
            end: CGPoint(x: 90, y: 37.0015)
        ),
    ]

    private let boldSegments = [
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 91.9285, y: 30.0015),
            control2: CGPoint(x: 92.7349, y: 30.6095),
            end: CGPoint(x: 93.1225, y: 31.4533)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 94.4247, y: 34.2877),
            control2: CGPoint(x: 96.7121, y: 36.5743),
            end: CGPoint(x: 99.5468, y: 37.8765)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 100.391, y: 38.2644),
            control2: CGPoint(x: 101, y: 39.0713),
            end: CGPoint(x: 101, y: 40.0006)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 101, y: 40.9298),
            control2: CGPoint(x: 100.391, y: 41.7367),
            end: CGPoint(x: 99.5469, y: 42.1247)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 96.712, y: 43.4272),
            control2: CGPoint(x: 94.4246, y: 45.7147),
            end: CGPoint(x: 93.1224, y: 48.5496)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 92.7348, y: 49.3934),
            control2: CGPoint(x: 91.9285, y: 50.0015),
            end: CGPoint(x: 90.9999, y: 50.0015)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 90.0713, y: 50.0015),
            control2: CGPoint(x: 89.2649, y: 49.3934),
            end: CGPoint(x: 88.8773, y: 48.5496)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 87.5751, y: 45.7147),
            control2: CGPoint(x: 85.2878, y: 43.4272),
            end: CGPoint(x: 82.4529, y: 42.1247)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 81.6084, y: 41.7367),
            control2: CGPoint(x: 80.9999, y: 40.9298),
            end: CGPoint(x: 80.9999, y: 40.0006)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 80.9999, y: 39.0713),
            control2: CGPoint(x: 81.6084, y: 38.2644),
            end: CGPoint(x: 82.4529, y: 37.8765)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 85.2877, y: 36.5743),
            control2: CGPoint(x: 87.575, y: 34.2877),
            end: CGPoint(x: 88.8772, y: 31.4533)
        ),
        ShatlMorphCubicSegment(
            control1: CGPoint(x: 89.2649, y: 30.6095),
            control2: CGPoint(x: 90.0712, y: 30.0015),
            end: CGPoint(x: 90.9999, y: 30.0015)
        ),
    ]
}

private struct ShatlLogomarkArtwork: View {
    @EnvironmentObject private var accentState: ShatlAccentState

    let animationPhase: CGFloat
    let renderingMode: ShatlBrandRenderingMode

    private var strokeWidth: CGFloat {
        ShatlBrandAnimation.strokeWidth(
            for: animationPhase,
            in: ShatlBrandAnimation.logomarkStrokeWidths
        )
    }

    private var strokeOpacity: Double {
        guard renderingMode == .glass else { return 1 }

        return ShatlBrandAnimation.interpolatedOpacity(
            phase: animationPhase,
            from: ShatlLogomarkOpacity.aShapeAtMinimumWidth,
            to: ShatlLogomarkOpacity.aShapeAtMaximumWidth
        )
    }

    private var starOpacity: Double {
        guard renderingMode == .glass else { return 1 }

        return ShatlBrandAnimation.interpolatedOpacity(
            phase: animationPhase,
            from: ShatlLogomarkOpacity.starAtMinimumWidth,
            to: ShatlLogomarkOpacity.starAtMaximumWidth
        )
    }

    private var aColor: Color {
        if accentState.isUsingAppAccent {
            ShatlColor.accent.opacity(strokeOpacity)
        } else {
            Color("AccentColor").opacity(strokeOpacity)
        }
    }

    private var starColor: Color {
        if accentState.isUsingAppAccent {
            ShatlColor.neonBlue.opacity(starOpacity)
        } else {
            accentState.systemAccentColor.opacity(starOpacity)
        }
    }

    var body: some View {
        ZStack {
            backgroundLayer
            aLayer
            starLayer
        }
        .frame(width: 84, height: 84)
    }

    /// Flat is macOS 26 (see `ShatlWordmark.effectiveRenderingMode`): the
    /// letter and the star take the glass's colors as solid ones, over a
    /// plain shape.
    @ViewBuilder
    private var backgroundLayer: some View {
        switch renderingMode {
        case .glass:
            Color.clear
                .glassEffect(
                    .regular.tint(.accent.opacity(ShatlGlassTint.subtleOpacity)),
                    in: ShatlLogomarkAppShape()
                )
        case .flat:
            ShatlLogomarkAppShape()
                .fill(ShatlColor.backgroundSecondary)
                .overlay {
                    ShatlLogomarkAppShape()
                        .stroke(ShatlColor.outlineTertiary, lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    private var aLayer: some View {
        switch renderingMode {
        case .glass:
            ShatlLogomarkAStrokeShape()
                .stroke(
                    aColor,
                    style: StrokeStyle(lineWidth: strokeWidth)
                )
                .glassEffect(
                    .clear.tint(aColor),
                    in: ShatlLogomarkAStrokeGlassShape(lineWidth: strokeWidth)
                )
        case .flat:
            ShatlLogomarkAStrokeShape()
                .stroke(
                    aColor,
                    style: StrokeStyle(lineWidth: strokeWidth)
                )
        }
    }

    @ViewBuilder
    private var starLayer: some View {
        switch renderingMode {
        case .glass:
            ShatlLogomarkStarMorphShape(progress: animationPhase)
                .glassEffect(
                    .clear.tint(starColor),
                    in: ShatlLogomarkStarMorphShape(progress: animationPhase)
                )
        case .flat:
            ShatlLogomarkStarMorphShape(progress: animationPhase)
                .fill(starColor)
        }
    }
}

enum ShatlPerformanceSpeedometerLevel {
    case oneOfThree
    case twoOfThree
    case threeOfThree
}

struct ShatlPerformanceSpeedometerTrackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let p = PerformanceSpeedometerPointMapper(rect: rect)

        path.move(to: p.point(24.0001, 0))
        path.addCurve(to: p.point(37.3341, 4.04492), control1: p.point(28.7469, 0.0000000566044), control2: p.point(33.3873, 1.40777))
        path.addCurve(to: p.point(46.173, 14.8154), control1: p.point(41.2807, 6.68202), control2: p.point(44.3565, 10.4302))
        path.addCurve(to: p.point(47.5392, 28.6826), control1: p.point(47.9895, 19.2009), control2: p.point(48.4652, 24.0271))
        path.addCurve(to: p.point(40.9708, 40.9707), control1: p.point(46.6131, 33.338), control2: p.point(44.3272, 37.6143))
        path.addLine(to: p.point(40.8214, 41.1123))
        path.addCurve(to: p.point(35.3136, 40.9707), control1: p.point(39.2512, 42.531), control2: p.point(36.8269, 42.484))
        path.addCurve(to: p.point(35.3136, 35.3135), control1: p.point(33.7516, 39.4086), control2: p.point(33.7516, 36.8756))
        path.addCurve(to: p.point(35.4454, 35.1875), control1: p.point(35.3568, 35.2703), control2: p.point(35.4008, 35.2283))
        path.addCurve(to: p.point(39.7003, 27.123), control1: p.point(37.6142, 32.9688), control2: p.point(39.0945, 30.1686))
        path.addCurve(to: p.point(38.7892, 17.874), control1: p.point(40.318, 24.0178), control2: p.point(40.0008, 20.7991))
        path.addCurve(to: p.point(32.8937, 10.6895), control1: p.point(37.5776, 14.949), control2: p.point(35.5261, 12.4484))
        path.addCurve(to: p.point(24.0001, 7.99219), control1: p.point(30.2612, 8.93055), control2: p.point(27.1661, 7.99219))
        path.addCurve(to: p.point(15.1065, 10.6895), control1: p.point(20.8341, 7.99219), control2: p.point(17.739, 8.93055))
        path.addCurve(to: p.point(9.21104, 17.874), control1: p.point(12.4741, 12.4484), control2: p.point(10.4227, 14.949))
        path.addCurve(to: p.point(8.29991, 27.123), control1: p.point(7.99943, 20.7991), control2: p.point(7.68224, 24.0178))
        path.addCurve(to: p.point(12.5646, 35.1982), control1: p.point(8.90667, 30.1734), control2: p.point(10.3903, 32.9779))
        path.addCurve(to: p.point(12.6857, 35.3135), control1: p.point(12.6054, 35.2358), control2: p.point(12.6461, 35.2739))
        path.addCurve(to: p.point(12.6857, 40.9707), control1: p.point(14.2477, 36.8756), control2: p.point(14.2477, 39.4086))
        path.addCurve(to: p.point(7.17882, 41.1123), control1: p.point(11.1724, 42.4836), control2: p.point(8.74893, 42.5307))
        path.addLine(to: p.point(7.0294, 40.9707))
        path.addLine(to: p.point(6.71788, 40.6533))
        path.addCurve(to: p.point(0.461042, 28.6826), control1: p.point(3.53151, 37.3467), control2: p.point(1.35819, 33.1925))
        path.addCurve(to: p.point(1.82725, 14.8154), control1: p.point(-0.465003, 24.0271), control2: p.point(0.0107495, 19.2009))
        path.addCurve(to: p.point(10.6661, 4.04492), control1: p.point(3.64372, 10.4302), control2: p.point(6.71955, 6.68202))
        path.addCurve(to: p.point(24.0001, 0), control1: p.point(14.6129, 1.40777), control2: p.point(19.2534, 0))
        path.closeSubpath()

        return path
    }
}

struct ShatlPerformanceSpeedometerProgressShape: Shape {
    let level: ShatlPerformanceSpeedometerLevel

    func path(in rect: CGRect) -> Path {
        switch level {
        case .oneOfThree:
            return oneOfThreePath(in: rect)
        case .twoOfThree:
            return twoOfThreePath(in: rect)
        case .threeOfThree:
            return ShatlPerformanceSpeedometerTrackShape().path(in: rect)
        }
    }

    private func oneOfThreePath(in rect: CGRect) -> Path {
        var path = Path()
        let p = PerformanceSpeedometerPointMapper(rect: rect)

        path.move(to: p.point(7.17871, 6.88811))
        path.addCurve(to: p.point(12.6865, 7.02971), control1: p.point(8.74891, 5.46916), control2: p.point(11.1732, 5.51635))
        path.addCurve(to: p.point(12.6865, 12.686), control1: p.point(14.2484, 8.59173), control2: p.point(14.2483, 11.1239))
        path.addCurve(to: p.point(12.5312, 12.8324), control1: p.point(12.636, 12.7365), control2: p.point(12.5838, 12.7852))
        path.addCurve(to: p.point(9.21094, 17.8744), control1: p.point(11.1151, 14.2868), control2: p.point(9.98825, 15.9979))
        path.addCurve(to: p.point(7.99219, 24.0004), control1: p.point(8.4065, 19.8166), control2: p.point(7.99219, 21.8983))
        path.addCurve(to: p.point(9.21094, 30.1264), control1: p.point(7.99223, 26.1025), control2: p.point(8.4065, 28.1843))
        path.addCurve(to: p.point(12.5342, 35.1694), control1: p.point(9.98865, 32.0038), control2: p.point(11.1171, 33.7146))
        path.addCurve(to: p.point(12.6855, 35.3139), control1: p.point(12.5857, 35.2158), control2: p.point(12.6359, 35.2643))
        path.addCurve(to: p.point(12.6855, 40.9701), control1: p.point(14.2476, 36.876), control2: p.point(14.2476, 39.408))
        path.addCurve(to: p.point(7.0293, 40.9701), control1: p.point(11.1235, 42.5322), control2: p.point(8.59139, 42.5322))
        path.addCurve(to: p.point(1.82715, 33.184), control1: p.point(4.80084, 38.7416), control2: p.point(3.0332, 36.0957))
        path.addCurve(to: p.point(0, 24.0004), control1: p.point(0.621164, 30.2724), control2: p.point(0.0000434508, 27.1519))
        path.addCurve(to: p.point(1.82715, 14.8158), control1: p.point(0.000000275531, 20.8487), control2: p.point(0.621049, 17.7276))
        path.addCurve(to: p.point(7.0293, 7.02971), control1: p.point(3.03323, 11.9041), control2: p.point(4.80077, 9.25829))
        path.addLine(to: p.point(7.17871, 6.88811))
        path.closeSubpath()

        return path
    }

    private func twoOfThreePath(in rect: CGRect) -> Path {
        var path = Path()
        let p = PerformanceSpeedometerPointMapper(rect: rect)

        path.move(to: p.point(24, 0))
        path.addCurve(to: p.point(40.9707, 7.0293), control1: p.point(30.3652, -0.000000000987952), control2: p.point(36.4698, 2.52843))
        path.addCurve(to: p.point(40.9707, 12.6865), control1: p.point(42.5328, 8.59139), control2: p.point(42.5328, 11.1244))
        path.addCurve(to: p.point(35.3145, 12.6865), control1: p.point(39.4087, 14.2483), control2: p.point(36.8765, 14.2483))
        path.addCurve(to: p.point(35.1699, 12.5342), control1: p.point(35.2647, 12.6368), control2: p.point(35.2165, 12.5858))
        path.addCurve(to: p.point(24, 7.99219), control1: p.point(32.1828, 9.62409), control2: p.point(28.1758, 7.99219))
        path.addCurve(to: p.point(12.6807, 12.6807), control1: p.point(19.7544, 7.99219), control2: p.point(15.6827, 9.67858))
        path.addCurve(to: p.point(7.99219, 24), control1: p.point(9.67858, 15.6827), control2: p.point(7.99219, 19.7544))
        path.addCurve(to: p.point(12.5439, 35.1787), control1: p.point(7.99219, 28.1802), control2: p.point(9.62813, 32.1906))
        path.addCurve(to: p.point(12.6855, 35.3135), control1: p.point(12.5919, 35.2223), control2: p.point(12.6392, 35.2671))
        path.addCurve(to: p.point(12.6855, 40.9707), control1: p.point(14.2476, 36.8756), control2: p.point(14.2476, 39.4086))
        path.addCurve(to: p.point(7.17871, 41.1123), control1: p.point(11.1723, 42.4836), control2: p.point(8.74882, 42.5307))
        path.addLine(to: p.point(7.0293, 40.9707))
        path.addLine(to: p.point(6.61328, 40.5439))
        path.addCurve(to: p.point(0, 24), control1: p.point(2.373, 36.0879), control2: p.point(0.000000196005, 30.1663))
        path.addCurve(to: p.point(7.0293, 7.0293), control1: p.point(-0.000000000292708, 17.6348), control2: p.point(2.52842, 11.5302))
        path.addCurve(to: p.point(24, 0), control1: p.point(11.5302, 2.52842), control2: p.point(17.6348, 0.000000682886))
        path.closeSubpath()

        return path
    }
}

struct ShatlPerformanceSpeedometerArrowShape: Shape {
    let level: ShatlPerformanceSpeedometerLevel

    func path(in rect: CGRect) -> Path {
        switch level {
        case .oneOfThree:
            return oneOfThreePath(in: rect)
        case .twoOfThree:
            return twoOfThreePath(in: rect)
        case .threeOfThree:
            return threeOfThreePath(in: rect)
        }
    }

    private func oneOfThreePath(in rect: CGRect) -> Path {
        var path = Path()
        let p = PerformanceSpeedometerPointMapper(rect: rect)

        path.move(to: p.point(5.61515, 5.6154))
        path.addCurve(to: p.point(7.02922, 5.6154), control1: p.point(6.00568, 5.22488), control2: p.point(6.63869, 5.22488))
        path.addLine(to: p.point(21.9667, 20.5529))
        path.addCurve(to: p.point(26.828, 21.172), control1: p.point(23.5006, 19.6469), control2: p.point(25.5101, 19.8541))
        path.addCurve(to: p.point(27.4452, 26.0314), control1: p.point(28.1456, 22.4899), control2: p.point(28.3509, 24.4977))
        path.addLine(to: p.point(28.9491, 27.5353))
        path.addCurve(to: p.point(28.9491, 28.9494), control1: p.point(29.3396, 27.9258), control2: p.point(29.3394, 28.5588))
        path.addCurve(to: p.point(27.5351, 28.9494), control1: p.point(28.5586, 29.3399), control2: p.point(27.9256, 29.3399))
        path.addLine(to: p.point(26.0321, 27.4465))
        path.addCurve(to: p.point(21.1708, 26.8283), control1: p.point(24.4982, 28.3527), control2: p.point(22.4889, 28.1463))
        path.addCurve(to: p.point(20.5536, 21.9679), control1: p.point(19.853, 25.5103), control2: p.point(19.6476, 23.5018))
        path.addLine(to: p.point(5.61515, 7.02947))
        path.addCurve(to: p.point(5.61515, 5.6154), control1: p.point(5.22463, 6.63894), control2: p.point(5.22464, 6.00593))
        path.closeSubpath()

        path.move(to: p.point(25.414, 22.5861))
        path.addCurve(to: p.point(22.5849, 22.5861), control1: p.point(24.6329, 21.8051), control2: p.point(23.3659, 21.8051))
        path.addCurve(to: p.point(22.5849, 25.4142), control1: p.point(21.8042, 23.3671), control2: p.point(21.8041, 24.6333))
        path.addCurve(to: p.point(25.414, 25.4142), control1: p.point(23.3659, 26.1953), control2: p.point(24.6329, 26.1953))
        path.addCurve(to: p.point(25.414, 22.5861), control1: p.point(26.1947, 24.6333), control2: p.point(26.1946, 23.3671))
        path.closeSubpath()

        return path
    }

    private func twoOfThreePath(in rect: CGRect) -> Path {
        var path = Path()
        let p = PerformanceSpeedometerPointMapper(rect: rect)

        path.move(to: p.point(40.9706, 5.61536))
        path.addCurve(to: p.point(42.3847, 5.61536), control1: p.point(41.3611, 5.22492), control2: p.point(41.9942, 5.22487))
        path.addCurve(to: p.point(42.3847, 7.02943), control1: p.point(42.7751, 6.00587), control2: p.point(42.7751, 6.63892))
        path.addLine(to: p.point(27.4462, 21.9669))
        path.addCurve(to: p.point(26.828, 26.8283), control1: p.point(28.3523, 23.5009), control2: p.point(28.146, 25.5102))
        path.addCurve(to: p.point(21.9677, 27.4454), control1: p.point(25.51, 28.1461), control2: p.point(23.5015, 28.3514))
        path.addLine(to: p.point(20.4647, 28.9493))
        path.addCurve(to: p.point(19.0507, 28.9493), control1: p.point(20.0742, 29.3398), control2: p.point(19.4412, 29.3398))
        path.addCurve(to: p.point(19.0507, 27.5353), control1: p.point(18.6602, 28.5588), control2: p.point(18.6602, 27.9258))
        path.addLine(to: p.point(20.5536, 26.0324))
        path.addCurve(to: p.point(21.1718, 21.171), control1: p.point(19.6473, 24.4984), control2: p.point(19.8537, 22.4891))
        path.addCurve(to: p.point(26.0321, 20.5538), control1: p.point(22.4898, 19.8532), control2: p.point(24.4983, 19.6477))
        path.addLine(to: p.point(40.9706, 5.61536))
        path.closeSubpath()

        path.move(to: p.point(25.4139, 22.5851))
        path.addCurve(to: p.point(22.5858, 22.5851), control1: p.point(24.633, 21.8043), control2: p.point(23.3668, 21.8044))
        path.addCurve(to: p.point(22.5858, 25.4142), control1: p.point(21.8048, 23.3661), control2: p.point(21.8048, 24.6331))
        path.addCurve(to: p.point(25.4139, 25.4142), control1: p.point(23.3668, 26.1948), control2: p.point(24.633, 26.1949))
        path.addCurve(to: p.point(25.4139, 22.5851), control1: p.point(26.195, 24.6331), control2: p.point(26.195, 23.3661))
        path.closeSubpath()

        return path
    }

    private func threeOfThreePath(in rect: CGRect) -> Path {
        var path = Path()
        let p = PerformanceSpeedometerPointMapper(rect: rect)

        path.move(to: p.point(19.0507, 19.0509))
        path.addCurve(to: p.point(20.4648, 19.0509), control1: p.point(19.4412, 18.6605), control2: p.point(20.0743, 18.6604))
        path.addLine(to: p.point(21.9677, 20.5539))
        path.addCurve(to: p.point(26.829, 21.172), control1: p.point(23.5016, 19.6477), control2: p.point(25.511, 19.854))
        path.addCurve(to: p.point(27.4462, 26.0324), control1: p.point(28.1467, 22.49), control2: p.point(28.3523, 24.4986))
        path.addLine(to: p.point(42.3847, 40.9708))
        path.addCurve(to: p.point(42.3847, 42.3849), control1: p.point(42.775, 41.3614), control2: p.point(42.7751, 41.9944))
        path.addCurve(to: p.point(40.9706, 42.3849), control1: p.point(41.9942, 42.7754), control2: p.point(41.3612, 42.7752))
        path.addLine(to: p.point(26.0322, 27.4464))
        path.addCurve(to: p.point(21.1718, 26.8283), control1: p.point(24.4983, 28.3522), control2: p.point(22.4897, 28.1461))
        path.addCurve(to: p.point(20.5536, 21.9679), control1: p.point(19.854, 25.5104), control2: p.point(19.6478, 23.5018))
        path.addLine(to: p.point(19.0507, 20.465))
        path.addCurve(to: p.point(19.0507, 19.0509), control1: p.point(18.6602, 20.0745), control2: p.point(18.6602, 19.4414))
        path.closeSubpath()

        path.move(to: p.point(25.414, 22.5861))
        path.addCurve(to: p.point(22.5859, 22.5861), control1: p.point(24.6329, 21.8051), control2: p.point(23.3669, 21.805))
        path.addCurve(to: p.point(22.5859, 25.4142), control1: p.point(21.805, 23.3671), control2: p.point(21.8049, 24.6332))
        path.addCurve(to: p.point(25.414, 25.4142), control1: p.point(23.3668, 26.1952), control2: p.point(24.6329, 26.195))
        path.addCurve(to: p.point(25.414, 22.5861), control1: p.point(26.195, 24.6332), control2: p.point(26.195, 23.3671))
        path.closeSubpath()

        return path
    }
}

struct ShatlWindowButtonCloseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let p = WindowButtonPointMapper(rect: rect)
        path.addEllipse(in: p.rect(x: 8, y: 8, width: 7, height: 7))
        return path
    }
}

struct ShatlWindowButtonMinimizeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let p = WindowButtonPointMapper(rect: rect)
        path.addEllipse(in: p.rect(x: 18, y: 8, width: 7, height: 7))
        return path
    }
}

struct ShatlWindowButtonExpandShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let p = WindowButtonPointMapper(rect: rect)
        path.addEllipse(in: p.rect(x: 28, y: 8, width: 7, height: 7))
        return path
    }
}

private struct ShatlSVGPathShape: Shape {
    let paths: [String]
    let viewport: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()

        for pathData in paths {
            var parser = ShatlSVGPathParser(pathData: pathData, viewport: viewport, rect: rect)
            path.addPath(parser.parse())
        }

        return path
    }
}

private struct ShatlSVGPathParser {
    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    private let tokens: [Token]
    private let viewport: CGSize
    private let rect: CGRect
    private var index = 0

    init(pathData: String, viewport: CGSize, rect: CGRect) {
        self.tokens = Self.tokenize(pathData)
        self.viewport = viewport
        self.rect = rect
    }

    mutating func parse() -> Path {
        var path = Path()
        var command: Character?
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        while index < tokens.count {
            if case let .command(nextCommand) = tokens[index] {
                index += 1

                if nextCommand == "Z" || nextCommand == "z" {
                    path.closeSubpath()
                    current = subpathStart
                    command = nil
                    continue
                }

                command = nextCommand
            }

            guard let currentCommand = command else { break }

            switch currentCommand {
            case "M", "m":
                guard let x = readNumber(), let y = readNumber() else { return path }
                current = mappedPoint(x, y, relativeTo: currentCommand == "m" ? current : nil)
                subpathStart = current
                path.move(to: current)
                command = currentCommand == "m" ? "l" : "L"

            case "L", "l":
                guard let x = readNumber(), let y = readNumber() else { return path }
                current = mappedPoint(x, y, relativeTo: currentCommand == "l" ? current : nil)
                path.addLine(to: current)

            case "H", "h":
                guard let x = readNumber() else { return path }
                let nextX = currentCommand == "h" ? current.x + scaledX(x) : mappedX(x)
                current = CGPoint(x: nextX, y: current.y)
                path.addLine(to: current)

            case "V", "v":
                guard let y = readNumber() else { return path }
                let nextY = currentCommand == "v" ? current.y + scaledY(y) : mappedY(y)
                current = CGPoint(x: current.x, y: nextY)
                path.addLine(to: current)

            case "C", "c":
                guard
                    let x1 = readNumber(), let y1 = readNumber(),
                    let x2 = readNumber(), let y2 = readNumber(),
                    let x = readNumber(), let y = readNumber()
                else { return path }

                let relativeOrigin = currentCommand == "c" ? current : nil
                let control1 = mappedPoint(x1, y1, relativeTo: relativeOrigin)
                let control2 = mappedPoint(x2, y2, relativeTo: relativeOrigin)
                current = mappedPoint(x, y, relativeTo: relativeOrigin)
                path.addCurve(to: current, control1: control1, control2: control2)

            default:
                return path
            }
        }

        return path
    }

    private mutating func readNumber() -> CGFloat? {
        guard index < tokens.count else { return nil }
        guard case let .number(number) = tokens[index] else { return nil }
        index += 1
        return number
    }

    private func mappedPoint(_ x: CGFloat, _ y: CGFloat, relativeTo origin: CGPoint?) -> CGPoint {
        let point = CGPoint(x: scaledX(x), y: scaledY(y))
        guard let origin else {
            return CGPoint(x: rect.minX + point.x, y: rect.minY + point.y)
        }
        return CGPoint(x: origin.x + point.x, y: origin.y + point.y)
    }

    private func mappedX(_ x: CGFloat) -> CGFloat {
        rect.minX + scaledX(x)
    }

    private func mappedY(_ y: CGFloat) -> CGFloat {
        rect.minY + scaledY(y)
    }

    private func scaledX(_ x: CGFloat) -> CGFloat {
        x * rect.width / viewport.width
    }

    private func scaledY(_ y: CGFloat) -> CGFloat {
        y * rect.height / viewport.height
    }

    private static func tokenize(_ pathData: String) -> [Token] {
        var tokens: [Token] = []
        var numberBuffer = ""
        var previousCharacter: Character?

        func flushNumber() {
            guard !numberBuffer.isEmpty else { return }
            if let value = Double(numberBuffer) {
                tokens.append(.number(CGFloat(value)))
            }
            numberBuffer.removeAll(keepingCapacity: true)
        }

        for character in pathData {
            if isCommand(character) {
                flushNumber()
                tokens.append(.command(character))
            } else if character == "-" || character == "+" {
                if numberBuffer.isEmpty || previousCharacter == "e" || previousCharacter == "E" {
                    numberBuffer.append(character)
                } else {
                    flushNumber()
                    numberBuffer.append(character)
                }
            } else if character.isNumber || character == "." || character == "e" || character == "E" {
                numberBuffer.append(character)
            } else {
                flushNumber()
            }

            previousCharacter = character
        }

        flushNumber()
        return tokens
    }

    private static func isCommand(_ character: Character) -> Bool {
        "MmLlHhVvCcZz".contains(character)
    }
}

private struct ShatlLogomarkAppShape: Shape {
    func path(in rect: CGRect) -> Path {
        ShatlSVGPathShape(
            paths: ["M0 35.2C0 22.8788 0 16.7183 2.39786 12.0122C4.50707 7.87264 7.87264 4.50707 12.0122 2.39786C16.7183 0 22.8788 0 35.2 0H48.8C61.1212 0 67.2817 0 71.9878 2.39786C76.1274 4.50707 79.4929 7.87264 81.6021 12.0122C84 16.7183 84 22.8788 84 35.2V48.8C84 61.1212 84 67.2817 81.6021 71.9878C79.4929 76.1274 76.1274 79.4929 71.9878 81.6021C67.2817 84 61.1212 84 48.8 84H35.2C22.8788 84 16.7183 84 12.0122 81.6021C7.87264 79.4929 4.50707 76.1274 2.39786 71.9878C0 67.2817 0 61.1212 0 48.8V35.2Z"],
            viewport: CGSize(width: 84, height: 84)
        )
        .path(in: rect)
    }
}

private struct ShatlLogomarkAStrokeShape: Shape {
    func path(in rect: CGRect) -> Path {
        ShatlSVGPathShape(
            paths: ["M20.236 49.9821C14.7612 31.1451 28.972 18.8118 42.1744 19.0342C55.4296 19.2575 67.8536 31.4135 64.0772 47.6361C63.043 52.0791 59.3624 58.0043 53.8955 61.4227C49.4457 64.2052 44.8972 64.966 41.3967 63.4563C38.545 62.2264 36.1679 59.0767 36.1679 54.6076C36.1679 51.3452 37.5086 47.9487 40.1008 45.4908C42.6921 43.0337 46.4313 41.7101 50.469 42.0497C55.2507 42.4518 61.999 46.2058 65.5742 53.5797C67.4536 57.4559 68.8814 64.2161 65.5296 70.875"],
            viewport: CGSize(width: 84, height: 84)
        )
        .path(in: rect)
    }
}

private struct ShatlLogomarkAStrokeGlassShape: Shape {
    var lineWidth: CGFloat

    var animatableData: CGFloat {
        get { lineWidth }
        set { lineWidth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        ShatlLogomarkAStrokeShape()
            .path(in: rect)
            .strokedPath(StrokeStyle(lineWidth: lineWidth))
    }
}

private struct ShatlLogomarkStarMorphShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: mapped(interpolated(thinStart, boldStart), in: rect))

        for index in thinSegments.indices {
            let thin = thinSegments[index]
            let bold = boldSegments[index]
            path.addCurve(
                to: mapped(interpolated(thin.end, bold.end), in: rect),
                control1: mapped(interpolated(thin.control1, bold.control1), in: rect),
                control2: mapped(interpolated(thin.control2, bold.control2), in: rect)
            )
        }

        path.closeSubpath()
        return path
    }

    private func interpolated(_ thin: CGPoint, _ bold: CGPoint) -> CGPoint {
        CGPoint(
            x: thin.x + (bold.x - thin.x) * progress,
            y: thin.y + (bold.y - thin.y) * progress
        )
    }

    private func mapped(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width / 84,
            y: rect.minY + point.y * rect.height / 84
        )
    }

    private let thinStart = CGPoint(x: 19.0029, y: 59.0013)
    private let boldStart = CGPoint(x: 17.8294, y: 56.3358)

    private let thinSegments = [
        ShatlMorphCubicSegment(control1: CGPoint(x: 19.2998, y: 59.0013), control2: CGPoint(x: 19.415, y: 59.3223), end: CGPoint(x: 19.5029, y: 59.8724)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 20.0029, y: 62.9999), control2: CGPoint(x: 21.0029, y: 63.9999), end: CGPoint(x: 24.1311, y: 64.4999)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 24.6818, y: 64.5879), control2: CGPoint(x: 25.0029, y: 64.6971), end: CGPoint(x: 25.0029, y: 65.0008)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 25.0029, y: 65.3046), control2: CGPoint(x: 24.6817, y: 65.4119), end: CGPoint(x: 24.1311, y: 65.4999)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 21.0029, y: 65.9999), control2: CGPoint(x: 20.0029, y: 66.9999), end: CGPoint(x: 19.5029, y: 70.1302)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 19.4151, y: 70.6804), control2: CGPoint(x: 19.3076, y: 71.0013), end: CGPoint(x: 19.0029, y: 71.0013)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 18.6982, y: 71.0013), control2: CGPoint(x: 18.5908, y: 70.6804), end: CGPoint(x: 18.5029, y: 70.1302)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 18.0029, y: 66.9999), control2: CGPoint(x: 17.0029, y: 65.9999), end: CGPoint(x: 13.8747, y: 65.4999)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 13.3241, y: 65.4119), control2: CGPoint(x: 13.0029, y: 65.2968), end: CGPoint(x: 13.0029, y: 65.0008)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 13.0029, y: 64.7049), control2: CGPoint(x: 13.3241, y: 64.5879), end: CGPoint(x: 13.8747, y: 64.4999)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 17.0029, y: 63.9999), control2: CGPoint(x: 18.0029, y: 62.9999), end: CGPoint(x: 18.5029, y: 59.8724)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 18.5909, y: 59.3223), control2: CGPoint(x: 18.7061, y: 59.0013), end: CGPoint(x: 19.0029, y: 59.0013)),
    ]

    private let boldSegments = [
        ShatlMorphCubicSegment(control1: CGPoint(x: 18.6194, y: 56.2248), control2: CGPoint(x: 19.3781, y: 56.6457), end: CGPoint(x: 19.8088, y: 57.3172)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 21.2556, y: 59.5731), control2: CGPoint(x: 23.4749, y: 61.245), end: CGPoint(x: 26.0422, y: 62.014)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 26.807, y: 62.2431), control2: CGPoint(x: 27.4212, y: 62.8569), end: CGPoint(x: 27.5323, y: 63.6475)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 27.6434, y: 64.4381), control2: CGPoint(x: 27.2222, y: 65.1974), end: CGPoint(x: 26.5502, y: 65.6284)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 24.2942, y: 67.0756), control2: CGPoint(x: 22.6218, y: 69.2953), end: CGPoint(x: 21.853, y: 71.8629)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 21.6241, y: 72.6272), control2: CGPoint(x: 21.0109, y: 73.2409), end: CGPoint(x: 20.2209, y: 73.3519)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 19.4309, y: 73.4629), control2: CGPoint(x: 18.6722, y: 73.042), end: CGPoint(x: 18.2416, y: 72.3705)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 16.7948, y: 70.1142), control2: CGPoint(x: 14.5753, y: 68.4415), end: CGPoint(x: 12.0078, y: 67.6722)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 11.243, y: 67.4431), control2: CGPoint(x: 10.6289, y: 66.8294), end: CGPoint(x: 10.5177, y: 66.0388)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 10.4066, y: 65.2481), control2: CGPoint(x: 10.8278, y: 64.4888), end: CGPoint(x: 11.4999, y: 64.0578)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 13.7558, y: 62.611), control2: CGPoint(x: 15.4283, y: 60.392), end: CGPoint(x: 16.1972, y: 57.8248)),
        ShatlMorphCubicSegment(control1: CGPoint(x: 16.4261, y: 57.0606), control2: CGPoint(x: 17.0394, y: 56.4469), end: CGPoint(x: 17.8294, y: 56.3358)),
    ]
}

private struct ShatlWordmarkStrokeShape: Shape {
    func path(in rect: CGRect) -> Path {
        ShatlSVGPathShape(
            paths: ["M140.398 42.7357C149.205 39.8762 158.761 38.7572 168.38 38.7572M209.435 74.3149C205.422 77.3299 201.608 78.3342 198.332 78.4149C180.011 78.8659 176.242 44.5554 180.761 23.7089C183.28 12.0891 187.546 6.37399 194.304 7.14705C197.021 7.45787 200.412 9.27972 201.643 14.4513C202.767 19.1758 202.33 23.5583 201.705 27.8165C198.31 50.9622 181.107 84.3489 165.666 77.2988C153.548 71.7662 148.801 45.1602 154.298 21.7866C149.364 43.5439 154 64.8486 147.144 74.4703C145.269 77.1011 142.176 78.648 139.273 78.542C132.435 78.2923 129.563 72.2014 127.565 66.9175C123.59 62.7672 118.758 61.9444 115.351 63.2809C112.157 64.534 109.852 67.6534 109.824 71.5797C109.826 77.4853 115.526 80.2689 121.006 77.4231C124.527 75.5952 128.254 71.2119 129.311 66.6066C131.966 55.0442 123.003 46.7142 113.571 46.7142C105.17 46.7142 96.4846 53.997 95.8349 68.2229C95.5226 75.0609 91.4627 78.2313 88.0274 78.5421C85.8144 78.7423 83.7583 78.1155 82.0312 76.5528C80.657 75.3096 79.2135 73.1534 79.5328 69.404C79.8451 65.7364 80.8132 63.2188 81.2816 60.266C82.2447 54.1953 78.7544 49.8947 74.411 48.9522C68.4399 47.6565 60.7923 52.4643 57.4692 63.6331C55.9921 68.5978 55.1209 74.3194 55.4517 82.0033C53.0132 63.5944 48.5524 22.2218 58.4211 10.2648C60.4723 7.77957 63.8881 6.34509 67.5404 7.30248C77.8801 10.0129 77.1593 31.2977 61.0733 55.4171C49.3708 72.964 34.4363 85.4112 19.0375 74.3771C28.5626 81.8678 37.0885 76.1798 38.2753 70.3986C39.462 64.6174 36.0892 60.6389 31.2172 57.7794C26.3453 54.9198 23.0349 50.6927 26.4703 42.7358C21.6275 54.1965 13.5448 66.1355 5.43481 75.0352"],
            viewport: ShatlWordmarkMetrics.viewport
        )
        .path(in: rect)
    }
}

private struct ShatlWordmarkStrokeGlassShape: Shape {
    var lineWidth: CGFloat

    var animatableData: CGFloat {
        get { lineWidth }
        set { lineWidth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        ShatlWordmarkStrokeShape()
            .path(in: rect)
            .strokedPath(StrokeStyle(lineWidth: lineWidth))
    }
}

private struct PerformanceSpeedometerPointMapper {
    let rect: CGRect

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(
            x: rect.minX + x * rect.width / 48,
            y: rect.minY + y * rect.height / 48
        )
    }
}

private struct WindowButtonPointMapper {
    let rect: CGRect

    func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX + x * rect.width / 76,
            y: rect.minY + y * rect.height / 76,
            width: width * rect.width / 76,
            height: height * rect.height / 76
        )
    }
}
