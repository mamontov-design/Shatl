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
        let alert = makeCancelPendingAdditionAlert(named: shortDisplayName, localeOverride: localeOverride)
        return await presentSafeConfirmation(alert, on: resolvedWindow(window))
    }

    static func makeCancelPendingAdditionAlert(
        named shortDisplayName: String,
        localeOverride: AppLocaleOverride = .system
    ) -> NSAlert {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .critical
        alert.messageText = L10n.format(
            "add_torrent.cancel.title",
            localeOverride: localeOverride,
            defaultValue: "",
            shortDisplayName
        )
        alert.informativeText = L10n.string(
            "add_torrent.cancel.message",
            localeOverride: localeOverride
        )
        // The same buttons as every other removal: the title asks "Удалить «X»?".
        addSafeConfirmationButtons(
            to: alert,
            cancelTitle: L10n.string("common.cancel", localeOverride: localeOverride, defaultValue: "Отменить"),
            destructiveTitle: L10n.string("common.delete", localeOverride: localeOverride, defaultValue: "Удалить")
        )
        return alert
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
            defaultValue: "",
            record.displayName
        )
        alert.informativeText = allowsDeleteWithFiles
            ? L10n.string(
                "remove_dialog.choice.message.with_files",
                localeOverride: localeOverride
            )
            : L10n.string(
                "remove_dialog.choice.message.list_only",
                localeOverride: localeOverride
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
        let alert = makeDeleteWithFilesAlert(for: record, localeOverride: localeOverride)
        return await presentSafeConfirmation(alert, on: resolvedWindow(window))
    }

    static func makeDeleteWithFilesAlert(
        for record: TorrentRecord,
        localeOverride: AppLocaleOverride = .system
    ) -> NSAlert {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .critical
        alert.messageText = L10n.format(
            "remove_dialog.delete_with_files.title",
            localeOverride: localeOverride,
            defaultValue: "",
            record.displayName
        )
        alert.informativeText = L10n.string(
            "remove_dialog.delete_with_files.message",
            localeOverride: localeOverride
        )
        addSafeConfirmationButtons(
            to: alert,
            cancelTitle: L10n.string("common.cancel", localeOverride: localeOverride, defaultValue: "Отменить"),
            destructiveTitle: L10n.string("common.delete", localeOverride: localeOverride, defaultValue: "Удалить")
        )
        return alert
    }

    /// An irreversible action is never the default: the cancel button on the
    /// right answers Return and Esc, the red destructive button on its left
    /// answers only a click or ⌘⌫, as Move to Trash does in Finder.
    static func addSafeConfirmationButtons(to alert: NSAlert, cancelTitle: String, destructiveTitle: String) {
        let cancel = alert.addButton(withTitle: cancelTitle)
        cancel.keyEquivalent = "\r"
        let destructive = alert.addButton(withTitle: destructiveTitle)
        destructive.keyEquivalent = "\u{8}"
        destructive.keyEquivalentModifierMask = [.command]
        markDestructiveIfPossible(destructive)
    }

    /// `true` only for the destructive button, the second one.
    private static func presentSafeConfirmation(_ alert: NSAlert, on window: NSWindow?) async -> Bool {
        // NSAlert gives Esc only to a button titled with AppKit's own "Cancel",
        // so the localized cancel button takes it from a monitor while shown.
        let cancelButton = alert.buttons[safe: 0]
        let escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            escapeClicksCancel(event, alert: alert, cancelButton: cancelButton)
        }
        defer {
            if let escapeMonitor {
                NSEvent.removeMonitor(escapeMonitor)
            }
        }

        return await present(alert, on: window) == .alertSecondButtonReturn
    }

    /// The virtual key code of Esc (`kVK_Escape`).
    private static let escapeKeyCode: UInt16 = 53

    /// Returns `nil` when Esc was used to cancel the visible alert.
    static func escapeClicksCancel(_ event: NSEvent, alert: NSAlert, cancelButton: NSButton?) -> NSEvent? {
        guard event.keyCode == escapeKeyCode, alert.window.isVisible, let cancelButton else { return event }
        cancelButton.performClick(nil)
        return nil
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
