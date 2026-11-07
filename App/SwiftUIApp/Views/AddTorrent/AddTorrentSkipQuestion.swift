// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation

/// The question "Не скачивать" asks among several downloads before one leaves
/// the add window. Trackers name their files like "tor164677.torrent", and a
/// download let go by mistake would be hard to find again; so the question
/// names the file and its folder, and offers to keep the download in the
/// list instead. Return and Esc go back, as in the removal questions:
/// nothing is lost by a key pressed in passing.
@MainActor
enum AddTorrentSkipQuestion {
    enum Answer: Equatable {
        case goBack
        case saveToList
        case skip
    }

    /// `canSave` is false for a draft with no file ticked: there is nothing
    /// to keep, and the question offers only to let it go.
    static func ask(
        about draft: AddTorrentDraft,
        canSave: Bool,
        localeOverride: AppLocaleOverride,
        window: NSWindow?
    ) async -> Answer {
        let alert = makeAlert(about: draft, canSave: canSave, localeOverride: localeOverride)
        return answer(for: await present(alert, on: window), canSave: canSave)
    }

    /// Shows a question of the add window as a sheet over it. Its first
    /// button, "Вернуться", takes Return and Esc: NSAlert gives Esc only to
    /// a button titled with AppKit's own "Cancel", so a monitor hands it over
    /// while the question is shown.
    static func present(_ alert: NSAlert, on window: NSWindow?) async -> NSApplication.ModalResponse {
        let goBackButton = alert.buttons.first
        let escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            TorrentRemovalDialogPresenter.escapeClicksCancel(event, alert: alert, cancelButton: goBackButton)
        }
        defer {
            if let escapeMonitor {
                NSEvent.removeMonitor(escapeMonitor)
            }
        }

        guard let window else { return alert.runModal() }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }

    static func makeAlert(
        about draft: AddTorrentDraft,
        canSave: Bool,
        localeOverride: AppLocaleOverride
    ) -> NSAlert {
        let question = ShatlErrorCatalog.skipDownloadQuestion(
            for: draft,
            canSave: canSave,
            localeOverride: localeOverride
        )
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = question.title
        alert.informativeText = question.message
        // The first button takes Return.
        alert.addButton(withTitle: L10n.string(
            "add_torrent.review.go_back",
            localeOverride: localeOverride,
            defaultValue: "Вернуться в окно добавления"
        ))
        if canSave {
            alert.addButton(withTitle: L10n.string(
                "add_torrent.question.save_one_to_list",
                localeOverride: localeOverride,
                defaultValue: "Сохранить загрузку в список"
            ))
        }
        alert.addButton(withTitle: L10n.string(
            "add_torrent.review.skip",
            localeOverride: localeOverride,
            defaultValue: "Не скачивать"
        ))
        return alert
    }

    static func answer(for response: NSApplication.ModalResponse, canSave: Bool) -> Answer {
        switch response {
        case .alertSecondButtonReturn:
            canSave ? .saveToList : .skip
        case .alertThirdButtonReturn:
            .skip
        default:
            .goBack
        }
    }
}
