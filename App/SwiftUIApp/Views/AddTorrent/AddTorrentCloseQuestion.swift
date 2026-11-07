// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation

/// The question closing the add window asks when that would lose work:
/// downloads still waiting for a decision, or a choice of files made in a
/// large torrent and about to go with a stray click or ⌘W. It names what
/// would go, and offers to keep it in the list. Return and Esc go back.
@MainActor
enum AddTorrentCloseQuestion {
    enum Answer: Equatable {
        case goBack
        case saveToList
        case close
    }

    static func ask(
        about loss: AddTorrentReviewModel.ClosingLoss,
        localeOverride: AppLocaleOverride,
        window: NSWindow?
    ) async -> Answer {
        let alert = makeAlert(about: loss, localeOverride: localeOverride)
        let response = await AddTorrentSkipQuestion.present(alert, on: window)
        return answer(for: response, canSave: !loss.savableDrafts.isEmpty)
    }

    static func makeAlert(
        about loss: AddTorrentReviewModel.ClosingLoss,
        localeOverride: AppLocaleOverride
    ) -> NSAlert {
        let question = ShatlErrorCatalog.closeWindowQuestion(
            losing: loss.drafts,
            savableCount: loss.savableDrafts.count,
            includesWaitingLinks: loss.includesWaitingLinks,
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
        // The button names what it saves: one download or several.
        if loss.savableDrafts.count == 1 {
            alert.addButton(withTitle: L10n.string(
                "add_torrent.question.save_one_to_list",
                localeOverride: localeOverride,
                defaultValue: "Сохранить загрузку в список"
            ))
        } else if loss.savableDrafts.count > 1 {
            alert.addButton(withTitle: L10n.string(
                "add_torrent.question.save_several_to_list",
                localeOverride: localeOverride,
                defaultValue: "Сохранить загрузки в список"
            ))
        }
        alert.addButton(withTitle: L10n.string(
            "add_torrent.close.close_window",
            localeOverride: localeOverride,
            defaultValue: "Закрыть окно добавления"
        ))
        return alert
    }

    static func answer(for response: NSApplication.ModalResponse, canSave: Bool) -> Answer {
        switch response {
        case .alertSecondButtonReturn:
            canSave ? .saveToList : .close
        case .alertThirdButtonReturn:
            .close
        default:
            .goBack
        }
    }
}
