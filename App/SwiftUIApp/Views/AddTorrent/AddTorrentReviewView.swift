// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

private struct AddTorrentSelectionIndicatorSource: Identifiable {
    let id: Bool
    let isSelected: Binding<Bool>
}

private struct AddTorrentFileTreeRow: Identifiable {
    let node: AddTorrentFileTreeNode
    let level: Int
    let ancestorFolderIDs: [String]
    let isExpanded: Bool

    var id: String { node.id }
}

private struct AddTorrentReviewDraftPresentationToken: Equatable {
    let id: UUID
    let fileSelectionRevision: UInt64
    let reviewState: AddTorrentReviewState
    let fileCount: Int

    /// The window shows this download's files, and so its summary.
    var showsFiles: Bool {
        reviewState == .ready && fileCount > 0
    }
}

/// The numbers the add window's summary shows, which follow the download on
/// screen at once or once the arrows rest; see `followSummary`.
private struct AddTorrentReviewSummaryCounts: Equatable {
    var selectedFileCount = 0
    var selectedBytes: Int64 = 0
    var totalFileCount = 0
}

private struct AddTorrentReviewFilePresentation {
    let tree: [AddTorrentFileTreeNode]
    let searchProjection: AddTorrentFileSearchProjection?
    let rows: [AddTorrentFileTreeRow]
    let rowIndexByID: [String: Int]
    let rowBottomOffsets: [CGFloat]
    let selectedFileCount: Int
    let selectedBytes: Int64
    let totalFileCount: Int

    static let empty = AddTorrentReviewFilePresentation(
        tree: [],
        searchProjection: nil,
        rows: [],
        rowIndexByID: [:],
        rowBottomOffsets: [],
        selectedFileCount: 0,
        selectedBytes: 0,
        totalFileCount: 0
    )
}

/// A transition that changes nothing in what it is given: the view stays
/// for the time of the animation and is drawn as it was, under no effect.
private struct AddTorrentReviewHeldStage: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
    }
}

/// The search over the files, in the window's toolbar. The window stays
/// between downloads, so a new one (`resetKey`) clears the field and takes
/// the focus off it: the last query, still focused, filtered the next
/// download's files to nothing.
private struct AddTorrentReviewSearchModifier: ViewModifier {
    let prompt: String
    let resetKey: UUID?
    let onDebouncedChange: (String) -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    func body(content: Content) -> some View {
        content
            .searchable(
                text: $searchText,
                placement: .toolbar,
                prompt: Text(prompt)
            )
            .searchFocused($isSearchFocused)
            .searchToolbarBehavior(.automatic)
            .onChange(of: resetKey) { _, _ in
                searchText = ""
                isSearchFocused = false
            }
            .task(id: searchText) {
                let pendingSearchText = searchText
                if !pendingSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    do {
                        try await Task.sleep(for: .milliseconds(180))
                    } catch {
                        return
                    }
                }
                guard !Task.isCancelled else { return }
                onDebouncedChange(pendingSearchText)
            }
    }
}

enum AddTorrentReviewRowLookup {
    static func index(
        at scrollOffset: CGFloat,
        contentTop: CGFloat,
        rowBottomOffsets: [CGFloat]
    ) -> Int? {
        guard scrollOffset >= contentTop, !rowBottomOffsets.isEmpty else { return nil }

        var lowerBound = 0
        var upperBound = rowBottomOffsets.count

        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if scrollOffset < rowBottomOffsets[middle] {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }

        return lowerBound < rowBottomOffsets.count ? lowerBound : nil
    }
}

enum AddTorrentInitialFolderExpansion {
    static func folderIDs(in nodes: [AddTorrentFileTreeNode]) -> Set<String> {
        Set(nodes.lazy.filter(\.isFolder).map(\.id))
    }
}

struct AddTorrentFileSearchProjection: Equatable {
    let visibleNodeIDs: Set<String>
    let foldersWithVisibleDescendants: Set<String>
    let matchingNodeIDs: Set<String>

    static func make(
        from nodes: [AddTorrentFileTreeNode],
        query rawQuery: String
    ) -> AddTorrentFileSearchProjection? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        var visibleNodeIDs: Set<String> = []
        var foldersWithVisibleDescendants: Set<String> = []
        var matchingNodeIDs: Set<String> = []

        @discardableResult
        func visit(_ node: AddTorrentFileTreeNode) -> Bool {
            let hasVisibleDescendant = node.children?.reduce(false) { result, child in
                visit(child) || result
            } ?? false
            let isMatch = node.name.localizedStandardContains(query)
            let isVisible = isMatch || hasVisibleDescendant

            if isMatch {
                matchingNodeIDs.insert(node.id)
            }
            if isVisible {
                visibleNodeIDs.insert(node.id)
            }
            if node.isFolder, hasVisibleDescendant {
                foldersWithVisibleDescendants.insert(node.id)
            }

            return isVisible
        }

        nodes.forEach { visit($0) }
        return AddTorrentFileSearchProjection(
            visibleNodeIDs: visibleNodeIDs,
            foldersWithVisibleDescendants: foldersWithVisibleDescendants,
            matchingNodeIDs: matchingNodeIDs
        )
    }
}

enum AddTorrentSearchFolderExpansion {
    static func isExpanded(
        folderID: String,
        projection: AddTorrentFileSearchProjection,
        collapsedFolderIDs: Set<String>,
        expandedFolderIDs: Set<String>
    ) -> Bool {
        if expandedFolderIDs.contains(folderID) {
            return true
        }

        return projection.foldersWithVisibleDescendants.contains(folderID)
            && !collapsedFolderIDs.contains(folderID)
    }
}

struct AddTorrentTextSegment: Identifiable, Equatable {
    enum Kind: Equatable {
        case text
        case number
    }

    let id: String
    let kind: Kind
    let value: String
    let animatesNumericChange: Bool
}

enum AddTorrentTextSegmentSpacing {
    static func movingTrailingWhitespaceToFollowingNumber(
        in segments: [AddTorrentTextSegment]
    ) -> [AddTorrentTextSegment] {
        guard segments.count > 1 else { return segments }

        var result = segments

        for index in result.indices.dropLast() {
            let followingIndex = result.index(after: index)
            let segment = result[index]
            guard segment.kind == .text,
                  result[followingIndex].kind == .number,
                  let lastNonWhitespaceIndex = segment.value.lastIndex(where: { !$0.isWhitespace })
            else {
                continue
            }

            let trailingWhitespaceIndex = segment.value.index(after: lastNonWhitespaceIndex)
            guard trailingWhitespaceIndex < segment.value.endIndex else { continue }

            let trailingWhitespace = String(segment.value[trailingWhitespaceIndex...])
            let followingSegment = result[followingIndex]

            result[index] = AddTorrentTextSegment(
                id: segment.id,
                kind: segment.kind,
                value: String(segment.value[..<trailingWhitespaceIndex]),
                animatesNumericChange: segment.animatesNumericChange
            )
            result[followingIndex] = AddTorrentTextSegment(
                id: followingSegment.id,
                kind: followingSegment.kind,
                value: trailingWhitespace + followingSegment.value,
                animatesNumericChange: followingSegment.animatesNumericChange
            )
        }

        return result
    }
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

/// The files list's scroll geometry: it moves the pinned folder, and in Debug
/// builds the review log records it.
private struct AddTorrentReviewScrollGeometry: Equatable {
    let offsetY: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat
    let visibleMinY: CGFloat
    let visibleMaxY: CGFloat
    let insetTop: CGFloat
    let insetBottom: CGFloat

    #if DEBUG
    static let zero = AddTorrentReviewScrollGeometry(
        offsetY: 0,
        contentHeight: 0,
        containerHeight: 0,
        visibleMinY: 0,
        visibleMaxY: 0,
        insetTop: 0,
        insetBottom: 0
    )
    #endif
}

#if DEBUG
@MainActor
private final class AddTorrentReviewDiagnosticsState {
    var operationID = "-"
    var scrollGeometry = AddTorrentReviewScrollGeometry.zero
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

    isolated deinit {
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
                    let event = "window.\(notification.name.rawValue)"
                    MainActor.assumeIsolated {
                        self?.report(event: event, source: source)
                    }
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
#endif

private let addTorrentIntegerFormatExpression = try? NSRegularExpression(
    pattern: #"%(?:(\d+)\$)?lld"#
)

#if DEBUG
private func addTorrentDiagnosticsToken(_ value: String?) -> String {
    guard let value else { return "-" }

    var hasher = Hasher()
    hasher.combine(value)
    return String(UInt(bitPattern: hasher.finalize()), radix: 16)
}

private func addTorrentDiagnosticsNumber(_ value: CGFloat) -> String {
    String(format: "%.2f", value)
}
#endif

enum AddTorrentReviewLayout {
    static let minimumWindowWidth: CGFloat = 780
    static let minimumWindowHeight: CGFloat = 570
    static let settingsColumnWidth: CGFloat = 380
    /// The window's corners are rounder on macOS 26: the buttons and cards
    /// near them keep more room, so the two curves sit together.
    static var settingsColumnPadding: CGFloat {
        if #available(macOS 27.0, *) { 12 } else { 18 }
    }
    static let leftColumnOutlineWidth: CGFloat = 1
    /// The summary card's distance from the window's edges, below and at
    /// the sides: 12 pt, and 8 pt on macOS 26, where the window's rounder
    /// corner leaves the card's corner one gap all round.
    static var summaryInset: CGFloat {
        if #available(macOS 27.0, *) { 12 } else { 8 }
    }

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
    static let stickyBackgroundTrailingInset: CGFloat = 0.5
    static let expandButtonContainerPadding: CGFloat = 2
    static let hoverAreaSpacing: CGFloat = 4
    static let hoverAreaPadding: CGFloat = 6
    static let hoverAreaCornerRadius: CGFloat = 8
    /// The summary is a card, rounded as a download card is, on both
    /// systems.
    static let summaryCornerRadius: CGFloat = TorrentCardLayout.cornerRadius
    static let summaryOutlineWidth: CGFloat = 0.5
    /// Between the card's edge and what it holds: the message and the row
    /// of numbers.
    static let summaryContentInset: CGFloat = 6
    /// Around the numbers, inside the row, as around a card's expanded
    /// metrics.
    static let summaryMetricsPadding: CGFloat = 6
    /// The low-space message sits inside the summary, this far from its edges
    /// and from the numbers below it.
    static let summaryMessageInset: CGFloat = summaryContentInset
    static let summaryMessagePadding: CGFloat = 8
    static var summaryMessageCornerRadius: CGFloat {
        ShatlCornerRadius.nested(in: summaryCornerRadius, inset: summaryMessageInset)
    }
    static let freeSpaceRefreshInterval = Duration.seconds(2)
    static let filesVerticalPadding: CGFloat = 4
    /// A group's title, the gap under it and a metric plate.
    static let standardSummaryMetricsHeight: CGFloat = 44
    static let cjkSummaryMetricsHeight: CGFloat = 46

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

    static func summaryMetricsHeight(for profile: ShatlTypographyProfile) -> CGFloat {
        switch profile {
        case .standard:
            standardSummaryMetricsHeight
        case .cjk:
            cjkSummaryMetricsHeight
        }
    }

    /// The numbers of the summary with the card's room above and below
    /// them: the card's height without a message.
    static func summaryRowHeight(for profile: ShatlTypographyProfile) -> CGFloat {
        summaryMetricsHeight(for: profile) + (summaryContentInset + summaryMetricsPadding) * 2
    }

    /// How much of the files the summary covers, with the gap under it.
    static func summaryOverlayHeight(for profile: ShatlTypographyProfile) -> CGFloat {
        summaryRowHeight(for: profile) + summaryInset
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

enum AddTorrentReviewSelectionIndicator {
    static func sourceValues(for state: AddTorrentTreeSelectionState) -> [Bool] {
        switch state {
        case .selected:
            [true]
        case .unselected:
            [false]
        case .mixed:
            [true, false]
        }
    }
}

private enum AddTorrentAvailableCapacity: Equatable {
    case loading
    case available(DiskSpaceInfo)
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

    @ViewBuilder
    var body: some View {
        #if DEBUG
        if ShatlAddTorrentReviewDiagnosticsLog.isEnabled {
            rowContent
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
        } else {
            rowContent
        }
        #else
        rowContent
        #endif
    }

    private var rowContent: some View {
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
                stickyBackground
                    .padding(.trailing, AddTorrentReviewLayout.stickyBackgroundTrailingInset)
                    .animation(ShatlMotion.stickyContentReplace, value: isPinned)
            }
        }
        .zIndex(isPinned ? 1 : 0)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = isPinned ? false : hovering
        }
    }

    private var stickyBackground: some View {
        Color.clear
            .glassEffect(
                .regular.interactive(false),
                in: Rectangle()
            )
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
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(ShatlColor.typographyPrimary)
                .frame(width: 16, height: 16)
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
                        // A step darker than the files' ground, which is
                        // itself a step darker than the window.
                        isHovered && !isPinned
                            ? ShatlColor.backgroundSecondary
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
        // Digits of one width, as the card's metrics: a rolling count keeps
        // the line's length.
        .monospacedDigit()
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
            // A changing number rolls in place; one that comes or goes with
            // the wording, as "3 файла" giving way to "Файлы не выбраны",
            // blurs like the words around it.
            Text(segment.value)
                .foregroundStyle(foregroundColor)
                .contentTransition(contentTransition)
                .id(folderSummarySegmentIdentity(segment, mode: mode))
                .transition(.blurReplace)
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

    #if DEBUG
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
    #endif
}

/// The add window's own keyboard focus, reached past SwiftUI.
///
/// SwiftUI takes the focus from a field a step after it is asked to, and the
/// window may be gone by then: the field's focus ring, which the system
/// draws apart from the window's content, stayed on screen for a moment
/// after the window had closed. Asked through the window, the focus leaves
/// at once.
@MainActor
final class AddTorrentReviewWindowFocus {
    fileprivate weak var window: NSWindow?

    /// Takes the keyboard from whatever field holds it, now.
    func release() {
        window?.makeFirstResponder(nil)
    }
}

/// Hands the window to `AddTorrentReviewWindowFocus` and releases the focus
/// as the window is about to close, however it is closed.
private struct AddTorrentReviewWindowFocusBridge: NSViewRepresentable {
    let focus: AddTorrentReviewWindowFocus
    let onWindowWillClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(focus: focus, onWindowWillClose: onWindowWillClose)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onWindowWillClose = onWindowWillClose
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            context.coordinator.observe(window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator {
        let focus: AddTorrentReviewWindowFocus
        var onWindowWillClose: () -> Void
        private weak var observedWindow: NSWindow?
        private var closeObservation: NSObjectProtocol?

        init(focus: AddTorrentReviewWindowFocus, onWindowWillClose: @escaping () -> Void) {
            self.focus = focus
            self.onWindowWillClose = onWindowWillClose
        }

        func observe(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            stopObserving()
            observedWindow = window
            focus.window = window
            closeObservation = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.focus.release()
                    self?.onWindowWillClose()
                }
            }
        }

        func stopObserving() {
            if let closeObservation {
                NotificationCenter.default.removeObserver(closeObservation)
            }
            closeObservation = nil
            observedWindow = nil
        }

        isolated deinit {
            if let closeObservation {
                NotificationCenter.default.removeObserver(closeObservation)
            }
        }
    }
}

/// The add window. It watches the window's own model, so what changes while
/// the window is in use reaches this window and not the main window's list;
/// see `AddTorrentReviewModel`.
struct AddTorrentReviewView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        AddTorrentReviewContent(review: store.addTorrentReview)
            // A download dropped here waits at the end, as one opened from
            // Finder. Only the system's "+" at the pointer says so: a screen
            // over the settings plate is the kind of effect that has drawn
            // its labels upside down; `AddTorrentReviewAppearanceTests`
            // builds the window with this catcher over it.
            .overlay {
                DraggedDownloadCatcher(
                    isAvailable: { store.acceptsDraggedDownloads },
                    onDrop: { downloads in
                        NSApp.activate()
                        store.addDraggedDownloads(downloads)
                    }
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

private struct AddTorrentReviewContent: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var review: AddTorrentReviewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.shatlTypographyProfile) private var typographyProfile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedFolderIDs: Set<String> = []
    @State private var searchCollapsedFolderIDs: Set<String> = []
    @State private var searchExpandedFolderIDs: Set<String> = []
    @State private var pinnedFolderID: String?
    @State private var availableCapacity: AddTorrentAvailableCapacity = .loading
    /// The folders of downloads writing to the disk the files go to; what
    /// they will still write is counted beside the free space.
    @State private var sameDiskFolders: Set<String> = []
    /// The low-space message's height as laid out: the summary's plate grows
    /// by it, and the file list leaves as much room under its last row.
    @State private var lowSpaceMessageHeight: CGFloat = 0
    #if DEBUG
    @State private var addTorrentDiagnosticsState = AddTorrentReviewDiagnosticsState()
    #endif
    @State private var filesScrollGeneration = 0
    @State private var pendingCollapsedFolderID: String?
    @State private var renderedDraft: AddTorrentDraft?
    @State private var appliedSearchText = ""
    @State private var filePresentation = AddTorrentReviewFilePresentation.empty
    /// What the summary shows, which may lag behind `filePresentation`
    /// while the arrows run; see `followSummary`.
    @State private var summaryCounts = AddTorrentReviewSummaryCounts()
    @State private var summarySettleTask: Task<Void, Never>?
    /// The free space the summary shows; see `followFreeSpace`.
    @State private var shownFreeSpace: AddTorrentFreeSpace = .reading
    @State private var freeSpaceSpinnerTask: Task<Void, Never>?
    /// Set once waiting has lasted long enough to be worth a message; see
    /// `AddTorrentReviewStage`.
    @State private var showsWaitingMessage = false
    @State private var waitingMessageTask: Task<Void, Never>?
    /// The stage that was on screen last, kept while the files are being
    /// prepared; see `shownStage` and `followStage`.
    @State private var settledStage = AddTorrentReviewStage.blank
    /// The files are built and wait unseen to be shown.
    @State private var isReviewPrepared = false
    @State private var stageTask: Task<Void, Never>?
    /// The message that was on screen last, for the moment the files are
    /// ready and the message is still what the window shows.
    @State private var lastMessage: ReviewMessage?
    @FocusState private var isAliasFocused: Bool
    /// The window's own focus, where it rests unless a field is clicked; see
    /// the note at `defaultFocus` below.
    @FocusState private var isWindowFocused: Bool
    @State private var windowFocus = AddTorrentReviewWindowFocus()

    var body: some View {
        // One stage at a time, each over the whole window and sharing
        // nothing with the next, so nothing is carried from one into the
        // other: one dissolves as the other comes. The animation sits on
        // what holds them all.
        ZStack {
            // The files take a moment to build and to draw, their rows last.
            // Shown as they were put into the window, they came in pieces:
            // buttons first, the tree and the settings a frame later. So
            // they are put in unseen and shown once they are whole; see
            // `followStage`.
            //
            // Unseen means under a cover, and never through an effect of
            // their own. Fading or scaling the files made SwiftUI move the
            // settings plate's labels into one AppKit view with its text
            // field and its switch for as long as the effect lasted, and
            // there the labels were at times drawn upside down, for the
            // whole fade (the owner's recording, October 2026; a blur over
            // the plate did the same in September).
            if shownStage == .review || isReviewPrepared {
                reviewStage
                    // Enabled from the start, though the window around it
                    // is not yet: it must not be drawn anew as it is shown.
                    .environment(\.isEnabled, true)
                    .allowsHitTesting(shownStage == .review)
                    .accessibilityHidden(shownStage != .review)
                    .transition(.asymmetric(insertion: .identity, removal: heldUnderCover))
                    .zIndex(0)
            }

            // The cover is the window's own colour: the files come out of
            // the window as it dissolves, and go back into it.
            if shownStage != .review {
                ShatlColor.backgroundWindow
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .transition(.opacity)
                    .zIndex(1)
            }

            if shownStage == .message, let message = reviewMessage ?? lastMessage {
                messageStage(message)
                    .transition(stageTransition)
                    .zIndex(2)
            }
        }
        .animation(ShatlMotion.mainContentMode, value: shownStage)
        .frame(
            minWidth: AddTorrentReviewLayout.minimumWindowWidth,
            minHeight: AddTorrentReviewLayout.minimumWindowHeight
        )
        .modifier(
            AddTorrentReviewSearchModifier(
                prompt: L10n.string(
                    "add_torrent.review.search_files",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Искать файлы…"
                ),
                resetKey: draftPresentationToken?.id,
                onDebouncedChange: applySearchText
            )
        )
        // Only the files are searched; a message enables its own buttons.
        .disabled(shownStage != .review)
        // The window itself holds the focus, as the main window's list does,
        // and the alias field takes it only by a click or Tab. Left to
        // itself, macOS focuses the first text field in a window as the
        // window is shown: a `.torrent` file is read at once, its files were
        // in the window before the window was on screen, and the alias field
        // came up focused, time after time. Outside `disabled`, or the
        // window could not hold the focus before the files are shown.
        .focusable()
        .focusEffectDisabled()
        .focused($isWindowFocused)
        .defaultFocus($isWindowFocused, true)
        // ⌘V adds copied links or `.torrent` files at the end, a message on
        // screen or not; the alias and search fields take ⌘V as text.
        .onPasteCommand(of: MainWindowDropLayout.draggedTypes) { providers in
            store.addPastedDownloads(from: providers)
        }
        .onChange(of: waitingKey, initial: true) { _, key in
            followWaiting(key)
        }
        .onChange(of: reviewMessage, initial: true) { _, message in
            if let message {
                lastMessage = message
            }
        }
        .onChange(of: stage, initial: true) { _, newStage in
            followStage(newStage)
        }
        .onChange(of: shownStage) { _, newStage in
            if newStage != .review {
                isAliasFocused = false
            }
        }
        .onDisappear {
            waitingMessageTask?.cancel()
            stageTask?.cancel()
            summarySettleTask?.cancel()
            freeSpaceSpinnerTask?.cancel()
        }
        #if DEBUG
        .onGeometryChange(for: CGSize.self) { geometry in
            geometry.size
        } action: { oldSize, newSize in
            logWindowRootSizeChange(from: oldSize, to: newSize)
        }
        .background {
            AddTorrentReviewWindowDiagnosticsReader(
                selectedTab: "combined",
                layoutMode: "split-window"
            )
            .frame(width: 0, height: 0)
        }
        #endif
        .background {
            AddTorrentReviewWindowFocusBridge(focus: windowFocus) {
                isAliasFocused = false
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            renderedDraft = review.draft
            if let draft {
                rebuildFilePresentation(
                    draft: draft,
                    expandsTopLevelFolders: draft.reviewState == .ready
                )
            }
            followSummary(waitsForTheArrows: false)
        }
        .onChange(of: draftPresentationToken) { oldToken, newToken in
            guard let newToken, let newDraft = review.draft else { return }
            let isNewDraft = oldToken?.id != newToken.id
            let becameReady = oldToken?.reviewState != .ready && newToken.reviewState == .ready
            if isNewDraft {
                // The search of the last download goes with it, before its
                // query can filter these files; the window takes the focus.
                appliedSearchText = ""
                isWindowFocused = true
                expandedFolderIDs.removeAll()
                searchCollapsedFolderIDs.removeAll()
                searchExpandedFolderIDs.removeAll()
                pinnedFolderID = nil
                pendingCollapsedFolderID = nil
                filesScrollGeneration += 1
            }
            renderedDraft = newDraft
            rebuildFilePresentation(
                draft: newDraft,
                expandsTopLevelFolders: isNewDraft || becameReady
            )
            // One download's files giving way to another's, by the arrows or
            // after "Скачать": the summary waits for the arrows to rest.
            followSummary(
                waitsForTheArrows: isNewDraft
                    && oldToken?.showsFiles == true
                    && newToken.showsFiles
            )
        }
        .onChange(of: typographyProfile) { _, _ in
            rebuildFilePresentation()
        }
        .task(id: draft?.suggestedSavePath) {
            // Free space is read again every few seconds while the window is
            // open: the low-space message leaves by itself once room appears.
            // One question to the system per read, off the main thread.
            availableCapacity = .loading
            sameDiskFolders = []
            while !Task.isCancelled {
                await refreshAvailableCapacity()
                try? await Task.sleep(for: AddTorrentReviewLayout.freeSpaceRefreshInterval)
            }
        }
        .onChange(of: availableCapacity, initial: true) { _, capacity in
            followFreeSpace(capacity)
        }
        .task(id: store.writingDownloadFolders) {
            // A download started in another folder of the same disk counts
            // at once, not at the next read of the free space.
            guard case let .available(info) = availableCapacity else { return }
            await refreshSameDiskFolders(volumeURL: info.volumeURL)
        }
    }

    private var stage: AddTorrentReviewStage {
        AddTorrentReviewStage.current(
            reviewState: draft?.reviewState,
            hasFiles: draft?.files.isEmpty == false,
            showsWaiting: showsWaitingMessage
        )
    }

    private var stageTransition: AnyTransition {
        reduceMotion ? .opacity : ShatlMotion.mainContent
    }

    /// Keeps the files in the window, as they were, for as long as the
    /// cover takes to come over them.
    private var heldUnderCover: AnyTransition {
        .modifier(
            active: AddTorrentReviewHeldStage(progress: 1),
            identity: AddTorrentReviewHeldStage(progress: 0)
        )
    }

    /// What the waiting message's delay is counted for: a new download, or
    /// the same one going from waiting to its result.
    private struct WaitingKey: Equatable {
        var draftID: UUID?
        var isWaiting: Bool
    }

    private var waitingKey: WaitingKey {
        let isWaiting: Bool
        switch draft?.reviewState {
        case .loadingMetadata?, nil:
            isWaiting = true
        case .ready?, .invalid?:
            isWaiting = false
        }
        return WaitingKey(draftID: draft?.id, isWaiting: isWaiting)
    }

    /// The waiting message comes only once waiting has lasted: a `.torrent`
    /// file is read at once, and the message would flash over the whole
    /// window before the files. Until then the window is empty.
    private func followWaiting(_ key: WaitingKey) {
        waitingMessageTask?.cancel()
        waitingMessageTask = nil

        if showsWaitingMessage {
            // A new wait starts from an empty window, not from the message
            // of the last one.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showsWaitingMessage = false
            }
        }
        guard key.isWaiting else { return }

        waitingMessageTask = Task { @MainActor in
            try? await Task.sleep(for: ShatlMotion.addTorrentWaitingMessageDelay)
            guard !Task.isCancelled else { return }
            showsWaitingMessage = true
        }
    }

    /// The stage on screen. A message, or the empty window, is shown the
    /// moment it is due, and a stage that leaves goes at once and as it was.
    /// Only the files wait: until they are prepared, the window keeps what
    /// it showed before them.
    private var shownStage: AddTorrentReviewStage {
        stage == .review ? settledStage : stage
    }

    /// Prepares the files before they are shown. They are put into the
    /// window unseen while the message, or the empty window, stays, and are
    /// shown once they have had the time to build and to draw: they then
    /// come as one.
    private func followStage(_ target: AddTorrentReviewStage) {
        stageTask?.cancel()
        stageTask = nil

        guard target == .review else {
            isReviewPrepared = false
            settledStage = target
            return
        }

        guard settledStage != .review else { return }
        isReviewPrepared = true
        stageTask = Task { @MainActor in
            try? await Task.sleep(for: ShatlMotion.reviewStageSettleDelay)
            guard !Task.isCancelled else { return }
            settledStage = .review
            isReviewPrepared = false
        }
    }

    /// The message with its actions, in the middle of the whole window.
    private func messageStage(_ message: ReviewMessage) -> some View {
        ShatlMessageBlockPrimary(
            systemImage: message.systemImage,
            title: message.title,
            message: message.message,
            primaryButton: primaryMessageButton(for: message.actions, leadsForward: message.leadsForward),
            secondaryButtons: secondaryMessageButtons(for: message.actions, leadsForward: message.leadsForward)
        )
        // The window is disabled outside the review, for its search; the
        // message's own actions stay pressable.
        .environment(\.isEnabled, true)
        .animation(ShatlMotion.messageBlockContent, value: message)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var reviewStage: some View {
        HStack(spacing: 0) {
            filesColumn

            settingsColumn
        }
    }

    private var filesColumn: some View {
        filesContainer()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottom) {
                torrentSummaryContainer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShatlColor.backgroundAddWindow)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(ShatlColor.outlineTertiary)
                    .frame(width: AddTorrentReviewLayout.leftColumnOutlineWidth)
                    .allowsHitTesting(false)
            }
    }

    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsTabContent

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                cancelButton
                confirmButton
            }
        }
        .padding(AddTorrentReviewLayout.settingsColumnPadding)
        .frame(width: AddTorrentReviewLayout.settingsColumnWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var draft: AddTorrentDraft? {
        review.draft ?? renderedDraft
    }

    private var draftPresentationToken: AddTorrentReviewDraftPresentationToken? {
        guard let draft = review.draft else { return nil }

        return AddTorrentReviewDraftPresentationToken(
            id: draft.id,
            fileSelectionRevision: draft.fileSelectionRevision,
            reviewState: draft.reviewState,
            fileCount: draft.files.count
        )
    }

    private func applySearchText(_ newSearchText: String) {
        guard appliedSearchText != newSearchText else { return }

        appliedSearchText = newSearchText
        searchCollapsedFolderIDs.removeAll()
        searchExpandedFolderIDs.removeAll()
        pinnedFolderID = nil
        pendingCollapsedFolderID = nil
        filesScrollGeneration += 1
        rebuildFilePresentation()
    }

    private func rebuildFilePresentation(
        draft newDraft: AddTorrentDraft? = nil,
        expandsTopLevelFolders: Bool = false
    ) {
        let tree = newDraft?.fileTree ?? filePresentation.tree
        if expandsTopLevelFolders {
            expandedFolderIDs = AddTorrentInitialFolderExpansion.folderIDs(in: tree)
        }
        let selectionMetrics = newDraft.map { draft in
            draft.files.reduce(into: (count: 0, bytes: Int64(0))) { result, file in
                guard file.isSelected else { return }
                result.count += 1
                result.bytes += file.sizeBytes
            }
        }
        let searchProjection = AddTorrentFileSearchProjection.make(
            from: tree,
            query: appliedSearchText
        )
        let rows = flattenedFileRows(
            tree,
            level: 0,
            ancestorFolderIDs: [],
            searchProjection: searchProjection,
            includesUnmatchedNodes: false
        )

        var rowIndexByID: [String: Int] = [:]
        rowIndexByID.reserveCapacity(rows.count)

        var rowBottomOffsets: [CGFloat] = []
        rowBottomOffsets.reserveCapacity(rows.count)
        var rowBottom = AddTorrentReviewLayout.filesVerticalPadding

        for (index, row) in rows.enumerated() {
            rowIndexByID[row.id] = index
            rowBottom += AddTorrentReviewLayout.listItemHeight(
                for: typographyProfile,
                showsFolderSummary: row.node.isFolder && row.node.fileCount >= 3
            )
            rowBottomOffsets.append(rowBottom)
        }

        #if DEBUG
        let oldRowCount = filePresentation.rows.count
        #endif
        filePresentation = AddTorrentReviewFilePresentation(
            tree: tree,
            searchProjection: searchProjection,
            rows: rows,
            rowIndexByID: rowIndexByID,
            rowBottomOffsets: rowBottomOffsets,
            selectedFileCount: selectionMetrics?.count ?? filePresentation.selectedFileCount,
            selectedBytes: selectionMetrics?.bytes ?? filePresentation.selectedBytes,
            totalFileCount: newDraft?.files.count ?? filePresentation.totalFileCount
        )

        #if DEBUG
        if ShatlAddTorrentReviewDiagnosticsLog.isEnabled {
            logRowsChange(
                oldCount: oldRowCount,
                newIDs: rows.map(\.id),
                rows: rows
            )
        }
        #endif
    }

    #if DEBUG
    private func logWindowRootSizeChange(from oldSize: CGSize, to newSize: CGSize) {
        guard ShatlAddTorrentReviewDiagnosticsLog.isEnabled else { return }

        ShatlAddTorrentReviewDiagnosticsLog.event(
            "window.root.size.changed",
            fields: [
                "layoutMode": "split-window",
                "new.height": addTorrentDiagnosticsNumber(newSize.height),
                "new.width": addTorrentDiagnosticsNumber(newSize.width),
                "old.height": addTorrentDiagnosticsNumber(oldSize.height),
                "old.width": addTorrentDiagnosticsNumber(oldSize.width),
            ],
            flush: true
        )
    }
    #endif

    /// What the window says while it has no files to show. One block for all
    /// of it, so waiting turns into a failure in place.
    private struct ReviewMessage: Equatable {
        var systemImage: String
        var title: String
        var message: String?
        var actions: AddTorrentReviewMessageActions
        /// Where "Следующая загрузка" / "Предыдущая загрузка" leads, taken
        /// as the message is made: a message on its way out keeps the label
        /// it was seen with, though the window has already moved on.
        var leadsForward: Bool
    }

    private var reviewMessage: ReviewMessage? {
        let locale = store.preferences.localeOverride
        let reviewState = draft?.reviewState
        // A duplicate whose download is known offers to show it in the list.
        let isKnownDuplicate = draft?.errorState?.kind == .duplicateTorrent && review.duplicateID != nil
        let actions = AddTorrentReviewMessageActions.current(
            reviewState: reviewState,
            isKnownDuplicate: isKnownDuplicate,
            othersWait: review.count > 1
        )

        switch reviewState {
        case .ready?:
            guard let draft, draft.files.isEmpty else { return nil }
            return ReviewMessage(
                systemImage: "tray",
                title: L10n.string("add_torrent.review.no_files.title", localeOverride: locale),
                message: L10n.string("add_torrent.review.no_files.message", localeOverride: locale),
                actions: actions,
                leadsForward: review.hasNext
            )

        case .loadingMetadata?:
            // Only a magnet link waits for peers; a file is read at once.
            let waitsForPeers = draft?.source.rawValue.hasPrefix("magnet:") ?? false
            return ReviewMessage(
                systemImage: "doc.text.magnifyingglass",
                title: L10n.string("add_torrent.review.loading.title", localeOverride: locale),
                message: waitsForPeers
                    ? L10n.string("add_torrent.review.loading.message", localeOverride: locale)
                    : nil,
                actions: actions,
                leadsForward: review.hasNext
            )

        case .invalid?:
            let errorState = draft?.errorState
            // Among several downloads, a text for the button there; it
            // changes by itself if more downloads arrive while it is shown.
            let isAmongSeveral = review.count > 1
            let textAmongSeveral = isAmongSeveral ? errorState?.messageAmongSeveral : nil
            // Among several, the title names the download: no file tree
            // shows which one it is.
            let titleAmongSeveral = isAmongSeveral ? errorState?.titleAmongSeveral : nil
            let message = textAmongSeveral ?? errorState?.message ?? ""
            return ReviewMessage(
                systemImage: errorState?.kind == .noConnection ? "wifi.slash" : "exclamationmark.circle",
                title: titleAmongSeveral
                    ?? errorState?.title
                    ?? L10n.string("add_torrent.review.invalid_placeholder", localeOverride: locale),
                message: message.isEmpty ? nil : message,
                actions: actions,
                leadsForward: review.hasNext
            )

        case .none:
            return ReviewMessage(
                systemImage: "hourglass",
                title: L10n.string("add_torrent.review.preparing.title", localeOverride: locale),
                message: L10n.string("add_torrent.review.preparing.message", localeOverride: locale),
                actions: actions,
                leadsForward: review.hasNext
            )
        }
    }

    private func primaryMessageButton(
        for actions: AddTorrentReviewMessageActions,
        leadsForward: Bool
    ) -> ShatlMessageBlockPrimaryButton {
        switch actions {
        case .cancel:
            // Closes the window and stops preparing the download, as the
            // window's close button does; among several, stops only this one.
            ShatlMessageBlockPrimaryButton(
                title: L10n.string("common.cancel", localeOverride: store.preferences.localeOverride),
                keyboardShortcut: .cancelAction
            ) {
                if review.isBatch {
                    skipCurrentDownload()
                } else {
                    closeWindow()
                }
            }
        case .close:
            closeWindowButton
        case .next:
            nextDownloadButton(leadsForward: leadsForward)
        case .showInListAndClose, .showInListAndNext:
            ShatlMessageBlockPrimaryButton(
                title: L10n.string("add_torrent.review.show_in_list", localeOverride: store.preferences.localeOverride)
            ) {
                showDuplicateInList()
            }
        }
    }

    private func secondaryMessageButtons(
        for actions: AddTorrentReviewMessageActions,
        leadsForward: Bool
    ) -> [ShatlMessageBlockPrimaryButton] {
        switch actions {
        case .cancel, .close, .next:
            []
        case .showInListAndClose:
            [closeWindowButton]
        case .showInListAndNext:
            [nextDownloadButton(leadsForward: leadsForward)]
        }
    }

    /// "Закрыть окно", not "Закрыть": inside a message a bare "Close" reads
    /// as closing the message.
    private var closeWindowButton: ShatlMessageBlockPrimaryButton {
        ShatlMessageBlockPrimaryButton(
            title: L10n.string("add_torrent.review.close", localeOverride: store.preferences.localeOverride),
            keyboardShortcut: .cancelAction
        ) {
            closeWindow()
        }
    }

    /// Among several downloads, one that cannot be downloaded leaves the
    /// window, and another is shown: "Закрыть окно" would take all the
    /// others with it. Named for where it leads, as the arrows are: the next
    /// download, or the one before when this was the last in line.
    private func nextDownloadButton(leadsForward: Bool) -> ShatlMessageBlockPrimaryButton {
        ShatlMessageBlockPrimaryButton(
            title: L10n.string(
                leadsForward ? "add_torrent.review.next" : "add_torrent.review.previous",
                localeOverride: store.preferences.localeOverride,
                defaultValue: leadsForward ? "Следующая загрузка" : "Предыдущая загрузка"
            ),
            keyboardShortcut: .cancelAction
        ) {
            skipCurrentDownload()
        }
    }

    /// The focus leaves before the window does; see
    /// `AddTorrentReviewWindowFocus`.
    private func closeWindow() {
        isAliasFocused = false
        windowFocus.release()
        store.dismissModal()
    }

    /// Brings the summary's numbers to the download on screen. A ticked file
    /// moves them at once. Another download moves them only once the arrows
    /// have rested (`ShatlMotion.reviewSummarySettleDelay`), and they roll
    /// to it then: stepping quickly through many downloads, the summary keeps
    /// the numbers it shows instead of blurring them and making its lines
    /// jump between two and three digits; the eye is on the top of the files
    /// meanwhile (the owner's decision, November 2026).
    private func followSummary(waitsForTheArrows: Bool) {
        summarySettleTask?.cancel()
        summarySettleTask = nil
        guard waitsForTheArrows else {
            summaryCounts = currentSummaryCounts
            return
        }
        summarySettleTask = Task { @MainActor in
            try? await Task.sleep(for: ShatlMotion.reviewSummarySettleDelay)
            guard !Task.isCancelled else { return }
            summaryCounts = currentSummaryCounts
        }
    }

    private var currentSummaryCounts: AddTorrentReviewSummaryCounts {
        AddTorrentReviewSummaryCounts(
            selectedFileCount: filePresentation.selectedFileCount,
            selectedBytes: filePresentation.selectedBytes,
            totalFileCount: filePresentation.totalFileCount
        )
    }

    /// "Показать в списке": the main window comes forward with the download,
    /// opened anew if it was closed. Among several the others keep waiting
    /// here, so it asks nothing; see `AppStore.showAddTorrentDuplicateInList`.
    private func showDuplicateInList() {
        windowFocus.release()
        store.showAddTorrentDuplicateInList()
        openWindow(id: AppWindowID.main)
    }

    /// The download on screen leaves the window, which shows the next one or
    /// closes after the last. The focus leaves first, as on closing.
    private func skipCurrentDownload() {
        isAliasFocused = false
        windowFocus.release()
        store.skipCurrentDraft()
    }

    /// The main list's block for a search with no results, about files.
    private var fileSearchEmptyState: some View {
        ShatlMessageBlockPrimary(
            systemImage: "exclamationmark.magnifyingglass",
            title: L10n.format(
                "search.empty.title",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Нет результатов для «%@».",
                ShatlSearchQueryDisplay.quoted(appliedSearchText)
            ),
            message: L10n.string(
                "add_torrent.review.search.empty.description",
                localeOverride: store.preferences.localeOverride
            )
        )
        .padding(.horizontal, 24)
        .padding(
            .bottom,
            AddTorrentReviewLayout.summaryOverlayHeight(for: typographyProfile) + lowSpaceExtraHeight
        )
        .allowsHitTesting(false)
    }

    private func filesContainer() -> some View {
        let rows = filePresentation.rows

        return ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        fileListItem(row)
                            .id(row.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, AddTorrentReviewLayout.filesVerticalPadding)
                .padding(
                    .bottom,
                    AddTorrentReviewLayout.summaryOverlayHeight(for: typographyProfile)
                        + lowSpaceExtraHeight
                )
            }
            .scrollIndicators(.hidden)
            // Nothing found: a tree with no rows looked like a torrent with
            // no files. The message stands on the tree's ground, above the
            // summary, not over the whole window.
            .overlay {
                if filePresentation.searchProjection != nil, rows.isEmpty {
                    fileSearchEmptyState
                }
            }
            .id(filesScrollGeneration)
            .task(id: filesScrollGeneration) {
                guard let targetID = pendingCollapsedFolderID else { return }
                await Task.yield()
                scrollProxy.scrollTo(targetID, anchor: .top)
                #if DEBUG
                logScrollRecreation(targetID: targetID)
                #endif
                pendingCollapsedFolderID = nil
            }
            .onScrollGeometryChange(for: AddTorrentReviewScrollGeometry.self) { geometry in
                AddTorrentReviewScrollGeometry(
                    offsetY: geometry.contentOffset.y + geometry.contentInsets.top,
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height,
                    visibleMinY: geometry.visibleRect.minY,
                    visibleMaxY: geometry.visibleRect.maxY,
                    insetTop: geometry.contentInsets.top,
                    insetBottom: geometry.contentInsets.bottom
                )
            } action: { oldSnapshot, newSnapshot in
                #if DEBUG
                if ShatlAddTorrentReviewDiagnosticsLog.isEnabled {
                    addTorrentDiagnosticsState.scrollGeometry = newSnapshot
                    logScrollGeometryChange(
                        from: oldSnapshot,
                        to: newSnapshot,
                        rows: rows
                    )
                }
                #endif
                updatePinnedFolder(scrollOffset: newSnapshot.offsetY, rows: rows)
            }
            #if DEBUG
            .onAppear {
                logFilesContainerLifecycleEvent("files.container.appeared", rows: rows)
            }
            .onDisappear {
                logFilesContainerLifecycleEvent("files.container.disappeared", rows: rows)
            }
            #endif
            .overlay(alignment: .top) {
                Group {
                    if let pinnedFolderID,
                       let pinnedRowIndex = filePresentation.rowIndexByID[pinnedFolderID],
                       rows.indices.contains(pinnedRowIndex) {
                        let pinnedRow = rows[pinnedRowIndex]
                        fileListItem(pinnedRow, isPinned: true)
                            .transition(ShatlMotion.stickyPinInsertion)
                    }
                }
                .animation(ShatlMotion.stickyContentReplace, value: pinnedFolderID)
                .animation(ShatlMotion.stickyContentReplace, value: pinnedFolderID != nil)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    #if DEBUG
    private func logScrollGeometryChange(
        from oldSnapshot: AddTorrentReviewScrollGeometry,
        to newSnapshot: AddTorrentReviewScrollGeometry,
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
        geometry: AddTorrentReviewScrollGeometry
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
        rows.reduce(
            AddTorrentReviewLayout.filesVerticalPadding * 2
                + AddTorrentReviewLayout.summaryOverlayHeight(for: typographyProfile)
        ) { height, row in
            height + AddTorrentReviewLayout.listItemHeight(
                for: typographyProfile,
                showsFolderSummary: row.node.isFolder && row.node.fileCount >= 3
            )
        }
    }
    #endif

    private func flattenedFileRows(
        _ nodes: [AddTorrentFileTreeNode],
        level: Int,
        ancestorFolderIDs: [String],
        searchProjection: AddTorrentFileSearchProjection?,
        includesUnmatchedNodes: Bool
    ) -> [AddTorrentFileTreeRow] {
        nodes.flatMap { node -> [AddTorrentFileTreeRow] in
            if let searchProjection,
               !includesUnmatchedNodes,
               !searchProjection.visibleNodeIDs.contains(node.id) {
                return []
            }

            let isExpanded = node.isFolder && isFolderExpanded(
                node,
                searchProjection: searchProjection
            )
            var rows = [
                AddTorrentFileTreeRow(
                    node: node,
                    level: level,
                    ancestorFolderIDs: ancestorFolderIDs,
                    isExpanded: isExpanded
                ),
            ]

            if node.isFolder,
               isExpanded,
               let children = node.children {
                let includesAllChildren = includesUnmatchedNodes
                    || searchExpandedFolderIDs.contains(node.id)
                rows.append(
                    contentsOf: flattenedFileRows(
                        children,
                        level: level + 1,
                        ancestorFolderIDs: ancestorFolderIDs + [node.id],
                        searchProjection: searchProjection,
                        includesUnmatchedNodes: includesAllChildren
                    )
                )
            }

            return rows
        }
    }

    private func fileListItem(_ row: AddTorrentFileTreeRow, isPinned: Bool = false) -> some View {
        let node = row.node

        return AddTorrentFileListItem(
            node: node,
            level: row.level,
            formattedSize: Metrics.formatBytes(
                node.sizeBytes,
                mode: .simplified,
                localeOverride: store.preferences.localeOverride
            ),
            folderSummary: folderSummary(for: node),
            isExpanded: row.isExpanded,
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

    private var torrentSummaryContainer: some View {
        torrentSummary
            .padding(.horizontal, AddTorrentReviewLayout.summaryInset)
            .padding(.bottom, AddTorrentReviewLayout.summaryInset)
    }

    private var torrentSummary: some View {
        let metrics = AddTorrentSummaryMetrics(groups: summaryGroups)
            .padding(AddTorrentReviewLayout.summaryContentInset + AddTorrentReviewLayout.summaryMetricsPadding)
            .frame(maxWidth: .infinity)

        // The numbers are what the summary is laid out by, and they never
        // move. The card behind them grows upward for the low-space message
        // the way a card grows for its expanded metrics: the height changes
        // smoothly while the message scales up and fades in, cut by the
        // card's shape. Stacked above the numbers, the message made the
        // card jump to its new height while the labels slid after it.
        return metrics
            .background {
                summaryCard
                    .padding(.top, -lowSpaceExtraHeight)
                    .animation(ShatlMotion.cardLayout, value: lowSpaceExtraHeight)
            }
            .overlay(alignment: .bottom) {
                lowSpaceMessageLayer
            }
    }

    /// A download card's fill, outline and corner, with a shadow of its own
    /// seen only around it.
    private var summaryCard: some View {
        torrentSummaryShape
            .fill(ShatlColor.cardBackgroundDefault)
            .overlay {
                torrentSummaryShape
                    .strokeBorder(
                        ShatlColor.cardOutlineDefault,
                        lineWidth: AddTorrentReviewLayout.summaryOutlineWidth
                    )
            }
            .shatlOutsideShadow(ShatlShadow.summary, in: torrentSummaryShape)
    }

    /// The numbers held for the download on screen (`followSummary`), and
    /// the free space as last read.
    private var summaryGroups: AddTorrentSummaryGroups {
        AddTorrentSummaryPresentation.groups(
            selectedFileCount: summaryCounts.selectedFileCount,
            totalFileCount: summaryCounts.totalFileCount,
            selectedBytes: summaryCounts.selectedBytes,
            freeSpace: shownFreeSpace,
            mode: store.preferences.metricsMode,
            localeOverride: store.preferences.localeOverride
        )
    }

    /// A new reading shows at once. While another folder's disk is read the
    /// summary keeps its number and rolls to the new one, and shows a
    /// spinner only if the reading takes a while
    /// (`ShatlMotion.freeSpaceSpinnerDelay`). The low-space message and the
    /// button follow `availableCapacity` itself, never this.
    private func followFreeSpace(_ capacity: AddTorrentAvailableCapacity) {
        freeSpaceSpinnerTask?.cancel()
        freeSpaceSpinnerTask = nil

        switch capacity {
        case .loading:
            guard shownFreeSpace != .reading else { return }
            freeSpaceSpinnerTask = Task { @MainActor in
                try? await Task.sleep(for: ShatlMotion.freeSpaceSpinnerDelay)
                guard !Task.isCancelled else { return }
                shownFreeSpace = .reading
            }
        case let .available(info):
            shownFreeSpace = .available(info.availableBytes)
        case .unavailable:
            shownFreeSpace = .unavailable
        }
    }

    /// The message in a box as tall as the plate at its fullest, standing on
    /// the summary's bottom edge. The box keeps its size as the message comes
    /// and goes, so a message on its way out stays where it was; inside the
    /// plate itself it rode the plate's falling top edge down over the
    /// numbers. A mask the shape of the plate cuts the message as the plate
    /// grows and shrinks.
    private var lowSpaceMessageLayer: some View {
        let rowHeight = AddTorrentReviewLayout.summaryRowHeight(for: typographyProfile)

        return Color.clear
            .frame(
                height: rowHeight
                    + lowSpaceMessageHeight
                    + AddTorrentReviewLayout.summaryMessageInset
            )
            .overlay(alignment: .bottom) {
                if let lowSpaceMessage {
                    lowSpaceMessageBlock(lowSpaceMessage)
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            geometry.size.height
                        } action: { height in
                            lowSpaceMessageHeight = height
                        }
                        .padding(.horizontal, AddTorrentReviewLayout.summaryMessageInset)
                        // Right above the numbers.
                        .padding(.bottom, rowHeight)
                        .transition(ShatlMotion.appearFromTop)
                }
            }
            .mask(alignment: .bottom) {
                torrentSummaryShape
                    .frame(height: rowHeight + lowSpaceExtraHeight)
            }
            .allowsHitTesting(false)
            .animation(ShatlMotion.cardLayout, value: lowSpaceMessage != nil)
            .animation(ShatlMotion.cardLayout, value: lowSpaceExtraHeight)
    }

    /// How far the plate reaches above the numbers: the message and the gap
    /// between it and the plate's top edge.
    private var lowSpaceExtraHeight: CGFloat {
        lowSpaceMessage == nil
            ? 0
            : lowSpaceMessageHeight + AddTorrentReviewLayout.summaryMessageInset
    }

    /// The selected files do not fit on the disk they are to be saved to.
    /// The button decides by the download on screen, always.
    private var spaceShortfall: DiskSpaceCheck? {
        spaceShortfall(neededBytes: filePresentation.selectedBytes)
    }

    /// The same for the numbers the summary shows: the message belongs to
    /// the summary and waits with it while the arrows run.
    private var shownSpaceShortfall: DiskSpaceCheck? {
        spaceShortfall(neededBytes: summaryCounts.selectedBytes)
    }

    private func spaceShortfall(neededBytes: Int64) -> DiskSpaceCheck? {
        guard areSettingsControlsEnabled, case let .available(info) = availableCapacity else {
            return nil
        }
        return DiskSpaceCheck.shortfall(neededBytes: neededBytes, promisedBytes: promisedBytes, on: info)
    }

    /// What downloads already writing to this disk will still write. Read
    /// from the list on every redraw, so a download stopped in the main
    /// window gives its room back at once.
    private var promisedBytes: Int64 {
        guard let path = draft?.suggestedSavePath else { return 0 }
        return store.promisedBytes(inFolders: sameDiskFolders.union([PromisedDiskSpace.folderKey(path)]))
    }

    /// Names the disk and what it lacks, and what downloads writing to it
    /// will take, then every way out; unticking files is one of them only
    /// when more than one is ticked, stopping downloads only when some write.
    private var lowSpaceMessage: String? {
        guard let spaceShortfall = shownSpaceShortfall else { return nil }
        let localeOverride = store.preferences.localeOverride
        let mode = store.preferences.metricsMode
        let volumeName = ShatlErrorCatalog.shortenedTorrentName(spaceShortfall.volumeName)
        let shortfall = spaceShortfall.shortfallText(mode: mode, localeOverride: localeOverride)
        let severalFiles = summaryCounts.selectedFileCount > 1

        guard spaceShortfall.promisedBytes != nil else {
            return L10n.format(
                severalFiles
                    ? "add_torrent.review.low_space.message.many_files"
                    : "add_torrent.review.low_space.message.one_file",
                localeOverride: localeOverride,
                defaultValue: "",
                volumeName,
                shortfall
            )
        }
        return L10n.format(
            severalFiles
                ? "add_torrent.review.low_space.message.many_files.promised"
                : "add_torrent.review.low_space.message.one_file.promised",
            localeOverride: localeOverride,
            defaultValue: "",
            volumeName,
            shortfall,
            spaceShortfall.promisedText(mode: mode, localeOverride: localeOverride)
        )
    }

    private func lowSpaceMessageBlock(_ message: String) -> some View {
        Text(message)
            .shatlTypography(ShatlTypography.captionRegular)
            .foregroundStyle(Color.white)
            .contentTransition(.numericText())
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AddTorrentReviewLayout.summaryMessagePadding)
            .background(ShatlColor.errorSolidBackground)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: AddTorrentReviewLayout.summaryMessageCornerRadius,
                    style: .continuous
                )
            )
            .animation(ShatlMotion.metricResize, value: message)
            .accessibilityAddTraits(.isStaticText)
    }

    private var torrentSummaryShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: AddTorrentReviewLayout.summaryCornerRadius,
            style: .continuous
        )
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

        return AddTorrentTextSegmentSpacing.movingTrailingWhitespaceToFollowingNumber(
            in: segments
        )
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
            let category = L10nPluralCategory.resolve(
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

        let category = L10nPluralCategory.resolve(
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
            #if DEBUG
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
            #endif
            pinnedFolderID = newPinnedFolderID
        }
    }

    private func pinnedFolderID(
        at scrollOffset: CGFloat,
        rows: [AddTorrentFileTreeRow]
    ) -> String? {
        guard let rowIndex = AddTorrentReviewRowLookup.index(
            at: scrollOffset,
            contentTop: AddTorrentReviewLayout.filesVerticalPadding,
            rowBottomOffsets: filePresentation.rowBottomOffsets
        ), rows.indices.contains(rowIndex) else {
            return nil
        }

        let row = rows[rowIndex]
        if row.node.isFolder, row.isExpanded {
            return row.node.id
        }

        return row.ancestorFolderIDs.last
    }

    private func selectionToggle(for node: AddTorrentFileTreeNode) -> some View {
        Group {
            if node.isFolder {
                Toggle(sources: selectionIndicatorSources(for: node), isOn: \.isSelected) {
                    EmptyView()
                }
            } else {
                Toggle(isOn: .constant(node.selectionState == .selected)) {
                    EmptyView()
                }
            }
        }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .fixedSize()
    }

    private func selectionIndicatorSources(
        for node: AddTorrentFileTreeNode
    ) -> [AddTorrentSelectionIndicatorSource] {
        // The surrounding row button owns the selection action. These sources
        // only let SwiftUI render the native selected, unselected, or mixed
        // checkbox without creating one Binding per descendant file.
        AddTorrentReviewSelectionIndicator.sourceValues(for: node.selectionState).map { value in
            AddTorrentSelectionIndicatorSource(
                id: value,
                isSelected: .constant(value)
            )
        }
    }

    private func toggleSelection(for node: AddTorrentFileTreeNode) {
        let shouldSelect = node.selectionState != .selected

        if node.isFolder {
            store.setDraftFolderSelection(path: node.path, isSelected: shouldSelect)
        } else if let fileID = node.fileID {
            store.setDraftFileSelection(id: fileID, isSelected: shouldSelect)
        }
    }

    private func isFolderExpanded(
        _ node: AddTorrentFileTreeNode,
        searchProjection: AddTorrentFileSearchProjection?
    ) -> Bool {
        if let searchProjection {
            return AddTorrentSearchFolderExpansion.isExpanded(
                folderID: node.id,
                projection: searchProjection,
                collapsedFolderIDs: searchCollapsedFolderIDs,
                expandedFolderIDs: searchExpandedFolderIDs
            )
        }

        return expandedFolderIDs.contains(node.id)
    }

    private func toggleFolderExpansion(
        _ node: AddTorrentFileTreeNode,
        source: String
    ) {
        let searchProjection = activeSearchProjection
        let wasExpanded = isFolderExpanded(node, searchProjection: searchProjection)
        #if DEBUG
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
        #endif

        if searchProjection != nil {
            if searchExpandedFolderIDs.contains(node.id) {
                searchExpandedFolderIDs.remove(node.id)
            } else if wasExpanded {
                searchCollapsedFolderIDs.insert(node.id)
                if pinnedFolderID == node.id {
                    pinnedFolderID = nil
                }
            } else if searchCollapsedFolderIDs.contains(node.id) {
                searchCollapsedFolderIDs.remove(node.id)
            } else {
                searchExpandedFolderIDs.insert(node.id)
            }
        } else if wasExpanded {
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

        rebuildFilePresentation()

        #if DEBUG
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
        #endif
    }

    #if DEBUG
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
        filePresentation.rows
    }
    #endif

    private var activeSearchProjection: AddTorrentFileSearchProjection? {
        filePresentation.searchProjection
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
                .foregroundStyle(ShatlColor.typographySecondary)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var areSettingsControlsEnabled: Bool {
        draft?.reviewState == .ready
    }

    private var isSuggestedSavePathDefault: Bool {
        (draft?.suggestedSavePath ?? "") == store.preferences.defaultDownloadPath
    }

    private var parametersGroup: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        L10n.format(
                            "add_torrent.review.download_to_folder",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: "Скачать в «%@»",
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

                HStack(spacing: 8) {
                    ShatlButton(
                        title: L10n.string(
                            "common.change",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: "Сменить"
                        ),
                        role: .borderedNeutral,
                        isDisabled: !areSettingsControlsEnabled,
                        fillsWidth: true
                    ) {
                        presentSavePathPicker()
                    }

                    ShatlButton(
                        title: L10n.string(
                            "add_torrent.review.set_as_default_folder",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: "Сделать по умолчанию"
                        ),
                        role: .borderedNeutral,
                        isDisabled: !areSettingsControlsEnabled || isSuggestedSavePathDefault
                    ) {
                        setSuggestedSavePathAsDefault()
                    }
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
                    .fixedSize(horizontal: false, vertical: true)

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
                Text(
                    L10n.string(
                        "add_torrent.review.use_alias",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Псевдоним"
                    )
                )
                    .shatlTypography(ShatlTypography.bodyRegular)
                    .foregroundStyle(ShatlColor.typographyPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField(
                    L10n.string(
                        "add_torrent.review.alias_placeholder",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Назовите загрузку…"
                    ),
                    text: Binding(
                        get: { draft?.alias ?? "" },
                        set: { store.updateDraftAlias($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .focused($isAliasFocused)
                .onKeyPress(.escape) {
                    guard isAliasFocused else { return .ignored }
                    isAliasFocused = false
                    return .handled
                }
            }
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

    /// Closes the window and stops preparing the download, as the window's
    /// close button does. With several downloads waiting, only the one on
    /// screen leaves, once the question has been answered: "Не скачивать".
    private var cancelButton: some View {
        ShatlButton(
            title: review.isBatch
                ? L10n.string(
                    "add_torrent.review.skip",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Не скачивать"
                )
                : L10n.string("common.cancel", localeOverride: store.preferences.localeOverride),
            role: .borderedNeutral
        ) {
            if review.isBatch {
                askToSkipCurrentDownload()
            } else {
                closeWindow()
            }
        }
        .keyboardShortcut(.cancelAction)
    }

    /// "Не скачивать" among several downloads asks first; see
    /// `AddTorrentSkipQuestion`. A download with no file ticked cannot be
    /// kept in the list, so it is only asked whether to let it go.
    private func askToSkipCurrentDownload() {
        guard let draft = review.draft else { return }
        let canSave = draft.canConfirmDownload
        isAliasFocused = false
        windowFocus.release()
        Task { @MainActor in
            let answer = await AddTorrentSkipQuestion.ask(
                about: draft,
                canSave: canSave,
                localeOverride: store.preferences.localeOverride,
                window: windowFocus.window
            )
            // Answered for the download it asked about: if the window has
            // moved on meanwhile, nothing is done to another one.
            guard review.draft?.id == draft.id else { return }
            switch answer {
            case .goBack:
                break
            case .saveToList:
                store.saveDraftToList(byChoice: true)
            case .skip:
                store.skipCurrentDraft()
            }
        }
    }

    /// With no room for the download the button saves it to the list
    /// instead of starting it, so the window is never a dead end.
    private var confirmButton: some View {
        let savesToList = spaceShortfall != nil
        return ShatlButton(
            title: L10n.string(
                savesToList ? "add_torrent.review.save_to_list" : "add_torrent.review.confirm",
                localeOverride: store.preferences.localeOverride,
                defaultValue: savesToList ? "Сохранить в список" : "Скачать"
            ),
            role: .borderedColored,
            isDisabled: !areSettingsControlsEnabled || filePresentation.selectedFileCount == 0
        ) {
            isAliasFocused = false
            windowFocus.release()
            if savesToList {
                store.saveDraftToList()
            } else {
                store.confirmDraft()
            }
        }
    }

    private var displayedFolderPath: String {
        let path = draft?.suggestedSavePath.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? folderNotSelectedTitle : path
    }

    private var displayedFolderName: String {
        let path = draft?.suggestedSavePath.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return folderNotSelectedTitle }

        // As Finder names it: "Загрузки", not the "Downloads" on disk.
        let folderName = ShatlErrorCatalog.folderDisplayName(forPath: path)
        return folderName.isEmpty ? path : folderName
    }

    private var folderNotSelectedTitle: String {
        L10n.string(
            "add_torrent.review.folder_not_selected",
            localeOverride: store.preferences.localeOverride,
            defaultValue: "Папка не выбрана"
        )
    }

    private func setSuggestedSavePathAsDefault() {
        guard let draft, !isSuggestedSavePathDefault else { return }

        store.setDefaultDownloadLocation(
            URL(fileURLWithPath: draft.suggestedSavePath, isDirectory: true),
            bookmarkData: draft.savePathBookmarkData
        )
    }

    private func refreshAvailableCapacity() async {
        guard let path = draft?.suggestedSavePath.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            availableCapacity = .unavailable
            return
        }

        let info = await store.diskSpace(atPath: path)
        let folders = await store.writingFolders(onDiskOf: path, volumeURL: info?.volumeURL)

        guard !Task.isCancelled else { return }
        availableCapacity = info.map(AddTorrentAvailableCapacity.available) ?? .unavailable
        sameDiskFolders = folders
    }

    private func refreshSameDiskFolders(volumeURL: URL?) async {
        guard let path = draft?.suggestedSavePath else { return }
        let folders = await store.writingFolders(onDiskOf: path, volumeURL: volumeURL)
        guard !Task.isCancelled else { return }
        sameDiskFolders = folders
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
