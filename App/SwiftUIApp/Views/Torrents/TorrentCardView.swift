import SwiftUI

private enum TorrentCardLayout {
    static let compactExpandedMetricsWidth: CGFloat = 480
    static let compactExpandedMetricsHiddenIconGroupIDs: Set<String> = ["upload-speed", "uploaded", "size"]
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
    var presentationMode: TorrentCardPresentationMode = .normal
    var isExpansionToggleEnabled = true
    var showsExpansionToggle = true
    var progressBarFillColorOverride: Color? = nil
    var usesProductionProgressColors = false
    var cardBackgroundColorOverride: Color? = nil
    var cardOutlineColorOverride: Color? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shatlTypographyProfile) private var typographyProfile
    @State private var isHovered = false
    @State private var isExpandButtonHovered = false
    @State private var canOpenPrimaryItem = false
    @State private var canRevealInFinder = false
    @State private var cardWidth: CGFloat = 0
    @State private var lastLayoutProbe: TorrentCardLayoutProbe?

    static func == (lhs: TorrentCardView, rhs: TorrentCardView) -> Bool {
        lhs.row == rhs.row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            torrentNameHeader

            if showsProgressBar {
                progressBar
                    .transition(.opacity)
            }

            primaryMetricContainer

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
        .background(cardLayoutProbeReader)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(ShatlMotion.cardState, value: isHovered)
        .animation(ShatlMotion.cardState, value: row.isSelected)
        .animation(ShatlMotion.cardState, value: row.errorState != nil)
        .overlay {
            if let cardOutlineColorOverride {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(cardOutlineColorOverride, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selectedOutlineColor, lineWidth: 1)
                .opacity(row.isSelected && row.errorState == nil ? 1 : 0)
                .allowsHitTesting(false)
                .animation(ShatlMotion.cardState, value: row.isSelected)
                .animation(ShatlMotion.cardState, value: row.errorState != nil)
        }
        .overlay {
            if row.errorState != nil {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(ShatlColor.cerisePink, lineWidth: 1)
                    .transition(.opacity)
            }
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
        .onPreferenceChange(TorrentCardHeightPreferenceKey.self) { height in
            recordLayoutProbe(height: height)
        }
        .onPreferenceChange(TorrentCardWidthPreferenceKey.self) { width in
            guard let width, abs(width - cardWidth) >= 0.5 else { return }
            cardWidth = width
        }
        .onChange(of: layoutSignature) { _, _ in
            recordLayoutProbe(height: lastLayoutProbe?.height)
        }
        .onHover { isHovered in
            guard presentationMode.allowsHoverEffects else { return }
            self.isHovered = isHovered
        }
        .onTapGesture {
            if presentationMode == .normal {
                onSelect()
            }
        }
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
            Text(row.title)
                .shatlTypography(ShatlTypography.bodySemibold)
                .foregroundStyle(ShatlColor.typographyPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if row.errorState == nil, showsExpansionToggle {
                expandButton
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if row.isSelected {
                selectedIndicator
                    .transition(ShatlMotion.selectedIndicator)
            }
        }
        .animation(ShatlMotion.cardControlSlide, value: row.errorState != nil)
        .animation(ShatlMotion.cardControlSlide, value: row.isExpanded)
        .animation(ShatlMotion.cardControlSlide, value: row.isSelected)
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
        .onHover { isHovered in
            guard isExpansionToggleEnabled else { return }
            guard presentationMode.allowsHoverEffects else { return }
            isExpandButtonHovered = isHovered
        }
        .animation(ShatlMotion.cardState, value: isExpandButtonHovered)
        .animation(ShatlMotion.cardControlSlide, value: row.isExpanded)
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

            Spacer(minLength: 8)

            if let transferMetricSet = row.compactTransferMetricSet {
                transferMetricSetView(transferMetricSet)
                    .transition(ShatlMotion.appearFromTop)
            }
        }
        .animation(ShatlMotion.metricResize, value: row.compactTransferMetricSet)
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            progressGroup

            if statusKind != .error {
                Text(row.statusTitle)
                    .shatlTypography(ShatlTypography.metricSemibold)
                    .foregroundStyle(ShatlColor.typographyPrimary)
                    .id(statusKind)
                    .transition(.blurReplace)
            }
        }
        .animation(ShatlMotion.progressStatusReplace, value: statusKind)
    }

    private func transferMetricSetView(_ metricSet: CompactTransferMetricSet) -> some View {
        ShatlMetricSet(
            items: metricSet.items,
            backgroundColorOverride: metricSetBackgroundColorOverride,
            outlineColorOverride: metricSetOutlineColorOverride,
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
        HStack(alignment: .bottom, spacing: 0) {
            if !metricGroups.dynamicGroups.isEmpty {
                ShatlMetricGroupSet(
                    groups: compactedDynamicMetricGroups(metricGroups.dynamicGroups),
                    metricSetBackgroundColorOverride: metricSetBackgroundColorOverride,
                    metricSetOutlineColorOverride: metricSetOutlineColorOverride,
                    metricSetHorizontalPadding: expandedMetricSetHorizontalPadding,
                    diagnosticsContext: metricDiagnosticsContext(source: "expandedDynamic")
                )
                    .layoutPriority(2)
                    .transition(ShatlMotion.appearFromTop)

                Spacer(minLength: 10)
                    .layoutPriority(0)
            }

            ShatlMetricGroup(
                group: compactedMetricGroup(metricGroups.sizeGroup),
                metricSetBackgroundColorOverride: metricSetBackgroundColorOverride,
                metricSetOutlineColorOverride: metricSetOutlineColorOverride,
                metricSetHorizontalPadding: expandedMetricSetHorizontalPadding,
                diagnosticsContext: metricDiagnosticsContext(source: "expandedSize")
            )
                .layoutPriority(1)
        }
        .animation(ShatlMotion.metricResize, value: metricGroups.dynamicGroups.isEmpty)
        .animation(ShatlMotion.metricResize, value: metricGroups.dynamicGroups)
        .animation(ShatlMotion.metricResize, value: hidesExpandedMetricIcons)
    }

    private var hidesExpandedMetricIcons: Bool {
        row.metricsMode == .detailed
            && cardWidth > 0
            && cardWidth < TorrentCardLayout.compactExpandedMetricsWidth
    }

    private func metricDiagnosticsContext(source: String) -> MetricSetDiagnosticsContext {
        MetricSetDiagnosticsContext(
            source: source,
            torrentID: row.id,
            groupID: nil,
            cardStatus: row.status,
            progressPercent: progressPercent,
            downloadSpeedBytesPerSecond: row.downloadSpeedBytesPerSecond,
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
        .animation(ShatlMotion.progressGroupResize, value: progressIconName)
        .animation(ShatlMotion.progressGroupResize, value: progressText)
        .animation(ShatlMotion.cardState, value: statusKind)
        .animation(ShatlMotion.cardState, value: usesHoverStatusPalette)
    }

    private var progressGroupContent: some View {
        HStack(spacing: 4) {
            Image(systemName: progressIconName)
                .shatlTypography(ShatlTypography.metricSemibold)
                .foregroundStyle(progressGroupForegroundColor)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(
                    progressIconSymbolEffect,
                    options: ShatlMotion.progressDownloadSymbolEffectOptions,
                    isActive: showsProgressIconActivity
                )
                .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)

            if let progressText {
                Text(progressText)
                    .shatlTypography(ShatlTypography.metricSemibold)
                    .foregroundStyle(progressGroupForegroundColor)
                    .monospacedDigit()
                    .frame(height: ShatlMetricLayout.contentHeight, alignment: .center)
            }
        }
        .padding(6)
        .frame(minWidth: progressGroupMinimumWidth, alignment: .center)
        .background(progressGroupColor)
        .clipShape(progressGroupShape)
        .frame(height: ShatlMetricLayout.containerHeight)
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

    private var progressIconName: String {
        switch statusKind {
        case .downloading:
            "square.and.arrow.down.fill"
        case .stopped:
            "stop.fill"
        case .seeding:
            "square.and.arrow.up.fill"
        case .completed:
            "checkmark.circle.fill"
        case .error:
            "exclamationmark.triangle.fill"
        case .checking:
            "text.magnifyingglass"
        }
    }

    private var progressText: String? {
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

    private var progressIconSymbolEffect: WiggleSymbolEffect {
        statusKind == .seeding ? .wiggle.up.byLayer : .wiggle.down.byLayer
    }

    private var showsProgressIconActivity: Bool {
        hasActiveTransfer && !reduceMotion
    }

    private var hasActiveTransfer: Bool {
        switch statusKind {
        case .downloading:
            row.downloadSpeedBytesPerSecond > 0
        case .seeding:
            clampedProgress >= 1 && row.uploadSpeedBytesPerSecond > 1
        case .stopped, .completed, .error, .checking:
            false
        }
    }

    private var progressGroupColor: Color {
        if presentationMode == .onboardingDemo, !usesProductionProgressColors {
            return ShatlColor.backgroundPrimary
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

    private var progressGroupForegroundColor: Color {
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

    private var expandedMetricSetHorizontalPadding: CGFloat? {
        presentationMode == .onboardingDemo ? 8 : nil
    }

    private var metricSetBackgroundColorOverride: Color? {
        presentationMode == .onboardingDemo && colorScheme == .dark ? ShatlColor.backgroundPrimary : nil
    }

    private var metricSetOutlineColorOverride: Color? {
        presentationMode == .onboardingDemo && colorScheme == .dark ? ShatlColor.backgroundPrimary : nil
    }

    private var selectedOutlineColor: Color {
        ShatlColor.accent
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
        row.errorState == nil
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let outerWidth = max(0, proxy.size.width)
            let innerPadding: CGFloat = 3
            let innerWidth = max(0, outerWidth - innerPadding * 2)
            let fillWidth = min(innerWidth, max(4, innerWidth * CGFloat(clampedProgress)))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(ShatlColor.backgroundTertiary)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(ShatlColor.outlinePrimary, lineWidth: 1)
                    }

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(progressBarFillColor)
                    .frame(width: fillWidth, height: 4)
                    .padding(.leading, innerPadding)
                    .animation(ShatlMotion.progressBarFill, value: fillWidth)
                    .animation(ShatlMotion.progressBarFill, value: isProgressBarComplete)
            }
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

        if presentationMode == .onboardingDemo {
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

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        if presentationMode == .onboardingDemo {
            shape.fill(backgroundColor)
        } else if
            let appearance = ShatlShadow.torrentCardInner.appearance(for: colorScheme),
            let secondary = appearance.secondary
        {
            shape.fill(
                backgroundColor
                    .shadow(
                        .inner(
                            color: ShatlColor.shadowKeyColor.opacity(appearance.primary.opacity),
                            radius: appearance.primary.radius,
                            x: appearance.primary.x,
                            y: appearance.primary.y
                        )
                    )
                    .shadow(
                        .inner(
                            color: ShatlColor.shadowKeyColor.opacity(secondary.opacity),
                            radius: secondary.radius,
                            x: secondary.x,
                            y: secondary.y
                        )
                    )
            )
        } else {
            shape.fill(backgroundColor)
        }
    }

    private var cardLayoutProbeReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: TorrentCardHeightPreferenceKey.self, value: proxy.size.height)
                .preference(key: TorrentCardWidthPreferenceKey.self, value: proxy.size.width)
        }
    }

    private var layoutSignature: TorrentCardLayoutSignature {
        TorrentCardLayoutSignature(
            status: row.status,
            progressPercent: progressPercent,
            showsProgressBar: showsProgressBar,
            hasCompactTransferMetricSet: row.compactTransferMetricSet != nil,
            compactTransferItemIDs: row.compactTransferMetricSet?.items.map(\.id) ?? [],
            isExpanded: row.isExpanded,
            hasExpandedMetricGroups: row.expandedMetricGroups != nil,
            expandedDynamicGroupIDs: row.expandedMetricGroups?.dynamicGroups.map(\.id) ?? [],
            hasError: row.errorState != nil,
            hasAlias: row.hasAlias
        )
    }

    private func recordLayoutProbe(height: CGFloat?) {
        guard presentationMode == .normal else { return }

        let probe = TorrentCardLayoutProbe(height: height, signature: layoutSignature)
        defer {
            lastLayoutProbe = probe
        }

        guard let previous = lastLayoutProbe else {
            ShatlLog.ui.criticalDebug(
                "torrent-card.layout.initial \(layoutLogFields(previous: nil, current: probe))"
            )
            return
        }

        let heightDelta = (probe.height ?? previous.height ?? 0) - (previous.height ?? probe.height ?? 0)
        guard abs(heightDelta) >= 0.5 || probe.signature != previous.signature else { return }

        let event = heightDelta < -0.5 ? "torrent-card.layout.shrink" : "torrent-card.layout.change"
        ShatlLog.ui.criticalDebug(
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
            "id=\(row.id.uuidString)",
            "title=\"\(escapedLayoutValue(row.title))\"",
            "height.previous=\(previousHeight)",
            "height.current=\(currentHeight)",
            "height.delta=\(delta)",
            "status.previous=\(previous?.signature.status.rawValue ?? "-")",
            "status.current=\(current.signature.status.rawValue)",
            "progress.previous=\(previous?.signature.progressPercent.description ?? "-")",
            "progress.current=\(current.signature.progressPercent)",
            "progressBar.previous=\(previous?.signature.showsProgressBar.description ?? "-")",
            "progressBar.current=\(current.signature.showsProgressBar)",
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

    @MainActor
    private func refreshNavigationAvailability() async {
        guard presentationMode == .normal else {
            canOpenPrimaryItem = false
            canRevealInFinder = false
            return
        }

        guard row.errorState == nil else {
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

private struct TorrentCardLayoutProbe: Equatable {
    var height: CGFloat?
    var signature: TorrentCardLayoutSignature
}

private struct TorrentCardLayoutSignature: Equatable {
    var status: TorrentStatus
    var progressPercent: Int
    var showsProgressBar: Bool
    var hasCompactTransferMetricSet: Bool
    var compactTransferItemIDs: [String]
    var isExpanded: Bool
    var hasExpandedMetricGroups: Bool
    var expandedDynamicGroupIDs: [String]
    var hasError: Bool
    var hasAlias: Bool
}

private struct TorrentCardHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

private struct TorrentCardWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

private func formatLayoutNumber(_ value: CGFloat) -> String {
    String(format: "%.1f", Double(value))
}

private func escapedLayoutValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
