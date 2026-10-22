// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Combine
import Foundation

nonisolated struct TorrentRowErrorState: Equatable, Sendable {
    var kind: TorrentErrorState.Kind
    var title: String
    var message: String
    var recoveryOptions: [TorrentErrorState.RecoveryOption]

    /// `saveFolderPath` lets a card name the folder its error is about;
    /// `metricsMode` writes sizes as the rest of the card does.
    init?(
        _ errorState: TorrentErrorState?,
        saveFolderPath: String? = nil,
        metricsMode: MetricsPresentationMode = .simplified,
        localeOverride: AppLocaleOverride = .russian
    ) {
        guard let errorState else { return nil }

        self.kind = errorState.kind
        self.title = Self.localizedTitle(for: errorState, localeOverride: localeOverride)
        self.message = Self.localizedMessage(
            for: errorState,
            saveFolderPath: saveFolderPath,
            metricsMode: metricsMode,
            localeOverride: localeOverride
        )
        self.recoveryOptions = errorState.recoveryOptions
    }

    private static func localizedTitle(
        for errorState: TorrentErrorState,
        localeOverride: AppLocaleOverride
    ) -> String {
        switch errorState.kind {
        case .missingContent:
            L10n.string("torrent.error.missing_content.title", localeOverride: localeOverride, defaultValue: errorState.title)
        case .savePathUnavailable:
            L10n.string("torrent.error.save_path_unavailable.title", localeOverride: localeOverride, defaultValue: errorState.title)
        case .torrentNotFound:
            L10n.string("torrent.error.not_found.title", localeOverride: localeOverride, defaultValue: errorState.title)
        case .engineFailure:
            L10n.string("torrent.error.runtime.title", localeOverride: localeOverride, defaultValue: errorState.title)
        case .notEnoughSpace:
            L10n.string("torrent.error.not_enough_space.title", localeOverride: localeOverride, defaultValue: errorState.title)
        default:
            errorState.title
        }
    }

    private static func localizedMessage(
        for errorState: TorrentErrorState,
        saveFolderPath: String?,
        metricsMode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride
    ) -> String {
        switch errorState.kind {
        case .notEnoughSpace:
            // The disk and what it lacks; without them, the plain sentence.
            if let check = errorState.spaceCheck, !check.volumeName.isEmpty {
                L10n.format(
                    "torrent.error.not_enough_space.named_message",
                    localeOverride: localeOverride,
                    defaultValue: errorState.message,
                    ShatlErrorCatalog.shortenedTorrentName(check.volumeName),
                    check.shortfallText(mode: metricsMode, localeOverride: localeOverride)
                )
            } else {
                L10n.string("torrent.error.not_enough_space.message", localeOverride: localeOverride, defaultValue: errorState.message)
            }
        case .missingContent:
            folderMessage(
                key: "torrent.error.missing_content",
                saveFolderPath: saveFolderPath,
                localeOverride: localeOverride,
                fallback: errorState.message
            )
        case .savePathUnavailable:
            folderMessage(
                key: "torrent.error.save_path_unavailable",
                saveFolderPath: saveFolderPath,
                localeOverride: localeOverride,
                fallback: errorState.message
            )
        case .torrentNotFound:
            L10n.string("torrent.error.not_found.message", localeOverride: localeOverride, defaultValue: errorState.message)
        case .engineFailure:
            // A file error names its folder; any other cause has none to name.
            if let cause = errorState.cause {
                folderMessage(
                    key: "torrent.error.runtime.\(ShatlErrorCatalog.causeKey(cause))",
                    saveFolderPath: saveFolderPath,
                    localeOverride: localeOverride,
                    fallback: errorState.message
                )
            } else {
                L10n.string("torrent.error.runtime.other.message", localeOverride: localeOverride, defaultValue: errorState.message)
            }
        default:
            errorState.message
        }
    }

    /// The card names the folder in question, "Загрузки" rather than "the
    /// download folder", when its name is known.
    private static func folderMessage(
        key: String,
        saveFolderPath: String?,
        localeOverride: AppLocaleOverride,
        fallback: String
    ) -> String {
        let folderName = saveFolderPath.map(ShatlErrorCatalog.folderDisplayName(forPath:)) ?? ""
        guard !folderName.isEmpty else {
            return L10n.string("\(key).message", localeOverride: localeOverride, defaultValue: fallback)
        }
        return L10n.format(
            "\(key).named_message",
            localeOverride: localeOverride,
            defaultValue: fallback,
            ShatlErrorCatalog.shortenedTorrentName(folderName)
        )
    }
}

nonisolated struct TorrentRowState: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var originalTitle: String
    var hasAlias: Bool
    var status: TorrentStatus
    var statusTitle: String
    var progress: Double
    var compactTransferMetricSet: CompactTransferMetricSet?
    var expandedMetricGroups: ExpandedMetricGroupsPresentation?
    var metricsMode: MetricsPresentationMode
    var colorizesDownloadSpeed: Bool = false
    /// Statuses and the speed set in greys; the speed icon keeps its colour
    /// while `colorizesDownloadSpeed` is on.
    var usesMonochromeAppearance: Bool = false
    #if DEBUG
    var enablesCardLayoutDiagnostics: Bool = false
    var enablesMetricAnimationDiagnostics: Bool = false
    #endif
    var errorState: TorrentRowErrorState?
    var isSelected: Bool
    /// Selected together with other cards: its menu then acts on all of them.
    var isSelectedWithOthers = false
    /// The card's number among the selected ones, worn in place of the check
    /// mark; `nil` for the check mark. See `TorrentSelectionCount`.
    var selectionNumber: Int?
    var isExpanded: Bool
    var canToggleRunningState: Bool
    var canRemoveFromList: Bool
    var canRemoveWithFiles: Bool
    var navigationAvailabilityKey: String
    var localeOverride: AppLocaleOverride
    var isPendingAddition = false
    var canExpand = true
    /// What the card leaves out with many downloads running.
    var simplification = CardSimplificationLevel.full
    /// "Проверить снова" or "Повторить" is at work on the card's error.
    var isRecovering = false
    /// Saved to the list for lack of room and not started yet: the card is
    /// outlined with dashes and its badge is a bookmark.
    var isSavedForLater = false
    /// Downloading or seeding without speed for a while: "Простаивает". The
    /// badge loses its fill. See `TransferActivity`.
    var isIdle = false
}

extension TorrentRowState {
    /// A finished download shows on one line: its status badge beside the
    /// title, without the progress bar; the badge names the status under the
    /// pointer. A check of a finished download keeps it
    /// there, the one after a restart or before seeding alike: the card shows
    /// the progress it last knew, 100 %.
    var usesFinishedLayout: Bool {
        guard errorState == nil, !isPendingAddition else { return false }

        switch status {
        case .completed, .seeding:
            return true
        case .checking:
            return progress >= 1
        case .downloading, .stopped, .error:
            return false
        }
    }
}

@MainActor
final class TorrentRowPresentationModel: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var state: TorrentRowState

    init(state: TorrentRowState) {
        id = state.id
        self.state = state
    }

    func update(state newState: TorrentRowState) {
        guard state != newState else { return }
        state = newState
    }
}

@MainActor
final class TorrentTransferSummaryModel: ObservableObject {
    @Published private(set) var chips: [BottomTransferChipPresentation]
    let visibility: TorrentTransferSummaryVisibilityModel

    init(chips: [BottomTransferChipPresentation] = []) {
        self.chips = chips
        self.visibility = TorrentTransferSummaryVisibilityModel(hasChips: !chips.isEmpty)
    }

    func update(chips newChips: [BottomTransferChipPresentation]) {
        guard chips != newChips else { return }
        chips = newChips
        visibility.update(hasChips: !newChips.isEmpty)
    }
}

@MainActor
final class TorrentTransferSummaryVisibilityModel: ObservableObject {
    @Published private(set) var hasChips: Bool

    init(hasChips: Bool) {
        self.hasChips = hasChips
    }

    func update(hasChips newValue: Bool) {
        guard hasChips != newValue else { return }
        hasChips = newValue
    }
}
