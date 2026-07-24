import AppKit
import SwiftUI

struct TorrentListView: View {
    @EnvironmentObject private var store: AppStore
    let searchText: String

    private var visibleTorrentIDs: [UUID] {
        store.torrentRowIDs(matching: searchText)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(visibleTorrentIDs, id: \.self) { torrentID in
                    if let row = store.rowState(for: torrentID) {
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
                            }
                        )
                        .equatable()
                        .transition(ShatlMotion.cardListItem)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
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
        .onAppear {
            store.clearHiddenSelection(visibleTorrentIDs: visibleTorrentIDs)
        }
        .onChange(of: visibleTorrentIDs) { _, newVisibleTorrentIDs in
            store.clearHiddenSelection(visibleTorrentIDs: newVisibleTorrentIDs)
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
