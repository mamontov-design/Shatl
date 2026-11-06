// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Combine
import Foundation

/// What the add window asks of the store: the list it adds to and the
/// window it is shown in. The store answers; the model never reaches past it.
@MainActor
protocol AddTorrentReviewHost: AnyObject {
    var addTorrentReviewLocaleOverride: AppLocaleOverride { get }
    /// Asked when a magnet link's file list does not arrive in time.
    func addTorrentReviewNetworkIsOffline() async -> Bool
    /// The download is in the list already, or being added.
    func addTorrentReviewRepeatsDownload(_ draft: AddTorrentDraft) -> Bool
    func addTorrentReviewDuplicateError(
        named name: String?,
        infoHash: String?
    ) -> (errorState: TorrentErrorState, duplicateID: UUID?)
    /// A confirmed draft hands its prepared metadata to its addition.
    func addTorrentReviewHasHandedOver(draftID: UUID) -> Bool
    func addTorrentReviewPresentWindow()
}

/// The add window's downloads: those waiting for a decision, one of them on
/// screen, each with its draft, its preparation and its edits.
///
/// Kept apart from `AppStore` so that what changes while the window is in
/// use — a file read, a file ticked, a letter of the alias — reaches the add
/// window alone. Every change the store publishes draws the main window's
/// list anew (see `AGENTS.md`, arrow keys), and the drafts are the part of
/// the add flow that changes often. Opening and closing the window, which is
/// rare, stays with the store.
///
/// Several `.torrent` files opened at once wait here in one window, in the
/// order they came, instead of a window each. "Скачать" hands the download
/// on screen to the list and shows the next one; the arrows move between
/// them freely. Published only for what the window shows: the download on
/// screen, how many wait, which one this is. A file read for a download off
/// screen changes none of it, so two hundred files opened at once do not
/// draw the window two hundred times.
@MainActor
final class AddTorrentReviewModel: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: UUID
        var draft: AddTorrentDraft
        /// The download in the list this one repeats, so the window can show
        /// it there rather than leave it to be found.
        var duplicateID: UUID?
    }

    weak var host: (any AddTorrentReviewHost)?

    /// The downloads waiting for a decision, in the order they came.
    private(set) var items: [Item] = []
    private(set) var currentIndex = 0
    /// Two downloads or more have been in the window since it opened. It
    /// keeps its title, arrows and count until it closes, down to the last
    /// download, so its toolbar never jumps as downloads leave.
    private(set) var isBatch = false

    private let engine: any TorrentEngine
    private var preparationTasks: [UUID: Task<Void, Never>] = [:]
    /// `.torrent` files are read one after another: each read holds the
    /// engine for a moment, and the list's second-by-second refresh waits for
    /// the engine. A magnet link waits for peers on its own.
    private var lastFilePreparation: Task<Void, Never>?

    init(engine: any TorrentEngine) {
        self.engine = engine
    }

    deinit {
        for task in preparationTasks.values {
            task.cancel()
        }
    }

    // MARK: - What the window shows

    private var currentItem: Item? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    /// The draft on screen. Set, it replaces that draft, or starts the
    /// window with it; set to `nil`, it empties the window.
    var draft: AddTorrentDraft? {
        get { currentItem?.draft }
        set {
            guard let newValue else {
                removeAll()
                return
            }
            if let currentItem {
                setDraft(newValue, forItem: currentItem.id)
            } else {
                publish { items = [Item(id: UUID(), draft: newValue)] }
            }
        }
    }

    var duplicateID: UUID? {
        currentItem?.duplicateID
    }

    /// Which download is on screen, counted from 1.
    var position: Int {
        currentIndex + 1
    }

    /// How many downloads wait for a decision, the one on screen included.
    var count: Int {
        items.count
    }

    var hasPrevious: Bool {
        currentIndex > 0
    }

    var hasNext: Bool {
        currentIndex + 1 < items.count
    }

    func showPrevious() {
        guard hasPrevious else { return }
        publish { currentIndex -= 1 }
    }

    func showNext() {
        guard hasNext else { return }
        publish { currentIndex += 1 }
    }

    // MARK: - Downloads coming in

    /// Starts the window anew with one download: a waiting draft at once, the
    /// download read behind it.
    func prepare(
        _ source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool,
        alias: String,
        savePathBookmarkData: Data?
    ) {
        removeAll()
        let itemID = UUID()
        publish {
            items = [Item(
                id: itemID,
                draft: makeLoadingDraft(
                    for: source,
                    suggestedSavePath: suggestedSavePath,
                    stopAfterDownload: stopAfterDownload,
                    alias: alias,
                    savePathBookmarkData: savePathBookmarkData
                )
            )]
            currentIndex = 0
        }
        host?.addTorrentReviewPresentWindow()
        startPreparation(
            of: itemID,
            source: source,
            suggestedSavePath: suggestedSavePath,
            stopAfterDownload: stopAfterDownload,
            alias: alias,
            savePathBookmarkData: savePathBookmarkData
        )
    }

    /// Puts a download at the end of the window's queue: one opened while the
    /// window is open, or the second and later of several opened at once.
    /// The same file or link twice takes one place, and the window shows it.
    func enqueue(
        _ source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool,
        alias: String,
        savePathBookmarkData: Data?
    ) {
        if let index = items.firstIndex(where: { Self.isSameSource($0.draft.source, as: source) }) {
            if index != currentIndex {
                publish { currentIndex = index }
            }
            return
        }

        let itemID = UUID()
        publish {
            items.append(Item(
                id: itemID,
                draft: makeLoadingDraft(
                    for: source,
                    suggestedSavePath: suggestedSavePath,
                    stopAfterDownload: stopAfterDownload,
                    alias: alias,
                    savePathBookmarkData: savePathBookmarkData
                )
            ))
            if items.count > 1 {
                isBatch = true
            }
        }
        startPreparation(
            of: itemID,
            source: source,
            suggestedSavePath: suggestedSavePath,
            stopAfterDownload: stopAfterDownload,
            alias: alias,
            savePathBookmarkData: savePathBookmarkData
        )
    }

    /// Stops reading every download; the drafts on screen stay.
    func cancelPreparation() {
        for task in preparationTasks.values {
            task.cancel()
        }
        preparationTasks.removeAll()
        lastFilePreparation = nil
    }

    /// The window is closed: nothing is read and nothing is shown.
    func dismiss() {
        removeAll()
    }

    // MARK: - Downloads leaving

    /// The download on screen went to the list ("Скачать", "Сохранить в
    /// список"): it leaves the window, which shows the next one, or the one
    /// before when it was the last. `true` when none are left.
    func finishCurrent() -> Bool {
        removeCurrent()
    }

    /// "Не скачивать": the download on screen leaves the window unadded.
    /// `true` when none are left.
    func skipCurrent() -> Bool {
        removeCurrent()
    }

    private func removeCurrent() -> Bool {
        guard let item = currentItem else { return true }
        preparationTasks.removeValue(forKey: item.id)?.cancel()
        publish {
            items.remove(at: currentIndex)
            if currentIndex >= items.count {
                currentIndex = max(items.count - 1, 0)
            }
        }
        releasePreparedDraftUnlessAdding(item.draft.id)
        return items.isEmpty
    }

    private func removeAll() {
        cancelPreparation()
        let draftIDs = items.map(\.draft.id)
        if !items.isEmpty || isBatch || currentIndex != 0 {
            publish {
                items.removeAll()
                currentIndex = 0
                isBatch = false
            }
        }
        for draftID in draftIDs {
            releasePreparedDraftUnlessAdding(draftID)
        }
    }

    // MARK: - Preparation

    private func startPreparation(
        of itemID: UUID,
        source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool,
        alias: String,
        savePathBookmarkData: Data?
    ) {
        let readsAFile = source.kind != .magnet
        let previousFileRead = readsAFile ? lastFilePreparation : nil

        let task = Task { [weak self] in
            await previousFileRead?.value
            guard let self, !Task.isCancelled else { return }
            defer { self.finishPreparation(of: itemID) }

            do {
                var preparedDraft = try await self.engine.prepareDraft(
                    from: source,
                    suggestedSavePath: suggestedSavePath,
                    stopAfterDownload: stopAfterDownload
                )

                guard !Task.isCancelled, self.contains(itemID) else {
                    // The window closed, or the download left it, while it was read.
                    self.releasePreparedDraft(preparedDraft.id)
                    return
                }

                preparedDraft.alias = alias
                preparedDraft.savePathBookmarkData = savePathBookmarkData
                if self.host?.addTorrentReviewRepeatsDownload(preparedDraft) == true {
                    self.releasePreparedDraft(preparedDraft.id)
                    self.presentDuplicate(of: preparedDraft, in: itemID)
                } else {
                    self.setDraft(preparedDraft, forItem: itemID)
                }
            } catch {
                guard !Task.isCancelled, self.contains(itemID) else { return }
                var errorState = ShatlErrorCatalog.reviewError(
                    for: error,
                    source: source,
                    localeOverride: self.localeOverride
                )
                let engineError = TorrentEngineError.normalized(from: error)
                if engineError.kind == .duplicateTorrent,
                   let duplicate = self.host?.addTorrentReviewDuplicateError(
                       named: engineError.torrentName,
                       infoHash: engineError.infoHash
                   ) {
                    self.presentInvalid(
                        for: source,
                        errorState: duplicate.errorState,
                        suggestedSavePath: suggestedSavePath,
                        stopAfterDownload: stopAfterDownload,
                        alias: alias,
                        savePathBookmarkData: savePathBookmarkData,
                        duplicateOfTorrentID: duplicate.duplicateID,
                        in: itemID
                    )
                    return
                }
                // The wait ran out with no network at all: say so directly.
                if errorState.kind == .metadataTimeout,
                   await self.host?.addTorrentReviewNetworkIsOffline() == true {
                    guard !Task.isCancelled, self.contains(itemID) else { return }
                    errorState = ShatlErrorCatalog.offlineMetadataError(
                        localeOverride: self.localeOverride
                    )
                }
                self.presentInvalid(
                    for: source,
                    errorState: errorState,
                    suggestedSavePath: suggestedSavePath,
                    stopAfterDownload: stopAfterDownload,
                    alias: alias,
                    savePathBookmarkData: savePathBookmarkData,
                    duplicateOfTorrentID: nil,
                    in: itemID
                )
            }
        }
        preparationTasks[itemID] = task
        if readsAFile {
            lastFilePreparation = task
        }
    }

    private func finishPreparation(of itemID: UUID) {
        preparationTasks[itemID] = nil
    }

    private func contains(_ itemID: UUID) -> Bool {
        items.contains { $0.id == itemID }
    }

    /// The same `.torrent` file or the same link, whatever way it came.
    private static func isSameSource(_ lhs: AddTorrentSource, as rhs: AddTorrentSource) -> Bool {
        let lhsIsLink = lhs.kind == .magnet
        let rhsIsLink = rhs.kind == .magnet
        guard lhsIsLink == rhsIsLink else { return false }
        if lhsIsLink {
            return lhs.rawValue == rhs.rawValue
        }
        return NSString(string: lhs.rawValue).standardizingPath
            == NSString(string: rhs.rawValue).standardizingPath
    }

    // MARK: - Messages

    /// A message in place of the download on screen, or of the only one when
    /// the window opens with it.
    func presentInvalid(
        for source: AddTorrentSource,
        errorState: TorrentErrorState,
        suggestedSavePath: String,
        stopAfterDownload: Bool,
        alias: String,
        savePathBookmarkData: Data? = nil,
        duplicateOfTorrentID: UUID? = nil
    ) {
        presentInvalid(
            for: source,
            errorState: errorState,
            suggestedSavePath: suggestedSavePath,
            stopAfterDownload: stopAfterDownload,
            alias: alias,
            savePathBookmarkData: savePathBookmarkData,
            duplicateOfTorrentID: duplicateOfTorrentID,
            in: nil
        )
    }

    func presentDuplicate(of draft: AddTorrentDraft) {
        presentDuplicate(of: draft, in: nil)
    }

    private func presentDuplicate(of draft: AddTorrentDraft, in itemID: UUID?) {
        guard let duplicate = host?.addTorrentReviewDuplicateError(
            named: draft.originalName,
            infoHash: draft.infoHash
        ) else { return }
        presentInvalid(
            for: draft.source,
            errorState: duplicate.errorState,
            suggestedSavePath: draft.suggestedSavePath,
            stopAfterDownload: draft.stopAfterDownload,
            alias: draft.alias,
            savePathBookmarkData: draft.savePathBookmarkData,
            duplicateOfTorrentID: duplicate.duplicateID,
            in: itemID
        )
    }

    /// `itemID` names the download the message is about; `nil` is the one on
    /// screen, or a new window when there is none.
    private func presentInvalid(
        for source: AddTorrentSource,
        errorState: TorrentErrorState,
        suggestedSavePath: String,
        stopAfterDownload: Bool,
        alias: String,
        savePathBookmarkData: Data?,
        duplicateOfTorrentID: UUID?,
        in itemID: UUID?
    ) {
        let invalidDraft = AddTorrentDraft(
            source: source,
            originalName: errorState.title,
            infoHash: nil,
            suggestedSavePath: suggestedSavePath,
            savePathBookmarkData: savePathBookmarkData,
            alias: alias,
            stopAfterDownload: stopAfterDownload,
            files: [],
            reviewState: .invalid(message: errorState.message),
            errorState: errorState
        )

        let targetID = itemID ?? currentItem?.id
        guard let targetID, contains(targetID) else {
            // No window yet: it opens with the message.
            guard itemID == nil else { return }
            publish {
                items = [Item(id: UUID(), draft: invalidDraft, duplicateID: duplicateOfTorrentID)]
                currentIndex = 0
            }
            host?.addTorrentReviewPresentWindow()
            return
        }

        setDraft(invalidDraft, forItem: targetID, duplicateID: duplicateOfTorrentID)
        // A message about the download on screen brings the window forward,
        // as it always did; one about a download off screen waits for it.
        if targetID == currentItem?.id {
            host?.addTorrentReviewPresentWindow()
        }
    }

    // MARK: - Edits

    func updateAlias(_ alias: String) {
        editCurrentDraft { $0.alias = alias }
    }

    func updateSaveLocation(_ url: URL, bookmarkData: Data?) {
        editCurrentDraft {
            $0.suggestedSavePath = NSString(string: url.path).standardizingPath
            $0.savePathBookmarkData = bookmarkData
        }
    }

    func updateStopAfterDownload(_ isEnabled: Bool) {
        editCurrentDraft { $0.stopAfterDownload = isEnabled }
    }

    func setFileSelection(id: UUID, isSelected: Bool) {
        guard var draft, draft.setFileSelection(id: id, isSelected: isSelected) else { return }
        self.draft = draft
    }

    func setFolderSelection(path: String, isSelected: Bool) {
        guard var draft, draft.setFolderSelection(path: path, isSelected: isSelected) else { return }
        self.draft = draft
    }

    private func editCurrentDraft(_ edit: (inout AddTorrentDraft) -> Void) {
        guard var draft else { return }
        edit(&draft)
        self.draft = draft
    }

    // MARK: - Drafts and their prepared metadata

    /// Replaces a download's draft. The window hears of it only when that
    /// download is on screen.
    private func setDraft(_ newDraft: AddTorrentDraft, forItem itemID: UUID, duplicateID: UUID?? = nil) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let oldDraftID = items[index].draft.id
        let update = {
            self.items[index].draft = newDraft
            if let duplicateID {
                self.items[index].duplicateID = duplicateID
            }
        }
        if index == currentIndex {
            publish(update)
        } else {
            update()
        }
        if oldDraftID != newDraft.id {
            releasePreparedDraftUnlessAdding(oldDraftID)
        }
    }

    private func publish(_ change: () -> Void) {
        objectWillChange.send()
        change()
    }

    /// A draft owns its prepared metadata until it is replaced, leaves the
    /// window or the window closes. A confirmed draft hands it over to its
    /// pending addition instead.
    private func releasePreparedDraftUnlessAdding(_ draftID: UUID) {
        guard host?.addTorrentReviewHasHandedOver(draftID: draftID) == false else { return }
        releasePreparedDraft(draftID)
    }

    private func releasePreparedDraft(_ draftID: UUID) {
        Task { [engine] in
            await engine.releasePreparedDraft(id: draftID)
        }
    }

    private var localeOverride: AppLocaleOverride {
        host?.addTorrentReviewLocaleOverride ?? .system
    }

    private func makeLoadingDraft(
        for source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool,
        alias: String,
        savePathBookmarkData: Data?
    ) -> AddTorrentDraft {
        AddTorrentDraft(
            source: source,
            originalName: L10n.string("add_torrent.loading_metadata", localeOverride: localeOverride, defaultValue: "Получение метаданных..."),
            infoHash: nil,
            suggestedSavePath: suggestedSavePath,
            savePathBookmarkData: savePathBookmarkData,
            alias: alias,
            stopAfterDownload: stopAfterDownload,
            files: [],
            reviewState: .loadingMetadata,
            errorState: nil
        )
    }
}
