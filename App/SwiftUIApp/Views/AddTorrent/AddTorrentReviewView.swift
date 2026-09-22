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

private struct AddTorrentReviewSearchModifier: ViewModifier {
    let prompt: String
    let onDebouncedChange: (String) -> Void

    @State private var searchText = ""

    func body(content: Content) -> some View {
        content
            .searchable(
                text: $searchText,
                placement: .toolbar,
                prompt: Text(prompt)
            )
            .searchToolbarBehavior(.automatic)
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

enum AddTorrentNumericTextSegmentation {
    static func segments(in value: String) -> [AddTorrentTextSegment] {
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

        return AddTorrentTextSegmentSpacing.movingTrailingWhitespaceToFollowingNumber(
            in: segments
        )
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
    static let minimumWindowWidth: CGFloat = 780
    static let minimumWindowHeight: CGFloat = 570
    static let settingsColumnWidth: CGFloat = 380
    static let settingsColumnPadding: CGFloat = 12
    static let leftColumnOutlineWidth: CGFloat = 1
    static let summaryContainerHorizontalPadding: CGFloat = 6
    static let summaryContainerBottomPadding: CGFloat = 6

    static let filesContainerCornerRadius: CGFloat = 12
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
    static let summaryCornerRadius: CGFloat = 12
    static let summaryHorizontalPadding: CGFloat = 6
    static let summaryVerticalPadding: CGFloat = 12
    static let summarySpacing: CGFloat = 24
    static let filesVerticalPadding: CGFloat = 4
    static let standardSummaryContentHeight: CGFloat = 29
    static let cjkSummaryContentHeight: CGFloat = 33

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

    static func summaryOverlayHeight(for profile: ShatlTypographyProfile) -> CGFloat {
        summaryContentHeight(for: profile)
            + summaryVerticalPadding * 2
            + summaryContainerBottomPadding
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

enum AddTorrentSummaryPresentation {
    static func showsSelectionMetrics(selectedFileCount: Int) -> Bool {
        selectedFileCount >= 4
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

    @ViewBuilder
    var body: some View {
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

    @ViewBuilder
    private var stickyBackground: some View {
        if #available(macOS 27.0, *) {
            Color.clear
                .glassEffect(
                    .regular.interactive(false),
                    in: Rectangle()
                )
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
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

private struct AddTorrentReviewAliasFocusWindowCloseObserver: NSViewRepresentable {
    let onWindowWillClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowWillClose: onWindowWillClose)
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
        var onWindowWillClose: () -> Void
        private weak var observedWindow: NSWindow?
        private var closeObservation: NSObjectProtocol?

        init(onWindowWillClose: @escaping () -> Void) {
            self.onWindowWillClose = onWindowWillClose
        }

        func observe(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            stopObserving()
            observedWindow = window
            closeObservation = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
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

        deinit {
            if let closeObservation {
                NotificationCenter.default.removeObserver(closeObservation)
            }
        }
    }
}

struct AddTorrentReviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.shatlTypographyProfile) private var typographyProfile
    @State private var expandedFolderIDs: Set<String> = []
    @State private var searchCollapsedFolderIDs: Set<String> = []
    @State private var searchExpandedFolderIDs: Set<String> = []
    @State private var pinnedFolderID: String?
    @State private var availableCapacity: AddTorrentAvailableCapacity = .loading
    @State private var addTorrentDiagnosticsState = AddTorrentReviewDiagnosticsState()
    @State private var filesScrollGeneration = 0
    @State private var pendingCollapsedFolderID: String?
    @State private var renderedDraft: AddTorrentDraft?
    @State private var appliedSearchText = ""
    @State private var filePresentation = AddTorrentReviewFilePresentation.empty
    @FocusState private var isAliasFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            filesColumn

            settingsColumn
        }
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
                onDebouncedChange: applySearchText
            )
        )
        .disabled(!areSettingsControlsEnabled)
        .onGeometryChange(for: CGSize.self) { geometry in
            geometry.size
        } action: { oldSize, newSize in
            addTorrentDiagnosticsState.rootSize = newSize
            logWindowRootSizeChange(from: oldSize, to: newSize)
        }
        .background {
            AddTorrentReviewWindowDiagnosticsReader(
                selectedTab: "combined",
                layoutMode: "split-window"
            )
            .frame(width: 0, height: 0)
        }
        .background {
            AddTorrentReviewAliasFocusWindowCloseObserver {
                isAliasFocused = false
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            renderedDraft = store.currentAddTorrentDraft
            if let draft {
                rebuildFilePresentation(
                    draft: draft,
                    expandsTopLevelFolders: draft.reviewState == .ready
                )
            }
        }
        .onChange(of: draftPresentationToken) { oldToken, newToken in
            guard let newToken, let newDraft = store.currentAddTorrentDraft else { return }
            let isNewDraft = oldToken?.id != newToken.id
            let becameReady = oldToken?.reviewState != .ready && newToken.reviewState == .ready
            if isNewDraft {
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
        }
        .onChange(of: typographyProfile) { _, _ in
            rebuildFilePresentation()
        }
        .task(id: draft?.suggestedSavePath) {
            await refreshAvailableCapacity()
        }
    }

    private var filesColumn: some View {
        filesTabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottom) {
                torrentSummaryContainer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            downloadButton
        }
        .padding(AddTorrentReviewLayout.settingsColumnPadding)
        .frame(width: AddTorrentReviewLayout.settingsColumnWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .opacity(areSettingsControlsEnabled ? 1 : 0.5)
    }

    private var draft: AddTorrentDraft? {
        store.currentAddTorrentDraft ?? renderedDraft
    }

    private var draftPresentationToken: AddTorrentReviewDraftPresentationToken? {
        guard let draft = store.currentAddTorrentDraft else { return nil }

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

        let oldRowCount = filePresentation.rows.count
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

        if ShatlAddTorrentReviewDiagnosticsLog.isEnabled {
            logRowsChange(
                oldCount: oldRowCount,
                newIDs: rows.map(\.id),
                rows: rows
            )
        }
    }

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

    private var invalidReviewContent: some View {
        let errorState = draft?.errorState
        let message = errorState?.message
        return ShatlMessageBlockPrimary(
            title: errorState?.title ?? L10n.string(
                "add_torrent.review.invalid_placeholder",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Не удалось подготовить загрузку."
            ),
            message: (message?.isEmpty ?? true) ? nil : message,
            background: ShatlColor.backgroundSecondary
        )
    }

    @ViewBuilder
    private var filesTabContent: some View {
        switch draft?.reviewState {
        case .loadingMetadata?:
            placeholderBlock(
                localizedTitle: "add_torrent.review.files_after_metadata",
                defaultValue: "Файлы появятся после получения метаданных."
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ShatlColor.backgroundTertiary)
                .clipShape(filesContainerShape)
                .overlay {
                    filesContainerShape
                        .strokeBorder(ShatlColor.outlineSecondary, lineWidth: 1)
                }

        case .invalid?:
            invalidReviewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(ShatlMotion.stickyPinInsertion)

        case .ready?:
            if let draft, !draft.files.isEmpty {
                filesContainer()
            } else {
                placeholderBlock(
                    localizedTitle: "add_torrent.review.no_files",
                    defaultValue: "Нет файлов для загрузки."
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ShatlColor.backgroundTertiary)
                .clipShape(filesContainerShape)
                .overlay {
                    filesContainerShape
                        .strokeBorder(ShatlColor.outlineSecondary, lineWidth: 1)
                }
        }
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
                )
            }
            .scrollIndicators(.hidden)
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
            .onAppear {
                logFilesContainerLifecycleEvent("files.container.appeared", rows: rows)
            }
            .onDisappear {
                logFilesContainerLifecycleEvent("files.container.disappeared", rows: rows)
            }
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

    private var filesContainerShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: AddTorrentReviewLayout.filesContainerCornerRadius,
            style: .continuous
        )
    }

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
            .padding(.horizontal, AddTorrentReviewLayout.summaryContainerHorizontalPadding)
            .padding(.bottom, AddTorrentReviewLayout.summaryContainerBottomPadding)
    }

    @ViewBuilder
    private var torrentSummary: some View {
        let selectedFileCount = filePresentation.selectedFileCount
        let selectedBytes = filePresentation.selectedBytes
        let showsSelectedMetrics = AddTorrentSummaryPresentation.showsSelectionMetrics(
            selectedFileCount: selectedFileCount
        )

        let content = HStack(spacing: AddTorrentReviewLayout.summarySpacing) {
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
                        Int64(selectedFileCount),
                        Int64(filePresentation.totalFileCount)
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
                        selectedBytes,
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
        .animation(
            ShatlMotion.metricResize,
            value: "\(selectedFileCount)-\(selectedBytes)-\(availableCapacityText)-\(store.preferences.metricsMode)"
        )

        if #available(macOS 27.0, *) {
            content
                .glassEffect(
                    .regular.interactive(false),
                    in: torrentSummaryShape
                )
        } else {
            content
                .background(.ultraThinMaterial, in: torrentSummaryShape)
        }
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

    private var torrentSummaryShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: AddTorrentReviewLayout.summaryCornerRadius,
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
            ForEach(AddTorrentNumericTextSegmentation.segments(in: value)) { segment in
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
        filePresentation.rows
    }

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
                .foregroundStyle(ShatlColor.typographyTertiary)
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

    private var downloadButton: some View {
        ShatlButton(
            title: L10n.string(
                "add_torrent.review.confirm",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Скачать"
            ),
            role: .borderedColored,
            isDisabled: !areSettingsControlsEnabled || filePresentation.selectedFileCount == 0
        ) {
            isAliasFocused = false
            store.confirmDraft()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
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

    private func setSuggestedSavePathAsDefault() {
        guard let draft, !isSuggestedSavePathDefault else { return }

        store.setDefaultDownloadLocation(
            URL(fileURLWithPath: draft.suggestedSavePath, isDirectory: true),
            bookmarkData: draft.savePathBookmarkData
        )
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
