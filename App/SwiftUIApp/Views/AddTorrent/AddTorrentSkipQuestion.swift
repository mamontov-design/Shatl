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

        // NSAlert gives Esc only to a button titled with AppKit's own
        // "Cancel", so "Вернуться" takes it from a monitor while shown.
        let goBackButton = alert.buttons.first
        let escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            TorrentRemovalDialogPresenter.escapeClicksCancel(event, alert: alert, cancelButton: goBackButton)
        }
        defer {
            if let escapeMonitor {
                NSEvent.removeMonitor(escapeMonitor)
            }
        }

        let response: NSApplication.ModalResponse
        if let window {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response)
                }
            }
        } else {
            response = alert.runModal()
        }
        return answer(for: response, canSave: canSave)
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
            defaultValue: "Вернуться"
        ))
        if canSave {
            alert.addButton(withTitle: L10n.string(
                "add_torrent.review.save_to_list",
                localeOverride: localeOverride,
                defaultValue: "Сохранить в список"
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
