// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// Messages about the saved list name their buttons exactly as the buttons
/// are labelled, in every language, and warn before the list is wiped.
final class SessionCopyTests: XCTestCase {
    private let languages = AppLocaleOverride.allCases.filter { $0 != .system }

    func testSaveFailuresNameTheCheckAgainButton() {
        let keys = [
            "session.persistence.background_failed.message",
            "session.persistence.remove_from_list_failed.message",
            "session.persistence.remove_with_files_failed.message",
            "session.persistence.stop_failed.message",
            "session.persistence.redownload_failed.message",
        ]
        for language in languages {
            let button = L10n.string("session.persistence.line.check_again", localeOverride: language)
            for key in keys {
                let message = L10n.string(key, localeOverride: language)
                XCTAssertTrue(message.contains(button), "\(language) \(key): \(message)")
            }
        }
    }

    /// The card keeps its error and its button when downloading again fails.
    func testFailedRedownloadNamesTheCardButton() {
        for language in languages {
            let button = L10n.string("torrent.action.redownload", localeOverride: language)
            let message = L10n.string("session.persistence.redownload_failed.message", localeOverride: language)
            XCTAssertTrue(message.contains(button), "\(language): \(message)")
        }
    }

    func testSecondCopyNamesTheOKButton() {
        for language in languages {
            let button = L10n.string("common.ok", localeOverride: language)
            let message = L10n.string("single_instance.already_running.message", localeOverride: language)
            XCTAssertTrue(message.contains(button), "\(language): \(message)")
        }
    }

    /// Starting with an empty list deletes the saved one for good; both
    /// screens that offer it say so.
    func testRecoveryScreensWarnThatTheListWillBeDeleted() {
        for key in ["session.load.unreadable.message", "session.load.unsupported.message"] {
            let message = L10n.string(key, localeOverride: .russian)
            XCTAssertTrue(message.contains("будет удалён"), "\(key): \(message)")
        }
    }
}

/// Removal dialogs say what each button does, and that files deleted with a
/// download do not go to the Trash.
final class RemovalCopyTests: XCTestCase {
    func testDeleteWithFilesWarnsThatFilesSkipTheTrash() {
        let message = L10n.string("remove_dialog.delete_with_files.message", localeOverride: .russian)
        XCTAssertTrue(message.contains("насовсем"), message)
        XCTAssertTrue(message.contains("Корзину"), message)
    }

    /// Deleting a download that is still being added asks the same question
    /// as any removal, in every language.
    func testPendingAdditionAsksTheRemovalQuestion() {
        for language in AppLocaleOverride.allCases where language != .system {
            XCTAssertEqual(
                L10n.string("add_torrent.cancel.title", localeOverride: language),
                L10n.string("remove_dialog.choice.title", localeOverride: language),
                "\(language)"
            )
        }
    }
}
