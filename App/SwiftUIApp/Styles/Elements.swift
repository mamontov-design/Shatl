// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import SwiftUI

enum ShatlButtonRole {
    case borderedNeutral
    case borderedColored
    case borderedMonochrome
}

enum ShatlIconSize {
    static let small: CGFloat = 16
}

enum ShatlMetricLayout {
    static let contentHeight: CGFloat = 15
    static let containerHeight: CGFloat = 27
}

enum ShatlBottomChipLayout {
    static let legacyEdgePadding: CGFloat = 12
    static let modernEdgePadding: CGFloat = 6
    static let modernCornerRadius: CGFloat = 10
    static let cardGap: CGFloat = 6
    static let standardListBottomPadding: CGFloat = 8
    static let modernListBottomPadding = modernEdgePadding
        + ShatlMetricLayout.containerHeight
        + cardGap
}

struct MetricSetDiagnosticsContext: Equatable {
    var source: String
    var torrentID: UUID?
    var groupID: String?
    var cardStatus: TorrentStatus?
    var progressPercent: Int?
    var downloadSpeedBytesPerSecond: Int64?
    var etaSeconds: Int?

    func withGroupID(_ groupID: String?) -> MetricSetDiagnosticsContext {
        var context = self
        context.groupID = groupID
        return context
    }
}

struct ShatlOnboardingProgressDots: View {
    let currentStep: Int
    var stepCount = 5

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...stepCount, id: \.self) { step in
                Circle()
                    .fill(fillColor(for: step))
                    .frame(width: 6, height: 6)
                    .overlay {
                        Circle()
                            .strokeBorder(strokeColor(for: step), lineWidth: strokeWidth(for: step))
                    }
            }
        }
        .animation(ShatlMotion.interface, value: currentStep)
    }

    private func fillColor(for step: Int) -> Color {
        if step == currentStep {
            return ShatlColor.accent
        }

        if step < currentStep {
            return ShatlColor.onboardingOutline
        }

        return ShatlColor.onboardingForeground
    }

    private func strokeColor(for step: Int) -> Color {
        ShatlColor.onboardingOutline
    }

    private func strokeWidth(for step: Int) -> CGFloat {
        step > currentStep ? 1 : 0
    }
}

enum ShatlTextContent {
    case verbatim(String)
    case localized(String)

    var text: Text {
        switch self {
        case .verbatim(let value):
            Text(verbatim: value)
        case .localized(let key):
            Text(LocalizedStringKey(key))
        }
    }
}

struct ShatlTabButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .shatlTypography(ShatlTypography.bodyMedium)
                .foregroundStyle(isActive ? ShatlColor.typographyPrimary : ShatlColor.typographySecondary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: ShatlCornerRadius.tab, style: .continuous)
                            .fill(ShatlColor.metricBackground)
                            .transition(ShatlMotion.appearFromTop)
                    }
                }
                .animation(ShatlMotion.metricResize, value: isActive)
                .clipShape(RoundedRectangle(cornerRadius: ShatlCornerRadius.tab, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: ShatlCornerRadius.tab, style: .continuous))
        }
        .buttonStyle(.plain)
        .shatlShadow(ShatlShadow.activeTab, isEnabled: isActive)
        .frame(maxWidth: .infinity)
    }
}

struct ShatlButton: View {
    let title: ShatlTextContent?
    var systemImage: String?
    let role: ShatlButtonRole
    var isDisabled = false
    var fillsWidth = false
    let action: () -> Void

    init(
        title: String,
        role: ShatlButtonRole,
        isDisabled: Bool = false,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = .verbatim(title)
        self.systemImage = nil
        self.role = role
        self.isDisabled = isDisabled
        self.fillsWidth = fillsWidth
        self.action = action
    }

    init(
        localizedTitle key: String,
        role: ShatlButtonRole,
        isDisabled: Bool = false,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = .localized(key)
        self.systemImage = nil
        self.role = role
        self.isDisabled = isDisabled
        self.fillsWidth = fillsWidth
        self.action = action
    }

    init(
        systemImage: String,
        role: ShatlButtonRole,
        isDisabled: Bool = false,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = nil
        self.systemImage = systemImage
        self.role = role
        self.isDisabled = isDisabled
        self.fillsWidth = fillsWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: ShatlIconSize.small, height: ShatlIconSize.small, alignment: .center)
                }

                if let title {
                    title.text
                        .shatlTypography(ShatlTypography.bodyMedium)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: ShatlCornerRadius.button, style: .continuous))
        }
        .buttonStyle(ShatlPressedButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }

    private var backgroundColor: Color {
        switch role {
        case .borderedNeutral:
            ShatlColor.buttonNeutral
        case .borderedColored:
            ShatlColor.accent
        case .borderedMonochrome:
            ShatlColor.onboardingButtonBody
        }
    }

    private var foregroundColor: Color {
        switch role {
        case .borderedNeutral:
            ShatlColor.typographyPrimary
        case .borderedColored:
            ShatlColor.typographyPrimaryInverted
        case .borderedMonochrome:
            ShatlColor.onboardingButtonText
        }
    }
}

struct ShatlModalCloseButton: View {
    var action: () -> Void
    var iconSize: CGFloat = ShatlIconSize.small
    var foregroundColor: Color = ShatlColor.typographyTertiary
    var hoverForegroundColor: Color = ShatlColor.cerisePink

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(isHovered ? hoverForegroundColor : foregroundColor)
                .frame(width: iconSize, height: iconSize, alignment: .center)
        }
        .buttonStyle(.plain)
        .frame(width: iconSize, height: iconSize)
        .contentShape(Rectangle())
        .onHover { isHovered in
            withAnimation(ShatlMotion.interface) {
                self.isHovered = isHovered
            }
        }
    }
}

struct ShatlMessageBlock: View {
    let title: String
    let message: String
    var buttonTitle: String?
    var buttonAction: (() -> Void)?
    var localeOverride: AppLocaleOverride = .system

    private let cornerRadius: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            labelGroup

            if let buttonTitle, let buttonAction {
                ShatlButton(
                    title: buttonTitle,
                    role: .borderedNeutral,
                    fillsWidth: true,
                    action: buttonAction
                )
            }
        }
        .padding(8)
        .frame(maxWidth: 250, alignment: .leading)
        .background(ShatlColor.backgroundTertiary)
        .clipShape(messageBlockShape)
        .overlay {
            messageBlockShape
                .strokeBorder(ShatlColor.accent, lineWidth: 1)
        }
        .shatlShadow(ShatlShadow.messageBlock)
    }

    private var labelGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            headers
            labelDescription
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headers: some View {
        HStack(alignment: .top, spacing: 6) {
            labelHeader
            labelError
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var labelError: some View {
        Text(
            L10n.string(
                "message_block.error",
                localeOverride: localeOverride,
                defaultValue: "Ошибка"
            )
        )
        .shatlTypography(ShatlTypography.metricSemibold)
        .foregroundStyle(Color.red)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var labelHeader: some View {
        Text(title)
            .shatlTypography(ShatlTypography.bodySemibold)
            .foregroundStyle(ShatlColor.typographyPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var labelDescription: some View {
        Text(message)
            .shatlTypography(ShatlTypography.captionRegular)
            .foregroundStyle(ShatlColor.typographySecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var messageBlockShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

struct ShatlSettingsParameter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 12) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShatlColor.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: ShatlCornerRadius.container, style: .continuous))
    }
}

struct ShatlSettingsParameterHeader: View {
    let title: ShatlTextContent

    init(title: String) {
        self.title = .verbatim(title)
    }

    init(localizedTitle key: String) {
        self.title = .localized(key)
    }

    var body: some View {
        title.text
            .shatlTypography(ShatlTypography.bodySemibold)
            .foregroundStyle(ShatlColor.typographyPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 24)
            .padding(.bottom, 2)
    }
}

struct ShatlSettingsParameterCaption: View {
    let text: ShatlTextContent
    let lines: [ShatlTextContent]?

    init(text: String) {
        self.text = .verbatim(text)
        self.lines = nil
    }

    init(localizedText key: String) {
        self.text = .localized(key)
        self.lines = nil
    }

    init(localizedLines keys: [String]) {
        self.text = .localized(keys.first ?? "")
        self.lines = keys.map { .localized($0) }
    }

    var body: some View {
        Group {
            if let lines {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        captionText(line)
                    }
                }
            } else if let separatedText {
                VStack(alignment: .leading, spacing: 4) {
                    captionText(separatedText.first)
                    captionText(separatedText.rest)
                }
            } else {
                captionText(text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private var separatedText: (first: ShatlTextContent, rest: ShatlTextContent)? {
        guard case .verbatim(let text) = text else { return nil }
        guard let newlineIndex = text.firstIndex(of: "\n") else { return nil }

        let first = String(text[..<newlineIndex])
        let restStart = text.index(after: newlineIndex)
        let rest = String(text[restStart...])

        return (.verbatim(first), .verbatim(rest))
    }

    private func captionText(_ value: ShatlTextContent) -> some View {
        value.text
            .shatlTypography(ShatlTypography.captionRegular)
            .foregroundStyle(ShatlColor.typographyTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShatlSettingsParameterDivider: View {
    var body: some View {
        Rectangle()
            .fill(ShatlColor.outlineTertiary)
            .frame(height: 1)
    }
}

struct ShatlSettingsToggleRow: View {
    let title: ShatlTextContent
    @Binding var isOn: Bool
    var isEnabled = true

    init(title: String, isOn: Binding<Bool>, isEnabled: Bool = true) {
        self.title = .verbatim(title)
        self._isOn = isOn
        self.isEnabled = isEnabled
    }

    init(localizedTitle key: String, isOn: Binding<Bool>, isEnabled: Bool = true) {
        self.title = .localized(key)
        self._isOn = isOn
        self.isEnabled = isEnabled
    }

    var body: some View {
        HStack(spacing: 16) {
            title.text
                .shatlTypography(ShatlTypography.bodyRegular)
                .foregroundStyle(ShatlColor.typographyPrimary)
                .opacity(isEnabled ? 1 : 0.5)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!isEnabled)
        }
    }
}

struct ShatlSettingsInputCard<Content: View>: View {
    let title: ShatlTextContent
    let isSelected: Bool
    var isEnabled = true
    var labelPlacement: ShatlSettingsInputCardLabelPlacement = .belowCard
    var imageContainerHeight: CGFloat? = nil
    var imageContentVerticalPadding: CGFloat? = nil
    var overlaysSelectionMark = false
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var isActivationPulseActive = false
    @State private var activationPulseTask: Task<Void, Never>?

    init(
        title: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        labelPlacement: ShatlSettingsInputCardLabelPlacement = .belowCard,
        imageContainerHeight: CGFloat? = nil,
        imageContentVerticalPadding: CGFloat? = nil,
        overlaysSelectionMark: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = .verbatim(title)
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.labelPlacement = labelPlacement
        self.imageContainerHeight = imageContainerHeight
        self.imageContentVerticalPadding = imageContentVerticalPadding
        self.overlaysSelectionMark = overlaysSelectionMark
        self.action = action
        self.content = content()
    }

    init(
        localizedTitle key: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        labelPlacement: ShatlSettingsInputCardLabelPlacement = .belowCard,
        imageContainerHeight: CGFloat? = nil,
        imageContentVerticalPadding: CGFloat? = nil,
        overlaysSelectionMark: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = .localized(key)
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.labelPlacement = labelPlacement
        self.imageContainerHeight = imageContainerHeight
        self.imageContentVerticalPadding = imageContentVerticalPadding
        self.overlaysSelectionMark = overlaysSelectionMark
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: activate) {
            VStack(spacing: labelPlacement == .belowCard ? 6 : 0) {
                imageContainer

                if labelPlacement == .belowCard {
                    labelContainer
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ShatlSettingsInputCardButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onDisappear {
            stopActivationPulse()
        }
    }

    private var imageContainer: some View {
        VStack(spacing: 0) {
            if labelPlacement == .belowCard {
                if overlaysSelectionMark {
                    content
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if usesCompactImageContainer {
                    Color.clear
                        .overlay(alignment: .top) {
                            content
                                .padding(.top, 25)
                        }
                } else {
                    HStack {
                        Spacer(minLength: 0)

                        selectMark
                    }

                    content
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                labelContainer
                    .frame(minHeight: 42)
                    .overlay(alignment: .topTrailing) {
                        selectMark
                    }
            }
        }
        .padding(.top, imageContainerTopPadding)
        .padding(.horizontal, 10)
        .padding(.bottom, imageContainerBottomPadding)
        .frame(maxWidth: .infinity)
        .frame(height: imageContainerHeight)
        .background(imageBackground)
        .clipShape(RoundedRectangle(cornerRadius: ShatlCornerRadius.container, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if usesCompactImageContainer || overlaysSelectionMark {
                selectMark
                    .padding(.top, 10)
                    .padding(.trailing, 10)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: ShatlCornerRadius.container, style: .continuous)
                    .strokeBorder(ShatlColor.accent.opacity(0.75), lineWidth: 1)
            }
        }
        .animation(ShatlMotion.cardState, value: isSelected)
    }

    private var usesCompactImageContainer: Bool {
        labelPlacement == .belowCard && imageContainerHeight != nil && !overlaysSelectionMark
    }

    private var imageContainerTopPadding: CGFloat {
        imageContentVerticalPadding ?? (usesCompactImageContainer ? 0 : 10)
    }

    private var imageContainerBottomPadding: CGFloat {
        if let imageContentVerticalPadding {
            return imageContentVerticalPadding
        }

        if usesCompactImageContainer {
            return 0
        }

        return labelPlacement == .belowCard ? 26 : 10
    }

    private var selectMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(ShatlColor.accent)
            .frame(width: 15, height: 15)
            .scaleEffect(isSelected ? 1 : 0.65, anchor: .center)
            .opacity(isSelected ? 1 : 0)
            .animation(
                isSelected ? ShatlMotion.selectedIndicatorAppear : ShatlMotion.selectedIndicatorDisappear,
                value: isSelected
            )
    }

    private var labelContainer: some View {
        ZStack {
            labelText(
                typography: ShatlTypography.bodyMedium,
                color: ShatlColor.typographySecondary
            )
            .opacity(isSelected ? 0 : 1)

            labelText(
                typography: ShatlTypography.bodySemibold,
                color: ShatlColor.accent
            )
            .opacity(isSelected ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.text)
        .padding(.horizontal, 12)
        .frame(
            maxWidth: .infinity,
            alignment: labelPlacement == .belowCard ? .leading : .center
        )
        .animation(ShatlMotion.cardState, value: isSelected)
    }

    private func labelText(typography: ShatlTextStyle, color: Color) -> some View {
        title.text
            .shatlTypography(typography)
            .foregroundStyle(color)
            .multilineTextAlignment(labelPlacement == .belowCard ? .leading : .center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: .infinity,
                alignment: labelPlacement == .belowCard ? .leading : .center
            )
    }

    private var imageBackground: Color {
        isActivationPulseActive
            ? ShatlColor.backgroundPrimary
            : ShatlColor.backgroundSecondary
    }

    private func activate() {
        startActivationPulse()
        action()
    }

    private func startActivationPulse() {
        activationPulseTask?.cancel()

        withAnimation(ShatlMotion.inputCardActivationPulseIn) {
            isActivationPulseActive = true
        }

        activationPulseTask = Task { @MainActor in
            do {
                try await Task.sleep(for: ShatlMotion.inputCardActivationPulseHoldDuration)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            withAnimation(ShatlMotion.inputCardActivationPulseOut) {
                isActivationPulseActive = false
            }

            activationPulseTask = nil
        }
    }

    private func stopActivationPulse() {
        activationPulseTask?.cancel()
        activationPulseTask = nil
        isActivationPulseActive = false
    }
}

enum ShatlSettingsInputCardLabelPlacement {
    case belowCard
    case insideCard
}

private struct ShatlSettingsInputCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

enum TorrentCardPreviewShadowStyle {
    case onboarding
    case settings
}

private struct TorrentCardPreviewShadowModifier: ViewModifier {
    let style: TorrentCardPreviewShadowStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .onboarding:
            content.shatlShadow(ShatlShadow.onboardingCard)
        case .settings:
            content.shatlShadow(ShatlShadow.settingsTorrentPreview)
        }
    }
}

struct TorrentCardPreviewView: View {
    private enum Layout {
        static let cardWidth: CGFloat = 376
        static let estimatedCompactCardHeight: CGFloat = 116
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var localeOverride: AppLocaleOverride = .russian
    var metricsMode: MetricsPresentationMode = .simplified
    var colorizesDownloadSpeed = false
    var downloadSpeedOutlineFlashTrigger = 0
    var initiallyExpanded = false
    var centersExpandedCard = false
    var allowsExpansionToggle = true
    var showsExpansionToggle = true
    var pulsesMetricSetOutlines = false
    var metricSetOutlineFlashTrigger = 0
    var metricSetOutlineFlashColor = ShatlColor.neonBlue
    var progressBarFillColorOverride: Color? = nil
    var progressGroupBackgroundColorOverride: Color? = nil
    var progressGroupForegroundColorOverride: Color? = nil
    var usesProductionProgressColors = false
    var cardBackgroundColorOverride: Color? = nil
    var cardOutlineColorOverride: Color? = nil
    var shadowStyle: TorrentCardPreviewShadowStyle = .onboarding
    var cardWidth: CGFloat? = Layout.cardWidth

    @State private var isExpanded: Bool
    @State private var demoProgress = 0.01
    @State private var demoTick = 0
    @State private var compactCardHeight: CGFloat?
    @State private var isExpandHintAnimating = false

    init(
        localeOverride: AppLocaleOverride = .russian,
        metricsMode: MetricsPresentationMode = .simplified,
        colorizesDownloadSpeed: Bool = false,
        downloadSpeedOutlineFlashTrigger: Int = 0,
        initiallyExpanded: Bool = false,
        centersExpandedCard: Bool = false,
        allowsExpansionToggle: Bool = true,
        showsExpansionToggle: Bool = true,
        pulsesMetricSetOutlines: Bool = false,
        metricSetOutlineFlashTrigger: Int = 0,
        metricSetOutlineFlashColor: Color = ShatlColor.neonBlue,
        progressBarFillColorOverride: Color? = nil,
        progressGroupBackgroundColorOverride: Color? = nil,
        progressGroupForegroundColorOverride: Color? = nil,
        usesProductionProgressColors: Bool = false,
        cardBackgroundColorOverride: Color? = nil,
        cardOutlineColorOverride: Color? = nil,
        shadowStyle: TorrentCardPreviewShadowStyle = .onboarding,
        cardWidth: CGFloat? = Layout.cardWidth
    ) {
        self.localeOverride = localeOverride
        self.metricsMode = metricsMode
        self.colorizesDownloadSpeed = colorizesDownloadSpeed
        self.downloadSpeedOutlineFlashTrigger = downloadSpeedOutlineFlashTrigger
        self.initiallyExpanded = initiallyExpanded
        self.centersExpandedCard = centersExpandedCard
        self.allowsExpansionToggle = allowsExpansionToggle
        self.showsExpansionToggle = showsExpansionToggle
        self.pulsesMetricSetOutlines = pulsesMetricSetOutlines
        self.metricSetOutlineFlashTrigger = metricSetOutlineFlashTrigger
        self.metricSetOutlineFlashColor = metricSetOutlineFlashColor
        self.progressBarFillColorOverride = progressBarFillColorOverride
        self.progressGroupBackgroundColorOverride = progressGroupBackgroundColorOverride
        self.progressGroupForegroundColorOverride = progressGroupForegroundColorOverride
        self.usesProductionProgressColors = usesProductionProgressColors
        self.cardBackgroundColorOverride = cardBackgroundColorOverride
        self.cardOutlineColorOverride = cardOutlineColorOverride
        self.shadowStyle = shadowStyle
        self.cardWidth = cardWidth
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        Group {
            if centersExpandedCard {
                demoCardContainer
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                GeometryReader { proxy in
                    demoCardContainer
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .offset(y: compactCardTop(in: proxy.size.height))
                }
            }
        }
        .onPreferenceChange(TorrentCardPreviewHeightPreferenceKey.self) { height in
            guard height > 0 else { return }

            Task { @MainActor in
                guard !isExpanded else { return }
                guard compactCardHeight.map({ abs($0 - height) > 0.5 }) ?? true else { return }

                compactCardHeight = height
            }
        }
        .task {
            await runDemoProgress()
        }
        .onAppear {
            startExpandHintAnimationIfNeeded()
        }
    }

    private var demoCardContainer: some View {
        ZStack(alignment: .topTrailing) {
            demoCard
                .frame(width: cardWidth)
                .frame(
                    minWidth: cardWidth,
                    idealWidth: cardWidth,
                    maxWidth: cardWidth ?? .infinity
                )
                .background(cardHeightReader)
                .modifier(TorrentCardPreviewShadowModifier(style: shadowStyle))
                .environment(\.shatlMetricSetOutlinePulseEnabled, pulsesMetricSetOutlines)
                .environment(\.shatlMetricSetOutlineFlashTrigger, metricSetOutlineFlashTrigger)
                .environment(\.shatlDownloadSpeedOutlineFlashTrigger, downloadSpeedOutlineFlashTrigger)
                .environment(\.shatlMetricSetBounceEnabled, false)
                .environment(\.shatlMetricSetOutlinePulseColor, ShatlColor.neonBlue)
                .environment(\.shatlMetricSetOutlineFlashColor, metricSetOutlineFlashColor)

            if !centersExpandedCard, showsExpansionToggle {
                expandHint
                    .offset(x: -2, y: 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: cardWidth)
        .frame(maxWidth: cardWidth == nil ? .infinity : cardWidth)
    }

    private var demoCard: some View {
        TorrentCardView(
            row: TorrentRowState.previewDemo(
                progress: demoProgress,
                tick: demoTick,
                isExpanded: isExpanded,
                metricsMode: metricsMode,
                colorizesDownloadSpeed: colorizesDownloadSpeed,
                localeOverride: localeOverride
            ),
            resolvePrimaryLocation: { nil },
            onSelect: {},
            onToggleExpanded: toggleExpanded,
            onOpen: {},
            onRevealInFinder: {},
            onToggleRunningState: {},
            onRedownload: {},
            onChooseAnotherFolder: {},
            onRemove: {},
            onRemoveWithFiles: {},
            presentationMode: .onboardingDemo,
            isExpansionToggleEnabled: allowsExpansionToggle,
            showsExpansionToggle: showsExpansionToggle,
            progressBarFillColorOverride: progressBarFillColorOverride,
            progressGroupBackgroundColorOverride: progressGroupBackgroundColorOverride,
            progressGroupForegroundColorOverride: progressGroupForegroundColorOverride,
            usesProductionProgressColors: usesProductionProgressColors,
            cardBackgroundColorOverride: cardBackgroundColorOverride,
            cardOutlineColorOverride: cardOutlineColorOverride
        )
    }

    private var expandHint: some View {
        Circle()
            .fill(expandHintColor)
            .frame(width: 34, height: 34)
            .scaleEffect(isExpandHintAnimating && !reduceMotion ? 1.24 : 0.94)
            .blendMode(expandHintBlendMode)
    }

    private var expandHintColor: Color {
        ShatlColor.neonBlue.opacity(0.5)
    }

    private var expandHintBlendMode: BlendMode {
        colorScheme == .dark ? .plusLighter : .plusDarker
    }

    private func toggleExpanded() {
        guard allowsExpansionToggle else { return }

        withAnimation(ShatlMotion.cardLayout) {
            isExpanded.toggle()
        }
    }

    private func compactCardTop(in presentationHeight: CGFloat) -> CGFloat {
        let measuredCompactHeight = compactCardHeight ?? Layout.estimatedCompactCardHeight
        return max(0, (presentationHeight - measuredCompactHeight) / 2)
    }

    private func runDemoProgress() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.linear(duration: 0.85)) {
                    demoProgress = demoProgress >= 0.99 ? 0.01 : min(0.99, demoProgress + 0.01)
                    demoTick += 1
                }
            }
        }
    }

    private func startExpandHintAnimationIfNeeded() {
        guard !centersExpandedCard, showsExpansionToggle, !reduceMotion else { return }

        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            isExpandHintAnimating = true
        }
    }

    private var cardHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: TorrentCardPreviewHeightPreferenceKey.self, value: proxy.size.height)
        }
    }
}

private extension TorrentRowState {
    static func previewDemo(
        progress: Double,
        tick: Int,
        isExpanded: Bool,
        metricsMode: MetricsPresentationMode,
        colorizesDownloadSpeed: Bool = false,
        localeOverride: AppLocaleOverride
    ) -> TorrentRowState {
        let record = TorrentRecord.previewDemo(progress: progress, tick: tick)
        let expandedMetricGroups = TorrentPresentation.expandedMetricGroups(
            for: record,
            mode: metricsMode,
            localeOverride: localeOverride
        )

        return TorrentRowState(
            id: record.id,
            title: L10n.string(
                "onboarding.expanded_card.demo_title",
                localeOverride: localeOverride,
                defaultValue: "Торрент"
            ),
            originalTitle: record.originalName,
            hasAlias: false,
            status: record.status,
            statusTitle: L10n.string(
                "torrent.status.downloading",
                localeOverride: localeOverride,
                defaultValue: "Загружается"
            ),
            progress: record.progress,
            downloadSpeedBytesPerSecond: record.metrics.downloadSpeedBytesPerSecond,
            uploadSpeedBytesPerSecond: record.metrics.uploadSpeedBytesPerSecond,
            visibleProgressPercent: record.visibleProgressPercent,
            compactTransferMetricSet: TorrentPresentation.compactTransferMetricSet(
                for: record,
                mode: metricsMode,
                localeOverride: localeOverride
            ),
            compactMetrics: TorrentPresentation.compactMetrics(
                for: record,
                mode: metricsMode,
                localeOverride: localeOverride
            ),
            expandedMetrics: isExpanded
                ? TorrentPresentation.expandedMetrics(
                    for: record,
                    mode: metricsMode,
                    localeOverride: localeOverride
                )
                : [],
            expandedMetricGroups: expandedMetricGroups,
            metricsMode: metricsMode,
            colorizesDownloadSpeed: colorizesDownloadSpeed,
            errorState: nil,
            isSelected: false,
            isExpanded: isExpanded,
            canToggleRunningState: false,
            canRemoveFromList: false,
            canRemoveWithFiles: false,
            navigationAvailabilityKey: "torrent-card-preview-demo",
            localeOverride: localeOverride
        )
    }
}

private extension TorrentRecord {
    static func previewDemo(progress: Double, tick: Int) -> TorrentRecord {
        let clampedProgress = min(max(progress, 0), 0.99)
        let downloadSpeedBytes = (6 + tick % 9) * 1_024 * 1_024
        let uploadSpeedBytes = (420 + (tick * 37) % 460) * 1_024
        let totalBytes = 7_700_000_000
        let uploadedBytes = 120_000_000 + Int64(tick) * 9_500_000
        let remainingSeconds = max(1, Int((1 - clampedProgress) * 4_800))

        return TorrentRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            attemptID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            infoHash: "torrent-card-preview-demo",
            originalName: "Torrent Card Preview",
            alias: nil,
            progress: clampedProgress,
            status: .downloading,
            metrics: TorrentMetrics(
                downloadSpeedBytesPerSecond: Int64(downloadSpeedBytes),
                uploadSpeedBytesPerSecond: Int64(uploadSpeedBytes),
                etaSeconds: remainingSeconds,
                seeds: 108 + tick % 37,
                peers: 18 + (tick * 3) % 23,
                uploadedBytes: uploadedBytes,
                totalBytes: Int64(totalBytes),
                selectedBytes: Int64(totalBytes)
            ),
            canonicalSavePath: "/Users/example/Downloads",
            selectedFileIndices: [0],
            selectedFileRelativePaths: ["Torrent Card Preview"],
            selectedFileCount: 1,
            totalFileCount: 1,
            materializedSelectionFootprint: nil,
            persistentIssue: nil,
            runtimeErrorState: nil,
            lastKnownProgress: clampedProgress,
            resumeCheckpointedAt: nil,
            resumeCheckpointProgress: nil,
            stopAfterDownload: false
        )
    }
}

private struct TorrentCardPreviewHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ShatlMetricItem: View {
    let item: MetricItemPresentation
    var iconColorOverride: Color? = nil
    var speedPalette: ShatlSpeedMetricPalette? = nil
    var showsSpeedBadge = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shatlAnimationMode) private var animationMode

    var body: some View {
        HStack(spacing: 5) {
            if let iconName = item.iconName {
                Image(systemName: iconName)
                    .shatlTypography(iconTypography(for: iconName))
                    .foregroundStyle(iconColor)
                    .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
            }

            if let number = item.number {
                HStack(spacing: 2) {
                    metricNumber(number)

                    if let unit = item.unit {
                        Text(unit)
                            .shatlTypography(ShatlTypography.metricSemibold)
                            .foregroundStyle(speedPalette?.label ?? ShatlColor.typographyTertiary)
                            .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.leading, item.iconName == nil ? 5 : 3)
        .padding(.trailing, 5)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(speedPalette?.badge ?? .clear)
                .opacity(showsSpeedBadge ? 1 : 0)
        }
        .animation(ShatlMotion.speedMetricColor, value: speedPalette)
        .animation(ShatlMotion.speedMetricColor, value: showsSpeedBadge)
    }

    private var iconColor: Color {
        if let speedPalette { return speedPalette.icon }

        if let iconColorOverride {
            return iconColorOverride
        }

        return item.usesAccentIcon ? ShatlColor.accent : ShatlColor.typographySecondary
    }

    @ViewBuilder
    private func metricNumber(_ number: String) -> some View {
        let text = Text(number)
            .shatlTypography(ShatlTypography.metricSemibold)
            .foregroundStyle(speedPalette?.label ?? ShatlColor.typographyPrimary)
            .monospacedDigit()
            .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
            .fixedSize(horizontal: true, vertical: false)

        if animationMode == .lively, !reduceMotion {
            text.contentTransition(.numericText())
        } else {
            text
        }
    }

    private func iconTypography(for iconName: String) -> ShatlTextStyle {
        switch iconName {
        case "tortoise.fill", "hare.fill", "bolt.fill":
            ShatlTypography.groupSemibold
        default:
            ShatlTypography.metricSemibold
        }
    }
}

private struct MetricSetBounceValues {
    var scale: CGFloat = 1
    var outlineOpacity: CGFloat = 0
    var shadowProgress: Double = 0
}

private nonisolated struct MetricSetBounceOutlineOpacityKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private extension EnvironmentValues {
    nonisolated var metricSetBounceOutlineOpacity: CGFloat {
        get { self[MetricSetBounceOutlineOpacityKey.self] }
        set { self[MetricSetBounceOutlineOpacityKey.self] = newValue }
    }
}

private struct MetricSetOutlineView: View {
    let baseColor: Color
    let pulseColor: Color
    let flashColor: Color
    let pulseEnabled: Bool
    let flashOpacity: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.metricSetBounceOutlineOpacity) private var bounceHighlightOpacity

    var body: some View {
        ZStack {
            if pulseEnabled, !reduceMotion {
                PhaseAnimator([false, true]) { isHighlighted in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isHighlighted
                                ? pulseColor
                                : baseColor,
                            lineWidth: 1
                        )
                } animation: { _ in
                    .easeInOut(duration: 0.65)
                }
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(baseColor, lineWidth: 1)
            }

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(ShatlColor.accent, lineWidth: 1)
                .opacity(bounceHighlightOpacity)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(flashColor, lineWidth: 1)
                .opacity(flashOpacity)
        }
    }
}

struct ShatlMetricSet: View {
    let items: [MetricItemPresentation]
    var metricIconColorOverride: Color? = nil
    var backgroundColorOverride: Color? = nil
    var outlineColorOverride: Color? = nil
    var colorizesDownloadSpeed = false
    var diagnosticsContext: MetricSetDiagnosticsContext? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shatlAnimationMode) private var animationMode
    @Environment(\.shatlMetricSetOutlinePulseEnabled) private var metricSetOutlinePulseEnabled
    @Environment(\.shatlMetricSetOutlineFlashTrigger) private var metricSetOutlineFlashTrigger
    @Environment(\.shatlDownloadSpeedOutlineFlashTrigger) private var downloadSpeedOutlineFlashTrigger
    @Environment(\.shatlMetricSetBounceEnabled) private var metricSetBounceEnabled
    @Environment(\.shatlMetricSetOutlinePulseColor) private var metricSetOutlinePulseColor
    @Environment(\.shatlMetricSetOutlineFlashColor) private var metricSetOutlineFlashColor
    @Namespace private var metricSetNamespace
    @State private var bounceToken = 0
    @State private var bounceTrigger = 0
    @State private var outlineFlashToken = 0
    @State private var outlineFlashOpacity: CGFloat = 0
    @State private var lastMetricSetSize: CGSize?

    var body: some View {
        let metricBounceShadow = ShatlShadow.metricBounce.appearance(for: colorScheme)?.primary
            ?? ShatlShadowLayer(opacity: 0, radius: 0)
        let metricBounceColor = ShatlColor.shadowKeyColor
        let restShadow = ShatlShadow.metricRest.appearance(for: colorScheme)?.primary
            ?? ShatlShadowLayer(opacity: 0, radius: 0)
        let restOpacity = usesColoredDownloadSpeed ? 0 : restShadow.opacity

        HStack(spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0, !usesColoredDownloadSpeed {
                    metricDivider
                        .transition(metricContentTransition)
                }

                ShatlMetricItem(
                    item: item,
                    iconColorOverride: metricIconColorOverride,
                    speedPalette: item.id == "download-speed" ? speedPalette : nil,
                    showsSpeedBadge: item.id == "download-speed" && items.contains { $0.id == "eta" }
                )
                .transition(metricContentTransition)
            }
        }
        .padding(3)
        .background(metricBackgroundColor)
        .overlay {
            MetricSetOutlineView(
                baseColor: metricOutlineColor,
                pulseColor: metricSetOutlinePulseColor,
                flashColor: metricSetOutlineFlashColor,
                pulseEnabled: metricSetOutlinePulseEnabled,
                flashOpacity: outlineFlashOpacity
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(height: ShatlMetricLayout.containerHeight)
        .matchedGeometryEffect(id: "metricSet", in: metricSetNamespace, properties: .frame)
        .keyframeAnimator(
            initialValue: MetricSetBounceValues(),
            trigger: bounceTrigger
        ) { content, value in
            content
                .environment(\.metricSetBounceOutlineOpacity, value.outlineOpacity)
                .scaleEffect(value.scale, anchor: .center)
                .shadow(
                    color: metricBounceColor.opacity(
                        restOpacity + (metricBounceShadow.opacity - restOpacity) * value.shadowProgress
                    ),
                    radius: restShadow.radius + (metricBounceShadow.radius - restShadow.radius) * value.shadowProgress,
                    x: restShadow.x + (metricBounceShadow.x - restShadow.x) * value.shadowProgress,
                    y: restShadow.y + (metricBounceShadow.y - restShadow.y) * value.shadowProgress
                )
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                SpringKeyframe(
                    ShatlMotion.metricSetBounceScale,
                    duration: ShatlMotion.metricSetBounceUpDuration,
                    spring: .smooth(duration: ShatlMotion.metricSetBounceUpDuration)
                )
                LinearKeyframe(
                    ShatlMotion.metricSetBounceScale,
                    duration: ShatlMotion.metricSetBounceHoldDuration
                )
                SpringKeyframe(
                    1,
                    duration: ShatlMotion.metricSetBounceDownDuration,
                    spring: .smooth(duration: ShatlMotion.metricSetBounceDownDuration)
                )
            }

            KeyframeTrack(\.outlineOpacity) {
                SpringKeyframe(
                    1,
                    duration: ShatlMotion.metricSetBounceUpDuration,
                    spring: .smooth(duration: ShatlMotion.metricSetBounceUpDuration)
                )
                LinearKeyframe(1, duration: ShatlMotion.metricSetBounceHoldDuration)
                SpringKeyframe(
                    0,
                    duration: ShatlMotion.metricSetBounceDownDuration,
                    spring: .smooth(duration: ShatlMotion.metricSetBounceDownDuration)
                )
            }

            KeyframeTrack(\.shadowProgress) {
                SpringKeyframe(
                    1,
                    duration: ShatlMotion.metricSetBounceUpDuration,
                    spring: .smooth(duration: ShatlMotion.metricSetBounceUpDuration)
                )
                LinearKeyframe(1, duration: ShatlMotion.metricSetBounceHoldDuration)
                SpringKeyframe(
                    0,
                    duration: ShatlMotion.metricSetBounceDownDuration,
                    spring: .smooth(duration: ShatlMotion.metricSetBounceDownDuration)
                )
            }
        }
        .background(metricSetDiagnosticsSizeReader)
        .animation(ShatlMotion.metricResize, value: items)
        .animation(ShatlMotion.metricResize, value: usesColoredDownloadSpeed)
        .onChange(of: items) { oldItems, newItems in
            logItemsChanged(from: oldItems, to: newItems)
        }
        .onChange(of: iconSignature) { oldIconSignature, newIconSignature in
            guard metricSetBounceEnabled else { return }
            guard hasIconReplacement(from: oldIconSignature, to: newIconSignature) else {
                return
            }
            logIconReplacementDetected(from: oldIconSignature, to: newIconSignature)
            bounceMetricSet()
        }
        .onChange(of: metricSetOutlineFlashTrigger) { _, newTrigger in
            guard newTrigger > 0 else { return }
            flashMetricSetOutline()
        }
        .onChange(of: downloadSpeedOutlineFlashTrigger) { _, newTrigger in
            guard newTrigger > 0, items.contains(where: { $0.id == "download-speed" }) else { return }
            flashMetricSetOutline()
        }
    }

    private var speedPalette: ShatlSpeedMetricPalette? {
        guard colorizesDownloadSpeed,
              let speed = items.first(where: { $0.id == "download-speed" }) else { return nil }
        return ShatlSpeedMetricPalette.downloadSymbol(speed.iconName)
    }

    private var usesColoredDownloadSpeed: Bool { speedPalette != nil }

    private var metricContentTransition: AnyTransition {
        reduceMotion ? .opacity : ShatlMotion.appearFromTop
    }

    private var metricBackgroundColor: Color {
        backgroundColorOverride ?? ShatlColor.metricBackground
    }

    private var metricOutlineColor: Color {
        outlineColorOverride ?? ShatlColor.metricOutline
    }

    private var iconSignature: [String?] {
        items.map(\.iconName)
    }

    private var metricSetDiagnosticsSizeReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    recordMetricSetSize(proxy.size)
                }
                .onChange(of: proxy.size) { _, newSize in
                    recordMetricSetSize(newSize)
                }
        }
    }

    private func hasIconReplacement(from oldIconSignature: [String?], to newIconSignature: [String?]) -> Bool {
        zip(oldIconSignature, newIconSignature).contains { oldIconName, newIconName in
            guard let oldIconName, let newIconName else { return false }
            return oldIconName != newIconName
        }
    }

    private var metricDivider: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(ShatlColor.metricDivider)
            .frame(width: 2, height: ShatlMetricLayout.contentHeight)
    }

    private func bounceMetricSet() {
        bounceToken += 1
        let token = bounceToken
        let startedAt = DispatchTime.now().uptimeNanoseconds

        logBounceEvent(
            "metricset.bounce.start",
            token: token,
            startedAt: startedAt,
            extra: [
                "upMs": "140",
                "holdMs": "140",
                "downMs": "240",
            ]
        )

        guard animationMode == .lively, !reduceMotion else {
            logBounceEvent(
                "metricset.bounce.skipped",
                token: token,
                startedAt: startedAt,
                extra: [
                    "animationMode": animationMode.rawValue,
                    "reduceMotion": reduceMotion.description,
                ]
            )
            return
        }

        bounceTrigger += 1
        logBounceEvent(
            "metricset.bounce.keyframes-commanded",
            token: token,
            startedAt: startedAt,
            extra: ["trigger": String(bounceTrigger)]
        )
    }

    private func flashMetricSetOutline() {
        outlineFlashToken += 1
        let token = outlineFlashToken

        guard animationMode == .lively, !reduceMotion else {
            return
        }

        withAnimation(.smooth(duration: ShatlMotion.metricSetBounceUpDuration)) {
            outlineFlashOpacity = 1
        }

        Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(ShatlMotion.metricSetBounceUpDuration + ShatlMotion.metricSetBounceHoldDuration)
            )
            guard token == outlineFlashToken else { return }

            withAnimation(.smooth(duration: ShatlMotion.metricSetBounceDownDuration)) {
                outlineFlashOpacity = 0
            }
        }
    }

    private func logItemsChanged(
        from oldItems: [MetricItemPresentation],
        to newItems: [MetricItemPresentation]
    ) {
        guard ShatlMetricAnimationDiagnosticsLog.isEnabled else { return }

        ShatlMetricAnimationDiagnosticsLog.event(
            "metricset.items.changed",
            fields: diagnosticsFields([
                "reason": itemChangeReason(from: oldItems, to: newItems),
                "items.previous": itemIDsSignature(oldItems),
                "items.current": itemIDsSignature(newItems),
                "icons.previous": iconSignature(oldItems),
                "icons.current": iconSignature(newItems),
                "values.previous": valueSignature(oldItems),
                "values.current": valueSignature(newItems),
            ])
        )
    }

    private func logIconReplacementDetected(from oldIconSignature: [String?], to newIconSignature: [String?]) {
        guard ShatlMetricAnimationDiagnosticsLog.isEnabled else { return }

        ShatlMetricAnimationDiagnosticsLog.event(
            "metricset.icon-replacement.detected",
            fields: diagnosticsFields([
                "icons.previous": joinedOptionalSignature(oldIconSignature),
                "icons.current": joinedOptionalSignature(newIconSignature),
                "replacements": iconReplacementSignature(from: oldIconSignature, to: newIconSignature),
                "animationMode": animationMode.rawValue,
                "reduceMotion": reduceMotion.description,
                "bounceEligible": (animationMode == .lively && !reduceMotion).description,
            ])
        )
    }

    private func recordMetricSetSize(_ size: CGSize) {
        guard ShatlMetricAnimationDiagnosticsLog.isEnabled else {
            lastMetricSetSize = size
            return
        }

        let previousSize = lastMetricSetSize
        lastMetricSetSize = size

        guard let previousSize else {
            ShatlMetricAnimationDiagnosticsLog.event(
                "metricset.layout.initial",
                fields: diagnosticsFields(sizeFields(previous: nil, current: size)),
                flush: false
            )
            return
        }

        let widthDelta = size.width - previousSize.width
        let heightDelta = size.height - previousSize.height
        let hasMeaningfulDelta = abs(widthDelta) >= 0.5 || abs(heightDelta) >= 0.5
        guard hasMeaningfulDelta else { return }

        ShatlMetricAnimationDiagnosticsLog.event(
            "metricset.layout.changed",
            fields: diagnosticsFields(sizeFields(previous: previousSize, current: size)),
            flush: false
        )
    }

    private func logBounceEvent(
        _ event: String,
        token: Int,
        startedAt: UInt64,
        extra: [String: String] = [:]
    ) {
        guard ShatlMetricAnimationDiagnosticsLog.isEnabled else { return }

        var fields = diagnosticsFields([
            "token": String(token),
            "elapsedMs": elapsedMilliseconds(since: startedAt),
        ])
        for (key, value) in extra {
            fields[key] = value
        }

        ShatlMetricAnimationDiagnosticsLog.event(event, fields: fields)
    }

    private func diagnosticsFields(_ fields: [String: String]) -> [String: String] {
        var resolvedFields: [String: String] = [
            "source": diagnosticsContext?.source ?? "unknown",
            "torrentID": diagnosticsContext?.torrentID?.uuidString ?? "-",
            "groupID": diagnosticsContext?.groupID ?? "-",
            "status": diagnosticsContext?.cardStatus?.rawValue ?? "-",
            "progressPercent": diagnosticsContext?.progressPercent.map(String.init) ?? "-",
            "downloadSpeedBytesPerSecond": diagnosticsContext?.downloadSpeedBytesPerSecond.map(String.init) ?? "-",
            "etaSeconds": diagnosticsContext?.etaSeconds.map(String.init) ?? "-",
        ]

        for (key, value) in fields {
            resolvedFields[key] = value
        }

        return resolvedFields
    }

    private func itemChangeReason(
        from oldItems: [MetricItemPresentation],
        to newItems: [MetricItemPresentation]
    ) -> String {
        if oldItems.count < newItems.count {
            return "itemInserted"
        }

        if oldItems.count > newItems.count {
            return "itemRemoved"
        }

        if hasIconReplacement(from: oldItems.map(\.iconName), to: newItems.map(\.iconName)) {
            return "iconReplacement"
        }

        if oldItems.map(\.number) != newItems.map(\.number) {
            return "numberChanged"
        }

        if oldItems.map(\.unit) != newItems.map(\.unit) {
            return "unitChanged"
        }

        return "other"
    }

    private func itemIDsSignature(_ items: [MetricItemPresentation]) -> String {
        items.map(\.id).joined(separator: ",")
    }

    private func iconSignature(_ items: [MetricItemPresentation]) -> String {
        joinedOptionalSignature(items.map(\.iconName))
    }

    private func valueSignature(_ items: [MetricItemPresentation]) -> String {
        items
            .map { item in
                "\(item.id):\(item.number ?? "-"):\(item.unit ?? "-")"
            }
            .joined(separator: ",")
    }

    private func joinedOptionalSignature(_ values: [String?]) -> String {
        values.map { $0 ?? "-" }.joined(separator: ",")
    }

    private func iconReplacementSignature(from oldIconSignature: [String?], to newIconSignature: [String?]) -> String {
        zip(oldIconSignature, newIconSignature).enumerated()
            .compactMap { index, pair in
                guard let oldIconName = pair.0, let newIconName = pair.1, oldIconName != newIconName else {
                    return nil
                }

                return "\(index):\(oldIconName)->\(newIconName)"
            }
            .joined(separator: ",")
    }

    private func sizeFields(previous: CGSize?, current: CGSize) -> [String: String] {
        [
            "width.previous": previous.map { formatMetricSetNumber($0.width) } ?? "-",
            "width.current": formatMetricSetNumber(current.width),
            "width.delta": previous.map { formatMetricSetNumber(current.width - $0.width) } ?? "-",
            "height.previous": previous.map { formatMetricSetNumber($0.height) } ?? "-",
            "height.current": formatMetricSetNumber(current.height),
            "height.delta": previous.map { formatMetricSetNumber(current.height - $0.height) } ?? "-",
        ]
    }

    private func elapsedMilliseconds(since startedAt: UInt64) -> String {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
        let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000
        return formatMetricSetNumber(elapsedMilliseconds)
    }

    private func formatMetricSetNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatMetricSetNumber(_ value: CGFloat) -> String {
        formatMetricSetNumber(Double(value))
    }
}

struct ShatlInfoBottomSpeedChip: View {
    let item: MetricItemPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shatlAnimationMode) private var animationMode
    @State private var isHovered = false

    @ViewBuilder
    var body: some View {
        if #available(macOS 27.0, *) {
            chipContent
                .glassEffect(
                    .regular
                        .tint(.accent.opacity(ShatlGlassTint.subtleOpacity))
                        .interactive(false),
                    in: RoundedRectangle(
                        cornerRadius: ShatlBottomChipLayout.modernCornerRadius,
                        style: .continuous
                    )
                )
                .fixedSize()
                .animation(ShatlMotion.metricResize, value: item)
        } else {
            chipContent
                .fixedSize()
                .scaleEffect(usesScaledHoverTransition && isHovered ? 0.85 : 1)
                .opacity(isHovered ? 0 : 1)
                .overlay {
                    Capsule()
                        .fill(Color.clear)
                }
                .contentShape(Capsule())
                .onHover { isHovered = $0 }
                .animation(ShatlMotion.mainContentMode, value: isHovered)
                .animation(ShatlMotion.metricResize, value: item)
        }
    }

    private var chipContent: some View {
        ShatlInfoBottomMetricItem(item: item)
            .padding(6)
    }

    private var usesScaledHoverTransition: Bool {
        animationMode == .lively && !reduceMotion
    }
}

private struct ShatlInfoBottomMetricItem: View {
    let item: MetricItemPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shatlAnimationMode) private var animationMode

    var body: some View {
        HStack(spacing: 5) {
            if let iconName = item.iconName {
                Image(systemName: iconName)
                    .shatlTypography(iconTypography(for: iconName))
                    .foregroundStyle(ShatlColor.typographyPrimary.opacity(0.50))
                    .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
            }

            if let number = item.number {
                HStack(spacing: 2) {
                    metricNumber(number)

                    if let unit = item.unit {
                        Text(unit)
                            .shatlTypography(ShatlTypography.metricSemibold)
                            .foregroundStyle(ShatlColor.typographyPrimary)
                            .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func metricNumber(_ number: String) -> some View {
        let text = Text(number)
            .shatlTypography(ShatlTypography.metricSemibold)
            .foregroundStyle(ShatlColor.typographyPrimary)
            .monospacedDigit()
            .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
            .fixedSize(horizontal: true, vertical: false)

        if animationMode == .lively, !reduceMotion {
            text.contentTransition(.numericText())
        } else {
            text
        }
    }

    private func iconTypography(for iconName: String) -> ShatlTextStyle {
        switch iconName {
        case "tortoise.fill", "hare.fill", "bolt.fill":
            ShatlTypography.groupSemibold
        default:
            ShatlTypography.metricSemibold
        }
    }
}

struct ShatlMetricGroup: View {
    let group: MetricGroupPresentation
    var metricIconColorOverride: Color? = nil
    var metricSetBackgroundColorOverride: Color? = nil
    var metricSetOutlineColorOverride: Color? = nil
    var diagnosticsContext: MetricSetDiagnosticsContext? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.title)
                .shatlTypography(ShatlTypography.groupSemibold)
                .foregroundStyle(ShatlColor.typographySecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            ShatlMetricSet(
                items: group.items,
                metricIconColorOverride: metricIconColorOverride,
                backgroundColorOverride: metricSetBackgroundColorOverride,
                outlineColorOverride: metricSetOutlineColorOverride,
                diagnosticsContext: diagnosticsContext?.withGroupID(group.id)
            )
        }
        .layoutPriority(1)
        .animation(ShatlMotion.metricResize, value: group)
    }
}

struct ShatlMetricGroupSet: View {
    let groups: [MetricGroupPresentation]
    var metricIconColorOverride: Color? = nil
    var metricSetBackgroundColorOverride: Color? = nil
    var metricSetOutlineColorOverride: Color? = nil
    var diagnosticsContext: MetricSetDiagnosticsContext? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(groups) { group in
                ShatlMetricGroup(
                    group: group,
                    metricIconColorOverride: metricIconColorOverride,
                    metricSetBackgroundColorOverride: metricSetBackgroundColorOverride,
                    metricSetOutlineColorOverride: metricSetOutlineColorOverride,
                    diagnosticsContext: diagnosticsContext
                )
                    .layoutPriority(1)
                    .transition(ShatlMotion.appearFromTop)
            }
        }
        .layoutPriority(1)
        .animation(ShatlMotion.metricResize, value: groups)
    }
}

private struct ShatlPressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
