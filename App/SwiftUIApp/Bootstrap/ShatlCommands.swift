// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct ShatlCommands: Commands {
    @ObservedObject var store: AppStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }
        CommandGroup(replacing: .sidebar) {
            Button("menu.view.enter_full_screen") { }
                .disabled(true)
        }

        #if DEBUG
        CommandMenu("settings.tab.debug") {
            Button("menu.debug.show_onboarding") {
                store.presentDebugOnboarding()
            }
            Button("menu.debug.preview_restore_status") {
                store.previewRestoreStatusForDebug()
            }
            Button("menu.debug.preview_unsupported_session") {
                store.toggleUnsupportedSessionPreviewForDebug()
            }
            .disabled(
                store.debugSessionLoadIssuePreview == nil
                    && !store.canPreviewUnsupportedSessionForDebug
            )
            Toggle("menu.debug.simulate_low_space", isOn: Binding(
                get: { store.debugSimulatesLowDiskSpace },
                set: { _ in store.toggleLowDiskSpaceForDebug() }
            ))
            Menu("menu.debug.runtime_error") {
                debugRuntimeErrorButton("menu.debug.runtime_error.disk_full", cause: .diskFull)
                debugRuntimeErrorButton("menu.debug.runtime_error.no_write_access", cause: .noWriteAccess)
                debugRuntimeErrorButton("menu.debug.runtime_error.disk_error", cause: .diskError)
                debugRuntimeErrorButton("menu.debug.runtime_error.files_missing", cause: .filesMissing)
                debugRuntimeErrorButton("menu.debug.runtime_error.other", cause: nil)
            }
            .disabled(!store.canSimulateRuntimeErrorForDebug(id: selectedTorrentID))
        }
        #endif

        CommandMenu("menu.torrent") {
            Button {
                store.presentAddTorrentEntry()
            } label: {
                Label("menu.torrent.add", systemImage: "plus")
            }
            .keyboardShortcut("n")
            .disabled(!store.canAddTorrent)

            Divider()

            Button {
                openSelectedLocation()
            } label: {
                Label("torrent.action.open", systemImage: "arrow.up.forward")
            }
            .keyboardShortcut("o")
            .disabled(!isOpenEnabled)

            Button {
                revealSelectedLocation()
            } label: {
                Label("torrent.action.reveal_in_finder", systemImage: "finder")
            }
            // As in Music and Photos.
            .keyboardShortcut("r", modifiers: [.command, .shift])
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
            // ⌘. stops, as in Safari and Xcode; the same keys start again.
            .keyboardShortcut(".")
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
            // Asks first. ⌘⌫ alone stays with text fields, where it deletes
            // to the start of the line; in the list, Delete asks the same as
            // the toolbar's trash button.
            .keyboardShortcut(.delete, modifiers: [.command, .option])
            .disabled(!isRemoveWithFilesEnabled)
        }
    }

    private var selectedTorrentID: UUID? {
        store.selectedTorrentID
    }

    #if DEBUG
    /// Stops the selected download as the engine would with `cause`.
    private func debugRuntimeErrorButton(_ titleKey: LocalizedStringKey, cause: TorrentErrorState.Cause?) -> some View {
        Button(titleKey) {
            guard let selectedTorrentID else { return }
            store.simulateRuntimeErrorForDebug(id: selectedTorrentID, cause: cause)
        }
    }
    #endif

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
