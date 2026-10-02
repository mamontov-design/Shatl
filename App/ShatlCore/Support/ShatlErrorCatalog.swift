// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Synchronization

/// The single place where Shatl converts technical failures
/// into user-friendly interface messages.
enum ShatlErrorCatalog {
    nonisolated static func persistentIssueState(
        for issue: TorrentPersistentIssue,
        localeOverride: AppLocaleOverride = .system
    ) -> TorrentErrorState {
        switch issue.kind {
        case .missingContent:
            return TorrentErrorState(
                kind: .missingContent,
                title: L10n.string("torrent.error.missing_content.title", localeOverride: localeOverride),
                message: L10n.string("torrent.error.missing_content.message", localeOverride: localeOverride),
                recoveryOptions: [.redownload, .removeFromList]
            )

        case .savePathUnavailable:
            return TorrentErrorState(
                kind: .savePathUnavailable,
                title: L10n.string("torrent.error.save_path_unavailable.title", localeOverride: localeOverride),
                message: L10n.string("torrent.error.save_path_unavailable.message", localeOverride: localeOverride),
                recoveryOptions: [.chooseAnotherFolder, .removeFromList]
            )
        }
    }

    /// A notification has no buttons: it names the event, then the download
    /// (the subtitle), then says where the error is fixed, not which button
    /// to press. The card's own text would point at buttons it cannot show.
    nonisolated static func persistentIssueNotification(
        for kind: TorrentPersistentIssue.Kind,
        localeOverride: AppLocaleOverride = .system
    ) -> (title: String, body: String) {
        switch kind {
        case .missingContent:
            (
                L10n.string("torrent.error.missing_content.title", localeOverride: localeOverride),
                L10n.string("torrent.error.missing_content.notification", localeOverride: localeOverride)
            )
        case .savePathUnavailable:
            (
                L10n.string("torrent.error.save_path_unavailable.title", localeOverride: localeOverride),
                L10n.string("torrent.error.save_path_unavailable.notification", localeOverride: localeOverride)
            )
        }
    }

    /// The folder's name as Finder shows it ("Загрузки" for ~/Downloads),
    /// looked up once per path: a card must not touch the disk each time it
    /// is rebuilt. A folder that is gone keeps its last path component.
    nonisolated static func folderDisplayName(forPath path: String) -> String {
        if let cached = folderDisplayNames.withLock({ $0[path] }) {
            return cached
        }
        let name = FileManager.default.displayName(atPath: path)
        folderDisplayNames.withLock { $0[path] = name }
        return name
    }

    nonisolated private static let folderDisplayNames = Mutex<[String: String]>([:])

    nonisolated static func inlineMagnetValidation(
        for input: String,
        localeOverride: AppLocaleOverride = .russian
    ) -> TorrentErrorState? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return TorrentErrorState(
                kind: .invalidMagnet,
                title: L10n.string(
                    "add_torrent.error.empty_magnet.title",
                    localeOverride: localeOverride
                ),
                message: L10n.string(
                    "add_torrent.error.empty_magnet.message",
                    localeOverride: localeOverride
                ),
                recoveryOptions: [.dismiss]
            )
        }

        guard trimmed.hasPrefix("magnet:?") else {
            return TorrentErrorState(
                kind: .invalidMagnet,
                title: L10n.string(
                    "add_torrent.error.unrecognized_link.title",
                    localeOverride: localeOverride
                ),
                message: L10n.string(
                    "add_torrent.error.unrecognized_link.message",
                    localeOverride: localeOverride
                ),
                recoveryOptions: [.dismiss]
            )
        }

        return nil
    }

    nonisolated static func reviewError(
        for error: Error,
        source: AddTorrentSource,
        localeOverride: AppLocaleOverride = .russian
    ) -> TorrentErrorState {
        let engineError = TorrentEngineError.normalized(from: error)

        switch engineError.kind {
        case .invalidMagnet:
            return TorrentErrorState(
                kind: .invalidMagnet,
                title: L10n.string(
                    "add_torrent.error.invalid_magnet.title",
                    localeOverride: localeOverride
                ),
                message: L10n.string(
                    "add_torrent.error.invalid_magnet.message",
                    localeOverride: localeOverride
                ),
                recoveryOptions: [.retry, .dismiss]
            )

        case .invalidTorrentFile:
            return TorrentErrorState(
                kind: .invalidTorrentFile,
                title: L10n.string(
                    "add_torrent.error.invalid_torrent_file.title",
                    localeOverride: localeOverride
                ),
                message: L10n.string(
                    "add_torrent.error.invalid_torrent_file.message",
                    localeOverride: localeOverride
                ),
                recoveryOptions: [.retry, .dismiss]
            )

        case .metadataTimeout:
            return TorrentErrorState(
                kind: .metadataTimeout,
                title: L10n.string(
                    "add_torrent.error.metadata_timeout.title",
                    localeOverride: localeOverride
                ),
                message: L10n.string(
                    "add_torrent.error.metadata_timeout.message",
                    localeOverride: localeOverride
                ),
                recoveryOptions: [.retry, .dismiss]
            )

        case .draftPreparationLost:
            return TorrentErrorState(
                kind: .draftPreparationLost,
                title: L10n.string(
                    "add_torrent.error.draft_lost.title",
                    localeOverride: localeOverride
                ),
                message: L10n.string(
                    "add_torrent.error.draft_lost.message",
                    localeOverride: localeOverride
                ),
                recoveryOptions: [.retry, .dismiss]
            )

        case .duplicateTorrent:
            return duplicateDraftError(torrentName: engineError.torrentName, localeOverride: localeOverride)

        case .torrentNotFound:
            return TorrentErrorState(
                kind: .torrentNotFound,
                // Its own title: the card's one also titles a notification,
                // which takes no full stop.
                title: L10n.string(
                    "add_torrent.error.not_found.title",
                    localeOverride: localeOverride
                ),
                message: L10n.string(
                    "add_torrent.error.not_found.message",
                    localeOverride: localeOverride
                ),
                recoveryOptions: [.dismiss]
            )

        case .engineFailure, .notImplemented:
            return genericAddFlowFailure(source: source, localeOverride: localeOverride)
        }
    }

    nonisolated static func torrentActionError(for error: Error) -> TorrentErrorState {
        let engineError = TorrentEngineError.normalized(from: error)

        switch engineError.kind {
        case .torrentNotFound:
            return TorrentErrorState(
                kind: .torrentNotFound,
                title: "Загрузка недоступна",
                message: "Не удалось найти этот торрент. Попробуйте добавить его заново.",
                recoveryOptions: [.removeFromList, .dismiss]
            )

        default:
            return TorrentErrorState(
                kind: .engineFailure,
                title: "Не удалось выполнить действие",
                message: "Произошла ошибка. Попробуйте ещё раз.",
                recoveryOptions: [.removeFromList, .dismiss]
            )
        }
    }

    nonisolated static func runtimeSnapshotError(debugReason: String?) -> TorrentErrorState {
        _ = debugReason

        return TorrentErrorState(
            kind: .engineFailure,
            title: "Не удалось обновить состояние загрузки",
            message: "Во время работы произошла ошибка. Попробуйте остановить и запустить загрузку снова.",
            recoveryOptions: [.removeFromList, .dismiss]
        )
    }

    /// A magnet link's file list comes from other peers; with no network at
    /// all the wait could not succeed, and the message says so instead of
    /// guessing at slow or missing peers.
    nonisolated static func offlineMetadataError(
        localeOverride: AppLocaleOverride = .russian
    ) -> TorrentErrorState {
        TorrentErrorState(
            kind: .noConnection,
            title: L10n.string("add_torrent.error.offline.title", localeOverride: localeOverride),
            message: L10n.string("add_torrent.error.offline.message", localeOverride: localeOverride),
            recoveryOptions: [.retry, .dismiss]
        )
    }

    /// Names the torrent when its name is known, so the message says which
    /// one is already in the list.
    /// `showsInList`: the window offers "Show in List", and the message
    /// points to it instead of asking to find the download by hand.
    nonisolated static func duplicateDraftError(
        torrentName: String? = nil,
        showsInList: Bool = false,
        localeOverride: AppLocaleOverride = .russian
    ) -> TorrentErrorState {
        let name = torrentName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prefix = showsInList ? "add_torrent.error.duplicate.in_list" : "add_torrent.error.duplicate"
        let message = name.isEmpty
            ? L10n.string("\(prefix).message", localeOverride: localeOverride)
            : L10n.format(
                "\(prefix).named_message",
                localeOverride: localeOverride,
                defaultValue: "",
                shortenedTorrentName(name)
            )
        return TorrentErrorState(
            kind: .duplicateTorrent,
            title: L10n.string(
                "add_torrent.error.duplicate.title",
                localeOverride: localeOverride
            ),
            message: message,
            recoveryOptions: [.dismiss]
        )
    }

    /// A torrent name short enough for a sentence: at most `limit` characters,
    /// shortened in the middle as Finder shortens file names, so the title at
    /// the start and the season, quality or extension at the end both stay.
    nonisolated static func shortenedTorrentName(_ name: String, limit: Int = 40) -> String {
        guard name.count > limit else { return name }
        let tailLength = (limit - 1) / 3
        let headLength = limit - 1 - tailLength
        return String(name.prefix(headLength)) + "…" + String(name.suffix(tailLength))
    }

    nonisolated private static func genericAddFlowFailure(
        source: AddTorrentSource,
        localeOverride: AppLocaleOverride
    ) -> TorrentErrorState {
        _ = source

        return TorrentErrorState(
            kind: .engineFailure,
            title: L10n.string(
                "add_torrent.error.generic.title",
                localeOverride: localeOverride
            ),
            message: L10n.string(
                "add_torrent.error.generic.message",
                localeOverride: localeOverride
            ),
            recoveryOptions: [.retry, .dismiss]
        )
    }
}
