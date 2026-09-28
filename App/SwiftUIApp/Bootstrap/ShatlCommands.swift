// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct ShatlCommands: Commands {
    @ObservedObject var store: AppStore

    #if DEBUG
    private func demoPresetTitle(_ preset: ShatlDemoPreset) -> String {
        let localeOverride = store.preferences.localeOverride
        guard preset.inactiveCount > 0 else {
            return L10n.format(
                "menu.debug.demo_list.active",
                localeOverride: localeOverride,
                defaultValue: "%ld активных",
                preset.activeCount
            )
        }
        return L10n.format(
            "menu.debug.demo_list.mixed",
            localeOverride: localeOverride,
            defaultValue: "%1$ld активных + %2$ld неактивных",
            preset.activeCount,
            preset.inactiveCount
        )
    }
    #endif

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }
        CommandGroup(replacing: .sidebar) {
            Button("menu.view.enter_full_screen") { }
                .disabled(true)
        }

        #if DEBUG
        CommandMenu("settings.tab.debug") {
            Button("menu.debug.show_onboarding") {
                NotificationCenter.default.post(
                    name: .shatlPresentDebugOnboarding,
                    object: nil
                )
            }

            Menu("menu.debug.demo_list") {
                ForEach(ShatlDemoPreset.allCases) { preset in
                    Button(demoPresetTitle(preset)) {
                        ShatlDemoList.relaunch(into: preset)
                    }
                    .disabled(preset == ShatlDemoList.activePreset)
                }

                Divider()

                Button("menu.debug.demo_list.exit") {
                    ShatlDemoList.relaunch(into: nil)
                }
                .disabled(ShatlDemoList.activePreset == nil)
            }
        }
        #endif

        CommandMenu("menu.torrent") {
            Button {
                store.presentAddTorrentEntry()
            } label: {
                Label("menu.torrent.add", systemImage: "plus")
            }
            .disabled(!store.canAddTorrent)

            Divider()

            Button {
                openSelectedLocation()
            } label: {
                Label("torrent.action.open", systemImage: "arrow.up.forward")
            }
            .disabled(!isOpenEnabled)

            Button {
                revealSelectedLocation()
            } label: {
                Label("torrent.action.reveal_in_finder", systemImage: "finder")
            }
            .disabled(!isRevealEnabled)

            Divider()

            Button {
                guard let selectedTorrentID else { return }
                store.toggleTorrentRunningState(id: selectedTorrentID)
            } label: {
                Label {
                    Text(LocalizedStringKey(selectedTorrent?.status.isSleeping == true ? "torrent.action.start" : "torrent.action.stop"))
                } icon: {
                    Image(systemName: selectedTorrent?.status.isSleeping == true ? "play" : "stop")
                }
            }
            .disabled(!isToggleRunningStateEnabled)

            Divider()

            Button(role: .destructive) {
                guard let selectedTorrentID else { return }
                Task {
                    if let shortDisplayName = store.pendingAdditionShortDisplayName(for: selectedTorrentID) {
                        guard await TorrentRemovalDialogPresenter.confirmCancelPendingAddition(
                            named: shortDisplayName,
                            localeOverride: store.preferences.localeOverride
                        ) else {
                            return
                        }
                        if store.isPendingAddition(id: selectedTorrentID) {
                            store.cancelPendingAddition(id: selectedTorrentID)
                        } else {
                            await store.removeTorrent(
                                id: selectedTorrentID,
                                policy: .removeFromListOnly
                            )
                        }
                        return
                    }
                    await store.removeTorrent(id: selectedTorrentID, policy: .removeFromListOnly)
                }
            } label: {
                Label("torrent.action.remove_from_list", systemImage: "rectangle.stack.badge.minus")
            }
            .disabled(!isRemoveFromListEnabled)

            Button(role: .destructive) {
                guard let selectedTorrent else { return }
                Task {
                    guard await TorrentRemovalDialogPresenter.confirmDeleteWithFiles(
                        for: selectedTorrent,
                        localeOverride: store.preferences.localeOverride
                    ) else {
                        return
                    }

                    await store.removeTorrent(
                        id: selectedTorrent.id,
                        policy: .removeFromListAndDeleteFiles
                    )
                }
            } label: {
                Label("torrent.action.remove_with_files", systemImage: "externaldrive.badge.xmark")
            }
            .disabled(!isRemoveWithFilesEnabled)
        }
    }

    private var selectedTorrentID: UUID? {
        store.selectedTorrentID
    }

    private var selectedTorrent: TorrentRecord? {
        store.selectedTorrent
    }

    private var isToggleRunningStateEnabled: Bool {
        guard let selectedTorrentID else { return false }
        return store.canToggleRunningState(for: selectedTorrentID)
    }

    private var isRemoveFromListEnabled: Bool {
        guard let selectedTorrentID else { return false }
        return store.canRemoveFromList(for: selectedTorrentID)
    }

    private var isRemoveWithFilesEnabled: Bool {
        guard let selectedTorrentID else { return false }
        return store.canRemoveWithFiles(for: selectedTorrentID)
    }

    private var isOpenEnabled: Bool {
        guard selectedTorrent?.errorState == nil else { return false }
        return store.selectedTorrentNavigationAvailability.canOpen
    }

    private var isRevealEnabled: Bool {
        guard selectedTorrent?.errorState == nil else { return false }
        return store.selectedTorrentNavigationAvailability.canReveal
    }

    private func openSelectedLocation() {
        guard let selectedTorrentID else { return }

        Task {
            guard let location = await store.primaryLocation(for: selectedTorrentID) else { return }
            await MainActor.run {
                TorrentFileNavigationPresenter.open(location)
            }
        }
    }

    private func revealSelectedLocation() {
        guard let selectedTorrentID else { return }

        Task {
            guard let location = await store.primaryLocation(for: selectedTorrentID) else { return }
            await MainActor.run {
                TorrentFileNavigationPresenter.revealInFinder(location)
            }
        }
    }
}

extension Notification.Name {
    static let shatlPresentDebugOnboarding = Notification.Name("ShatlPresentDebugOnboarding")
}
