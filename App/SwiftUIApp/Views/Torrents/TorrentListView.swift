// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

struct TorrentListView: View {
    @EnvironmentObject private var store: AppStore
    let searchText: String
    let bottomContentPadding: CGFloat

    private static let maximumDisplayedSearchQueryLength = 32
    private static let horizontalContentPadding: CGFloat = 8
    @State private var usesCompactExpandedMetricsLayout = false

    private var visibleTorrentIDs: [UUID] {
        store.torrentRowIDs(matching: searchText)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsSearchEmptyState: Bool {
        !normalizedSearchText.isEmpty && visibleTorrentIDs.isEmpty
    }

    private var displayedSearchText: String {
        guard normalizedSearchText.count > Self.maximumDisplayedSearchQueryLength else {
            return normalizedSearchText
        }

        let prefixLength = Self.maximumDisplayedSearchQueryLength - 1
        let prefix = normalizedSearchText
            .prefix(prefixLength)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "…"
    }

    var body: some View {
        // A plain stack, not a lazy one: every card is built once and scrolling
        // moves finished layers. A lazy stack builds and lays out cards as they
        // scroll in, and on a short list the start of every scroll jerked.
        // The list scrolls to a download when asked, for "Show in List" in
        // the add window.
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(visibleTorrentIDs, id: \.self) { torrentID in
                        if let rowModel = store.torrentRowPresentationModel(for: torrentID) {
                            TorrentRowPresentationObserver(model: rowModel) { row in
                                TorrentCardView(
                                    row: row,
                                    resolvePrimaryLocation: {
                                        await store.primaryLocation(for: torrentID)
                                    },
                                    onSelect: { store.toggleTorrentSelection(id: torrentID) },
                                    onToggleExpanded: {
                                        withAnimation(ShatlMotion.cardLayout) {
                                            store.toggleExpanded(for: torrentID)
                                        }
                                    },
                                    onOpen: {
                                        Task {
                                            guard let location = await store.primaryLocation(for: torrentID) else { return }
                                            await MainActor.run {
                                                TorrentFileNavigationPresenter.open(location)
                                            }
                                        }
                                    },
                                    onRevealInFinder: {
                                        Task {
                                            guard let location = await store.primaryLocation(for: torrentID) else { return }
                                            await MainActor.run {
                                                TorrentFileNavigationPresenter.revealInFinder(location)
                                            }
                                        }
                                    },
                                    onToggleRunningState: {
                                        store.toggleTorrentRunningState(id: torrentID)
                                    },
                                    onRedownload: { store.redownloadTorrent(id: torrentID) },
                                    onChooseAnotherFolder: {
                                        presentRedownloadFolderPicker(for: torrentID)
                                    },
                                    onRemove: {
                                        Task {
                                            if let shortDisplayName = store.pendingAdditionShortDisplayName(for: torrentID) {
                                                guard await TorrentRemovalDialogPresenter.confirmCancelPendingAddition(
                                                    named: shortDisplayName,
                                                    localeOverride: store.preferences.localeOverride
                                                ) else {
                                                    return
                                                }
                                                if store.isPendingAddition(id: torrentID) {
                                                    store.cancelPendingAddition(id: torrentID)
                                                } else {
                                                    await store.removeTorrent(
                                                        id: torrentID,
                                                        policy: .removeFromListOnly
                                                    )
                                                }
                                                return
                                            }
                                            await store.removeTorrent(id: torrentID, policy: .removeFromListOnly)
                                        }
                                    },
                                    onRemoveWithFiles: {
                                        Task {
                                            guard let record = store.torrentRecord(for: torrentID) else {
                                                return
                                            }
                                            guard await TorrentRemovalDialogPresenter.confirmDeleteWithFiles(
                                                for: record,
                                                localeOverride: store.preferences.localeOverride
                                            ) else {
                                                return
                                            }

                                            await store.removeTorrent(id: torrentID, policy: .removeFromListAndDeleteFiles)
                                        }
                                    },
                                    onCollapse: { store.collapseExpanded(for: torrentID) },
                                    onRecheckFolder: { store.recheckUnavailableFolder(id: torrentID) },
                                    onRetry: { store.retryAfterRuntimeError(id: torrentID) },
                                    usesCompactExpandedMetricsLayout: usesCompactExpandedMetricsLayout
                                )
                                .equatable()
                            }
                            .transition(ShatlMotion.cardListItem)
                        }
                    }
                }
                // Full width even with no cards: an empty stack shrank to its
                // padding and sat in the middle, and the last card, leaving from
                // it, was cut off there and slid to the right.
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, 8)
                .padding(.horizontal, Self.horizontalContentPadding)
                .padding(.bottom, bottomContentPadding)
                .animation(ShatlMotion.mainContentMode, value: bottomContentPadding)
                .animation(ShatlMotion.cardListMutation, value: visibleTorrentIDs)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.clearTorrentSelection()
                            withAnimation(ShatlMotion.cardLayout) {
                                store.collapseExpandedTorrent()
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: Bool.self) { proxy in
                let cardWidth = max(0, proxy.size.width - Self.horizontalContentPadding * 2)
                return cardWidth < TorrentCardLayout.compactExpandedMetricsWidth
            } action: { newValue in
                usesCompactExpandedMetricsLayout = newValue
            }
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.clearTorrentSelection()
                        withAnimation(ShatlMotion.cardLayout) {
                            store.collapseExpandedTorrent()
                        }
                    }
            }
            .overlay {
                if showsSearchEmptyState {
                    TorrentSearchEmptyStateView(
                        query: displayedSearchText,
                        localeOverride: store.preferences.localeOverride
                    )
                        .padding(.horizontal, 32)
                        .padding(.bottom, bottomContentPadding)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                store.clearHiddenSelection(visibleTorrentIDs: visibleTorrentIDs)
            }
            .onChange(of: visibleTorrentIDs) { _, newVisibleTorrentIDs in
                store.clearHiddenSelection(visibleTorrentIDs: newVisibleTorrentIDs)
            }
            .onChange(of: store.listRevealRequest) { _, request in
                guard let request else { return }
                reveal(request.torrentID, with: scrollProxy)
            }
        }
    }

    /// Waits a moment, so a search cleared for this download has put its card
    /// back into the list, then scrolls it to the middle.
    private func reveal(_ torrentID: UUID, with scrollProxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(ShatlMotion.cardLayout) {
                scrollProxy.scrollTo(torrentID, anchor: .center)
            }
        }
    }

    private func presentRedownloadFolderPicker(for torrentID: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.string("common.choose", localeOverride: store.preferences.localeOverride)

        if FileManager.default.fileExists(atPath: store.preferences.defaultDownloadPath) {
            panel.directoryURL = URL(fileURLWithPath: store.preferences.defaultDownloadPath, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        store.redownloadTorrent(id: torrentID, toSaveLocation: url, bookmarkData: bookmarkData)
    }
}

private struct TorrentRowPresentationObserver<Content: View>: View {
    @ObservedObject var model: TorrentRowPresentationModel
    @ViewBuilder let content: (TorrentRowState) -> Content

    var body: some View {
        content(model.state)
    }
}

private struct TorrentSearchEmptyStateView: View {
    let query: String
    let localeOverride: AppLocaleOverride

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 36, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ShatlColor.typographyTertiary)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(
                    L10n.format(
                        "search.empty.title",
                        localeOverride: localeOverride,
                        defaultValue: "Нет результатов для «%@»",
                        query
                    )
                )
                    .shatlTypography(ShatlTypography.headlineSemibold)
                    .foregroundStyle(ShatlColor.typographyPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    L10n.string(
                        "search.empty.description",
                        localeOverride: localeOverride,
                        defaultValue: "Попробуйте другое название или псевдоним."
                    )
                )
                    .shatlTypography(ShatlTypography.captionRegular)
                    .foregroundStyle(ShatlColor.typographyTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 300)
        }
        .accessibilityElement(children: .combine)
    }
}
