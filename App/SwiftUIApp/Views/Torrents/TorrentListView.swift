// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

struct TorrentListView: View {
    @EnvironmentObject private var store: AppStore
    let searchText: String
    let bottomContentPadding: CGFloat
    /// Delete in the list: the same choice as the toolbar's trash button.
    let onRemoveSelected: () -> Void

    private static let maximumDisplayedSearchQueryLength = 32
    private nonisolated static let horizontalContentPadding: CGFloat = 8
    @State private var usesCompactExpandedMetricsLayout = false
    @FocusState private var isListFocused: Bool

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
                                    onSelect: {
                                        isListFocused = true
                                        return store.clickTorrent(
                                            id: torrentID,
                                            .ofCurrentEvent,
                                            visibleTorrentIDs: visibleTorrentIDs
                                        )
                                    },
                                    onToggleExpanded: {
                                        withAnimation(ShatlMotion.cardLayout) {
                                            store.toggleExpanded(for: torrentID)
                                        }
                                    },
                                    onOpen: {
                                        TorrentSelectionActions.open(id: torrentID, in: store)
                                    },
                                    // The menu of a card selected with others
                                    // acts on all of them; any other card's
                                    // menu, on that card alone.
                                    onRevealInFinder: {
                                        if store.isSelectedWithOthers(torrentID) {
                                            TorrentSelectionActions.revealInFinder(in: store)
                                        } else {
                                            TorrentSelectionActions.revealInFinder(id: torrentID, in: store)
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
                                        if store.isSelectedWithOthers(torrentID) {
                                            TorrentSelectionActions.removeFromList(in: store)
                                        } else {
                                            TorrentSelectionActions.removeFromList(id: torrentID, in: store)
                                        }
                                    },
                                    onRemoveWithFiles: {
                                        if store.isSelectedWithOthers(torrentID) {
                                            TorrentSelectionActions.removeWithFiles(in: store)
                                        } else {
                                            TorrentSelectionActions.removeWithFiles(id: torrentID, in: store)
                                        }
                                    },
                                    onStartSelected: { store.startSelectedTorrent() },
                                    onStopSelected: { store.stopSelectedTorrent() },
                                    onCollapse: { store.collapseExpanded(for: torrentID) },
                                    onRecheckFolder: { store.recheckUnavailableFolder(id: torrentID) },
                                    onRetry: { store.retryAfterRuntimeError(id: torrentID) },
                                    resolveSavedSpaceStatus: {
                                        await store.savedDownloadSpaceStatus(for: torrentID)
                                    },
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
                            isListFocused = true
                            withAnimation(ShatlMotion.cardLayout) {
                                store.collapseExpandedTorrent()
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The keyboard works on the list as the toolbar does on the
            // selected cards: arrows select, with Shift several; ⌘A selects
            // all, Esc none; Space starts or stops, Delete offers to remove.
            // The search field keeps its own keys.
            .focusable()
            .focusEffectDisabled()
            .focused($isListFocused)
            .defaultFocus($isListFocused, true)
            .onMoveCommand { direction in
                moveSelection(direction, with: scrollProxy)
            }
            // Shift+↑ and Shift+↓ are not move commands for the system.
            .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
                guard press.modifiers.contains(.shift) else { return .ignored }
                moveSelection(
                    press.key == .upArrow ? .previous : .next,
                    extending: true,
                    with: scrollProxy
                )
                return .handled
            }
            // With nothing selected Esc stays with the system: it leaves
            // full screen.
            .onKeyPress(.escape) {
                guard store.selectedTorrentCount > 0 else { return .ignored }
                store.clearTorrentSelection()
                return .handled
            }
            .onCommand(#selector(NSResponder.selectAll(_:))) {
                store.selectAllTorrents(visibleTorrentIDs: visibleTorrentIDs)
            }
            .onKeyPress(.space) {
                guard store.isToolbarStartStopEnabled else { return .ignored }
                store.toggleSelectedTorrentsRunningState()
                return .handled
            }
            .onDeleteCommand {
                guard store.isToolbarRemoveEnabled else { return }
                onRemoveSelected()
            }
            // ⌘V adds a copied magnet link or `.torrent` file the way a drop
            // into the window does; anything else gets the system's "no".
            .onPasteCommand(of: MainWindowDropLayout.draggedTypes) { providers in
                Task {
                    let content = await DraggedContent.pasted(providers)
                    if store.acceptsDraggedDownloads, case let .accept(download) = content.offer {
                        store.addDraggedDownload(download)
                    } else {
                        NSSound.beep()
                    }
                }
            }
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
                        isListFocused = true
                        withAnimation(ShatlMotion.cardLayout) {
                            store.collapseExpandedTorrent()
                        }
                    }
            }
            .overlay {
                if showsSearchEmptyState {
                    // The same block as every message in the middle of a
                    // window.
                    ShatlMessageBlockPrimary(
                        systemImage: "exclamationmark.magnifyingglass",
                        title: L10n.format(
                            "search.empty.title",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: "Нет результатов для «%@».",
                            displayedSearchText
                        ),
                        message: L10n.string(
                            "search.empty.description",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: "Попробуйте другое название или псевдоним."
                        )
                    )
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

    /// Selects the card above or below and scrolls just enough to show it.
    private func moveSelection(_ direction: MoveCommandDirection, with scrollProxy: ScrollViewProxy) {
        let step: TorrentListSelectionStep
        switch direction {
        case .up:
            step = .previous
        case .down:
            step = .next
        default:
            return
        }

        moveSelection(step, extending: false, with: scrollProxy)
    }

    private func moveSelection(
        _ step: TorrentListSelectionStep,
        extending: Bool,
        with scrollProxy: ScrollViewProxy
    ) {
        guard let target = store.moveTorrentSelection(
            step,
            extending: extending,
            visibleTorrentIDs: visibleTorrentIDs
        ) else {
            return
        }
        withAnimation(ShatlMotion.cardLayout) {
            scrollProxy.scrollTo(target)
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

private extension TorrentListSelectionClick {
    /// How the click being handled was made: with ⌘, with Shift or plain.
    @MainActor
    static var ofCurrentEvent: TorrentListSelectionClick {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        if modifiers.contains(.command) {
            return .toggle
        }
        return modifiers.contains(.shift) ? .range : .plain
    }
}

private struct TorrentRowPresentationObserver<Content: View>: View {
    @ObservedObject var model: TorrentRowPresentationModel
    @ViewBuilder let content: (TorrentRowState) -> Content

    var body: some View {
        content(model.state)
    }
}
