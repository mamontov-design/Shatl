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

/// The add window's download: the draft under review, its preparation and
/// its edits.
///
/// Kept apart from `AppStore` so that what changes while the window is in
/// use — a file read, a file ticked, a letter of the alias — reaches the add
/// window alone. Every change the store publishes draws the main window's
/// list anew (see `AGENTS.md`, arrow keys), and the draft is the part of the
/// add flow that changes often. Opening and closing the window, which is
/// rare, stays with the store.
@MainActor
final class AddTorrentReviewModel: ObservableObject {
    weak var host: (any AddTorrentReviewHost)?

    @Published var draft: AddTorrentDraft? {
        didSet {
            guard let oldValue, oldValue.id != draft?.id else { return }
            releasePreparedDraftUnlessAdding(oldValue.id)
        }
    }

    /// The download a duplicate in the add window already is, so the window
    /// can show it in the list rather than leave it to be found.
    @Published private(set) var duplicateID: UUID?

    private let engine: any TorrentEngine
    private var preparationTask: Task<Void, Never>?

    init(engine: any TorrentEngine) {
        self.engine = engine
    }

    deinit {
        preparationTask?.cancel()
    }

    // MARK: - Preparation

    /// Shows a waiting draft at once and reads the download behind it.
    func prepare(
        _ source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool,
        alias: String,
        savePathBookmarkData: Data?
    ) {
        preparationTask?.cancel()
        duplicateID = nil
        draft = makeLoadingDraft(
            for: source,
            suggestedSavePath: suggestedSavePath,
            stopAfterDownload: stopAfterDownload,
            alias: alias,
            savePathBookmarkData: savePathBookmarkData
        )
        host?.addTorrentReviewPresentWindow()

        preparationTask = Task { [weak self] in
            guard let self else { return }

            do {
                var preparedDraft = try await self.engine.prepareDraft(
                    from: source,
                    suggestedSavePath: suggestedSavePath,
                    stopAfterDownload: stopAfterDownload
                )

                guard !Task.isCancelled,
                      self.draft?.source == source else {
                    // Review was closed or moved on while the metadata loaded.
                    self.releasePreparedDraft(preparedDraft.id)
                    return
                }

                preparedDraft.alias = alias
                preparedDraft.savePathBookmarkData = savePathBookmarkData
                if self.host?.addTorrentReviewRepeatsDownload(preparedDraft) == true {
                    self.releasePreparedDraft(preparedDraft.id)
                    self.presentDuplicate(of: preparedDraft)
                } else {
                    self.draft = preparedDraft
                }
            } catch {
                guard !Task.isCancelled else { return }
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
                        duplicateOfTorrentID: duplicate.duplicateID
                    )
                    return
                }
                // The wait ran out with no network at all: say so directly.
                if errorState.kind == .metadataTimeout,
                   await self.host?.addTorrentReviewNetworkIsOffline() == true {
                    guard !Task.isCancelled else { return }
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
                    savePathBookmarkData: savePathBookmarkData
                )
            }
        }
    }

    /// Stops reading the download; the draft on screen stays.
    func cancelPreparation() {
        preparationTask?.cancel()
    }

    /// The window is closed: nothing is read and nothing is shown.
    func dismiss() {
        duplicateID = nil
        preparationTask?.cancel()
        draft = nil
    }

    // MARK: - Messages

    func presentInvalid(
        for source: AddTorrentSource,
        errorState: TorrentErrorState,
        suggestedSavePath: String,
        stopAfterDownload: Bool,
        alias: String,
        savePathBookmarkData: Data? = nil,
        duplicateOfTorrentID: UUID? = nil
    ) {
        duplicateID = duplicateOfTorrentID
        draft = AddTorrentDraft(
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
        host?.addTorrentReviewPresentWindow()
    }

    func presentDuplicate(of draft: AddTorrentDraft) {
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
            duplicateOfTorrentID: duplicate.duplicateID
        )
    }

    // MARK: - Edits

    func updateAlias(_ alias: String) {
        guard var draft else { return }
        draft.alias = alias
        self.draft = draft
    }

    func updateSaveLocation(_ url: URL, bookmarkData: Data?) {
        guard var draft else { return }
        draft.suggestedSavePath = NSString(string: url.path).standardizingPath
        draft.savePathBookmarkData = bookmarkData
        self.draft = draft
    }

    func updateStopAfterDownload(_ isEnabled: Bool) {
        guard var draft else { return }
        draft.stopAfterDownload = isEnabled
        self.draft = draft
    }

    func setFileSelection(id: UUID, isSelected: Bool) {
        guard var draft, draft.setFileSelection(id: id, isSelected: isSelected) else { return }
        self.draft = draft
    }

    func setFolderSelection(path: String, isSelected: Bool) {
        guard var draft, draft.setFolderSelection(path: path, isSelected: isSelected) else { return }
        self.draft = draft
    }

    // MARK: - Prepared metadata

    /// The Review draft owns its prepared metadata until it is replaced or
    /// closed. A confirmed draft hands it over to its pending addition instead.
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
