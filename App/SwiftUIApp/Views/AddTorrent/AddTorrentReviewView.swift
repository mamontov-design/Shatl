// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

private enum AddTorrentReviewTab: String, CaseIterable, Identifiable {
    case files
    case settings

    var id: Self { self }

    func title(localeOverride: AppLocaleOverride) -> String {
        switch self {
        case .files:
            L10n.string("add_torrent.review.tab.files", localeOverride: localeOverride, defaultValue: "Файлы")
        case .settings:
            L10n.string("add_torrent.review.tab.settings", localeOverride: localeOverride, defaultValue: "Настройки")
        }
    }
}

private struct AddTorrentFileSelectionBinding: Identifiable {
    let id: UUID
    let isSelected: Binding<Bool>
}

private struct AddTorrentFileTreeRow: Identifiable {
    let node: AddTorrentFileTreeNode
    let level: Int
    let ancestorFolderIDs: [String]

    var id: String { node.id }
}

private struct AddTorrentTextSegment: Identifiable, Equatable {
    enum Kind: Equatable {
        case text
        case number
    }

    let id: String
    let kind: Kind
    let value: String
    let animatesNumericChange: Bool
}

private struct AddTorrentFolderSummary: Equatable {
    enum Mode: Hashable {
        case noneSelected
        case allSelected
        case partiallySelected
    }

    let mode: Mode
    let segments: [AddTorrentTextSegment]
}

private struct AddTorrentReviewScrollDiagnosticsSnapshot: Equatable {
    let offsetY: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat
    let visibleMinY: CGFloat
    let visibleMaxY: CGFloat
    let insetTop: CGFloat
    let insetBottom: CGFloat

    static let zero = AddTorrentReviewScrollDiagnosticsSnapshot(
        offsetY: 0,
        contentHeight: 0,
        containerHeight: 0,
        visibleMinY: 0,
        visibleMaxY: 0,
        insetTop: 0,
        insetBottom: 0
    )
}

@MainActor
private final class AddTorrentReviewDiagnosticsState {
    var operationID = "-"
    var scrollGeometry = AddTorrentReviewScrollDiagnosticsSnapshot.zero
    var rootSize = CGSize.zero
}

private struct AddTorrentReviewWindowDiagnosticsReader: NSViewRepresentable {
    let selectedTab: String
    let layoutMode: String

    func makeNSView(context: Context) -> AddTorrentReviewWindowDiagnosticsNSView {
        AddTorrentReviewWindowDiagnosticsNSView()
    }

    func updateNSView(
        _ nsView: AddTorrentReviewWindowDiagnosticsNSView,
        context: Context
    ) {
        nsView.selectedTab = selectedTab
        nsView.layoutMode = layoutMode
        nsView.report(event: "window.context.updated", source: "sheet")
    }
}

private final class AddTorrentReviewWindowDiagnosticsNSView: NSView {
    var selectedTab = "-"
    var layoutMode = "-"

    private var observations: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installWindowObservers()
        report(event: "window.attached", source: "sheet")
    }

    deinit {
        removeWindowObservers()
    }

    func report(event: String, source: String) {
        guard ShatlAddTorrentReviewDiagnosticsLog.isEnabled,
              let window
        else {
            return
        }

        let parentWindow = window.sheetParent ?? window.parent
        var fields: [String: String] = [
            "eventSource": source,
            "isSheet": (window.sheetParent != nil).description,
            "layoutMode": layoutMode,
            "selectedTab": selectedTab,
            "sheet.contentHeight": addTorrentDiagnosticsNumber(window.contentLayoutRect.height),
            "sheet.contentWidth": addTorrentDiagnosticsNumber(window.contentLayoutRect.width),
            "sheet.fittingHeight": addTorrentDiagnosticsNumber(
                window.contentView?.fittingSize.height ?? 0
            ),
            "sheet.fittingWidth": addTorrentDiagnosticsNumber(
                window.contentView?.fittingSize.width ?? 0
            ),
            "sheet.frameHeight": addTorrentDiagnosticsNumber(window.frame.height),
            "sheet.frameMaxY": addTorrentDiagnosticsNumber(window.frame.maxY),
            "sheet.frameMinY": addTorrentDiagnosticsNumber(window.frame.minY),
            "sheet.frameWidth": addTorrentDiagnosticsNumber(window.frame.width),
        ]

        if let parentWindow {
            fields["parent.frameHeight"] = addTorrentDiagnosticsNumber(parentWindow.frame.height)
            fields["parent.frameMaxY"] = addTorrentDiagnosticsNumber(parentWindow.frame.maxY)
            fields["parent.frameMinY"] = addTorrentDiagnosticsNumber(parentWindow.frame.minY)
            fields["parent.frameWidth"] = addTorrentDiagnosticsNumber(parentWindow.frame.width)
        }

        if let visibleFrame = window.screen?.visibleFrame {
            fields["screen.visibleHeight"] = addTorrentDiagnosticsNumber(visibleFrame.height)
            fields["screen.visibleMaxY"] = addTorrentDiagnosticsNumber(visibleFrame.maxY)
            fields["screen.visibleMinY"] = addTorrentDiagnosticsNumber(visibleFrame.minY)
            fields["screen.visibleWidth"] = addTorrentDiagnosticsNumber(visibleFrame.width)
        }

        ShatlAddTorrentReviewDiagnosticsLog.event(
            event,
            fields: fields,
            flush: true
        )
    }

    private func installWindowObservers() {
        removeWindowObservers()
        guard let window else { return }

        observe(window, source: "sheet")
        if let parentWindow = window.sheetParent ?? window.parent {
            observe(parentWindow, source: "parent")
        }
    }

    private func observe(_ window: NSWindow, source: String) {
        let notificationCenter = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didChangeScreenNotification,
        ]

        for name in names {
            observations.append(
                notificationCenter.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] notification in
                    self?.report(
                        event: "window.\(notification.name.rawValue)",
                        source: source
                    )
                }
            )
        }
    }

    private func removeWindowObservers() {
        let notificationCenter = NotificationCenter.default
        observations.forEach(notificationCenter.removeObserver)
        observations.removeAll()
    }
}

private let addTorrentIntegerFormatExpression = try? NSRegularExpression(
    pattern: #"%(?:(\d+)\$)?lld"#
)

private func addTorrentDiagnosticsToken(_ value: String?) -> String {
    guard let value else { return "-" }

    var hasher = Hasher()
    hasher.combine(value)
    return String(UInt(bitPattern: hasher.finalize()), radix: 16)
}

private func addTorrentDiagnosticsNumber(_ value: CGFloat) -> String {
    String(format: "%.2f", value)
}

enum AddTorrentReviewLayout {
    static var windowEdgePadding: CGFloat {
        if #available(macOS 27.0, *) {
            12
        } else {
            18
        }
    }

    static let filesContainerCornerRadius: CGFloat = 12
    static let filesContainerHeight: CGFloat = 360
    static let standardListItemHeight: CGFloat = 32
    static let cjkListItemHeight: CGFloat = 34
    static let standardDetailedListItemHeight: CGFloat = 46
    static let cjkDetailedListItemHeight: CGFloat = 52
    static let standardFileTypeIconWidth: CGFloat = 18
    static let cjkFileTypeIconWidth: CGFloat = 20
    static let rootFolderLeadingPadding: CGFloat = 10
    static let rootFileLeadingPadding: CGFloat = 6
    static let nestedItemLeadingPadding: CGFloat = 20
    static let itemTrailingPadding: CGFloat = 6
    static let hierarchyGuideWidth: CGFloat = 20
    static let nearestHierarchyGuideWidth: CGFloat = 10
    static let hierarchyGuideLineWidth: CGFloat = 1
    static let expandButtonContainerPadding: CGFloat = 2
    static let hoverAreaSpacing: CGFloat = 4
    static let hoverAreaPadding: CGFloat = 6
    static let hoverAreaCornerRadius: CGFloat = 8
    static let summaryCornerRadius: CGFloat = 8
    static let summaryHorizontalPadding: CGFloat = 6
    static let summaryVerticalPadding: CGFloat = 8
    static let summarySpacing: CGFloat = 16
    static let filesVerticalPadding: CGFloat = 4
    static let standardSummaryContentHeight: CGFloat = 29
    static let cjkSummaryContentHeight: CGFloat = 33
    static let standardInvalidContentHeight: CGFloat = 491
    static let cjkInvalidContentHeight: CGFloat = 499

    static func listItemHeight(
        for profile: ShatlTypographyProfile,
        showsFolderSummary: Bool = false
    ) -> CGFloat {
        switch (profile, showsFolderSummary) {
        case (.standard, false):
            standardListItemHeight
        case (.cjk, false):
            cjkListItemHeight
        case (.standard, true):
            standardDetailedListItemHeight
        case (.cjk, true):
            cjkDetailedListItemHeight
        }
    }

    static func fileTypeIconWidth(for profile: ShatlTypographyProfile) -> CGFloat {
        switch profile {
        case .standard:
            standardFileTypeIconWidth
        case .cjk:
            cjkFileTypeIconWidth
        }
    }

    static func summaryContentHeight(for profile: ShatlTypographyProfile) -> CGFloat {
        switch profile {
        case .standard:
            standardSummaryContentHeight
        case .cjk:
            cjkSummaryContentHeight
        }
    }

    static func tabContentHeight(
        for profile: ShatlTypographyProfile,
        showsSummary: Bool
    ) -> CGFloat {
        guard showsSummary else { return filesContainerHeight }

        return filesContainerHeight
            + summaryContentHeight(for: profile)
            + summaryVerticalPadding * 2
    }

    static func invalidContentHeight(for profile: ShatlTypographyProfile) -> CGFloat {
        switch profile {
        case .standard:
            standardInvalidContentHeight
        case .cjk:
            cjkInvalidContentHeight
        }
    }

    static func leadingPadding(isFolder: Bool, level: Int) -> CGFloat {
        guard level > 0 else {
            return isFolder ? rootFolderLeadingPadding : rootFileLeadingPadding
        }

        return nestedItemLeadingPadding
    }

    static func hierarchyGuideWidths(for level: Int) -> [CGFloat] {
        guard level > 0 else { return [] }

        return (0..<level).map { guideIndex in
            guideIndex == level - 1 ? nearestHierarchyGuideWidth : hierarchyGuideWidth
        }
    }
}

enum AddTorrentSummaryByteRounding {
    case up
    case down
}

enum AddTorrentSummaryByteFormatter {
    static func format(
        _ bytes: Int64,
        mode: MetricsPresentationMode,
        rounding: AddTorrentSummaryByteRounding,
        localeOverride: AppLocaleOverride
    ) -> String {
        switch mode {
        case .detailed:
            Metrics.formatBytes(bytes, mode: mode, localeOverride: localeOverride)
        case .simplified:
            formatSimplified(bytes, rounding: rounding, localeOverride: localeOverride)
        }
    }

    private static func formatSimplified(
        _ bytes: Int64,
        rounding: AddTorrentSummaryByteRounding,
        localeOverride: AppLocaleOverride
    ) -> String {
        let positiveBytes = max(bytes, 0)
        guard let unit = units(localeOverride: localeOverride).first(where: { Double(positiveBytes) >= $0.threshold }) else {
            return metricValue(positiveBytes, unitKey: "unit.byte", fallback: "Б", localeOverride: localeOverride)
        }

        let visibleValue = Double(positiveBytes) / unit.threshold
        let roundedValue: Int64
        switch rounding {
        case .up:
            roundedValue = Int64(visibleValue.rounded(.up))
        case .down:
            roundedValue = Int64(visibleValue.rounded(.down))
        }

        return "\(localizedInteger(roundedValue, localeOverride: localeOverride)) \(unit.label)"
    }

    private static func metricValue<T>(
        _ value: T,
        unitKey: String,
        fallback: String,
        localeOverride: AppLocaleOverride
    ) -> String {
        "\(value) \(L10n.string(unitKey, localeOverride: localeOverride, defaultValue: fallback))"
    }

    private static func localizedInteger(
        _ value: Int64,
        localeOverride: AppLocaleOverride
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = L10n.locale(for: localeOverride)
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func units(
        localeOverride: AppLocaleOverride
    ) -> [(threshold: Double, label: String)] {
        [
            (
                1_000_000_000_000,
                L10n.string("unit.terabyte", localeOverride: localeOverride, defaultValue: "ТБ")
            ),
            (
                1_000_000_000,
                L10n.string("unit.gigabyte", localeOverride: localeOverride, defaultValue: "ГБ")
            ),
            (
                1_000_000,
                L10n.string("unit.megabyte", localeOverride: localeOverride, defaultValue: "МБ")
            ),
            (
                1_000,
                L10n.string("unit.kilobyte", localeOverride: localeOverride, defaultValue: "КБ")
            ),
        ]
    }
}

enum AddTorrentFilePluralCategory: String {
    case one
    case few
    case many
    case other

    static func resolve(count: Int, localeOverride: AppLocaleOverride) -> Self {
        let languageCode = L10n.locale(for: localeOverride).language.languageCode?.identifier

        switch languageCode {
        case "ru":
            let modulo10 = count % 10
            let modulo100 = count % 100
            if modulo10 == 1, modulo100 != 11 {
                return .one
            }
            if (2...4).contains(modulo10), !(12...14).contains(modulo100) {
                return .few
            }
            return .many
        case "en", "de", "es":
            return count == 1 ? .one : .other
        case "fr":
            return count == 0 || count == 1 ? .one : .other
        default:
            return .other
        }
    }
}

private enum AddTorrentAvailableCapacity: Equatable {
    case loading
    case available(Int64)
    case unavailable
}

private struct AddTorrentFileListItem<SelectionControl: View>: View {
    let node: AddTorrentFileTreeNode
    let level: Int
    let formattedSize: String
    let folderSummary: AddTorrentFolderSummary?
    let isExpanded: Bool
    let isPinned: Bool
    let onToggleExpansion: () -> Void
    let onToggleSelection: () -> Void
    let selectionControl: SelectionControl

    @Environment(\.shatlTypographyProfile) private var typographyProfile
    @State private var isHovered = false

    init(
        node: AddTorrentFileTreeNode,
        level: Int,
        formattedSize: String,
        folderSummary: AddTorrentFolderSummary?,
        isExpanded: Bool,
        isPinned: Bool,
        onToggleExpansion: @escaping () -> Void,
        onToggleSelection: @escaping () -> Void,
        @ViewBuilder selectionControl: () -> SelectionControl
    ) {
        self.node = node
        self.level = level
        self.formattedSize = formattedSize
        self.folderSummary = folderSummary
        self.isExpanded = isExpanded
        self.isPinned = isPinned
        self.onToggleExpansion = onToggleExpansion
        self.onToggleSelection = onToggleSelection
        self.selectionControl = selectionControl()
    }

    var body: some View {
        HStack(spacing: 0) {
            hierarchyGuides

            if node.isFolder {
                expandButtonContainer
            }

            hoverArea
        }
        .padding(
            .leading,
            AddTorrentReviewLayout.leadingPadding(isFolder: node.isFolder, level: level)
        )
        .padding(.trailing, AddTorrentReviewLayout.itemTrailingPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: listItemHeight,
            maxHeight: listItemHeight,
            alignment: .leading
        )
        .background {
            if isPinned {
                Rectangle()
                    .fill(ShatlColor.backgroundTertiary)
                    .shatlShadow(ShatlShadow.addTorrentStickyRow)
                    .animation(ShatlMotion.stickyContentReplace, value: isPinned)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ShatlColor.outlinePrimary)
                .frame(height: 1)
                .opacity(isPinned ? 1 : 0)
                .allowsHitTesting(false)
        }
        .zIndex(isPinned ? 1 : 0)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = isPinned ? false : hovering
        }
        .onAppear {
            logFolderLifecycleEvent("folder.row.appeared")
        }
        .onDisappear {
            logFolderLifecycleEvent("folder.row.disappeared")
        }
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .scrollView(axis: .vertical))
        } action: { oldFrame, newFrame in
            logFolderFrameChange(from: oldFrame, to: newFrame)
        }
    }

    private var hierarchyGuides: some View {
        HStack(spacing: 0) {
            ForEach(
                Array(AddTorrentReviewLayout.hierarchyGuideWidths(for: level).enumerated()),
                id: \.offset
            ) { _, guideWidth in
                Color.clear
                    .frame(width: guideWidth, height: listItemHeight)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(ShatlColor.outlinePrimary)
                            .frame(width: AddTorrentReviewLayout.hierarchyGuideLineWidth)
                    }
            }
        }
    }

    private var expandButtonContainer: some View {
        Button(action: onToggleExpansion) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(ShatlColor.typographyPrimary)
                .frame(width: 16, height: 16)
                .background(ShatlColor.backgroundPrimary)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ShatlCornerRadius.expandButton,
                        style: .continuous
                    )
                )
                .contentTransition(.symbolEffect(.replace))
                .padding(AddTorrentReviewLayout.expandButtonContainerPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hoverArea: some View {
        Button(action: onToggleSelection) {
            HStack(spacing: AddTorrentReviewLayout.hoverAreaSpacing) {
                Image(systemName: node.isFolder ? "folder.fill" : "document")
                    .shatlTypography(
                        node.isFolder ? ShatlTypography.bodySemibold : ShatlTypography.bodyRegular
                    )
                    .foregroundStyle(ShatlColor.typographyPrimary)
                    .frame(width: fileTypeIconWidth, alignment: .center)

                VStack(alignment: .leading, spacing: 0) {
                    Text(node.name)
                        .shatlTypography(
                            node.isFolder ? ShatlTypography.bodySemibold : ShatlTypography.bodyRegular
                        )
                        .foregroundStyle(ShatlColor.typographyPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let folderSummary {
                        folderSummaryView(folderSummary)
                            .shatlTypography(ShatlTypography.captionRegular)
                            .lineLimit(1)
                    }
                }
                    .id(node.id)
                    .transition(.blurReplace)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(node.name)

                Text(formattedSize)
                    .shatlTypography(ShatlTypography.bodyRegular)
                    .foregroundStyle(ShatlColor.typographyTertiary)
                    .fixedSize(horizontal: true, vertical: false)
                    .id("\(node.id)-size")
                    .transition(.blurReplace)

                selectionControl
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(AddTorrentReviewLayout.hoverAreaPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                hoverAreaShape
                    .fill(
                        isHovered && !isPinned
                            ? ShatlColor.backgroundPrimary
                            : Color.clear
                    )
            }
            .contentShape(hoverAreaShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(node.name)
        .accessibilityAddTraits(node.selectionState == .selected ? .isSelected : [])
    }

    private var hoverAreaShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: AddTorrentReviewLayout.hoverAreaCornerRadius,
            bottomLeadingRadius: AddTorrentReviewLayout.hoverAreaCornerRadius,
            bottomTrailingRadius: AddTorrentReviewLayout.hoverAreaCornerRadius,
            topTrailingRadius: AddTorrentReviewLayout.hoverAreaCornerRadius,
            style: .continuous
        )
    }

    private var listItemHeight: CGFloat {
        AddTorrentReviewLayout.listItemHeight(
            for: typographyProfile,
            showsFolderSummary: folderSummary != nil
        )
    }

    private var fileTypeIconWidth: CGFloat {
        AddTorrentReviewLayout.fileTypeIconWidth(for: typographyProfile)
    }

    private func folderSummaryView(_ summary: AddTorrentFolderSummary) -> some View {
        HStack(spacing: 0) {
            ForEach(summary.segments) { segment in
                folderSummarySegmentView(segment, mode: summary.mode)
            }
        }
        .animation(ShatlMotion.stickyContentReplace, value: summary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func folderSummarySegmentView(
        _ segment: AddTorrentTextSegment,
        mode: AddTorrentFolderSummary.Mode
    ) -> some View {
        let foregroundColor = segment.kind == .number
            ? ShatlColor.typographySecondary
            : ShatlColor.typographyTertiary
        let contentTransition: ContentTransition = segment.animatesNumericChange
            ? .numericText()
            : .identity

        switch segment.kind {
        case .text:
            Text(segment.value)
                .foregroundStyle(foregroundColor)
                .contentTransition(contentTransition)
                .id(folderSummarySegmentIdentity(segment, mode: mode))
                .transition(.blurReplace)
        case .number:
            Text(segment.value)
                .foregroundStyle(foregroundColor)
                .contentTransition(contentTransition)
                .id(folderSummarySegmentIdentity(segment, mode: mode))
                .transition(.identity)
                .animation(
                    segment.animatesNumericChange ? ShatlMotion.metricResize : nil,
                    value: segment.value
                )
        }
    }

    private func folderSummarySegmentIdentity(
        _ segment: AddTorrentTextSegment,
        mode: AddTorrentFolderSummary.Mode
    ) -> String {
        switch segment.kind {
        case .number:
            segment.id
        case .text:
            "\(mode)-\(segment.id)-\(segment.value)"
        }
    }

    private func logFolderLifecycleEvent(_ event: String) {
        guard node.isFolder, ShatlAddTorrentReviewDiagnosticsLog.isEnabled else { return }

        ShatlAddTorrentReviewDiagnosticsLog.event(
            event,
            fields: [
                "expanded": isExpanded.description,
                "folder": addTorrentDiagnosticsToken(node.id),
                "level": String(level),
                "presentation": isPinned ? "sticky" : "regular",
                "summary": (folderSummary != nil).description,
            ],
            flush: true
        )
    }

    private func logFolderFrameChange(from oldFrame: CGRect, to newFrame: CGRect) {
        guard node.isFolder, ShatlAddTorrentReviewDiagnosticsLog.isEnabled else { return }
        let meaningfulChange =
            abs(oldFrame.minY - newFrame.minY) >= 0.5 ||
            abs(oldFrame.maxY - newFrame.maxY) >= 0.5 ||
            abs(oldFrame.height - newFrame.height) >= 0.5
        guard meaningfulChange else { return }

        ShatlAddTorrentReviewDiagnosticsLog.event(
            "folder.row.frame.changed",
            fields: [
                "expanded": isExpanded.description,
                "folder": addTorrentDiagnosticsToken(node.id),
                "level": String(level),
                "new.height": addTorrentDiagnosticsNumber(newFrame.height),
                "new.maxY": addTorrentDiagnosticsNumber(newFrame.maxY),
                "new.minY": addTorrentDiagnosticsNumber(newFrame.minY),
                "old.height": addTorrentDiagnosticsNumber(oldFrame.height),
                "old.maxY": addTorrentDiagnosticsNumber(oldFrame.maxY),
                "old.minY": addTorrentDiagnosticsNumber(oldFrame.minY),
                "presentation": isPinned ? "sticky" : "regular",
            ]
        )
    }
}

struct AddTorrentReviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.shatlTypographyProfile) private var typographyProfile
    @State private var selectedTab: AddTorrentReviewTab = .files
    @State private var expandedFolderIDs: Set<String> = []
    @State private var pinnedFolderID: String?
    @State private var availableCapacity: AddTorrentAvailableCapacity = .loading
    @State private var addTorrentDiagnosticsState = AddTorrentReviewDiagnosticsState()
    @State private var filesScrollGeneration = 0
    @State private var pendingCollapsedFolderID: String?
    @State private var isAliasEnabled = false
    @State private var renderedDraft: AddTorrentDraft?
    @FocusState private var isAliasFocused: Bool

    var body: some View {
        Group {
            if usesEdgeToEdgeFilesLayout, let draft {
                edgeToEdgeFilesLayout(for: draft)
            } else if isReviewInvalid {
                invalidReviewLayout
            } else {
                insetReviewLayout
            }
        }
        .frame(width: 440)
        .onGeometryChange(for: CGSize.self) { geometry in
            geometry.size
        } action: { oldSize, newSize in
            addTorrentDiagnosticsState.rootSize = newSize
            logModalRootSizeChange(from: oldSize, to: newSize)
        }
        .background {
            AddTorrentReviewWindowDiagnosticsReader(
                selectedTab: selectedTab.rawValue,
                layoutMode: addTorrentDiagnosticsLayoutMode
            )
            .frame(width: 0, height: 0)
        }
        .onAppear {
            renderedDraft = store.currentAddTorrentDraft
            syncAliasToggleWithDraft()
        }
        .onChange(of: store.currentAddTorrentDraft) { oldDraft, newDraft in
            guard let newDraft else { return }
            if oldDraft?.id != newDraft.id {
                expandedFolderIDs.removeAll()
                pinnedFolderID = nil
                pendingCollapsedFolderID = nil
                filesScrollGeneration += 1
            }
            renderedDraft = newDraft
            syncAliasToggleWithDraft()
        }
        .task(id: draft?.suggestedSavePath) {
            await refreshAvailableCapacity()
        }
    }

    private var insetReviewLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            heroHeaderGroup
            reviewContentArea
            buttonContainer
        }
        .padding(AddTorrentReviewLayout.windowEdgePadding)
    }

    private var invalidReviewLayout: some View {
        VStack(spacing: 16) {
            invalidReviewContent
        }
        .frame(
            maxWidth: .infinity,
            minHeight: AddTorrentReviewLayout.invalidContentHeight(for: typographyProfile),
            alignment: .center
        )
        .padding(12)
        .transition(ShatlMotion.stickyPinInsertion)
        .animation(ShatlMotion.interface, value: isReviewInvalid)
    }

    private func edgeToEdgeFilesLayout(for draft: AddTorrentDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                heroHeaderGroup
                tabsContainer
            }
            .padding(.horizontal, AddTorrentReviewLayout.windowEdgePadding)

            filesAndSummaryContainer(for: draft)

            buttonContainer
                .padding(.horizontal, AddTorrentReviewLayout.windowEdgePadding)
        }
        .padding(.vertical, AddTorrentReviewLayout.windowEdgePadding)
    }

    private var draft: AddTorrentDraft? {
        store.currentAddTorrentDraft ?? renderedDraft
    }

    private var isReviewInvalid: Bool {
        if case .invalid? = draft?.reviewState {
            true
        } else {
            false
        }
    }

    private var usesEdgeToEdgeFilesLayout: Bool {
        guard selectedTab == .files,
              draft?.reviewState == .ready,
              draft?.files.isEmpty == false
        else {
            return false
        }

        return true
    }

    private var heroHeaderGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(
                L10n.string(
                    "add_torrent.title",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Добавление загрузки"
                )
            )
                .shatlTypography(ShatlTypography.subheadlineBold)
                .foregroundStyle(ShatlColor.typographyPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(draft?.originalName ?? L10n.string(
                    "add_torrent.review.no_selection",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Раздача пока не выбрана"
                ))
                .shatlTypography(ShatlTypography.bodyRegular)
                .foregroundStyle(ShatlColor.typographySecondary)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(isReviewInvalid ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reviewContentArea: some View {
        ZStack(alignment: .topLeading) {
            if isReviewInvalid {
                invalidReviewContent
                    .transition(ShatlMotion.stickyPinInsertion)
            } else {
                VStack(spacing: 12) {
                    tabsContainer
                    selectedTabContent
                }
                .transition(.identity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .animation(ShatlMotion.interface, value: isReviewInvalid)
    }

    private var tabsContainer: some View {
        HStack(spacing: 6) {
            ForEach(AddTorrentReviewTab.allCases) { tab in
                ShatlTabButton(
                    title: tab.title(localeOverride: store.preferences.localeOverride),
                    isActive: selectedTab == tab
                ) {
                    let previousTab = selectedTab
                    logTabSelection(
                        event: "tab.selection.requested",
                        previousTab: previousTab,
                        newTab: tab,
                        phase: "requested"
                    )
                    selectedTab = tab
                    if tab == .settings {
                        pinnedFolderID = nil
                        syncAliasToggleWithDraft()
                    }
                    scheduleTabPostLayoutDiagnostics(
                        previousTab: previousTab,
                        newTab: tab
                    )
                }
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity)
        .background(ShatlColor.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: ShatlCornerRadius.tabsContainer, style: .continuous))
    }

    private var addTorrentDiagnosticsLayoutMode: String {
        usesEdgeToEdgeFilesLayout ? "edge-to-edge-files" : "inset-review"
    }

    private func logModalRootSizeChange(from oldSize: CGSize, to newSize: CGSize) {
        guard ShatlAddTorrentReviewDiagnosticsLog.isEnabled else { return }

        ShatlAddTorrentReviewDiagnosticsLog.event(
            "modal.root.size.changed",
            fields: [
                "layoutMode": addTorrentDiagnosticsLayoutMode,
                "new.height": addTorrentDiagnosticsNumber(newSize.height),
                "new.width": addTorrentDiagnosticsNumber(newSize.width),
                "old.height": addTorrentDiagnosticsNumber(oldSize.height),
                "old.width": addTorrentDiagnosticsNumber(oldSize.width),
                "selectedTab": selectedTab.rawValue,
            ],
            flush: true
        )
    }

    private func logTabSelection(
        event: String,
        previousTab: AddTorrentReviewTab,
        newTab: AddTorrentReviewTab,
        phase: String
    ) {
        guard ShatlAddTorrentReviewDiagnosticsLog.isEnabled else { return }

        let rootSize = addTorrentDiagnosticsState.rootSize
        ShatlAddTorrentReviewDiagnosticsLog.event(
            event,
            fields: [
                "layoutMode": addTorrentDiagnosticsLayoutMode,
                "newTab": newTab.rawValue,
                "phase": phase,
                "previousTab": previousTab.rawValue,
                "root.height": addTorrentDiagnosticsNumber(rootSize.height),
                "root.width": addTorrentDiagnosticsNumber(rootSize.width),
                "selectedTab": selectedTab.rawValue,
            ],
            flush: true
        )
    }

    private func scheduleTabPostLayoutDiagnostics(
        previousTab: AddTorrentReviewTab,
        newTab: AddTorrentReviewTab
    ) {
        guard ShatlAddTorrentReviewDiagnosticsLog.isEnabled else { return }

        Task { @MainActor in
            await Task.yield()
            logTabSelection(
                event: "tab.selection.post-layout",
                previousTab: previousTab,
                newTab: newTab,
                phase: "first-yield"
            )
            await Task.yield()
            logTabSelection(
                event: "tab.selection.post-layout",
                previousTab: previousTab,
                newTab: newTab,
                phase: "second-yield"
            )
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .files:
            filesTabContent
        case .settings:
            settingsTabContent
        }
    }

    @ViewBuilder
    private var invalidReviewContent: some View {
        if let errorState = draft?.errorState {
            invalidErrorStateContent(for: errorState)
        } else {
            invalidErrorStateContent(
                title: L10n.string(
                    "add_torrent.review.invalid_placeholder",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Не удалось подготовить загрузку."
                ),
                message: ""
            )
        }
    }

    @ViewBuilder
    private var filesTabContent: some View {
        switch draft?.reviewState {
        case .loadingMetadata?:
            placeholderBlock(
                localizedTitle: "add_torrent.review.files_after_metadata",
                defaultValue: "Файлы появятся после получения метаданных."
            )
                .frame(maxWidth: .infinity, minHeight: 360)
                .background(ShatlColor.backgroundTertiary)
                .clipShape(filesContainerShape)
                .overlay {
                    filesContainerShape
                        .strokeBorder(ShatlColor.outlineSecondary, lineWidth: 1)
                }

        case .invalid?:
            EmptyView()

        case .ready?:
            if let draft, !draft.files.isEmpty {
                filesAndSummaryContainer(for: draft)
            } else {
                placeholderBlock(
                    localizedTitle: "add_torrent.review.no_files",
                    defaultValue: "Нет файлов для загрузки."
                )
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .background(ShatlColor.backgroundTertiary)
                    .clipShape(filesContainerShape)
                    .overlay {
                        filesContainerShape
                            .strokeBorder(ShatlColor.outlineSecondary, lineWidth: 1)
                    }
            }

        case .none:
            placeholderBlock(
                localizedTitle: "add_torrent.review.no_draft",
                defaultValue: "Черновик загрузки пока не создан."
            )
                .frame(maxWidth: .infinity, minHeight: 360)
                .background(ShatlColor.backgroundTertiary)
                .clipShape(filesContainerShape)
                .overlay {
                    filesContainerShape
                        .strokeBorder(ShatlColor.outlineSecondary, lineWidth: 1)
                }
        }
    }

    private func filesAndSummaryContainer(for draft: AddTorrentDraft) -> some View {
        VStack(spacing: 0) {
            filesContainer(for: draft)

            if draft.files.count >= 3 {
                torrentSummaryContainer(for: draft)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func filesContainer(for draft: AddTorrentDraft) -> some View {
        let rows = flattenedFileRows(
            draft.fileTree,
            level: 0,
            ancestorFolderIDs: []
        )

        return ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        fileListItem(row.node, level: row.level)
                            .id(row.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, AddTorrentReviewLayout.filesVerticalPadding)
            }
            .id(filesScrollGeneration)
            .task(id: filesScrollGeneration) {
                guard let targetID = pendingCollapsedFolderID else { return }
                await Task.yield()
                scrollProxy.scrollTo(targetID, anchor: .top)
                logScrollRecreation(targetID: targetID)
                pendingCollapsedFolderID = nil
            }
            .onScrollGeometryChange(for: AddTorrentReviewScrollDiagnosticsSnapshot.self) { geometry in
                AddTorrentReviewScrollDiagnosticsSnapshot(
                    offsetY: geometry.contentOffset.y + geometry.contentInsets.top,
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height,
                    visibleMinY: geometry.visibleRect.minY,
                    visibleMaxY: geometry.visibleRect.maxY,
                    insetTop: geometry.contentInsets.top,
                    insetBottom: geometry.contentInsets.bottom
                )
            } action: { oldSnapshot, newSnapshot in
                if ShatlAddTorrentReviewDiagnosticsLog.isEnabled {
                    addTorrentDiagnosticsState.scrollGeometry = newSnapshot
                    logScrollGeometryChange(
                        from: oldSnapshot,
                        to: newSnapshot,
                        rows: rows
                    )
                }
                updatePinnedFolder(scrollOffset: newSnapshot.offsetY, rows: rows)
            }
            .onChange(of: rows.map(\.id)) { oldIDs, newIDs in
                logRowsChange(
                    oldCount: oldIDs.count,
                    newIDs: newIDs,
                    rows: rows
                )
            }
            .onAppear {
                logFilesContainerLifecycleEvent("files.container.appeared", rows: rows)
            }
            .onDisappear {
                logFilesContainerLifecycleEvent("files.container.disappeared", rows: rows)
            }
            .overlay(alignment: .top) {
                Group {
                    if let pinnedRow = rows.first(where: { $0.node.id == pinnedFolderID }) {
                        fileListItem(pinnedRow.node, level: pinnedRow.level, isPinned: true)
                            .transition(ShatlMotion.stickyPinInsertion)
                    }
                }
                .animation(ShatlMotion.stickyContentReplace, value: pinnedFolderID)
                .animation(ShatlMotion.stickyContentReplace, value: pinnedFolderID != nil)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: AddTorrentReviewLayout.filesContainerHeight,
            alignment: .topLeading
        )
        .background(ShatlColor.backgroundFiles)
        .overlay(alignment: .top) {
            filesContainerOutline
        }
        .overlay(alignment: .bottom) {
            filesContainerOutline
        }
    }

    private var filesContainerOutline: some View {
        Rectangle()
            .fill(ShatlColor.outlinePrimary)
            .frame(height: 1)
            .allowsHitTesting(false)
    }

    private func logScrollGeometryChange(
        from oldSnapshot: AddTorrentReviewScrollDiagnosticsSnapshot,
        to newSnapshot: AddTorrentReviewScrollDiagnosticsSnapshot,
        rows: [AddTorrentFileTreeRow]
    ) {
        guard ShatlAddTorrentReviewDiagnosticsLog.isEnabled else { return }

        var fields = addTorrentDiagnosticsFields(rows: rows, geometry: newSnapshot)
        fields["old.contentHeight"] = addTorrentDiagnosticsNumber(oldSnapshot.contentHeight)
        fields["old.containerHeight"] = addTorrentDiagnosticsNumber(oldSnapshot.containerHeight)
        fields["old.offsetY"] = addTorrentDiagnosticsNumber(oldSnapshot.offsetY)
        fields["old.visibleMaxY"] = addTorrentDiagnosticsNumber(oldSnapshot.visibleMaxY)
        fields["old.visibleMinY"] = addTorrentDiagnosticsNumber(oldSnapshot.visibleMinY)

        ShatlAddTorrentReviewDiagnosticsLog.event(
            "scroll.geometry.changed",
            fields: fields
        )
    }

    private func logRowsChange(
        oldCount: Int,
        newIDs: [String],
        rows: [AddTorrentFileTreeRow]
    ) {
        guard ShatlAddTorrentReviewDiagnosticsLog.isEnabled else { return }

        var fields = addTorrentDiagnosticsFields(
            rows: rows,
            geometry: addTorrentDiagnosticsState.scrollGeometry
        )
        fields["old.rows"] = String(oldCount)
        fields["new.rows"] = String(newIDs.count)

        ShatlAddTorrentReviewDiagnosticsLog.event(
            "tree.rows.changed",
            fields: fields,
            flush: true
        )
    }

    private func logFilesContainerLifecycleEvent(
        _ event: String,
        rows: [AddTorrentFileTreeRow]
    ) {
        guard ShatlAddTorrentReviewDiagnosticsLog.isEnabled else { return }

        ShatlAddTorrentReviewDiagnosticsLog.event(
            event,
            fields: addTorrentDiagnosticsFields(
                rows: rows,
                geometry: addTorrentDiagnosticsState.scrollGeometry
            ),
            flush: true
        )
    }

    private func logScrollRecreation(targetID: String) {
        guard ShatlAddTorrentReviewDiagnosticsLog.isEnabled else { return }

        var fields = addTorrentDiagnosticsFields(
            rows: currentFlattenedFileRows,
            geometry: addTorrentDiagnosticsState.scrollGeometry
        )
        fields["targetFolder"] = addTorrentDiagnosticsToken(targetID)

        ShatlAddTorrentReviewDiagnosticsLog.event(
            "scroll.recreated",
            fields: fields,
            flush: true
        )
    }

    private func addTorrentDiagnosticsFields(
        rows: [AddTorrentFileTreeRow],
        geometry: AddTorrentReviewScrollDiagnosticsSnapshot
    ) -> [String: String] {
        [
            "contentHeight": addTorrentDiagnosticsNumber(geometry.contentHeight),
            "containerHeight": addTorrentDiagnosticsNumber(geometry.containerHeight),
            "draft": draft?.id.uuidString ?? "-",
            "expandedFolders": String(expandedFolderIDs.count),
            "expectedContentHeight": addTorrentDiagnosticsNumber(expectedContentHeight(for: rows)),
            "firstRow": addTorrentDiagnosticsToken(rows.first?.id),
            "folderRows": String(rows.lazy.filter(\.node.isFolder).count),
            "insetBottom": addTorrentDiagnosticsNumber(geometry.insetBottom),
            "insetTop": addTorrentDiagnosticsNumber(geometry.insetTop),
            "lastRow": addTorrentDiagnosticsToken(rows.last?.id),
            "offsetY": addTorrentDiagnosticsNumber(geometry.offsetY),
            "operation": addTorrentDiagnosticsState.operationID,
            "pinnedFolder": addTorrentDiagnosticsToken(pinnedFolderID),
            "rows": String(rows.count),
            "scrollGeneration": String(filesScrollGeneration),
            "visibleMaxY": addTorrentDiagnosticsNumber(geometry.visibleMaxY),
            "visibleMinY": addTorrentDiagnosticsNumber(geometry.visibleMinY),
        ]
    }

    private func expectedContentHeight(for rows: [AddTorrentFileTreeRow]) -> CGFloat {
        rows.reduce(AddTorrentReviewLayout.filesVerticalPadding * 2) { height, row in
            height + AddTorrentReviewLayout.listItemHeight(
                for: typographyProfile,
                showsFolderSummary: row.node.isFolder && row.node.fileCount >= 3
            )
        }
    }

    private var filesContainerShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: AddTorrentReviewLayout.filesContainerCornerRadius,
            style: .continuous
        )
    }

    private func flattenedFileRows(
        _ nodes: [AddTorrentFileTreeNode],
        level: Int,
        ancestorFolderIDs: [String]
    ) -> [AddTorrentFileTreeRow] {
        nodes.flatMap { node -> [AddTorrentFileTreeRow] in
            let isExpanded = node.isFolder && isFolderExpanded(node)
            var rows = [
                AddTorrentFileTreeRow(
                    node: node,
                    level: level,
                    ancestorFolderIDs: ancestorFolderIDs
                ),
            ]

            if node.isFolder,
               isExpanded,
               let children = node.children {
                rows.append(
                    contentsOf: flattenedFileRows(
                        children,
                        level: level + 1,
                        ancestorFolderIDs: ancestorFolderIDs + [node.id]
                    )
                )
            }

            return rows
        }
    }

    private func fileListItem(
        _ node: AddTorrentFileTreeNode,
        level: Int,
        isPinned: Bool = false
    ) -> some View {
        AddTorrentFileListItem(
            node: node,
            level: level,
            formattedSize: Metrics.formatBytes(
                node.sizeBytes,
                mode: .simplified,
                localeOverride: store.preferences.localeOverride
            ),
            folderSummary: folderSummary(for: node),
            isExpanded: node.isFolder && isFolderExpanded(node),
            isPinned: isPinned,
            onToggleExpansion: {
                toggleFolderExpansion(
                    node,
                    source: isPinned ? "sticky" : "regular"
                )
            },
            onToggleSelection: {
                toggleSelection(for: node)
            }
        ) {
            selectionToggle(for: node)
        }
    }

    private func torrentSummaryContainer(for draft: AddTorrentDraft) -> some View {
        torrentSummary(for: draft)
            .padding(.horizontal, AddTorrentReviewLayout.windowEdgePadding)
    }

    private func torrentSummary(for draft: AddTorrentDraft) -> some View {
        let showsSelectedMetrics = draft.selectedFileCount > 0

        return HStack(spacing: AddTorrentReviewLayout.summarySpacing) {
            if showsSelectedMetrics {
                torrentSummaryMetric(
                    label: L10n.string(
                        "add_torrent.review.summary.selected_files",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Files selected"
                    ),
                    value: L10n.format(
                        "add_torrent.review.summary.selected_count",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "%lld of %lld",
                        Int64(draft.selectedFileCount),
                        Int64(draft.files.count)
                    ),
                    expands: true
                )
                .transition(torrentSummarySupplementaryTransition)

                torrentSummaryDivider
                    .transition(.opacity)

                torrentSummaryMetric(
                    label: L10n.string(
                        "add_torrent.review.summary.size",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Size"
                    ),
                    value: AddTorrentSummaryByteFormatter.format(
                        draft.selectedBytes,
                        mode: store.preferences.metricsMode,
                        rounding: .up,
                        localeOverride: store.preferences.localeOverride
                    ),
                    expands: false
                )
                .transition(torrentSummarySupplementaryTransition)

                torrentSummaryDivider
                    .transition(.opacity)
            }

            torrentSummaryMetric(
                label: L10n.string(
                    "add_torrent.review.summary.free_space",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Available"
                ),
                value: availableCapacityText,
                expands: true
            )
        }
        .padding(.horizontal, AddTorrentReviewLayout.summaryHorizontalPadding)
        .padding(.vertical, AddTorrentReviewLayout.summaryVerticalPadding)
        .frame(maxWidth: .infinity)
        .background(ShatlColor.backgroundSecondary)
        .clipShape(torrentSummaryShape)
        .animation(
            ShatlMotion.metricResize,
            value: "\(draft.selectedFileCount)-\(draft.selectedBytes)-\(availableCapacityText)-\(store.preferences.metricsMode)"
        )
    }

    private var torrentSummarySupplementaryTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func torrentSummaryMetric(
        label: String,
        value: String,
        expands: Bool
    ) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .shatlTypography(ShatlTypography.groupSemibold)
                .foregroundStyle(ShatlColor.typographySecondary)
                .lineLimit(1)

            numericText(value)
                .shatlTypography(ShatlTypography.bodySemibold)
                .foregroundStyle(ShatlColor.typographyPrimary)
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: expands ? .infinity : nil, alignment: .center)
        .fixedSize(horizontal: !expands, vertical: true)
        .animation(ShatlMotion.metricResize, value: value)
    }

    private var torrentSummaryDivider: some View {
        Rectangle()
            .fill(ShatlColor.outlinePrimary)
            .frame(
                width: 1,
                height: AddTorrentReviewLayout.summaryContentHeight(for: typographyProfile)
            )
    }

    private var torrentSummaryShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: AddTorrentReviewLayout.summaryCornerRadius,
            bottomTrailingRadius: AddTorrentReviewLayout.summaryCornerRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    private var availableCapacityText: String {
        switch availableCapacity {
        case .loading:
            "…"
        case let .available(bytes):
            AddTorrentSummaryByteFormatter.format(
                bytes,
                mode: store.preferences.metricsMode,
                rounding: .down,
                localeOverride: store.preferences.localeOverride
            )
        case .unavailable:
            L10n.string(
                "add_torrent.review.summary.unavailable",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Unavailable"
            )
        }
    }

    private func numericText(_ value: String) -> some View {
        HStack(spacing: 0) {
            ForEach(numericSegments(in: value)) { segment in
                Text(segment.value)
                    .contentTransition(
                        segment.animatesNumericChange
                            ? .numericText()
                            : .identity
                    )
                    .id(numericTextSegmentIdentity(segment))
                    .transition(numericTextSegmentTransition(for: segment))
                    .animation(
                        segment.animatesNumericChange
                            ? ShatlMotion.metricResize
                            : nil,
                        value: segment.value
                    )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func numericTextSegmentIdentity(_ segment: AddTorrentTextSegment) -> String {
        switch segment.kind {
        case .number:
            segment.id
        case .text:
            "\(segment.id)-\(segment.value)"
        }
    }

    private func numericTextSegmentTransition(
        for segment: AddTorrentTextSegment
    ) -> AnyTransition {
        switch segment.kind {
        case .number:
            .identity
        case .text:
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        }
    }

    private func numericSegments(in value: String) -> [AddTorrentTextSegment] {
        var segments: [AddTorrentTextSegment] = []
        var buffer = ""
        var currentKind: AddTorrentTextSegment.Kind?
        var textIndex = 0
        var numberIndex = 0

        func appendBuffer() {
            guard let currentKind, !buffer.isEmpty else { return }
            let isNumber = currentKind == .number
            let index = isNumber ? numberIndex : textIndex
            segments.append(
                AddTorrentTextSegment(
                    id: "\(isNumber ? "number" : "text")-\(index)",
                    kind: currentKind,
                    value: buffer,
                    animatesNumericChange: isNumber
                )
            )
            if isNumber {
                numberIndex += 1
            } else {
                textIndex += 1
            }
            buffer = ""
        }

        for character in value {
            let kind: AddTorrentTextSegment.Kind = character.isNumber ? .number : .text
            if let currentKind, currentKind != kind {
                appendBuffer()
            }
            currentKind = kind
            buffer.append(character)
        }
        appendBuffer()

        return segments
    }

    private func localizedTemplateSegments(
        _ template: String,
        values: [Int],
        animatedArgumentIndices: Set<Int>
    ) -> [AddTorrentTextSegment] {
        guard let expression = addTorrentIntegerFormatExpression else {
            return [
                AddTorrentTextSegment(
                    id: "text-0",
                    kind: .text,
                    value: template,
                    animatesNumericChange: false
                ),
            ]
        }

        let matches = expression.matches(
            in: template,
            range: NSRange(template.startIndex..., in: template)
        )
        var segments: [AddTorrentTextSegment] = []
        var cursor = template.startIndex
        var sequentialArgumentIndex = 0
        var textIndex = 0

        for match in matches {
            guard let matchRange = Range(match.range, in: template) else { continue }

            if cursor < matchRange.lowerBound {
                segments.append(
                    AddTorrentTextSegment(
                        id: "text-\(textIndex)",
                        kind: .text,
                        value: String(template[cursor..<matchRange.lowerBound]),
                        animatesNumericChange: false
                    )
                )
                textIndex += 1
            }

            let argumentIndex: Int
            if match.range(at: 1).location != NSNotFound,
               let positionalRange = Range(match.range(at: 1), in: template),
               let position = Int(template[positionalRange]) {
                argumentIndex = position - 1
            } else {
                argumentIndex = sequentialArgumentIndex
                sequentialArgumentIndex += 1
            }

            if values.indices.contains(argumentIndex) {
                segments.append(
                    AddTorrentTextSegment(
                        id: "argument-\(argumentIndex)",
                        kind: .number,
                        value: String(values[argumentIndex]),
                        animatesNumericChange: animatedArgumentIndices.contains(argumentIndex)
                    )
                )
            }

            cursor = matchRange.upperBound
        }

        if cursor < template.endIndex {
            segments.append(
                AddTorrentTextSegment(
                    id: "text-\(textIndex)",
                    kind: .text,
                    value: String(template[cursor...]),
                    animatesNumericChange: false
                )
            )
        }

        return segments
    }

    private func folderSummary(for node: AddTorrentFileTreeNode) -> AddTorrentFolderSummary? {
        guard node.isFolder, node.fileCount >= 3 else { return nil }

        if node.selectedFileCount == 0 {
            return AddTorrentFolderSummary(
                mode: .noneSelected,
                segments: [
                    AddTorrentTextSegment(
                        id: "text-0",
                        kind: .text,
                        value: L10n.string(
                            "add_torrent.review.folder.files.none",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: "No files selected"
                        ),
                        animatesNumericChange: false
                    ),
                ]
            )
        }

        if node.selectedFileCount == node.fileCount {
            let category = AddTorrentFilePluralCategory.resolve(
                count: node.fileCount,
                localeOverride: store.preferences.localeOverride
            )
            let fallback = node.fileCount == 1 ? "%lld file" : "%lld files"
            let template = L10n.string(
                "add_torrent.review.folder.files.count.\(category.rawValue)",
                localeOverride: store.preferences.localeOverride,
                defaultValue: fallback
            )

            return AddTorrentFolderSummary(
                mode: .allSelected,
                segments: localizedTemplateSegments(
                    template,
                    values: [node.fileCount],
                    animatedArgumentIndices: []
                )
            )
        }

        let category = AddTorrentFilePluralCategory.resolve(
            count: node.selectedFileCount,
            localeOverride: store.preferences.localeOverride
        )
        let fallback = "%lld of %lld files selected"
        let template = L10n.string(
            "add_torrent.review.folder.files.partial.\(category.rawValue)",
            localeOverride: store.preferences.localeOverride,
            defaultValue: fallback
        )

        return AddTorrentFolderSummary(
            mode: .partiallySelected,
            segments: localizedTemplateSegments(
                template,
                values: [node.selectedFileCount, node.fileCount],
                animatedArgumentIndices: [0]
            )
        )
    }

    private func updatePinnedFolder(
        scrollOffset: CGFloat,
        rows: [AddTorrentFileTreeRow]
    ) {
        let newPinnedFolderID = pinnedFolderID(
            at: scrollOffset,
            rows: rows
        )

        if pinnedFolderID != newPinnedFolderID {
            if ShatlAddTorrentReviewDiagnosticsLog.isEnabled {
                var fields = addTorrentDiagnosticsFields(
                    rows: rows,
                    geometry: addTorrentDiagnosticsState.scrollGeometry
                )
                fields["newPinnedFolder"] = addTorrentDiagnosticsToken(newPinnedFolderID)
                fields["oldPinnedFolder"] = addTorrentDiagnosticsToken(pinnedFolderID)
                fields["resolvedAtOffsetY"] = addTorrentDiagnosticsNumber(scrollOffset)
                ShatlAddTorrentReviewDiagnosticsLog.event(
                    "sticky.folder.changed",
                    fields: fields,
                    flush: true
                )
            }
            pinnedFolderID = newPinnedFolderID
        }
    }

    private func pinnedFolderID(
        at scrollOffset: CGFloat,
        rows: [AddTorrentFileTreeRow]
    ) -> String? {
        var rowTop = AddTorrentReviewLayout.filesVerticalPadding
        guard scrollOffset >= rowTop else { return nil }

        for row in rows {
            let rowHeight = AddTorrentReviewLayout.listItemHeight(
                for: typographyProfile,
                showsFolderSummary: row.node.isFolder && row.node.fileCount >= 3
            )
            let rowBottom = rowTop + rowHeight

            if scrollOffset < rowBottom {
                if row.node.isFolder, isFolderExpanded(row.node) {
                    return row.node.id
                }

                return row.ancestorFolderIDs.last
            }

            rowTop = rowBottom
        }

        return nil
    }

    private func selectionToggle(for node: AddTorrentFileTreeNode) -> some View {
        Group {
            if node.isFolder {
                Toggle(sources: fileSelectionBindings(in: node), isOn: \.isSelected) {
                    EmptyView()
                }
            } else if let fileID = node.fileID {
                Toggle(
                    isOn: Binding(
                        get: { isDraftFileSelected(id: fileID) },
                        set: { store.setDraftFileSelection(id: fileID, isSelected: $0) }
                    )
                ) {
                    EmptyView()
                }
            }
        }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .fixedSize()
    }

    private func fileSelectionBindings(in node: AddTorrentFileTreeNode) -> [AddTorrentFileSelectionBinding] {
        fileIDs(in: node).map { fileID in
            AddTorrentFileSelectionBinding(
                id: fileID,
                isSelected: Binding(
                    get: { isDraftFileSelected(id: fileID) },
                    set: { store.setDraftFileSelection(id: fileID, isSelected: $0) }
                )
            )
        }
    }

    private func fileIDs(in node: AddTorrentFileTreeNode) -> [UUID] {
        if let fileID = node.fileID {
            return [fileID]
        }

        return node.children?.flatMap(fileIDs(in:)) ?? []
    }

    private func isDraftFileSelected(id: UUID) -> Bool {
        draft?.files.first { $0.id == id }?.isSelected ?? false
    }

    private func toggleSelection(for node: AddTorrentFileTreeNode) {
        let shouldSelect = node.selectionState != .selected

        if node.isFolder {
            store.setDraftFolderSelection(path: node.path, isSelected: shouldSelect)
        } else if let fileID = node.fileID {
            store.setDraftFileSelection(id: fileID, isSelected: shouldSelect)
        }
    }

    private func isFolderExpanded(_ node: AddTorrentFileTreeNode) -> Bool {
        expandedFolderIDs.contains(node.id)
    }

    private func toggleFolderExpansion(
        _ node: AddTorrentFileTreeNode,
        source: String
    ) {
        let wasExpanded = expandedFolderIDs.contains(node.id)
        let diagnosticsEnabled = ShatlAddTorrentReviewDiagnosticsLog.isEnabled
        let operationID = diagnosticsEnabled ? UUID().uuidString : "-"
        if diagnosticsEnabled {
            addTorrentDiagnosticsState.operationID = operationID
            logFolderToggleEvent(
                "folder.toggle.requested",
                node: node,
                source: source,
                wasExpanded: wasExpanded,
                operationID: operationID
            )
        }

        if wasExpanded {
            let shouldRecreateScroll =
                source == "sticky" &&
                pinnedFolderID == node.id
            if shouldRecreateScroll {
                pendingCollapsedFolderID = node.id
            }
            expandedFolderIDs.remove(node.id)
            if pinnedFolderID == node.id {
                pinnedFolderID = nil
            }
            if shouldRecreateScroll {
                filesScrollGeneration += 1
            }
        } else {
            expandedFolderIDs.insert(node.id)
        }

        guard diagnosticsEnabled else { return }

        logFolderToggleEvent(
            "folder.toggle.applied",
            node: node,
            source: source,
            wasExpanded: wasExpanded,
            operationID: operationID
        )
        Task { @MainActor in
            await Task.yield()
            logAddTorrentPostLayoutSnapshot(
                phase: "first-yield",
                operationID: operationID
            )
            await Task.yield()
            logAddTorrentPostLayoutSnapshot(
                phase: "second-yield",
                operationID: operationID
            )
        }
    }

    private func logFolderToggleEvent(
        _ event: String,
        node: AddTorrentFileTreeNode,
        source: String,
        wasExpanded: Bool,
        operationID: String
    ) {
        let rows = currentFlattenedFileRows
        var fields = addTorrentDiagnosticsFields(
            rows: rows,
            geometry: addTorrentDiagnosticsState.scrollGeometry
        )
        fields["action"] = wasExpanded ? "collapse" : "expand"
        fields["folder"] = addTorrentDiagnosticsToken(node.id)
        fields["operation"] = operationID
        fields["source"] = source
        fields["wasExpanded"] = wasExpanded.description

        ShatlAddTorrentReviewDiagnosticsLog.event(
            event,
            fields: fields,
            flush: true
        )
    }

    private func logAddTorrentPostLayoutSnapshot(
        phase: String,
        operationID: String
    ) {
        guard ShatlAddTorrentReviewDiagnosticsLog.isEnabled else { return }

        var fields = addTorrentDiagnosticsFields(
            rows: currentFlattenedFileRows,
            geometry: addTorrentDiagnosticsState.scrollGeometry
        )
        fields["operation"] = operationID
        fields["phase"] = phase

        ShatlAddTorrentReviewDiagnosticsLog.event(
            "folder.toggle.post-layout",
            fields: fields,
            flush: true
        )
    }

    private var currentFlattenedFileRows: [AddTorrentFileTreeRow] {
        guard let draft else { return [] }

        return flattenedFileRows(
            draft.fileTree,
            level: 0,
            ancestorFolderIDs: []
        )
    }

    private var settingsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            parametersGroup

            Text(
                L10n.string(
                    "add_torrent.review.alias_caption",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Псевдоним будет отображаться в карточке торрента вместо оригинального названия раздачи. Оригинальное название раздачи можно посмотреть, переведя карточку торрента в расширенный вид."
                )
            )
                .shatlTypography(ShatlTypography.captionRegular)
                .foregroundStyle(ShatlColor.typographyTertiary)
                .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: AddTorrentReviewLayout.tabContentHeight(
                for: typographyProfile,
                showsSummary: draft?.reviewState == .ready && (draft?.files.count ?? 0) >= 3
            ),
            alignment: .topLeading
        )
        .onAppear(perform: syncAliasToggleWithDraft)
    }

    private var parametersGroup: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        L10n.format(
                            "add_torrent.review.download_to_folder",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: "Загрузить в «%@»",
                            displayedFolderName
                        )
                    )
                        .shatlTypography(ShatlTypography.bodyRegular)
                        .foregroundStyle(ShatlColor.typographyPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(displayedFolderPath)
                        .shatlTypography(ShatlTypography.bodyRegular)
                        .foregroundStyle(ShatlColor.typographySecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.disabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ShatlButton(
                    title: L10n.string(
                        "common.change",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Сменить"
                    ),
                    role: .borderedNeutral
                ) {
                    presentSavePathPicker()
                }
            }

            parameterDivider

            HStack(spacing: 12) {
                Text(
                    L10n.string(
                        "add_torrent.review.stop_after_download",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Остановить раздачу после завершения загрузки"
                    )
                )
                    .shatlTypography(ShatlTypography.bodyRegular)
                    .foregroundStyle(ShatlColor.typographyPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { draft?.stopAfterDownload ?? false },
                        set: { store.updateDraftStopAfterDownload($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            parameterDivider

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(
                        L10n.string(
                            "add_torrent.review.use_alias",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: "Использовать псевдоним"
                        )
                    )
                        .shatlTypography(ShatlTypography.bodyRegular)
                        .foregroundStyle(ShatlColor.typographyPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Toggle(
                        "",
                        isOn: Binding(
                            get: { isAliasEnabled },
                            set: { setAliasEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                if isAliasEnabled {
                    TextField(
                        L10n.string(
                            "add_torrent.review.alias_placeholder",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: "Укажите псевдоним"
                        ),
                        text: Binding(
                            get: { draft?.alias ?? "" },
                            set: { store.updateDraftAlias($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .focused($isAliasFocused)
                    .transition(ShatlMotion.appearFromTop)
                }
            }
            .animation(ShatlMotion.interface, value: isAliasEnabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(ShatlColor.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: ShatlCornerRadius.container, style: .continuous))
    }

    private var parameterDivider: some View {
        Rectangle()
            .fill(ShatlColor.outlineSecondary)
            .frame(height: 1)
    }

    private var buttonContainer: some View {
        HStack(spacing: 6) {
            Spacer()

            ShatlButton(
                title: L10n.string(
                    "common.cancel",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Отменить"
                ),
                role: .borderedNeutral
            ) {
                store.dismissModal()
            }

            ShatlButton(
                title: L10n.string(
                    "add_torrent.review.confirm",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Скачать"
                ),
                role: .borderedColored,
                isDisabled: !(draft?.canConfirmDownload ?? false)
            ) {
                store.confirmDraft()
            }
        }
    }

    private func placeholderBlock(localizedTitle key: String, defaultValue: String) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(ShatlColor.typographyTertiary)

            Text(L10n.string(key, localeOverride: store.preferences.localeOverride, defaultValue: defaultValue))
                .shatlTypography(ShatlTypography.bodyRegular)
                .foregroundStyle(ShatlColor.typographySecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
    }

    private var displayedFolderPath: String {
        let path = draft?.suggestedSavePath.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? folderNotSelectedTitle : path
    }

    private func invalidErrorStateContent(for errorState: TorrentErrorState) -> some View {
        invalidErrorStateContent(title: errorState.title, message: errorState.message)
    }

    private func invalidErrorStateContent(title: String, message: String) -> some View {
        VStack(spacing: 16) {
            invalidErrorLabelGroup(title: title, message: message)

            ShatlButton(
                title: L10n.string(
                    "onboarding.action.close",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Закрыть"
                ),
                role: .borderedColored
            ) {
                store.dismissModal()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func invalidErrorLabelGroup(title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(Color.red)

            Text(title)
                .shatlTypography(ShatlTypography.subheadlineBold)
                .foregroundStyle(ShatlColor.typographyPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !message.isEmpty {
                Text(message)
                    .shatlTypography(ShatlTypography.captionRegular)
                    .foregroundStyle(ShatlColor.typographySecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var displayedFolderName: String {
        let path = draft?.suggestedSavePath.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return folderNotSelectedTitle }

        let folderName = URL(fileURLWithPath: path).lastPathComponent
        return folderName.isEmpty ? path : folderName
    }

    private var folderNotSelectedTitle: String {
        L10n.string(
            "add_torrent.review.folder_not_selected",
            localeOverride: store.preferences.localeOverride,
            defaultValue: "Папка не выбрана"
        )
    }

    private func setAliasEnabled(_ isEnabled: Bool) {
        withAnimation(ShatlMotion.interface) {
            isAliasEnabled = isEnabled
        }

        if isEnabled {
            Task { @MainActor in
                isAliasFocused = true
            }
        } else {
            store.updateDraftAlias("")
            isAliasFocused = false
        }
    }

    private func syncAliasToggleWithDraft() {
        isAliasEnabled = draft?.alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func refreshAvailableCapacity() async {
        availableCapacity = .loading

        guard let path = draft?.suggestedSavePath.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            availableCapacity = .unavailable
            return
        }

        let capacity = await Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return values?.volumeAvailableCapacity.map(Int64.init)
        }.value

        guard !Task.isCancelled else { return }
        availableCapacity = capacity.map(AddTorrentAvailableCapacity.available) ?? .unavailable
    }

    private func presentSavePathPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.string("common.choose", localeOverride: store.preferences.localeOverride)

        if let draft,
           !draft.suggestedSavePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            panel.directoryURL = URL(fileURLWithPath: draft.suggestedSavePath, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        store.updateDraftSaveLocation(url, bookmarkData: bookmarkData)
    }
}
