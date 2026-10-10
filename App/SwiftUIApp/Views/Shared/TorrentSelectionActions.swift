// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation

/// What the toolbar, the Downloads menu, the keyboard and a card's own menu
/// do with the selected downloads, one or several.
@MainActor
enum TorrentSelectionActions {
    /// The toolbar's trash button and Delete in the list: asks how to remove
    /// what is selected, then removes it.
    static func presentRemovalChoice(in store: AppStore) {
        let localeOverride = store.preferences.localeOverride

        if store.selectedTorrentCount > 1 {
            // Exactly the downloads the question counted, whatever happens
            // to the selection while it is on screen.
            let ids = store.selectedTorrents.map(\.id)
            Task {
                guard let policy = await TorrentRemovalDialogPresenter.presentRemovalChoice(
                    forSeveral: ids.count,
                    localeOverride: localeOverride
                ) else {
                    return
                }
                await store.removeTorrents(ids: ids, policy: policy)
            }
            return
        }

        guard let selectedTorrentID = store.selectedTorrentID else { return }

        if store.pendingAdditionShortDisplayName(for: selectedTorrentID) != nil {
            removeFromList(in: store)
            return
        }

        guard let record = store.selectedTorrent else { return }

        Task {
            guard let policy = await TorrentRemovalDialogPresenter.presentRemovalChoice(
                for: record,
                allowsDeleteWithFiles: record.errorState == nil,
                localeOverride: localeOverride
            ) else {
                return
            }

            await store.removeTorrent(id: record.id, policy: policy)
        }
    }

    /// "Удалить из списка": files stay on disk, so only a download still
    /// being added is asked about first.
    static func removeFromList(in store: AppStore) {
        if store.selectedTorrentCount > 1 {
            let ids = store.selectedTorrents.map(\.id)
            Task {
                await store.removeTorrents(ids: ids, policy: .removeFromListOnly)
            }
            return
        }

        guard let selectedTorrentID = store.selectedTorrentID else { return }
        removeFromList(id: selectedTorrentID, in: store)
    }

    /// The same for one download, selected or not: a card's own menu and the
    /// button of a card with an error.
    static func removeFromList(id: UUID, in store: AppStore) {
        Task {
            if let shortDisplayName = store.pendingAdditionShortDisplayName(for: id) {
                guard await TorrentRemovalDialogPresenter.confirmCancelPendingAddition(
                    named: shortDisplayName,
                    localeOverride: store.preferences.localeOverride
                ) else {
                    return
                }
                if store.isPendingAddition(id: id) {
                    store.cancelPendingAddition(id: id)
                } else {
                    await store.removeTorrent(id: id, policy: .removeFromListOnly)
                }
                return
            }
            await store.removeTorrent(id: id, policy: .removeFromListOnly)
        }
    }

    /// "Удалить вместе с файлами": always asks first.
    static func removeWithFiles(in store: AppStore) {
        if store.selectedTorrentCount > 1 {
            let ids = store.selectedTorrents.map(\.id)
            Task {
                guard await TorrentRemovalDialogPresenter.confirmDeleteWithFiles(
                    forSeveral: ids.count,
                    localeOverride: store.preferences.localeOverride
                ) else {
                    return
                }
                await store.removeTorrents(ids: ids, policy: .removeFromListAndDeleteFiles)
            }
            return
        }

        guard let selectedTorrentID = store.selectedTorrentID else { return }
        removeWithFiles(id: selectedTorrentID, in: store)
    }

    static func removeWithFiles(id: UUID, in store: AppStore) {
        Task {
            guard let record = store.torrentRecord(for: id) else { return }
            guard await TorrentRemovalDialogPresenter.confirmDeleteWithFiles(
                for: record,
                localeOverride: store.preferences.localeOverride
            ) else {
                return
            }

            await store.removeTorrent(id: id, policy: .removeFromListAndDeleteFiles)
        }
    }

    /// One download is opened at a time.
    static func open(in store: AppStore) {
        guard let selectedTorrentID = store.selectedTorrentID else { return }
        open(id: selectedTorrentID, in: store)
    }

    static func open(id: UUID, in store: AppStore) {
        Task {
            guard let location = await store.primaryLocation(for: id) else { return }
            TorrentFileNavigationPresenter.open(location)
        }
    }

    /// Finder selects the files of every selected download that has any; it
    /// opens a window for each folder they are in.
    static func revealInFinder(in store: AppStore) {
        if store.selectedTorrentCount > 1 {
            Task {
                let urls = await store.selectedTorrentRevealURLs()
                guard !urls.isEmpty else {
                    NSSound.beep()
                    return
                }
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
            return
        }

        guard let selectedTorrentID = store.selectedTorrentID else { return }
        revealInFinder(id: selectedTorrentID, in: store)
    }

    static func revealInFinder(id: UUID, in store: AppStore) {
        Task {
            guard let location = await store.primaryLocation(for: id) else { return }
            TorrentFileNavigationPresenter.revealInFinder(location)
        }
    }
}
