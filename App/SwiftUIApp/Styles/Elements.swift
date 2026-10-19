// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import SwiftUI

enum ShatlButtonRole {
    case borderedNeutral
    case borderedColored
    case lineMessage
}

enum ShatlIconSize {
    static let small: CGFloat = 16
}

enum ShatlMetricLayout {
    static let contentHeight: CGFloat = 15
    static let containerHeight: CGFloat = 27
    /// Between a metric set's edge and its items.
    static let setPadding: CGFloat = 3
}

enum ShatlBottomChipLayout {
    static let legacyEdgePadding: CGFloat = 12
    static let modernEdgePadding: CGFloat = 6
    static let modernCornerRadius: CGFloat = 10
    /// macOS 26 rounds window corners more: the chip is a capsule there.
    static let legacyCornerRadius: CGFloat = 13.5
    static let cardGap: CGFloat = 6
    static let standardListBottomPadding: CGFloat = 8
    static let modernListBottomPadding = modernEdgePadding
        + ShatlMetricLayout.containerHeight
        + cardGap
}

#if DEBUG
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

private struct ShatlMetricSetDiagnosticsContextKey: EnvironmentKey {
    static let defaultValue: MetricSetDiagnosticsContext? = nil
}

extension EnvironmentValues {
    /// Which card and group a metric set belongs to, for its animation log.
    var shatlMetricSetDiagnosticsContext: MetricSetDiagnosticsContext? {
        get { self[ShatlMetricSetDiagnosticsContextKey.self] }
        set { self[ShatlMetricSetDiagnosticsContextKey.self] = newValue }
    }
}
#endif

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

/// While `isBusy`, the button shows `busyTitle`, ignores clicks without
/// dimming, and resizes to the new title. Neighbors slide only when their
/// container animates the same change, e.g. `.geometryGroup()` plus
/// `.animation(ShatlMotion.metricResize, value:)`.
struct ShatlButton: View {
    let title: ShatlTextContent?
    var busyTitle: ShatlTextContent?
    var isBusy = false
    var systemImage: String?
    var iconSize: CGFloat = ShatlIconSize.small
    let role: ShatlButtonRole
    var isDisabled = false
    var fillsWidth = false
    var lineLimit: Int? = 1
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        busyTitle: String? = nil,
        isBusy: Bool = false,
        role: ShatlButtonRole,
        isDisabled: Bool = false,
        fillsWidth: Bool = false,
        lineLimit: Int? = 1,
        action: @escaping () -> Void
    ) {
        self.title = .verbatim(title)
        self.busyTitle = busyTitle.map { .verbatim($0) }
        self.isBusy = isBusy
        self.systemImage = nil
        self.role = role
        self.isDisabled = isDisabled
        self.fillsWidth = fillsWidth
        self.lineLimit = lineLimit
        self.action = action
    }

    init(
        localizedTitle key: String,
        role: ShatlButtonRole,
        isDisabled: Bool = false,
        fillsWidth: Bool = false,
        lineLimit: Int? = 1,
        action: @escaping () -> Void
    ) {
        self.title = .localized(key)
        self.systemImage = nil
        self.role = role
        self.isDisabled = isDisabled
        self.fillsWidth = fillsWidth
        self.lineLimit = lineLimit
        self.action = action
    }

    init(
        systemImage: String,
        iconSize: CGFloat = ShatlIconSize.small,
        role: ShatlButtonRole,
        isDisabled: Bool = false,
        fillsWidth: Bool = false,
        lineLimit: Int? = 1,
        action: @escaping () -> Void
    ) {
        self.title = nil
        self.systemImage = systemImage
        self.iconSize = iconSize
        self.role = role
        self.isDisabled = isDisabled
        self.fillsWidth = fillsWidth
        self.lineLimit = lineLimit
        self.action = action
    }

    var body: some View {
        Button {
            // A busy button reports progress; repeated clicks must not restart it.
            guard !isBusy else { return }
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                        .frame(width: ShatlIconSize.small, height: ShatlIconSize.small, alignment: .center)
                }

                if let displayedTitle {
                    displayedTitle.text
                        .shatlTypography(ShatlTypography.bodyMedium)
                        .lineLimit(lineLimit)
                        .fixedSize(horizontal: lineLimit == 1, vertical: false)
                        .multilineTextAlignment(.center)
                        .id(showsBusyTitle)
                        .transition(titleTransition)
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(backgroundColor)
            // Clipping keeps the outgoing title inside the button while it resizes.
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(ShatlMotion.metricResize, value: showsBusyTitle)
        }
        .buttonStyle(ShatlPressedButtonStyle())
        .allowsHitTesting(!isBusy)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }

    private var showsBusyTitle: Bool {
        isBusy && busyTitle != nil
    }

    private var displayedTitle: ShatlTextContent? {
        showsBusyTitle ? busyTitle : title
    }

    private var titleTransition: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }

    private var backgroundColor: Color {
        switch role {
        case .borderedNeutral:
            ShatlColor.buttonNeutral
        case .borderedColored:
            ShatlColor.accent
        case .lineMessage:
            ShatlColor.lineMessageButtonBackground
        }
    }

    private var foregroundColor: Color {
        switch role {
        case .borderedNeutral:
            ShatlColor.typographyPrimary
        case .borderedColored:
            ShatlColor.typographyPrimaryInverted
        case .lineMessage:
            ShatlColor.lineMessageButtonLabel
        }
    }

    private var horizontalPadding: CGFloat {
        role == .lineMessage ? 6 : 8
    }

    private var verticalPadding: CGFloat {
        role == .lineMessage ? 4 : 6
    }

    private var cornerRadius: CGFloat {
        role == .lineMessage ? ShatlCornerRadius.tab : ShatlCornerRadius.button
    }
}

/// A small capsule that opens a page in the browser: its name is the
/// button, and the arrow says that the page opens outside the app.
struct ShatlLinkButton: View {
    let title: ShatlTextContent
    let url: URL

    @Environment(\.shatlTypographyProfile) private var typographyProfile
    @State private var isHovered = false

    init(title: String, url: URL) {
        self.title = .verbatim(title)
        self.url = url
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 2) {
                title.text
                    .lineLimit(1)
                    .fixedSize()

                Image(systemName: "arrow.up.right.circle.fill")
                    .accessibilityHidden(true)
            }
            .shatlTypography(ShatlTypography.captionRegular)
            .frame(height: ShatlTypography.captionRegular.variant(for: typographyProfile).lineHeight)
            .foregroundStyle(isHovered ? ShatlColor.linkButtonHoverLabel : ShatlColor.typographyPrimary)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(isHovered ? ShatlColor.linkButtonHoverBackground : ShatlColor.backgroundSecondary)
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(ShatlPressedButtonStyle())
        .onHover { isHovered = $0 }
        .animation(ShatlMotion.cardState, value: isHovered)
        .pointerStyle(.link)
        .accessibilityAddTraits(.isLink)
        .accessibilityRemoveTraits(.isButton)
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

/// A button of a message block. It has no look of its own: the block
/// colours its main button and keeps the others neutral.
struct ShatlMessageBlockPrimaryButton {
    let title: String
    var isDisabled = false
    var lineLimit: Int?
    /// Esc for the button that closes or cancels.
    var keyboardShortcut: KeyboardShortcut?
    let action: () -> Void

    init(
        title: String,
        isDisabled: Bool = false,
        lineLimit: Int? = nil,
        keyboardShortcut: KeyboardShortcut? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isDisabled = isDisabled
        self.lineLimit = lineLimit
        self.keyboardShortcut = keyboardShortcut
        self.action = action
    }
}

/// A message in the middle of a window: icon, title, text and buttons. One
/// look everywhere: its own fill on the window's own background.
///
/// When the message changes, the block stays in place and its content is
/// replaced, so waiting turns into the result without a jump: the text and
/// the buttons blur into the new ones and the block takes its new height,
/// then the icon is replaced.
struct ShatlMessageBlockPrimary: View {
    var systemImage = "exclamationmark.circle"
    let title: String
    var message: String?
    /// The only button, or the main one of several. It is always the
    /// coloured one, whatever it does: a message's only action is its main
    /// one.
    var primaryButton: ShatlMessageBlockPrimaryButton?
    /// Further choices under the main one, always neutral; with any of them
    /// every button takes the full width.
    var secondaryButtons: [ShatlMessageBlockPrimaryButton] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The icon on screen: it follows `systemImage` once the block has
    /// settled; see `followSystemImage`.
    @State private var displayedSystemImage: String?
    @State private var systemImageTask: Task<Void, Never>?

    private let cornerRadius: CGFloat = 18
    /// The room the icon is laid out in, whatever its own height.
    static let iconCellHeight: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            labelGroup

            if primaryButton != nil || !secondaryButtons.isEmpty {
                // Old and new buttons overlap while one set replaces the
                // other, as the text does: nothing slides or stretches from
                // one into the other.
                ZStack(alignment: .topLeading) {
                    buttonStack
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(buttonsIdentity)
                        .transition(contentReplace)
                }
            }
        }
        .padding(10)
        .frame(width: 340, alignment: .leading)
        .background(ShatlColor.backgroundSecondary)
        .clipShape(messageBlockShape)
        .overlay {
            messageBlockShape
                .strokeBorder(ShatlColor.outlineTertiary, lineWidth: 0.5)
        }
        // Held from the start, so a new `systemImage` never shows before
        // its turn.
        .onAppear {
            if displayedSystemImage == nil {
                displayedSystemImage = systemImage
            }
        }
        .onChange(of: contentSignature) { old, new in
            followSystemImage(from: old, to: new)
        }
        .onDisappear {
            systemImageTask?.cancel()
        }
    }

    private var contentReplace: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace)
    }

    private var textIdentity: String {
        title + "\n" + (message ?? "")
    }

    private var buttonsIdentity: String {
        (primaryButton?.title ?? "") + "\n" + secondaryButtons.map(\.title).joined(separator: "\n")
    }

    private struct ContentSignature: Equatable {
        var systemImage: String
        var text: String
        var buttons: String
    }

    private var contentSignature: ContentSignature {
        ContentSignature(systemImage: systemImage, text: textIdentity, buttons: buttonsIdentity)
    }

    /// SF Symbols' replace looks right only while the icon stands still. A
    /// new text or new buttons change the block's height, and the block is
    /// centred, so the icon moves with its top edge: the icon then waits for
    /// the block to settle. Alone, it changes at once.
    private func followSystemImage(from old: ContentSignature, to new: ContentSignature) {
        guard old.systemImage != new.systemImage else { return }

        systemImageTask?.cancel()
        let resizes = old.text != new.text || old.buttons != new.buttons
        guard resizes, !reduceMotion else {
            displayedSystemImage = new.systemImage
            return
        }

        systemImageTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(ShatlMotion.messageBlockContentDuration))
            guard !Task.isCancelled else { return }
            displayedSystemImage = new.systemImage
        }
    }

    private var labelGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: displayedSystemImage ?? systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(ShatlColor.typographyTertiary)
                .contentTransition(.symbolEffect(.replace))
                .animation(ShatlMotion.messageBlockContent, value: displayedSystemImage ?? systemImage)
                // One height for every icon. Symbols of one font size differ
                // in height, from 25 to 34 pt here: laid out by its own
                // height, a new icon changed the block's height in one frame,
                // before the replace was drawn. The tallest reach a point or
                // two past the cell, into the room around it.
                .frame(height: Self.iconCellHeight)

            // Old and new text overlap while one replaces the other.
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .shatlTypography(ShatlTypography.bodySemibold)
                        .foregroundStyle(ShatlColor.typographyPrimary)

                    if let message {
                        Text(message)
                            .shatlTypography(ShatlTypography.bodyRegular)
                            .foregroundStyle(ShatlColor.typographySecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(textIdentity)
                .transition(contentReplace)
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private var buttonStack: some View {
        if !secondaryButtons.isEmpty {
            VStack(spacing: 6) {
                if let primaryButton {
                    button(primaryButton, role: .borderedColored, fillsWidth: true)
                }
                ForEach(secondaryButtons.indices, id: \.self) { index in
                    button(secondaryButtons[index], role: .borderedNeutral, fillsWidth: true)
                }
            }
        } else if let primaryButton {
            HStack {
                button(primaryButton, role: .borderedColored, fillsWidth: false)
                Spacer(minLength: 0)
            }
        }
    }

    private func button(
        _ button: ShatlMessageBlockPrimaryButton,
        role: ShatlButtonRole,
        fillsWidth: Bool
    ) -> some View {
        ShatlButton(
            title: button.title,
            role: role,
            isDisabled: button.isDisabled,
            fillsWidth: fillsWidth,
            lineLimit: button.lineLimit,
            action: button.action
        )
        .keyboardShortcut(button.keyboardShortcut)
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
            .foregroundStyle(ShatlColor.typographySecondary)
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

/// A dot before the title of a settings toggle row that reports what the
/// switch achieved, such as whether the router opened a port.
struct ShatlSettingsStatusDot: Equatable {
    var color: Color
    /// What the dot means, for VoiceOver and the tooltip: colour alone does
    /// not tell red from green for everyone.
    var description: String
}

struct ShatlSettingsToggleRow: View {
    let title: ShatlTextContent
    @Binding var isOn: Bool
    var isEnabled = true
    var statusDot: ShatlSettingsStatusDot?
    /// Off while the row takes its first state, so opening Settings does not
    /// animate a dot that was already there.
    var animatesStatusDot = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String, isOn: Binding<Bool>, isEnabled: Bool = true) {
        self.title = .verbatim(title)
        self._isOn = isOn
        self.isEnabled = isEnabled
    }

    init(
        localizedTitle key: String,
        isOn: Binding<Bool>,
        isEnabled: Bool = true,
        statusDot: ShatlSettingsStatusDot? = nil,
        animatesStatusDot: Bool = true
    ) {
        self.title = .localized(key)
        self._isOn = isOn
        self.isEnabled = isEnabled
        self.statusDot = statusDot
        self.animatesStatusDot = animatesStatusDot
    }

    var body: some View {
        HStack(spacing: 16) {
            // The dot enters like a metric set and the title slides aside with it.
            HStack(spacing: 4) {
                if let statusDot {
                    Circle()
                        .fill(statusDot.color)
                        .animation(animatesStatusDot ? ShatlMotion.speedMetricColor : nil, value: statusDot.color)
                        .frame(width: 6, height: 6)
                        .transition(reduceMotion ? .opacity : ShatlMotion.appearFromTop)
                        .accessibilityElement()
                        .accessibilityLabel(statusDot.description)
                }

                title.text
                    .shatlTypography(ShatlTypography.bodyRegular)
                    .foregroundStyle(ShatlColor.typographyPrimary)
                    .opacity(isEnabled ? 1 : 0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            .help(statusDot?.description ?? "")
            .animation(animatesStatusDot ? ShatlMotion.metricResize : nil, value: statusDot != nil)

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .accessibilityLabel(title.text)
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
        imageContainerHeight: CGFloat? = nil,
        imageContentVerticalPadding: CGFloat? = nil,
        overlaysSelectionMark: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = .verbatim(title)
        self.isSelected = isSelected
        self.isEnabled = isEnabled
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
        imageContainerHeight: CGFloat? = nil,
        imageContentVerticalPadding: CGFloat? = nil,
        overlaysSelectionMark: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = .localized(key)
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.imageContainerHeight = imageContainerHeight
        self.imageContentVerticalPadding = imageContentVerticalPadding
        self.overlaysSelectionMark = overlaysSelectionMark
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: activate) {
            VStack(spacing: 6) {
                imageContainer
                labelContainer
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
        imageContainerHeight != nil && !overlaysSelectionMark
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

        return 26
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
            alignment: .leading
        )
        .animation(ShatlMotion.cardState, value: isSelected)
    }

    private func labelText(typography: ShatlTextStyle, color: Color) -> some View {
        title.text
            .foregroundStyle(color)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .shatlTypography(typography)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
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
    var metricSetOutlineFlashColor = ShatlColor.accentColored
    var progressBarFillColorOverride: Color? = nil
    var progressGroupBackgroundColorOverride: Color? = nil
    var progressGroupForegroundColorOverride: Color? = nil
    var usesProductionProgressColors = false
    var usesProductionCardColors = false
    var cardBackgroundColorOverride: Color? = nil
    var cardOutlineColorOverride: Color? = nil
    var shadowStyle: TorrentCardPreviewShadowStyle = .onboarding
    var cardWidth: CGFloat? = Layout.cardWidth
    /// What a Settings toggle put in focus; the rest of the card blurs.
    var focus: TorrentCardPreviewFocus? = nil

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
        metricSetOutlineFlashColor: Color = ShatlColor.accentColored,
        progressBarFillColorOverride: Color? = nil,
        progressGroupBackgroundColorOverride: Color? = nil,
        progressGroupForegroundColorOverride: Color? = nil,
        usesProductionProgressColors: Bool = false,
        usesProductionCardColors: Bool = false,
        cardBackgroundColorOverride: Color? = nil,
        cardOutlineColorOverride: Color? = nil,
        shadowStyle: TorrentCardPreviewShadowStyle = .onboarding,
        cardWidth: CGFloat? = Layout.cardWidth,
        focus: TorrentCardPreviewFocus? = nil
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
        self.usesProductionCardColors = usesProductionCardColors
        self.cardBackgroundColorOverride = cardBackgroundColorOverride
        self.cardOutlineColorOverride = cardOutlineColorOverride
        self.shadowStyle = shadowStyle
        self.cardWidth = cardWidth
        self.focus = focus
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
                .environment(\.shatlMetricSetOutlinePulseColor, ShatlColor.accentColored)
                .environment(\.shatlMetricSetOutlineFlashColor, metricSetOutlineFlashColor)
                .environment(\.shatlIsCardPreview, true)
                .environment(\.shatlCardPreviewFocus, focus)

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
            onSelect: { true },
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
            usesProductionCardColors: usesProductionCardColors,
            cardBackgroundColorOverride: cardBackgroundColorOverride,
            cardOutlineColorOverride: cardOutlineColorOverride,
            usesCompactExpandedMetricsLayout: (cardWidth ?? .infinity)
                < TorrentCardLayout.compactExpandedMetricsWidth
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
        ShatlColor.accentColored.opacity(0.5)
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
                demoProgress = demoProgress >= 0.99 ? 0.01 : min(0.99, demoProgress + 0.01)
                demoTick += 1
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
                defaultValue: "Так выглядит загрузка"
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
            compactTransferMetricSet: TorrentPresentation.compactTransferMetricSet(
                for: record,
                mode: metricsMode,
                localeOverride: localeOverride
            ),
            expandedMetricGroups: isExpanded ? expandedMetricGroups : nil,
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
    /// The number and unit hide; a chevron before the icon says so.
    var isFolded = false
    /// The chevron shows while the speed has the ETA beside it; at the end
    /// of a download the ETA leaves and takes it along.
    var showsFoldMark = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shatlRollsMetricDigits) private var rollsDigits

    var body: some View {
        HStack(spacing: 5) {
            if isFolded, showsFoldMark {
                Image(systemName: "chevron.backward")
                    .shatlTypography(ShatlTypography.metricSemibold)
                    .foregroundStyle(foldMarkColor)
                    .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
                    // VoiceOver reads the hidden value here.
                    .accessibilityLabel(Text(spokenValue))
                    .transition(contentTransition)
            }

            if let iconName = item.iconName {
                Image(systemName: iconName)
                    .shatlTypography(iconTypography(for: iconName))
                    .foregroundStyle(iconColor)
                    .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
            }

            if let number = item.number, !isFolded {
                HStack(spacing: 2) {
                    metricNumber(number)

                    if let unit = item.unit {
                        Text(unit)
                            .shatlTypography(ShatlTypography.metricSemibold)
                            .foregroundStyle(cellPalette?.label ?? ShatlColor.typographyTertiary)
                            .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
                .fixedSize(horizontal: true, vertical: false)
                .transition(contentTransition)
            }
        }
        .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
        .padding(.vertical, 3)
        .frame(minWidth: iconAloneMinimumWidth)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(speedPalette?.badge ?? .clear)
                .opacity(showsSpeedBadge ? 1 : 0)
        }
        // A colored cell keeps its text inside while it grows or shrinks.
        .clipShape(MetricItemClip(clips: cellPalette != nil))
        .animation(ShatlMotion.speedMetricColor, value: speedPalette)
        .animation(ShatlMotion.speedMetricColor, value: showsSpeedBadge)
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? .opacity : ShatlMotion.appearFromTop
    }

    /// The wider trailing padding leaves room after the unit; with the number
    /// folded away the paddings match, so what is left sits in the middle.
    private var leadingPadding: CGFloat {
        if isFolded { return 4 }
        return item.iconName == nil ? 5 : 3
    }

    private var trailingPadding: CGFloat {
        isFolded ? 4 : 5
    }

    /// An icon left alone, at the end of a download, keeps its set at least
    /// square, as wide as it is tall, with the icon in the middle.
    private var iconAloneMinimumWidth: CGFloat? {
        guard isFolded, !showsFoldMark else { return nil }
        return ShatlMetricLayout.containerHeight - ShatlMetricLayout.setPadding * 2
    }

    /// The colors made for the colored cell, while it shows. Without it, at
    /// the end of a download, the speed takes the colors it has with the
    /// colored speed off.
    private var cellPalette: ShatlSpeedMetricPalette? {
        showsSpeedBadge ? speedPalette : nil
    }

    private var foldMarkColor: Color {
        cellPalette.map { $0.icon.opacity(0.35) } ?? ShatlColor.typographyTertiary
    }

    private var spokenValue: String {
        [item.number, item.unit].compactMap { $0 }.joined(separator: " ")
    }

    private var iconColor: Color {
        if let cellPalette { return cellPalette.icon }

        if let iconColorOverride {
            return iconColorOverride
        }

        return item.usesAccentIcon ? ShatlColor.accent : ShatlColor.typographySecondary
    }

    @ViewBuilder
    private func metricNumber(_ number: String) -> some View {
        let text = Text(number)
            .shatlTypography(ShatlTypography.metricSemibold)
            .foregroundStyle(cellPalette?.label ?? ShatlColor.typographyPrimary)
            .monospacedDigit()
            .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
            .fixedSize(horizontal: true, vertical: false)

        if !reduceMotion, rollsDigits {
            text
                .contentTransition(.numericText())
                .animation(ShatlMotion.metricResize, value: number)
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

/// The cell's own shape, or nothing to clip: switching between the two
/// keeps the item's view.
private nonisolated struct MetricItemClip: Shape {
    var clips: Bool

    func path(in rect: CGRect) -> Path {
        guard clips else {
            return Path(rect.insetBy(dx: -1_000, dy: -1_000))
        }
        return RoundedRectangle(cornerRadius: 5, style: .continuous).path(in: rect)
    }
}

private struct MetricSetOutlineView: View {
    let baseColor: Color
    let pulseColor: Color
    let flashColor: Color
    let pulseEnabled: Bool
    let flashOpacity: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    /// The quiet plate of the expanded metrics: filled, with no outline and
    /// no shadow; `Muted` in Figma.
    var isMuted = false
    var colorizesDownloadSpeed = false
    /// The shadow under the set's plate.
    var showsShadows = true
    /// The download speed shows its level icon alone; its number comes back
    /// while the pointer rests on the set.
    var foldsDownloadSpeed = false
    #if DEBUG
    @Environment(\.shatlMetricSetDiagnosticsContext) private var diagnosticsContext
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shatlMetricSetOutlinePulseEnabled) private var metricSetOutlinePulseEnabled
    @Environment(\.shatlMetricSetOutlineFlashTrigger) private var metricSetOutlineFlashTrigger
    @Environment(\.shatlDownloadSpeedOutlineFlashTrigger) private var downloadSpeedOutlineFlashTrigger
    @Environment(\.shatlMetricSetOutlinePulseColor) private var metricSetOutlinePulseColor
    @Environment(\.shatlMetricSetOutlineFlashColor) private var metricSetOutlineFlashColor
    @State private var outlineFlashToken = 0
    @State private var outlineFlashOpacity: CGFloat = 0
    @State private var isDownloadSpeedUnfolded = false
    @State private var downloadSpeedHoverIntent = TorrentCardHoverIntent()

    var body: some View {
        let restShadow = ShatlShadow.metricRest.appearance(for: colorScheme)?.primary
            ?? ShatlShadowLayer(opacity: 0, radius: 0)
        let restOpacity = usesColoredDownloadSpeed ? 0 : restShadow.opacity
        let plateColor = metricBackgroundColor

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
                    showsSpeedBadge: item.id == "download-speed" && items.contains { $0.id == "eta" },
                    isFolded: item.id == "download-speed" && foldsDownloadSpeed && !isDownloadSpeedUnfolded,
                    showsFoldMark: items.contains { $0.id == "eta" }
                )
                .transition(metricContentTransition)
            }
        }
        .padding(ShatlMetricLayout.setPadding)
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
        // The plate sits outside the clip so its shadow shows, and the
        // shadow follows the plate alone: new digits leave the blur as it
        // is. A new speed level changes the icon and the colours, nothing
        // more: until October 2026 the set also grew for a moment and lit
        // its outline.
        .background {
            let plate = RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(plateColor)
            if showsShadows, !isMuted, restOpacity > 0 {
                plate.shadow(
                    color: ShatlColor.shadowKeyColor.opacity(restOpacity),
                    radius: restShadow.radius,
                    x: restShadow.x,
                    y: restShadow.y
                )
            } else {
                plate
            }
        }
        .frame(height: ShatlMetricLayout.containerHeight)
        #if DEBUG
        .metricSetDiagnostics(items: items, context: diagnosticsContext)
        #endif
        .onHover { isInside in
            unfoldDownloadSpeed(isInside)
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
        backgroundColorOverride ?? (isMuted ? ShatlColor.metricBackgroundMuted : ShatlColor.metricBackground)
    }

    private var metricOutlineColor: Color {
        outlineColorOverride ?? (isMuted ? .clear : ShatlColor.metricOutline)
    }

    /// The number comes back once the pointer rests on the set, and folds
    /// again as soon as it leaves; see `TorrentCardHoverTiming`.
    private func unfoldDownloadSpeed(_ isInside: Bool) {
        if isInside {
            guard foldsDownloadSpeed else { return }
            downloadSpeedHoverIntent.pointerEntered {
                guard !isDownloadSpeedUnfolded else { return }
                withAnimation(ShatlMotion.metricResize) {
                    isDownloadSpeedUnfolded = true
                }
            }
        } else {
            downloadSpeedHoverIntent.pointerExited()
            guard isDownloadSpeedUnfolded else { return }
            withAnimation(ShatlMotion.metricResize) {
                isDownloadSpeedUnfolded = false
            }
        }
    }

    private var metricDivider: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(isMuted ? ShatlColor.metricDividerMuted : ShatlColor.metricDivider)
            .frame(width: 2, height: ShatlMetricLayout.contentHeight)
    }

    private func flashMetricSetOutline() {
        outlineFlashToken += 1
        let token = outlineFlashToken

        guard !reduceMotion else {
            return
        }

        withAnimation(.smooth(duration: ShatlMotion.metricSetOutlineFlashInDuration)) {
            outlineFlashOpacity = 1
        }

        Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(ShatlMotion.metricSetOutlineFlashInDuration + ShatlMotion.metricSetOutlineFlashHoldDuration)
            )
            guard token == outlineFlashToken else { return }

            withAnimation(.smooth(duration: ShatlMotion.metricSetOutlineFlashOutDuration)) {
                outlineFlashOpacity = 0
            }
        }
    }

}

#if DEBUG
private extension View {
    @ViewBuilder
    func metricSetDiagnostics(
        items: [MetricItemPresentation],
        context: MetricSetDiagnosticsContext?
    ) -> some View {
        if let context {
            modifier(MetricSetDiagnosticsModifier(items: items, context: context))
        } else {
            self
        }
    }
}

private struct MetricSetDiagnosticsModifier: ViewModifier {
    let items: [MetricItemPresentation]
    let context: MetricSetDiagnosticsContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastSize: CGSize?

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            recordSize(proxy.size)
                        }
                        .onChange(of: proxy.size) { _, newSize in
                            recordSize(newSize)
                        }
                }
            }
            .onChange(of: items) { oldItems, newItems in
                logItemsChanged(from: oldItems, to: newItems)
            }
            .onChange(of: items.map(\.iconName)) { oldIcons, newIcons in
                guard hasMetricSetIconReplacement(from: oldIcons, to: newIcons) else { return }
                logIconReplacementDetected(from: oldIcons, to: newIcons)
            }
    }

    private func logItemsChanged(
        from oldItems: [MetricItemPresentation],
        to newItems: [MetricItemPresentation]
    ) {
        guard ShatlMetricAnimationDiagnosticsLog.isEnabled else { return }

        ShatlMetricAnimationDiagnosticsLog.event(
            "metricset.items.changed",
            fields: metricSetDiagnosticsFields(context: context, merging: [
                "reason": itemChangeReason(from: oldItems, to: newItems),
                "items.previous": itemIDsSignature(oldItems),
                "items.current": itemIDsSignature(newItems),
                "icons.previous": joinedOptionalSignature(oldItems.map(\.iconName)),
                "icons.current": joinedOptionalSignature(newItems.map(\.iconName)),
                "values.previous": valueSignature(oldItems),
                "values.current": valueSignature(newItems),
            ])
        )
    }

    private func logIconReplacementDetected(from oldIcons: [String?], to newIcons: [String?]) {
        guard ShatlMetricAnimationDiagnosticsLog.isEnabled else { return }

        ShatlMetricAnimationDiagnosticsLog.event(
            "metricset.icon-replacement.detected",
            fields: metricSetDiagnosticsFields(context: context, merging: [
                "icons.previous": joinedOptionalSignature(oldIcons),
                "icons.current": joinedOptionalSignature(newIcons),
                "replacements": iconReplacementSignature(from: oldIcons, to: newIcons),
                "reduceMotion": reduceMotion.description,
            ])
        )
    }

    private func recordSize(_ size: CGSize) {
        guard ShatlMetricAnimationDiagnosticsLog.isEnabled else { return }

        let previousSize = lastSize
        lastSize = size

        guard let previousSize else {
            ShatlMetricAnimationDiagnosticsLog.event(
                "metricset.layout.initial",
                fields: metricSetDiagnosticsFields(
                    context: context,
                    merging: sizeFields(previous: nil, current: size)
                ),
                flush: false
            )
            return
        }

        let widthDelta = size.width - previousSize.width
        let heightDelta = size.height - previousSize.height
        guard abs(widthDelta) >= 0.5 || abs(heightDelta) >= 0.5 else { return }

        ShatlMetricAnimationDiagnosticsLog.event(
            "metricset.layout.changed",
            fields: metricSetDiagnosticsFields(
                context: context,
                merging: sizeFields(previous: previousSize, current: size)
            ),
            flush: false
        )
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

        if hasMetricSetIconReplacement(from: oldItems.map(\.iconName), to: newItems.map(\.iconName)) {
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

}

#endif

private func hasMetricSetIconReplacement(from oldIcons: [String?], to newIcons: [String?]) -> Bool {
    zip(oldIcons, newIcons).contains { oldIconName, newIconName in
        guard let oldIconName, let newIconName else { return false }
        return oldIconName != newIconName
    }
}

#if DEBUG
private func metricSetDiagnosticsFields(
    context: MetricSetDiagnosticsContext,
    merging fields: [String: String]
) -> [String: String] {
    var resolvedFields: [String: String] = [
        "source": context.source,
        "torrentID": context.torrentID?.uuidString ?? "-",
        "groupID": context.groupID ?? "-",
        "status": context.cardStatus?.rawValue ?? "-",
        "progressPercent": context.progressPercent.map(String.init) ?? "-",
        "downloadSpeedBytesPerSecond": context.downloadSpeedBytesPerSecond.map(String.init) ?? "-",
        "etaSeconds": context.etaSeconds.map(String.init) ?? "-",
    ]

    for (key, value) in fields {
        resolvedFields[key] = value
    }

    return resolvedFields
}

private func metricSetElapsedMilliseconds(since startedAt: UInt64) -> String {
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
#endif

struct ShatlInfoBottomSpeedChip: View {
    let item: MetricItemPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    @ViewBuilder
    var body: some View {
        if #available(macOS 27.0, *) {
            glassChip
                .animation(ShatlMotion.metricResize, value: item.widthAnimationSignature)
        } else {
            // The same glass as on macOS 27. The list leaves no room under
            // the chips here, and a chip steps aside under the pointer.
            glassChip
                .scaleEffect(usesScaledHoverTransition && isHovered ? 0.85 : 1)
                .opacity(isHovered ? 0 : 1)
                .overlay {
                    Capsule()
                        .fill(Color.clear)
                }
                .contentShape(Capsule())
                .onHover { isHovered = $0 }
                .animation(ShatlMotion.mainContentMode, value: isHovered)
                .animation(ShatlMotion.metricResize, value: item.widthAnimationSignature)
        }
    }

    private var glassChip: some View {
        ShatlInfoBottomMetricItem(item: item)
            .padding(6)
            .glassEffect(
                .regular
                    .tint(.accent.opacity(ShatlGlassTint.subtleOpacity))
                    .interactive(false),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .fixedSize()
    }

    private var cornerRadius: CGFloat {
        if #available(macOS 27.0, *) {
            ShatlBottomChipLayout.modernCornerRadius
        } else {
            ShatlBottomChipLayout.legacyCornerRadius
        }
    }

    private var usesScaledHoverTransition: Bool {
        !reduceMotion
    }
}

private struct ShatlInfoBottomMetricItem: View {
    let item: MetricItemPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shatlRollsMetricDigits) private var rollsDigits

    var body: some View {
        HStack(spacing: 5) {
            if let iconName = item.iconName {
                Image(systemName: iconName)
                    .shatlTypography(iconTypography(for: iconName))
                    .foregroundStyle(ShatlColor.typographyPrimary)
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

        if !reduceMotion, rollsDigits {
            text
                .contentTransition(.numericText())
                .animation(ShatlMotion.metricResize, value: number)
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
    var isMuted = false
    var showsShadows = true
    #if DEBUG
    @Environment(\.shatlMetricSetDiagnosticsContext) private var diagnosticsContext
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.title)
                .shatlTypography(ShatlTypography.groupSemibold)
                .foregroundStyle(ShatlColor.typographySecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .shatlCardPreviewBlur(.metricGroupTitles)

            ShatlMetricSet(
                items: group.items,
                metricIconColorOverride: metricIconColorOverride,
                backgroundColorOverride: metricSetBackgroundColorOverride,
                outlineColorOverride: metricSetOutlineColorOverride,
                isMuted: isMuted,
                showsShadows: showsShadows
            )
            #if DEBUG
            .environment(\.shatlMetricSetDiagnosticsContext, diagnosticsContext?.withGroupID(group.id))
            #endif
            .shatlCardPreviewBlur(.expandedMetrics)
        }
        .layoutPriority(1)
    }
}

struct ShatlMetricGroupSet: View {
    let groups: [MetricGroupPresentation]
    var metricIconColorOverride: Color? = nil
    var metricSetBackgroundColorOverride: Color? = nil
    var metricSetOutlineColorOverride: Color? = nil
    var isMuted = false
    var showsShadows = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(groups) { group in
                ShatlMetricGroup(
                    group: group,
                    metricIconColorOverride: metricIconColorOverride,
                    metricSetBackgroundColorOverride: metricSetBackgroundColorOverride,
                    metricSetOutlineColorOverride: metricSetOutlineColorOverride,
                    isMuted: isMuted,
                    showsShadows: showsShadows
                )
                    .layoutPriority(1)
                    .transition(ShatlMotion.appearFromTop)
            }
        }
        .layoutPriority(1)
    }
}

struct ShatlPressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
