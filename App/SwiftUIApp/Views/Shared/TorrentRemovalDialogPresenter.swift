// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation

@MainActor
enum TorrentRemovalDialogPresenter {
    static func confirmCancelPendingAddition(
        named shortDisplayName: String,
        localeOverride: AppLocaleOverride = .system,
        window: NSWindow? = nil
    ) async -> Bool {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .critical
        alert.messageText = L10n.format(
            "add_torrent.cancel.title",
            localeOverride: localeOverride,
            defaultValue: "Отменить добавление «%@»?",
            shortDisplayName
        )
        alert.informativeText = L10n.string(
            "add_torrent.cancel.message",
            localeOverride: localeOverride,
            defaultValue: "Shatl остановит добавление и удалит загрузку из списка. Это действие необратимо."
        )
        alert.addButton(
            withTitle: L10n.string(
                "add_torrent.cancel.delete_action",
                localeOverride: localeOverride,
                defaultValue: "Удалить загрузку"
            )
        )
        alert.addButton(
            withTitle: L10n.string(
                "add_torrent.cancel.cancel_action",
                localeOverride: localeOverride,
                defaultValue: "Отмена"
            )
        )
        markDestructiveIfPossible(alert.buttons[safe: 0])

        let response = await present(alert, on: resolvedWindow(window))
        return response == .alertFirstButtonReturn
    }

    static func presentRemovalChoice(
        for record: TorrentRecord,
        allowsDeleteWithFiles: Bool = true,
        localeOverride: AppLocaleOverride = .system,
        window: NSWindow? = nil
    ) async -> TorrentRemovalPolicy? {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = L10n.format(
            "remove_dialog.choice.title",
            localeOverride: localeOverride,
            defaultValue: "Удалить «%@»?",
            record.displayName
        )
        alert.informativeText = allowsDeleteWithFiles
            ? L10n.string(
                "remove_dialog.choice.message.with_files",
                localeOverride: localeOverride,
                defaultValue: "Можно удалить только запись из списка или удалить запись вместе с загруженными файлами."
            )
            : L10n.string(
                "remove_dialog.choice.message.list_only",
                localeOverride: localeOverride,
                defaultValue: "Shatl удалит только запись из списка. Удаление файлов для этой карточки недоступно."
            )
        alert.addButton(withTitle: L10n.string("torrent.action.remove_from_list", localeOverride: localeOverride, defaultValue: "Удалить из списка"))
        if allowsDeleteWithFiles {
            alert.addButton(withTitle: L10n.string("torrent.action.remove_with_files", localeOverride: localeOverride, defaultValue: "Удалить вместе с файлами"))
            alert.addButton(withTitle: L10n.string("common.cancel", localeOverride: localeOverride, defaultValue: "Отменить"))
            markDestructiveIfPossible(alert.buttons[safe: 1])
        } else {
            alert.addButton(withTitle: L10n.string("common.cancel", localeOverride: localeOverride, defaultValue: "Отменить"))
        }

        let response = await present(alert, on: resolvedWindow(window))

        switch response {
        case .alertFirstButtonReturn:
            return .removeFromListOnly
        case .alertSecondButtonReturn where allowsDeleteWithFiles:
            return .removeFromListAndDeleteFiles
        default:
            return nil
        }
    }

    static func confirmDeleteWithFiles(
        for record: TorrentRecord,
        localeOverride: AppLocaleOverride = .system,
        window: NSWindow? = nil
    ) async -> Bool {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .critical
        alert.messageText = L10n.format(
            "remove_dialog.delete_with_files.title",
            localeOverride: localeOverride,
            defaultValue: "Удалить «%@» вместе с файлами?",
            record.displayName
        )
        alert.informativeText = L10n.string(
            "remove_dialog.delete_with_files.message",
            localeOverride: localeOverride,
            defaultValue: "Shatl удалит торрент из списка, а также все связанные файлы с диска."
        )
        alert.addButton(withTitle: L10n.string("common.delete", localeOverride: localeOverride, defaultValue: "Удалить"))
        alert.addButton(withTitle: L10n.string("common.cancel", localeOverride: localeOverride, defaultValue: "Отменить"))
        markDestructiveIfPossible(alert.buttons[safe: 0])

        let response = await present(alert, on: resolvedWindow(window))
        return response == .alertFirstButtonReturn
    }

    private static func present(
        _ alert: NSAlert,
        on window: NSWindow?
    ) async -> NSApplication.ModalResponse {
        guard let window else {
            return alert.runModal()
        }

        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }

    private static func resolvedWindow(_ explicitWindow: NSWindow?) -> NSWindow? {
        explicitWindow ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
    }

    private static func markDestructiveIfPossible(_ button: NSButton?) {
        guard let button else { return }

        if #available(macOS 11.0, *) {
            button.hasDestructiveAction = true
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
