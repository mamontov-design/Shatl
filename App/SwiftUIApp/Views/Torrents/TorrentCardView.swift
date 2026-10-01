// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

enum TorrentCardLayout {
    static let compactExpandedMetricsWidth: CGFloat = 480
    static let compactExpandedMetricsHiddenIconGroupIDs: Set<String> = ["upload-speed", "uploaded", "size"]
}

private struct CompactTransferMetricAnimationKey: Equatable {
    var widthSignature: [MetricItemWidthAnimationSignature]?
    var colorizesDownloadSpeed: Bool
    var foldsDownloadSpeed: Bool
}

private struct ExpandedMetricAnimationKey: Equatable {
    var dynamicGroups: [MetricGroupWidthAnimationSignature]
    var sizeGroup: MetricGroupWidthAnimationSignature
}

private struct ProgressGroupResizeAnimationKey: Equatable {
    var iconName: String
    var textWidthPattern: String?
}

private struct TorrentProgressFillShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let horizontalInset: CGFloat = 3
        let fillHeight: CGFloat = 4
        let innerWidth = max(0, rect.width - horizontalInset * 2)
        let clampedProgress = min(max(progress, 0), 1)
        let fillWidth = min(innerWidth, max(4, innerWidth * clampedProgress))
        let fillRect = CGRect(
            x: rect.minX + horizontalInset,
            y: rect.midY - fillHeight / 2,
            width: fillWidth,
            height: fillHeight
        )

        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .path(in: fillRect)
    }
}

/// The steps a card takes into the one-line layout of a finished download.
/// They run one after another, each once the one before has settled, so the
/// parts of the card do not move all at once.
private enum TorrentCardFinishStage: Int, Comparable {
    /// Progress bar, and the status under the title.
    case regular
    /// The download has just finished: its speed set leaves, the new status
    /// shows for a second, then an open card closes. The expand button hides
    /// until the last step.
    case closing
    /// The badge and the status under the title have left together.
    case statusHidden
    /// The progress bar has left.
    case barHidden
    /// The title has slid aside, and the status badge has come in beside it,
    /// on one line.
    case merged
    /// The expand button is back.
    case finished

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What a card knew when it appeared. Not observed: it changes only while
/// the card already shows what it says.
private final class TorrentCardFinishSteps {
    /// Whether the card appeared with a finished download; nil before it did.
    var appearedFinished: Bool?
}

private enum TorrentCardOutlineState: Equatable {
    case normal
    case selected
    case error
}

enum TorrentCardPresentationMode {
    case normal
    case onboardingDemo

    var allowsHoverEffects: Bool {
        self == .normal
    }

    var allowsContextMenu: Bool {
        self == .normal
    }
}

struct TorrentCardView: View, Equatable {
    let row: TorrentRowState
    let resolvePrimaryLocation: @Sendable () async -> ManagedTorrentLocation?
    let onSelect: () -> Void
    let onToggleExpanded: () -> Void
    let onOpen: () -> Void
    let onRevealInFinder: () -> Void
    let onToggleRunningState: () -> Void
    let onRedownload: () -> Void
    let onChooseAnotherFolder: () -> Void
    let onRemove: () -> Void
    let onRemoveWithFiles: () -> Void
    /// Closes the card when its download finishes open.
    var onCollapse: () -> Void = {}
    var presentationMode: TorrentCardPresentationMode = .normal
    var isExpansionToggleEnabled = true
    var showsExpansionToggle = true
    var progressBarFillColorOverride: Color? = nil
    var progressGroupBackgroundColorOverride: Color? = nil
    var progressGroupForegroundColorOverride: Color? = nil
    var usesProductionProgressColors = false
    var usesProductionCardColors = false
    var cardBackgroundColorOverride: Color? = nil
    var cardOutlineColorOverride: Color? = nil
    var usesCompactExpandedMetricsLayout = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shatlTypographyProfile) private var typographyProfile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isExpandButtonHovered = false
    @State private var cardHoverIntent = TorrentCardHoverIntent()
    @State private var expandButtonHoverIntent = TorrentCardHoverIntent()
    @State private var isStatusBadgeHovered = false
    @State private var statusBadgeHoverIntent = TorrentCardHoverIntent()
    @State private var canOpenPrimaryItem = false
    @State private var canRevealInFinder = false
    /// Set once the card first changes its layout; see `layoutStage`.
    @State private var finishStage: TorrentCardFinishStage?
    @State private var finishSteps = TorrentCardFinishSteps()

    static func == (lhs: TorrentCardView, rhs: TorrentCardView) -> Bool {
        lhs.row == rhs.row
            && lhs.usesCompactExpandedMetricsLayout == rhs.usesCompactExpandedMetricsLayout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            torrentNameHeader

            if showsProgressBar {
                progressBar
                    .transition(progressBarTransition)
            }

            if layoutStage < .statusHidden {
                primaryMetricContainer
                    .transition(statusRowTransition)
            }

            if row.errorState == nil, row.isExpanded, let expandedMetricGroups = row.expandedMetricGroups {
                expandedContent(expandedMetricGroups)
                    .transition(ShatlMotion.appearFromTop)
            }

            if let errorState = row.errorState {
                errorBlock(errorState)
                    .transition(ShatlMotion.appearFromTop)
            }
        }
        .animation(ShatlMotion.cardLayout, value: row.isExpanded)
        .animation(ShatlMotion.cardLayout, value: row.errorState != nil)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            cardBackground
        }
        .background {
            if row.enablesCardLayoutDiagnostics {
                TorrentCardLayoutDiagnosticsProbe(
                    torrentID: row.id,
                    title: row.title,
                    signature: layoutSignature
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(ShatlMotion.cardState, value: isHovered)
        .animation(ShatlMotion.cardState, value: row.isSelected)
        .animation(ShatlMotion.cardState, value: row.errorState != nil)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(cardOutlineColor, lineWidth: cardOutlineLineWidth)
                .allowsHitTesting(false)
                .animation(ShatlMotion.cardState, value: cardOutlineState)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .contextMenu {
            if presentationMode.allowsContextMenu {
                contextMenuContent
            }
        }
        .task(id: row.navigationAvailabilityKey) {
            await refreshNavigationAvailability()
        }
        .task(id: row.usesFinishedLayout) {
            await followFinishedLayout()
        }
        .onHover { isInside in
            guard presentationMode.allowsHoverEffects else { return }
            setHover(isInside, intent: cardHoverIntent, isHovered: $isHovered)
        }
        .onTapGesture {
            if presentationMode == .normal {
                onSelect()
            }
        }
        // With many downloads running, the speed set stops bouncing and, at
        // the deepest level, digits stop rolling.
        .transformEnvironment(\.shatlMetricSetBounceEnabled) { isEnabled in
            if row.simplification > .full {
                isEnabled = false
            }
        }
        .environment(\.shatlRollsMetricDigits, row.simplification < .lightest)
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if row.errorState != nil {
            Button(role: .destructive, action: onRemove) {
                Label {
                    Text("torrent.action.remove_from_list")
                } icon: {
                    Image(systemName: "trash")
                }
            }
            .disabled(!row.canRemoveFromList)
        } else {
            Button(action: onOpen) {
                Label {
                    Text("torrent.action.open")
                } icon: {
                    Image(systemName: "arrow.up.forward")
                }
            }
            .disabled(!canOpenPrimaryItem)

            Button(action: onRevealInFinder) {
                Label {
                    Text("torrent.action.reveal_in_finder")
                } icon: {
                    Image(systemName: "finder")
                }
            }
            .disabled(!canRevealInFinder)

            Divider()

            Button(action: onToggleRunningState) {
                Label {
                    Text(LocalizedStringKey(row.status.isSleeping ? "torrent.action.start" : "torrent.action.stop"))
                } icon: {
                    Image(systemName: row.status.isSleeping ? "play" : "stop")
                }
            }
            .disabled(!row.canToggleRunningState)

            Divider()

            Button(role: .destructive, action: onRemove) {
                Label {
                    Text("torrent.action.remove_from_list")
                } icon: {
                    Image(systemName: "rectangle.stack.badge.minus")
                }
            }
            .disabled(!row.canRemoveFromList)

            Button(role: .destructive, action: onRemoveWithFiles) {
                Label {
                    Text("torrent.action.remove_with_files")
                } icon: {
                    Image(systemName: "externaldrive.badge.xmark")
                }
            }
            .disabled(!row.canRemoveWithFiles)
        }
    }

    private var torrentNameHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            nameExpandMark

            if row.hasAlias && row.errorState != nil {
                originalTitleLine
            }
        }
    }

    private var nameExpandMark: some View {
        HStack(spacing: 8) {
            if layoutStage >= .merged {
                // Comes in once the title is out of its way, and names the
                // status under a resting pointer.
                progressGroup
                    .onHover { isInside in
                        guard presentationMode.allowsHoverEffects else { return }
                        setHover(isInside, intent: statusBadgeHoverIntent, isHovered: $isStatusBadgeHovered)
                    }
                    .accessibilityLabel(Text(row.statusTitle))
                    .transition(ShatlMotion.finishedStatusBesideTitle)
            }

            Text(row.title)
                .shatlTypography(ShatlTypography.bodySemibold)
                .foregroundStyle(ShatlColor.typographyPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.interpolate)

            if row.errorState == nil, showsExpansionToggle {
                ZStack {
                    if showsExpandButton {
                        expandButton
                            .transition(ShatlMotion.appearFromTop)
                    }
                }
                .frame(width: 18, height: 18)
                .animation(ShatlMotion.metricResize, value: showsExpandButton)
            }

            if row.isSelected {
                selectedIndicator
                    .transition(ShatlMotion.selectedIndicator)
            }
        }
        .animation(ShatlMotion.cardControlSlide, value: row.errorState != nil)
        .animation(ShatlMotion.cardControlSlide, value: row.isExpanded)
        .animation(ShatlMotion.cardControlSlide, value: row.isSelected)
        // The badge beside the title widens with its status under the
        // pointer, or with a new status, and the title moves with it.
        .animation(ShatlMotion.progressGroupResize, value: isStatusBadgeHovered)
        .animation(ShatlMotion.progressStatusReplace, value: statusPresentationKey)
    }

    /// Hidden while a finished download takes its steps, so a click cannot
    /// open the card halfway through.
    private var showsExpandButton: Bool {
        row.canExpand && (layoutStage == .regular || layoutStage == .finished)
    }

    private var expandButton: some View {
        Button {
            onToggleExpanded()
        } label: {
            Image(systemName: row.isExpanded ? "arrow.up.right.and.arrow.down.left" : "arrow.down.left.and.arrow.up.right")
                .shatlTypography(ShatlTypography.bodyRegular)
                .foregroundStyle(expandButtonForegroundColor)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isExpansionToggleEnabled)
        .onHover { isInside in
            guard isExpansionToggleEnabled else { return }
            guard presentationMode.allowsHoverEffects else { return }
            setHover(isInside, intent: expandButtonHoverIntent, isHovered: $isExpandButtonHovered)
        }
        .animation(ShatlMotion.cardState, value: isExpandButtonHovered)
        .animation(ShatlMotion.cardControlSlide, value: row.isExpanded)
    }

    /// Lights up once the pointer rests; goes dark at once. See
    /// `TorrentCardHoverTiming`.
    private func setHover(_ isInside: Bool, intent: TorrentCardHoverIntent, isHovered: Binding<Bool>) {
        if isInside {
            intent.pointerEntered {
                if !isHovered.wrappedValue {
                    isHovered.wrappedValue = true
                }
            }
        } else {
            intent.pointerExited()
            if isHovered.wrappedValue {
                isHovered.wrappedValue = false
            }
        }
    }

    private var expandButtonForegroundColor: Color {
        return isExpandButtonHovered ? ShatlColor.accent : ShatlColor.typographyTertiary
    }

    private var selectedIndicator: some View {
        Image(systemName: "checkmark.circle.fill")
            .shatlTypography(ShatlTypography.bodyRegular)
            .foregroundStyle(row.errorState == nil ? ShatlColor.accent : ShatlColor.cerisePink)
    }

    private var primaryMetricContainer: some View {
        HStack(spacing: 8) {
            statusBadge
            compactTransferMetricContainer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactTransferMetricContainer: some View {
        ZStack(alignment: .trailing) {
            if let transferMetricSet = row.compactTransferMetricSet {
                transferMetricSetView(transferMetricSet)
                    .fixedSize(horizontal: true, vertical: false)
                    .geometryGroup()
                    .transition(ShatlMotion.appearFromTop)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(ShatlMotion.metricResize, value: compactTransferMetricAnimationKey)
    }

    private var compactTransferMetricAnimationKey: CompactTransferMetricAnimationKey {
        CompactTransferMetricAnimationKey(
            widthSignature: row.compactTransferMetricSet?.items.metricWidthAnimationSignature,
            colorizesDownloadSpeed: row.colorizesDownloadSpeed,
            foldsDownloadSpeed: foldsDownloadSpeed
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            progressGroup

            if statusKind != .error {
                statusTitle
                    .transition(.blurReplace)
            }
        }
        .animation(ShatlMotion.progressStatusReplace, value: statusPresentationKey)
    }

    private var statusTitle: some View {
        Text(row.statusTitle)
            .shatlTypography(ShatlTypography.metricSemibold)
            .foregroundStyle(ShatlColor.typographyPrimary)
            .id(statusPresentationKey)
    }

    private func transferMetricSetView(_ metricSet: CompactTransferMetricSet) -> some View {
        ShatlMetricSet(
            items: metricSet.items,
            backgroundColorOverride: metricSetBackgroundColorOverride,
            outlineColorOverride: metricSetOutlineColorOverride,
            colorizesDownloadSpeed: row.colorizesDownloadSpeed,
            showsShadows: showsMetricShadows,
            foldsDownloadSpeed: foldsDownloadSpeed,
            outlinesUnfoldedSpeedLevelChange: row.simplification.outlinesUnfoldedSpeedLevelChange,
            diagnosticsContext: metricDiagnosticsContext(source: "compactTransfer")
        )
    }

    private func expandedContent(_ metricGroups: ExpandedMetricGroupsPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if row.hasAlias {
                originalTitleLine
            }

            cardDivider
            extraMetric(metricGroups)
        }
    }

    private func extraMetric(_ metricGroups: ExpandedMetricGroupsPresentation) -> some View {
        let dynamicGroups = compactedDynamicMetricGroups(metricGroups.dynamicGroups)
        let sizeGroup = compactedMetricGroup(metricGroups.sizeGroup)
        let animationKey = ExpandedMetricAnimationKey(
            dynamicGroups: dynamicGroups.groupWidthAnimationSignature,
            sizeGroup: sizeGroup.widthAnimationSignature
        )

        return HStack(alignment: .bottom, spacing: 0) {
            if !dynamicGroups.isEmpty {
                ShatlMetricGroupSet(
                    groups: dynamicGroups,
                    metricSetBackgroundColorOverride: metricSetBackgroundColorOverride,
                    metricSetOutlineColorOverride: metricSetOutlineColorOverride,
                    showsShadows: showsMetricShadows,
                    diagnosticsContext: metricDiagnosticsContext(source: "expandedDynamic")
                )
                    .layoutPriority(2)
                    .transition(ShatlMotion.appearFromTop)

                Spacer(minLength: 10)
                    .layoutPriority(0)
            }

            ShatlMetricGroup(
                group: sizeGroup,
                metricSetBackgroundColorOverride: metricSetBackgroundColorOverride,
                metricSetOutlineColorOverride: metricSetOutlineColorOverride,
                showsShadows: showsMetricShadows,
                diagnosticsContext: metricDiagnosticsContext(source: "expandedSize")
            )
                .layoutPriority(1)
        }
        .geometryGroup()
        .animation(ShatlMotion.metricResize, value: animationKey)
    }

    /// Only in the list: the onboarding and the settings preview have no
    /// pointer to unfold it.
    private var foldsDownloadSpeed: Bool {
        presentationMode == .normal && row.simplification.foldsDownloadSpeed
    }

    /// Off from the first card simplification.
    private var showsMetricShadows: Bool {
        row.simplification == .full
    }

    private var hidesExpandedMetricIcons: Bool {
        row.metricsMode == .detailed
            && usesCompactExpandedMetricsLayout
    }

    private func metricDiagnosticsContext(source: String) -> MetricSetDiagnosticsContext? {
        guard row.enablesMetricAnimationDiagnostics else { return nil }

        return MetricSetDiagnosticsContext(
            source: source,
            torrentID: row.id,
            groupID: nil,
            cardStatus: row.status,
            progressPercent: progressPercent,
            downloadSpeedBytesPerSecond: nil,
            etaSeconds: nil
        )
    }

    private func compactedDynamicMetricGroups(_ groups: [MetricGroupPresentation]) -> [MetricGroupPresentation] {
        groups.map(compactedMetricGroup)
    }

    private func compactedMetricGroup(_ group: MetricGroupPresentation) -> MetricGroupPresentation {
        if presentationMode == .onboardingDemo {
            var compactedGroup = group
            compactedGroup.items = compactedGroup.items.map { item in
                var compactedItem = item
                compactedItem.iconName = nil
                return compactedItem
            }
            return compactedGroup
        }

        guard hidesExpandedMetricIcons,
              TorrentCardLayout.compactExpandedMetricsHiddenIconGroupIDs.contains(group.id)
        else {
            return group
        }

        var compactedGroup = group
        compactedGroup.items = compactedGroup.items.map { item in
            var compactedItem = item
            compactedItem.iconName = nil
            return compactedItem
        }
        return compactedGroup
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(ShatlColor.outlineSecondary)
            .frame(height: 1)
    }

    private var progressGroup: some View {
        progressGroupContent
        .animation(ShatlMotion.progressGroupResize, value: progressGroupResizeAnimationKey)
        .animation(ShatlMotion.cardState, value: statusKind)
        .animation(ShatlMotion.cardState, value: usesHoverStatusPalette)
    }

    private var progressGroupResizeAnimationKey: ProgressGroupResizeAnimationKey {
        ProgressGroupResizeAnimationKey(
            iconName: progressIconName,
            textWidthPattern: progressText.map(MetricWidthAnimationPattern.forText)
        )
    }

    private var progressGroupContent: some View {
        HStack(spacing: 4) {
            Image(systemName: progressIconName)
                .shatlTypography(ShatlTypography.metricSemibold)
                .foregroundStyle(progressGroupForegroundColor)
                .contentTransition(.symbolEffect(.replace))
                .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
                .frame(minWidth: progressIconMinimumWidth)

            if let progressText {
                Text(progressText)
                    .shatlTypography(ShatlTypography.metricSemibold)
                    .foregroundStyle(progressGroupForegroundColor)
                    .monospacedDigit()
                    .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
            }
        }
        .padding(Self.progressGroupPadding)
        .frame(minWidth: progressGroupMinimumWidth, alignment: .center)
        .background(progressGroupColor)
        .clipShape(progressGroupShape)
        .overlay {
            progressGroupShape
                .strokeBorder(pendingProgressGroupBorderColor, lineWidth: 1)
                .opacity(row.isPendingAddition ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(height: ShatlMetricLayout.containerHeight)
        .animation(ShatlMotion.cardState, value: row.isPendingAddition)
    }

    private static let progressGroupPadding: CGFloat = 6

    /// A badge with its icon alone centres the icon in its minimum width; one
    /// with text puts the icon at its padding. Beside the title, where the
    /// badge opens under the pointer, the icon keeps a box as wide as that
    /// centre, so it stays put as the status comes in.
    private var progressIconMinimumWidth: CGFloat? {
        guard layoutStage >= .merged else { return nil }
        return progressGroupMinimumWidth - Self.progressGroupPadding * 2
    }

    private var progressGroupMinimumWidth: CGFloat {
        switch typographyProfile {
        case .standard:
            27
        case .cjk:
            28
        }
    }

    private var progressGroupShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private var usesHoverStatusPalette: Bool {
        presentationMode == .normal && (isHovered || row.isSelected)
    }

    private var statusKind: TorrentStatus {
        row.errorState == nil ? row.status : .error
    }

    private var statusPresentationKey: String {
        row.isPendingAddition ? "pending-addition" : statusKind.rawValue
    }

    private var progressIconName: String {
        if row.isPendingAddition {
            return "clock.fill"
        }

        switch statusKind {
        case .downloading:
            return "square.and.arrow.down.fill"
        case .stopped:
            return "stop.fill"
        case .seeding:
            return "square.and.arrow.up.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .checking:
            return "text.magnifyingglass"
        }
    }

    private var progressText: String? {
        if row.isPendingAddition {
            return nil
        }

        if layoutStage >= .merged {
            // One line: the badge names the status only under the pointer.
            return isStatusBadgeHovered ? row.statusTitle : nil
        }

        switch statusKind {
        case .seeding, .completed:
            return nil
        case .error:
            return row.statusTitle
        case .downloading, .stopped, .checking:
            guard progressPercent >= 1 else { return nil }
            return "\(progressPercent)%"
        }
    }

    private var progressPercent: Int {
        Int((clampedProgress * 100).rounded(.down))
    }

    private var progressGroupColor: Color {
        if let progressGroupBackgroundColorOverride {
            return progressGroupBackgroundColorOverride
        }

        if presentationMode == .onboardingDemo, !usesProductionProgressColors {
            return ShatlColor.backgroundPrimary
        }

        if row.isPendingAddition {
            return .clear
        }

        switch statusKind {
        case .downloading, .checking:
            return usesHoverStatusPalette
                ? ShatlColor.statusBadgeDownloadingHover
                : ShatlColor.statusBadgeDownloadingDefault
        case .stopped:
            return usesHoverStatusPalette
                ? ShatlColor.statusBadgePausedHover
                : ShatlColor.statusBadgePausedDefault
        case .seeding:
            return usesHoverStatusPalette
                ? ShatlColor.statusBadgeSeedingHover
                : ShatlColor.statusBadgeSeedingDefault
        case .completed:
            return usesHoverStatusPalette
                ? ShatlColor.statusBadgeCompletedHover
                : ShatlColor.statusBadgeCompletedDefault
        case .error:
            return usesHoverStatusPalette
                ? ShatlColor.statusBadgeErrorHover
                : ShatlColor.statusBadgeErrorDefault
        }
    }

    private var pendingProgressGroupBorderColor: Color {
        usesHoverStatusPalette
            ? ShatlColor.statusBadgeDownloadingHover
            : ShatlColor.statusBadgeDownloadingDefault
    }

    private var progressGroupForegroundColor: Color {
        if let progressGroupForegroundColorOverride {
            return progressGroupForegroundColorOverride
        }

        if presentationMode == .onboardingDemo, !usesProductionProgressColors {
            return ShatlColor.typographyPrimary
        }

        switch statusKind {
        case .downloading, .checking:
            return usesHoverStatusPalette
                ? ShatlColor.statusTextDownloadingHover
                : ShatlColor.statusTextDownloadingDefault
        case .stopped:
            return usesHoverStatusPalette
                ? ShatlColor.statusTextPausedHover
                : ShatlColor.statusTextPausedDefault
        case .seeding:
            return usesHoverStatusPalette
                ? ShatlColor.statusTextSeedingHover
                : ShatlColor.statusTextSeedingDefault
        case .completed:
            return usesHoverStatusPalette
                ? ShatlColor.statusTextCompletedHover
                : ShatlColor.statusTextCompletedDefault
        case .error:
            return usesHoverStatusPalette
                ? ShatlColor.statusTextErrorHover
                : ShatlColor.statusTextErrorDefault
        }
    }

    private var metricSetBackgroundColorOverride: Color? {
        presentationMode == .onboardingDemo && !usesProductionCardColors && colorScheme == .dark
            ? ShatlColor.backgroundPrimary
            : nil
    }

    private var metricSetOutlineColorOverride: Color? {
        presentationMode == .onboardingDemo && !usesProductionCardColors && colorScheme == .dark
            ? ShatlColor.backgroundPrimary
            : nil
    }

    private var cardOutlineState: TorrentCardOutlineState {
        if row.errorState != nil {
            return .error
        }

        return row.isSelected ? .selected : .normal
    }

    private var cardOutlineColor: Color {
        switch cardOutlineState {
        case .normal:
            cardOutlineColorOverride ?? ShatlColor.outlinePrimary
        case .selected:
            ShatlColor.accent
        case .error:
            ShatlColor.cerisePink
        }
    }

    private var cardOutlineLineWidth: CGFloat {
        cardOutlineState == .selected ? 1 : 0.5
    }

    private var originalTitleLine: some View {
        Text(
            L10n.format(
                "torrent.card.original_title",
                localeOverride: row.localeOverride,
                defaultValue: "Название торрента — %@",
                row.originalTitle
            )
        )
            .shatlTypography(ShatlTypography.captionRegular)
            .foregroundStyle(ShatlColor.typographySecondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var showsProgressBar: Bool {
        row.errorState == nil && layoutStage < .barHidden
    }

    /// Where the card stands on its way to the finished layout. A card built
    /// for a finished download, at launch too, is one line from the start.
    /// After that the card changes its layout only in `followFinishedLayout`,
    /// inside an animation, so the cards below move with it.
    private var layoutStage: TorrentCardFinishStage {
        if let finishStage {
            return finishStage
        }
        let isFinished = finishSteps.appearedFinished ?? row.usesFinishedLayout
        return isFinished ? .finished : .regular
    }

    /// Parts leave on the way to the finished layout the way the speed set does.
    private func finishStepTransition(otherwise transition: AnyTransition) -> AnyTransition {
        layoutStage == .regular ? transition : ShatlMotion.appearFromTop
    }

    /// The bar comes back once the title above it has settled: the card
    /// grows around its new parts, and a bar that showed at once would pass
    /// under the title.
    private var progressBarTransition: AnyTransition {
        .asymmetric(
            insertion: ShatlMotion.finishedCardPartReturn,
            removal: finishStepTransition(otherwise: .opacity)
        )
    }

    /// The badge and the status under the title leave as one, the way the
    /// speed set does, shrinking towards the edge they sit at; on the way
    /// back they come in with the bar.
    private var statusRowTransition: AnyTransition {
        .asymmetric(
            insertion: ShatlMotion.finishedCardPartReturn,
            removal: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity)
        )
    }

    /// Takes a download that finished in view into the one-line layout step
    /// by step, each step once the one before has settled. A finished
    /// download that starts again or fails goes back in one move.
    private func followFinishedLayout() async {
        guard finishSteps.appearedFinished != nil else {
            finishSteps.appearedFinished = row.usesFinishedLayout
            return
        }

        guard row.usesFinishedLayout else {
            // The badge beside the title leaves; so does its pointer.
            statusBadgeHoverIntent.pointerExited()
            if isStatusBadgeHovered {
                isStatusBadgeHovered = false
            }
            guard layoutStage != .regular else { return }
            withAnimation(reduceMotion ? nil : ShatlMotion.cardLayout) {
                finishStage = .regular
            }
            return
        }

        guard layoutStage < .finished else { return }

        if reduceMotion || presentationMode != .normal {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                onCollapse()
                finishStage = .finished
            }
            return
        }

        if layoutStage < .closing {
            withAnimation(ShatlMotion.metricResize) {
                finishStage = .closing
            }
            // The speed set leaves and the status changes with the finish;
            // the new status stays a moment before the card rearranges.
            guard await settle(for: ShatlMotion.finishedCardPause) else { return }
        }

        // With many downloads running the list has no room for the steps.
        if row.simplification == .lightest {
            withAnimation(ShatlMotion.cardLayout) {
                onCollapse()
                finishStage = .finished
            }
            return
        }

        if layoutStage < .statusHidden, row.isExpanded {
            withAnimation(ShatlMotion.cardLayout) {
                onCollapse()
            }
            guard await settle(for: ShatlMotion.cardLayoutDuration) else { return }
        }

        if layoutStage < .statusHidden {
            withAnimation(ShatlMotion.metricResize) {
                finishStage = .statusHidden
            }
            guard await settle(for: ShatlMotion.metricResizeDuration) else { return }
        }

        if layoutStage < .barHidden {
            withAnimation(ShatlMotion.metricResize) {
                finishStage = .barHidden
            }
            guard await settle(for: ShatlMotion.metricResizeDuration) else { return }
        }

        if layoutStage < .merged {
            withAnimation(ShatlMotion.cardLayout) {
                finishStage = .merged
            }
            guard await settle(for: ShatlMotion.finishedStatusSettleDuration) else { return }
        }

        withAnimation(ShatlMotion.metricResize) {
            finishStage = .finished
        }
    }

    /// Waits for a step to settle; false once the steps are called off.
    private func settle(for duration: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(duration))
            return true
        } catch {
            return false
        }
    }

    private var progressBar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(ShatlColor.progressBarTrack)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(ShatlColor.outlinePrimary, lineWidth: 1)
                }

            TorrentProgressFillShape(progress: CGFloat(displayedBarProgress))
                .fill(progressBarFillColor)
                .animation(ShatlMotion.progressBarFill, value: displayedBarProgress)
                .animation(ShatlMotion.progressBarFill, value: isProgressBarComplete)
        }
        .frame(height: 10)
    }

    private var progressBarFillColor: Color {
        if let progressBarFillColorOverride {
            return progressBarFillColorOverride
        }

        return isProgressBarComplete ? ShatlColor.outlinePrimary : ShatlColor.typographyPrimary
    }

    private var isProgressBarComplete: Bool {
        row.status == .completed || row.status == .seeding || clampedProgress >= 1
    }

    /// The bar moves in steps, longer ones with many downloads running; see
    /// `TorrentProgressBarSteps`.
    private var displayedBarProgress: Double {
        TorrentProgressBarSteps.displayedProgress(row.progress, simplification: row.simplification)
    }

    private var clampedProgress: Double {
        min(max(row.progress, 0), 1)
    }

    private func errorBlock(_ errorState: TorrentRowErrorState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(errorState.message)
                .shatlTypography(ShatlTypography.captionRegular)
                .foregroundStyle(ShatlColor.typographySecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !errorState.recoveryOptions.isEmpty {
                HStack(spacing: 6) {
                    if errorState.recoveryOptions.contains(.redownload) {
                        ShatlButton(localizedTitle: "torrent.action.redownload", role: .borderedNeutral, action: onRedownload)
                    }

                    if errorState.recoveryOptions.contains(.chooseAnotherFolder) {
                        ShatlButton(
                            localizedTitle: "torrent.action.download_to_another_folder",
                            role: .borderedNeutral,
                            action: onChooseAnotherFolder
                        )
                    }

                    if errorState.recoveryOptions.contains(.removeFromList) {
                        ShatlButton(localizedTitle: "torrent.action.remove_from_list", role: .borderedNeutral, action: onRemove)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backgroundColor: Color {
        if let cardBackgroundColorOverride {
            return cardBackgroundColorOverride
        }

        if presentationMode == .onboardingDemo, !usesProductionCardColors {
            return ShatlColor.onboardingForeground
        }

        if row.isSelected {
            if row.errorState != nil {
                return ShatlColor.cardSelectedError
            }

            return ShatlColor.cardDefault
        }

        return isHovered ? ShatlColor.cardHover : ShatlColor.cardDefault
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(backgroundColor)
    }

    private var layoutSignature: TorrentCardLayoutSignature {
        TorrentCardLayoutSignature(
            status: row.status,
            progressPercent: progressPercent,
            showsProgressBar: showsProgressBar,
            finishStage: "\(layoutStage)",
            hasCompactTransferMetricSet: row.compactTransferMetricSet != nil,
            compactTransferItemIDs: row.compactTransferMetricSet?.items.map(\.id) ?? [],
            isExpanded: row.isExpanded,
            hasExpandedMetricGroups: row.expandedMetricGroups != nil,
            expandedDynamicGroupIDs: row.expandedMetricGroups?.dynamicGroups.map(\.id) ?? [],
            hasError: row.errorState != nil,
            hasAlias: row.hasAlias
        )
    }

    @MainActor
    private func refreshNavigationAvailability() async {
        guard presentationMode == .normal else {
            canOpenPrimaryItem = false
            canRevealInFinder = false
            return
        }

        guard row.errorState == nil, !row.isPendingAddition else {
            canOpenPrimaryItem = false
            canRevealInFinder = false
            return
        }

        guard let location = await resolvePrimaryLocation() else {
            canOpenPrimaryItem = false
            canRevealInFinder = false
            return
        }

        canOpenPrimaryItem = location.openItemURL != nil
        canRevealInFinder = true
    }

}

private struct TorrentCardLayoutDiagnosticsProbe: View {
    let torrentID: UUID
    let title: String
    let signature: TorrentCardLayoutSignature

    @State private var lastProbe: TorrentCardLayoutProbe?

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    recordLayoutProbe(height: proxy.size.height)
                }
                .onChange(of: proxy.size.height) { _, height in
                    recordLayoutProbe(height: height)
                }
                .onChange(of: signature) { _, _ in
                    recordLayoutProbe(height: proxy.size.height)
                }
        }
    }

    private func recordLayoutProbe(height: CGFloat?) {
        guard ShatlCardLayoutDiagnosticsLog.isEnabled else { return }

        let probe = TorrentCardLayoutProbe(height: height, signature: signature)
        defer {
            lastProbe = probe
        }

        guard let previous = lastProbe else {
            ShatlCardLayoutDiagnosticsLog.write(
                "torrent-card.layout.initial \(layoutLogFields(previous: nil, current: probe))"
            )
            return
        }

        let heightDelta = (probe.height ?? previous.height ?? 0) - (previous.height ?? probe.height ?? 0)
        guard abs(heightDelta) >= 0.5 || probe.signature != previous.signature else { return }

        let event = heightDelta < -0.5 ? "torrent-card.layout.shrink" : "torrent-card.layout.change"
        ShatlCardLayoutDiagnosticsLog.write(
            "\(event) \(layoutLogFields(previous: previous, current: probe))"
        )
    }

    private func layoutLogFields(
        previous: TorrentCardLayoutProbe?,
        current: TorrentCardLayoutProbe
    ) -> String {
        let previousHeight = previous?.height.map { formatLayoutNumber($0) } ?? "-"
        let currentHeight = current.height.map { formatLayoutNumber($0) } ?? "-"
        let delta = previous?.height.flatMap { oldHeight in
            current.height.map { formatLayoutNumber($0 - oldHeight) }
        } ?? "-"

        return [
            "id=\(torrentID.uuidString)",
            "title=\"\(escapedLayoutValue(title))\"",
            "height.previous=\(previousHeight)",
            "height.current=\(currentHeight)",
            "height.delta=\(delta)",
            "status.previous=\(previous?.signature.status.rawValue ?? "-")",
            "status.current=\(current.signature.status.rawValue)",
            "progress.previous=\(previous?.signature.progressPercent.description ?? "-")",
            "progress.current=\(current.signature.progressPercent)",
            "progressBar.previous=\(previous?.signature.showsProgressBar.description ?? "-")",
            "progressBar.current=\(current.signature.showsProgressBar)",
            "finish.previous=\(previous?.signature.finishStage ?? "-")",
            "finish.current=\(current.signature.finishStage)",
            "compactTransfer.previous=\(previous?.signature.hasCompactTransferMetricSet.description ?? "-")",
            "compactTransfer.current=\(current.signature.hasCompactTransferMetricSet)",
            "compactItems.previous=\(previous?.signature.compactTransferItemIDs.joined(separator: ",") ?? "-")",
            "compactItems.current=\(current.signature.compactTransferItemIDs.joined(separator: ","))",
            "expanded.previous=\(previous?.signature.isExpanded.description ?? "-")",
            "expanded.current=\(current.signature.isExpanded)",
            "expandedGroups.previous=\(previous?.signature.expandedDynamicGroupIDs.joined(separator: ",") ?? "-")",
            "expandedGroups.current=\(current.signature.expandedDynamicGroupIDs.joined(separator: ","))",
            "hasError.previous=\(previous?.signature.hasError.description ?? "-")",
            "hasError.current=\(current.signature.hasError)",
            "hasAlias=\(current.signature.hasAlias)"
        ].joined(separator: " ")
    }
}

private struct TorrentCardLayoutProbe: Equatable {
    var height: CGFloat?
    var signature: TorrentCardLayoutSignature
}

private struct TorrentCardLayoutSignature: Equatable {
    var status: TorrentStatus
    var progressPercent: Int
    var showsProgressBar: Bool
    var finishStage: String
    var hasCompactTransferMetricSet: Bool
    var compactTransferItemIDs: [String]
    var isExpanded: Bool
    var hasExpandedMetricGroups: Bool
    var expandedDynamicGroupIDs: [String]
    var hasError: Bool
    var hasAlias: Bool
}

private func formatLayoutNumber(_ value: CGFloat) -> String {
    String(format: "%.1f", Double(value))
}

private func escapedLayoutValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
