// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit

/// Runs instead of `ShatlApp` when another copy owns the data folder. It
/// builds no store and no windows and never touches the session.
enum ShatlSecondaryInstance {
    static func run(handoff: ShatlSecondaryInstanceHandoff) -> Never {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = ShatlSecondaryInstanceDelegate(handoff: handoff)
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
        exit(0)
    }
}

/// What a second copy does with its launch. Torrents and magnet links go
/// straight to the running copy: the user opened a torrent, not a second
/// Shatl. A plain launch first says that Shatl is already running, then brings
/// the running copy forward.
struct ShatlSecondaryInstanceHandoff {
    var holder: SingleInstanceHolder?
    var openURLs: (_ urls: [URL], _ applicationURL: URL, _ completion: @escaping () -> Void) -> Void
    var reopenApplication: (_ applicationURL: URL, _ completion: @escaping () -> Void) -> Void
    /// Other running copies, for a holder that has not written its record yet.
    var runningCopyURLs: () -> [URL]
    var presentAlreadyRunningNotice: () -> Void

    func run(urls: [URL], completion: @escaping () -> Void) {
        let applicationURL = holder.map { URL(fileURLWithPath: $0.bundlePath, isDirectory: true) }
            ?? runningCopyURLs().first

        if urls.isEmpty {
            presentAlreadyRunningNotice()
        }
        guard let applicationURL else {
            completion()
            return
        }

        // LaunchServices delivers open and reopen events to the copy at this
        // path, even when copies at other paths run too.
        if urls.isEmpty {
            reopenApplication(applicationURL, completion)
        } else {
            openURLs(urls, applicationURL, completion)
        }
    }

    static func live(holder: SingleInstanceHolder?) -> ShatlSecondaryInstanceHandoff {
        ShatlSecondaryInstanceHandoff(
            holder: holder,
            openURLs: { urls, applicationURL, completion in
                NSWorkspace.shared.open(
                    urls,
                    withApplicationAt: applicationURL,
                    configuration: activatingConfiguration()
                ) { _, _ in
                    DispatchQueue.main.async(execute: completion)
                }
            },
            reopenApplication: { applicationURL, completion in
                NSWorkspace.shared.openApplication(
                    at: applicationURL,
                    configuration: activatingConfiguration()
                ) { _, _ in
                    DispatchQueue.main.async(execute: completion)
                }
            },
            runningCopyURLs: {
                NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                    .filter { $0.processIdentifier != getpid() }
                    .compactMap(\.bundleURL)
            },
            presentAlreadyRunningNotice: {
                ShatlAlreadyRunningNotice.present(
                    localeOverride: AppEnvironment.livePreferencesStore.load().localeOverride
                )
            }
        )
    }

    private static func activatingConfiguration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return configuration
    }
}

final class ShatlSecondaryInstanceDelegate: NSObject, NSApplicationDelegate {
    /// Open events of a launch arrive around `applicationDidFinishLaunching`;
    /// the pause also catches a magnet link that comes right after it.
    static let openEventGracePeriod: TimeInterval = 0.3
    /// Quits even if LaunchServices never answers.
    static let handoffTimeout: TimeInterval = 10

    private let handoff: ShatlSecondaryInstanceHandoff
    private var pendingURLs: [URL] = []
    private var didHandOff = false

    init(handoff: ShatlSecondaryInstanceHandoff) {
        self.handoff = handoff
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.openEventGracePeriod) { [self] in
            handOff()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receive(urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        receive(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    private func receive(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard didHandOff else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        handoff.run(urls: urls) {}
    }

    private func handOff() {
        didHandOff = true
        let urls = pendingURLs
        pendingURLs.removeAll()
        handoff.run(urls: urls) {
            NSApp.terminate(nil)
        }
        // Armed after the notice, so it never closes the notice under the user.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handoffTimeout) {
            NSApp.terminate(nil)
        }
    }
}

/// A plain launch of a second copy tells the user why no new window opened.
enum ShatlAlreadyRunningNotice {
    static func present(localeOverride: AppLocaleOverride) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.string(
            "single_instance.already_running.title",
            localeOverride: localeOverride,
            defaultValue: "Shatl уже запущен"
        )
        alert.informativeText = L10n.string(
            "single_instance.already_running.message",
            localeOverride: localeOverride,
            defaultValue: "Одновременно может работать только один Shatl, поэтому эта копия закроется. Нажмите «ОК», чтобы перейти к уже открытому."
        )
        alert.addButton(
            withTitle: L10n.string(
                "common.ok",
                localeOverride: localeOverride,
                defaultValue: "ОК"
            )
        )

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
