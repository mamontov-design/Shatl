import AppKit
import UserNotifications

final class ShatlAppDelegate: NSObject, NSApplicationDelegate {
    weak var terminationHandler: (any ShatlTerminationPreparing)?
    weak var userAttentionHandler: (any ShatlUserAttentionHandling)?
    private var isPreparingForTermination = false
    private var windowObserver: NSObjectProtocol?
    private let notificationCenterDelegate = ShatlUserNotificationCenterDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSWindow.allowsAutomaticWindowTabbing = false
        UNUserNotificationCenter.current().delegate = notificationCenterDelegate

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in
                Self.configureWindowChrome(window)
            }
        }

        Task { @MainActor in
            NSApplication.shared.windows.forEach(Self.configureWindowChrome)
        }
    }

    deinit {
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
    }

    /// Closing the last window must not terminate the torrent client.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        _ = notification
        userAttentionHandler?.setApplicationUserAttentionActive(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        _ = notification
        userAttentionHandler?.setApplicationUserAttentionActive(false)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let terminationHandler, !isPreparingForTermination else {
            return .terminateNow
        }

        isPreparingForTermination = true
        Task { [weak self, weak sender] in
            await terminationHandler.prepareForTermination()
            self?.isPreparingForTermination = false
            sender?.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    /// Clicking the Dock icon should restore the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        userAttentionHandler?.clearUserEventBadge()

        if !flag {
            sender.activate(ignoringOtherApps: true)
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }

        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NSApp.activate(ignoringOtherApps: true)
        ExternalOpenRouter.shared.receive(urls: urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        NSApp.activate(ignoringOtherApps: true)
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        ExternalOpenRouter.shared.receive(urls: urls)
        sender.reply(toOpenOrPrint: .success)
    }

    static func configureWindowChrome(_ window: NSWindow) {
        guard window.title == "Shatl" else { return }

        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
    }
}

private final class ShatlUserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        _ = center
        _ = notification
        completionHandler([.banner, .sound])
    }
}
