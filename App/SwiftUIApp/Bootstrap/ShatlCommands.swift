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
            Button("menu.debug.cycle_drop_screen") {
                store.cycleDropScreenPreviewForDebug()
            }
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
                TorrentSelectionActions.open(in: store)
            } label: {
                Label("torrent.action.open", systemImage: "arrow.up.forward")
            }
            .keyboardShortcut("o")
            .disabled(!isOpenEnabled)

            Button {
                TorrentSelectionActions.revealInFinder(in: store)
            } label: {
                Label("torrent.action.reveal_in_finder", systemImage: "finder")
            }
            // As in Music and Photos.
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!isRevealEnabled)

            Divider()

            if hasSeveralSelected {
                // Several downloads may both run and wait, so the menu
                // offers both. ⌘. goes to what the toolbar's button would do.
                Button {
                    store.startSelectedTorrent()
                } label: {
                    Label("torrent.action.start", systemImage: "play")
                }
                .keyboardShortcut(store.toolbarRunAction == .start ? KeyboardShortcut(".") : nil)
                .disabled(!store.canStartSelectedTorrents)

                Button {
                    store.stopSelectedTorrent()
                } label: {
                    Label("torrent.action.stop", systemImage: "stop")
                }
                .keyboardShortcut(store.toolbarRunAction == .stop ? KeyboardShortcut(".") : nil)
                .disabled(!store.canStopSelectedTorrents)
            } else {
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
            }

            Divider()

            Button(role: .destructive) {
                TorrentSelectionActions.removeFromList(in: store)
            } label: {
                Label("torrent.action.remove_from_list", systemImage: "rectangle.stack.badge.minus")
            }
            .disabled(!isRemoveFromListEnabled)

            Button(role: .destructive) {
                TorrentSelectionActions.removeWithFiles(in: store)
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

    /// With several downloads selected the commands act on all of them.
    private var hasSeveralSelected: Bool {
        store.selectedTorrentCount > 1
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
        if hasSeveralSelected {
            return store.isToolbarRemoveEnabled
        }
        guard let selectedTorrentID else { return false }
        return store.canRemoveFromList(for: selectedTorrentID)
    }

    private var isRemoveWithFilesEnabled: Bool {
        if hasSeveralSelected {
            return store.isToolbarRemoveEnabled
        }
        guard let selectedTorrentID else { return false }
        return store.canRemoveWithFiles(for: selectedTorrentID)
    }

    /// One download is opened at a time.
    private var isOpenEnabled: Bool {
        guard selectedTorrent?.errorState == nil else { return false }
        return store.selectedTorrentNavigationAvailability.canOpen
    }

    /// Several are shown without asking each for its files first: the ones
    /// with nothing on disk yet are left out as Finder opens.
    private var isRevealEnabled: Bool {
        if hasSeveralSelected {
            return true
        }
        guard selectedTorrent?.errorState == nil else { return false }
        return store.selectedTorrentNavigationAvailability.canReveal
    }
}
