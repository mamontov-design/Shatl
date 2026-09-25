// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import CoreServices

/// Separates a quit the user asked for from a logout, restart or shutdown
/// requested by macOS. Shatl must never cancel the latter.
enum ShatlTerminationRequestSource: Equatable {
    case user
    case system

    private static let systemQuitReasons: Set<OSType> = [
        OSType(kAELogOut),
        OSType(kAEReallyLogOut),
        OSType(kAEShowRestartDialog),
        OSType(kAERestart),
        OSType(kAEShowShutdownDialog),
        OSType(kAEShutDown),
    ]

    init(quitReason: OSType?) {
        if let quitReason, Self.systemQuitReasons.contains(quitReason) {
            self = .system
        } else {
            self = .user
        }
    }

    /// Must be read synchronously inside `applicationShouldTerminate`,
    /// while the quit Apple event is still the current one.
    static func current(appleEventManager: NSAppleEventManager = .shared()) -> ShatlTerminationRequestSource {
        let quitReason = appleEventManager.currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?
            .typeCodeValue
        return ShatlTerminationRequestSource(quitReason: quitReason)
    }
}

enum ShatlTerminationSaveFailureChoice: Equatable {
    case retry
    case returnToApp
    case quitWithoutSaving
}

@MainActor
protocol ShatlTerminationFailurePresenting: AnyObject {
    func presentSessionSaveFailure() -> ShatlTerminationSaveFailureChoice
}

@MainActor
enum ShatlTerminationFlow {
    /// A failed session save must not trap the user in the app: they can
    /// retry, stay in Shatl, or quit with the last committed session on disk.
    /// A decided quit finishes with `finishTermination`, which stops the engine.
    static func resolve(
        handler: any ShatlTerminationPreparing,
        source: ShatlTerminationRequestSource,
        presenter: any ShatlTerminationFailurePresenting
    ) async -> Bool {
        let shouldTerminate = await decide(handler: handler, source: source, presenter: presenter)
        if shouldTerminate {
            await handler.finishTermination()
        }
        return shouldTerminate
    }

    private static func decide(
        handler: any ShatlTerminationPreparing,
        source: ShatlTerminationRequestSource,
        presenter: any ShatlTerminationFailurePresenting
    ) async -> Bool {
        while true {
            if await handler.prepareForTermination() {
                return true
            }

            // Logout, restart and shutdown keep the last committed session
            // instead of being cancelled by Shatl.
            guard source == .user else {
                return true
            }

            switch presenter.presentSessionSaveFailure() {
            case .retry:
                continue
            case .returnToApp:
                return false
            case .quitWithoutSaving:
                return true
            }
        }
    }
}

/// Uses an app-modal alert so it stays visible even when the main window is closed.
@MainActor
final class ShatlTerminationAlertPresenter: ShatlTerminationFailurePresenting {
    private let localeOverride: () -> AppLocaleOverride

    init(localeOverride: @escaping () -> AppLocaleOverride = { .system }) {
        self.localeOverride = localeOverride
    }

    func presentSessionSaveFailure() -> ShatlTerminationSaveFailureChoice {
        let localeOverride = localeOverride()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string(
            "session.persistence.save_failed.title",
            localeOverride: localeOverride,
            defaultValue: "Не удалось сохранить состояние загрузок"
        )
        alert.informativeText = L10n.string(
            "session.persistence.quit_dialog.message",
            localeOverride: localeOverride,
            defaultValue: "Скорее всего, на диске закончилось место или у Shatl нет доступа к папке с данными. Если выйти сейчас, последние изменения прогресса и статусов не сохранятся, и при следующем запуске Shatl может заново проверить часть скачанных данных. Скачанные файлы и список загрузок не пострадают."
        )

        // The first button is the default one, so Return retries the save.
        alert.addButton(
            withTitle: L10n.string(
                "session.persistence.quit_dialog.retry",
                localeOverride: localeOverride,
                defaultValue: "Повторить"
            )
        )
        let returnButton = alert.addButton(
            withTitle: L10n.string(
                "session.persistence.quit_dialog.return",
                localeOverride: localeOverride,
                defaultValue: "Вернуться в Shatl"
            )
        )
        returnButton.keyEquivalent = "\u{1b}"
        let quitButton = alert.addButton(
            withTitle: L10n.string(
                "session.persistence.quit_dialog.quit",
                localeOverride: localeOverride,
                defaultValue: "Выйти без сохранения"
            )
        )
        quitButton.hasDestructiveAction = true

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .retry
        case .alertThirdButtonReturn:
            return .quitWithoutSaving
        default:
            return .returnToApp
        }
    }
}
