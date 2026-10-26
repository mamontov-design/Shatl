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

    private nonisolated static let horizontalContentPadding: CGFloat = 8
    @State private var usesCompactExpandedMetricsLayout = false
    @FocusState private var isListFocused: Bool
    /// Moves the list with a card and after cards that leave; see the type.
    @State private var scrollDriver = TorrentListScrollDriver()
    /// Counts the expansions, each of which the list follows.
    @State private var expansionCount = 0
    /// Room added under the content while it shrinks: cards leave, or the
    /// speed chips go and the room under the last card with them; see
    /// `TorrentListScrollDriver.settleAfterRemoval`.
    @State private var roomWhileContentShrinks: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The coordinates of the scrolled content, in which cards report their
    /// frames to the scroll driver.
    private static let contentSpace = "torrent-list-content"

    private var visibleTorrentIDs: [UUID] {
        store.torrentRowIDs(matching: searchText)
    }

    private var normalizedSearchText: String {
        ShatlSearchQueryDisplay.trimmed(searchText)
    }

    private var showsSearchEmptyState: Bool {
        !normalizedSearchText.isEmpty && visibleTorrentIDs.isEmpty
    }

    private var displayedSearchText: String {
        ShatlSearchQueryDisplay.quoted(searchText)
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
                                            isRepeated: TorrentListSelectionClick.isSecondOfQuickPair,
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
                            // Only the card that expands tells the scroll
                            // driver where it is.
                            .background {
                                if store.expandedTorrentID == torrentID {
                                    ExpandingCardFrameReader(
                                        space: Self.contentSpace,
                                        serial: expansionCount
                                    ) { frame in
                                        // A card that collapses as another
                                        // expands is on its way out and
                                        // still tells where it is: the list
                                        // went after it, to its end.
                                        guard store.expandedTorrentID == torrentID else { return }
                                        scrollDriver.follow(frame)
                                    }
                                    .transition(.identity)
                                }
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
                // Added and taken away in one step, never animated: it only
                // holds the content's height while the content shrinks.
                .padding(.bottom, roomWhileContentShrinks)
                .animation(nil, value: roomWhileContentShrinks)
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
                // At the content's top left corner: the scroll driver reads
                // where the content lies in the scroll view from it.
                .background(alignment: .topLeading) {
                    TorrentListScrollAnchor(driver: scrollDriver)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
                .coordinateSpace(.named(Self.contentSpace))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The keyboard works on the list as the toolbar does on the
            // selected cards: ⌘A selects all, Esc none; Space starts or
            // stops, Delete offers to remove. The search field keeps its own
            // keys. Arrows do not select: every step drew the whole list
            // anew, and a held arrow dropped to a quarter of the frames
            // (measured in October 2026).
            .focusable()
            .focusEffectDisabled()
            .focused($isListFocused)
            .defaultFocus($isListFocused, true)
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
            .onChange(of: visibleTorrentIDs) { oldVisibleTorrentIDs, newVisibleTorrentIDs in
                store.clearHiddenSelection(visibleTorrentIDs: newVisibleTorrentIDs)
                if !Set(oldVisibleTorrentIDs).isSubset(of: newVisibleTorrentIDs) {
                    keepListInPlaceWhileContentShrinks(over: ShatlMotion.cardListMutationDuration)
                }
            }
            // The room under the last card follows the speed chips. SwiftUI
            // animates it, but the scroll view takes the new height at once:
            // a list at its end was pushed to its new end in one frame when
            // the chips went, and lost its last card under them when they
            // came. It glides both ways now, at the chips' pace.
            .onChange(of: bottomContentPadding, initial: true) { oldPadding, padding in
                scrollDriver.bottomMargin = padding
                if padding < oldPadding {
                    keepListInPlaceWhileContentShrinks(over: ShatlMotion.mainContentModeDuration)
                } else if padding > oldPadding, scrollDriver.position?.isAtItsEnd == true {
                    scrollDriver.keepToTheEnd(duration: scrollDuration(ShatlMotion.mainContentModeDuration))
                }
            }
            .onChange(of: store.expandedTorrentID) { _, expandedTorrentID in
                guard expandedTorrentID != nil else { return }
                // A little longer than the card takes to grow.
                scrollDriver.beginFollowing(
                    for: ShatlMotion.cardLayoutDuration * 2,
                    catchingUpOver: scrollDuration(ShatlMotion.cardLayoutDuration)
                )
                expansionCount += 1
            }
            .onChange(of: store.listRevealRequest) { _, request in
                guard let request else { return }
                reveal(request.torrentID, with: scrollProxy)
            }
        }
    }

    /// No gliding with Reduce Motion: the list is simply there.
    private func scrollDuration(_ duration: TimeInterval) -> TimeInterval {
        reduceMotion ? 0 : duration
    }

    /// Called as the content shrinks, before it has lost the height: cards
    /// leave the list, or the room under the last card goes with the speed
    /// chips. A list scrolled down would be pushed to its new end in one
    /// frame; room under the content holds it where it is, the scroll driver
    /// takes it down over `duration`, and the room goes once the list stands
    /// at its new end.
    private func keepListInPlaceWhileContentShrinks(over duration: TimeInterval) {
        guard let position = scrollDriver.position else { return }
        // At its top the list has nowhere to be pushed; with room under it
        // already, it is on its way and takes this change in its stride.
        guard position.isScrolled || roomWhileContentShrinks > 0 else { return }

        // As tall as the content was: enough for the list to stay where it
        // is, whatever has gone.
        let room = max(roomWhileContentShrinks, position.contentHeight - roomWhileContentShrinks)
        roomWhileContentShrinks = room
        scrollDriver.settleAfterRemoval(
            room: room,
            duration: scrollDuration(duration)
        ) {
            roomWhileContentShrinks = 0
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

    /// Whether the click being handled is the second of a double click, by
    /// the system's own count and interval. Nothing is timed or waited for:
    /// a first click acts at once, as before. A third click is not counted,
    /// so a card answers a burst of clicks once.
    @MainActor
    static var isSecondOfQuickPair: Bool {
        // Only mouse events carry a click count.
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseUp || event.type == .leftMouseDown else {
            return false
        }
        return event.clickCount == 2
    }
}

/// Tells where an expanding card is, at first and whenever its frame
/// changes.
private struct ExpandingCardFrameReader: View {
    let space: String
    let serial: Int
    let onFrame: (CGRect) -> Void

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(space))
            Color.clear
                .onChange(of: serial, initial: true) {
                    onFrame(frame)
                }
                .onChange(of: frame) { _, newFrame in
                    onFrame(newFrame)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TorrentRowPresentationObserver<Content: View>: View {
    @ObservedObject var model: TorrentRowPresentationModel
    @ViewBuilder let content: (TorrentRowState) -> Content

    var body: some View {
        content(model.state)
    }
}
