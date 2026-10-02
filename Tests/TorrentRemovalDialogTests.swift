// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import XCTest
@testable import Shatl

/// Deleting files is irreversible (`unlinkat`, not the Trash), so a stray
/// Return must never confirm it. The toolbar sheet already defaults to
/// «Удалить из списка»; the menus asked with «Удалить» as the default.
final class TorrentRemovalDialogTests: XCTestCase {
    func testDeleteWithFilesDefaultsToCancel() {
        let alert = TorrentRemovalDialogPresenter.makeDeleteWithFilesAlert(
            for: makeTestRecord(originalName: "Movie"),
            localeOverride: .russian
        )

        assertSafeConfirmation(alert, cancelTitle: "Отменить", destructiveTitle: "Удалить")
    }

    func testCancelPendingAdditionDefaultsToCancel() {
        let alert = TorrentRemovalDialogPresenter.makeCancelPendingAdditionAlert(
            named: "Movie",
            localeOverride: .russian
        )

        assertSafeConfirmation(alert, cancelTitle: "Отменить", destructiveTitle: "Удалить")
    }

    func testEscapeCancelsOnlyAVisibleAlert() {
        let alert = TorrentRemovalDialogPresenter.makeDeleteWithFilesAlert(
            for: makeTestRecord(originalName: "Movie"),
            localeOverride: .russian
        )
        let recorder = ButtonRecorder(alert)
        alert.layout()

        let hiddenResult = TorrentRemovalDialogPresenter.escapeClicksCancel(
            keyEvent("\u{1b}", keyCode: 53, in: alert.window),
            alert: alert,
            cancelButton: alert.buttons[0]
        )
        XCTAssertNotNil(hiddenResult)
        XCTAssertEqual(recorder.pressed, [])

        alert.window.orderFront(nil)
        addTeardownBlock { alert.window.orderOut(nil) }
        let escapeResult = TorrentRemovalDialogPresenter.escapeClicksCancel(
            keyEvent("\u{1b}", keyCode: 53, in: alert.window),
            alert: alert,
            cancelButton: alert.buttons[0]
        )
        let returnResult = TorrentRemovalDialogPresenter.escapeClicksCancel(
            keyEvent("\r", keyCode: 36, in: alert.window),
            alert: alert,
            cancelButton: alert.buttons[0]
        )

        XCTAssertNil(escapeResult)
        XCTAssertNotNil(returnResult)
        XCTAssertEqual(recorder.pressed, ["Отменить"])
    }

    // MARK: - Helpers

    private func assertSafeConfirmation(
        _ alert: NSAlert,
        cancelTitle: String,
        destructiveTitle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(alert.buttons.map(\.title), [cancelTitle, destructiveTitle], file: file, line: line)
        XCTAssertTrue(alert.buttons[1].hasDestructiveAction, file: file, line: line)

        let recorder = ButtonRecorder(alert)
        alert.layout()
        XCTAssertEqual(alert.window.defaultButtonCell?.title, cancelTitle, file: file, line: line)
        // A button takes Return only in a window brought forward to be key.
        alert.window.makeKeyAndOrderFront(nil)
        defer { alert.window.orderOut(nil) }

        let keys: [(String, String, UInt16, NSEvent.ModifierFlags, [String])] = [
            ("Return", "\r", 36, [], [cancelTitle]),
            ("⌘⌫", "\u{8}", 51, [.command], [destructiveTitle]),
            ("⌫", "\u{8}", 51, [], []),
        ]
        for (name, characters, keyCode, modifiers, expected) in keys {
            recorder.pressed.removeAll()
            _ = alert.window.contentView?.performKeyEquivalent(
                with: keyEvent(characters, keyCode: keyCode, modifiers: modifiers, in: alert.window)
            )
            XCTAssertEqual(recorder.pressed, expected, name, file: file, line: line)
        }
    }

    private func keyEvent(
        _ characters: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        in window: NSWindow
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}

/// Stands in for the alert's own target, so a pressed button is recorded
/// instead of ending a modal session that is not running.
private final class ButtonRecorder: NSObject {
    var pressed: [String] = []

    init(_ alert: NSAlert) {
        super.init()
        for button in alert.buttons {
            button.target = self
            button.action = #selector(press(_:))
        }
    }

    @objc private func press(_ sender: NSButton) {
        pressed.append(sender.title)
    }
}
