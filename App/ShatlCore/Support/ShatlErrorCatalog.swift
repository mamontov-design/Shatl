// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// The single place where Shatl converts technical failures
/// into user-friendly interface messages.
enum ShatlErrorCatalog {
    nonisolated static func persistentIssueState(for issue: TorrentPersistentIssue) -> TorrentErrorState {
        switch issue.kind {
        case .missingContent:
            return TorrentErrorState(
                kind: .missingContent,
                title: "Файлы загрузки недоступны",
                message: "Shatl не нашёл данные торрента по сохранённому пути. Вы можете скачать их заново или удалить запись из списка.",
                recoveryOptions: [.redownload, .removeFromList]
            )

        case .savePathUnavailable:
            return TorrentErrorState(
                kind: .savePathUnavailable,
                title: "Папка загрузки недоступна",
                message: "Shatl не смог открыть папку сохранения. Выберите другую папку для загрузки или удалите торрент из списка",
                recoveryOptions: [.chooseAnotherFolder, .removeFromList]
            )
        }
    }

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
                    localeOverride: localeOverride,
                    defaultValue: "Добавьте magnet-ссылку"
                ),
                message: L10n.string(
                    "add_torrent.error.empty_magnet.message",
                    localeOverride: localeOverride,
                    defaultValue: "Поле пустое. Вставьте magnet-ссылку и попробуйте снова."
                ),
                recoveryOptions: [.dismiss]
            )
        }

        guard trimmed.hasPrefix("magnet:?") else {
            return TorrentErrorState(
                kind: .invalidMagnet,
                title: L10n.string(
                    "add_torrent.error.unrecognized_link.title",
                    localeOverride: localeOverride,
                    defaultValue: "Не удалось распознать ссылку"
                ),
                message: L10n.string(
                    "add_torrent.error.unrecognized_link.message",
                    localeOverride: localeOverride,
                    defaultValue: "Проверьте, что она начинается с magnet:? и скопирована полностью."
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
                    localeOverride: localeOverride,
                    defaultValue: "Не удалось распознать magnet-ссылку."
                ),
                message: L10n.string(
                    "add_torrent.error.invalid_magnet.message",
                    localeOverride: localeOverride,
                    defaultValue: "Проверьте, что ссылка скопирована полностью, и попробуйте снова."
                ),
                recoveryOptions: [.retry, .dismiss]
            )

        case .invalidTorrentFile:
            return TorrentErrorState(
                kind: .invalidTorrentFile,
                title: L10n.string(
                    "add_torrent.error.invalid_torrent_file.title",
                    localeOverride: localeOverride,
                    defaultValue: "Не удалось открыть файл."
                ),
                message: L10n.string(
                    "add_torrent.error.invalid_torrent_file.message",
                    localeOverride: localeOverride,
                    defaultValue: "Файл может быть повреждён или не поддерживается. Выберите другой .torrent-файл и попробуйте снова."
                ),
                recoveryOptions: [.retry, .dismiss]
            )

        case .metadataTimeout:
            return TorrentErrorState(
                kind: .metadataTimeout,
                title: L10n.string(
                    "add_torrent.error.metadata_timeout.title",
                    localeOverride: localeOverride,
                    defaultValue: "Не удалось получить метаданные."
                ),
                message: L10n.string(
                    "add_torrent.error.metadata_timeout.message",
                    localeOverride: localeOverride,
                    defaultValue: "Источники не успели передать данные. Попробуйте снова через некоторое время."
                ),
                recoveryOptions: [.retry, .dismiss]
            )

        case .draftPreparationLost:
            return TorrentErrorState(
                kind: .draftPreparationLost,
                title: L10n.string(
                    "add_torrent.error.draft_lost.title",
                    localeOverride: localeOverride,
                    defaultValue: "Подготовка загрузки прервана."
                ),
                message: L10n.string(
                    "add_torrent.error.draft_lost.message",
                    localeOverride: localeOverride,
                    defaultValue: "Данные не сохранились. Закройте окно и добавьте торрент заново."
                ),
                recoveryOptions: [.retry, .dismiss]
            )

        case .duplicateTorrent:
            return duplicateDraftError(localeOverride: localeOverride)

        case .torrentNotFound:
            return TorrentErrorState(
                kind: .torrentNotFound,
                // Its own title: the card's one also titles a notification,
                // which takes no full stop.
                title: L10n.string(
                    "add_torrent.error.not_found.title",
                    localeOverride: localeOverride,
                    defaultValue: "Загрузка недоступна."
                ),
                message: L10n.string(
                    "torrent.error.not_found.message",
                    localeOverride: localeOverride,
                    defaultValue: "Не удалось найти этот торрент. Попробуйте добавить его заново."
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

    /// Names the torrent when its name is known, so the message says which
    /// one is already in the list.
    nonisolated static func duplicateDraftError(
        torrentName: String? = nil,
        localeOverride: AppLocaleOverride = .russian
    ) -> TorrentErrorState {
        let name = torrentName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let message = name.isEmpty
            ? L10n.string(
                "add_torrent.error.duplicate.message",
                localeOverride: localeOverride,
                defaultValue: "Этот торрент уже добавлен в список загрузок."
            )
            : L10n.format(
                "add_torrent.error.duplicate.named_message",
                localeOverride: localeOverride,
                defaultValue: "Торрент «%@» уже добавлен в список загрузок.",
                shortenedTorrentName(name)
            )
        return TorrentErrorState(
            kind: .duplicateTorrent,
            title: L10n.string(
                "add_torrent.error.duplicate.title",
                localeOverride: localeOverride,
                defaultValue: "Такая загрузка уже есть."
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
                localeOverride: localeOverride,
                defaultValue: "Не удалось подготовить загрузку."
            ),
            message: L10n.string(
                "add_torrent.error.generic.message",
                localeOverride: localeOverride,
                defaultValue: "Попробуйте ещё раз. Если ошибка повторится, проверьте файл или ссылку."
            ),
            recoveryOptions: [.retry, .dismiss]
        )
    }
}
