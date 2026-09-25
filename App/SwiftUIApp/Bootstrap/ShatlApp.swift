// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// Started by `ShatlMain` once this copy owns the data folder.
struct ShatlApp: App {
    @NSApplicationDelegateAdaptor(ShatlAppDelegate.self) private var appDelegate
    @StateObject private var store: AppStore
    @StateObject private var accentState = ShatlAccentState()
    @StateObject private var updaterController: ShatlUpdaterController

    init() {
        let launchMode = ShatlLaunchMode.current

        _updaterController = StateObject(
            wrappedValue: ShatlUpdaterController(
                startingUpdater: launchMode == .live
            )
        )

        #if DEBUG
        // Previews and the unit-test host get an inert store on temporary
        // folders, so they never load, clean or rewrite the user's session.
        if launchMode != .live {
            _store = StateObject(wrappedValue: AppEnvironment.previewStore())
            return
        }
        #endif

        let environment = AppEnvironment.live()
        _store = StateObject(
            wrappedValue: AppStore(
                engine: environment.engine,
                preferencesStore: environment.preferencesStore,
                sessionStore: environment.sessionStore,
                torrentArchiveStore: environment.torrentArchiveStore,
                bookmarkStore: environment.bookmarkStore,
                sessionRestoreCoordinator: environment.sessionRestoreCoordinator,
                diskIssueDetector: environment.diskIssueDetector,
                torrentPayloadLocator: environment.torrentPayloadLocator,
                torrentPayloadDeletionService: environment.torrentPayloadDeletionService,
                externalOpenRouter: environment.externalOpenRouter,
                userEventNotifier: environment.userEventNotifier,
                userEventBadgeDisplay: environment.userEventBadgeDisplay,
                usageTelemetryCoordinator: environment.usageTelemetryCoordinator,
                usageTelemetrySender: environment.usageTelemetrySender
            )
        )
    }

    var body: some Scene {
        // Shatl must have exactly one main window.
        // WindowGroup can create new scene instances, but external torrent or magnet
        // opening would then produce multiple unwanted windows.
        Window("Shatl", id: "main") {
            mainWindowContent
                .frame(minWidth:440, minHeight: 440)
                .windowFullScreenBehavior(.disabled)
        }
        .defaultSize(width: 440, height: 440)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            ShatlCommands(store: store)
        }

        Window("Добавление загрузки", id: AppWindowID.addTorrentReview) {
            AddTorrentReviewWindowRoot()
                .environmentObject(store)
                .environmentObject(accentState)
                .environment(\.locale, store.preferences.localeOverride.swiftUILocale)
                .shatlTypographyProfile(localeOverride: store.preferences.localeOverride)
                .modifier(ShatlApplicationAppearanceModifier(theme: store.preferences.theme))
                .frame(
                    minWidth: AddTorrentReviewLayout.minimumWindowWidth,
                    minHeight: AddTorrentReviewLayout.minimumWindowHeight
                )
                .windowFullScreenBehavior(.disabled)
        }
        .defaultSize(
            width: AddTorrentReviewLayout.minimumWindowWidth,
            height: AddTorrentReviewLayout.minimumWindowHeight
        )
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            ShatlSettingsView()
                .environmentObject(store)
                .environmentObject(accentState)
                .environmentObject(updaterController)
                .environment(\.locale, store.preferences.localeOverride.swiftUILocale)
                .shatlTypographyProfile(localeOverride: store.preferences.localeOverride)
                .modifier(ShatlApplicationAppearanceModifier(theme: store.preferences.theme))
                // Release width: 440.
                .frame(width: 440)
                .windowFullScreenBehavior(.disabled)
        }
        .windowResizability(.contentSize)
    }

    /// The unit-test host shows an empty window: `MainWindowView` would
    /// bootstrap the store, ask for notifications and present onboarding.
    @ViewBuilder
    private var mainWindowContent: some View {
        if ShatlLaunchMode.current == .unitTestHost {
            Color.clear
        } else {
            MainWindowView()
                .environmentObject(store)
                .environmentObject(accentState)
                .environment(\.locale, store.preferences.localeOverride.swiftUILocale)
                .shatlTypographyProfile(localeOverride: store.preferences.localeOverride)
                .modifier(ShatlApplicationAppearanceModifier(theme: store.preferences.theme))
                .onAppear {
                    appDelegate.terminationHandler = store
                    appDelegate.userAttentionHandler = store
                    appDelegate.terminationFailurePresenter = ShatlTerminationAlertPresenter { [weak store = store] in
                        store?.preferences.localeOverride ?? .system
                    }
                    store.setApplicationUserAttentionActive(NSApp.isActive)
                }
        }
    }
}

private struct AddTorrentReviewWindowRoot: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        AddTorrentReviewView()
            .background {
                AddTorrentReviewWindowChromeConfigurator(
                    title: L10n.string(
                        "add_torrent.title",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Добавление загрузки"
                    ),
                    subtitle: reviewWindowSubtitle,
                    onClose: finishReviewWindowClosure
                )
                .frame(width: 0, height: 0)
            }
            .onAppear {
                guard !store.isAddTorrentReviewWindowActive else { return }
                dismissWindow(id: AppWindowID.addTorrentReview)
            }
            .onChange(of: store.presentedModal) { _, presentation in
                guard presentation != .addTorrentReview else { return }
                dismissWindow(id: AppWindowID.addTorrentReview)
            }
    }

    private var reviewWindowSubtitle: String {
        guard let draft = store.currentAddTorrentDraft else {
            return L10n.string(
                "add_torrent.loading_metadata",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Получение метаданных…"
            )
        }

        if draft.reviewState == .loadingMetadata {
            return L10n.string(
                "add_torrent.loading_metadata",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Получение метаданных…"
            )
        }

        if case .invalid = draft.reviewState {
            return ""
        }

        return draft.originalName
    }

    private func finishReviewWindowClosure() {
        store.addTorrentReviewWindowDidClose()
    }
}

private struct AddTorrentReviewWindowChromeConfigurator: NSViewRepresentable {
    let title: String
    let subtitle: String
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    func makeNSView(context: Context) -> ChromeNSView {
        let view = ChromeNSView()
        view.coordinator = context.coordinator
        view.title = title
        view.subtitle = subtitle
        return view
    }

    func updateNSView(_ nsView: ChromeNSView, context: Context) {
        context.coordinator.onClose = onClose
        nsView.title = title
        nsView.subtitle = subtitle
        nsView.applyToWindowIfAttached()
    }

    static func dismantleNSView(_ nsView: ChromeNSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class ChromeNSView: NSView {
        var title = ""
        var subtitle = ""
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyToWindowIfAttached()
        }

        func applyToWindowIfAttached() {
            guard let window else { return }
            coordinator?.observe(window)
            window.title = title
            window.subtitle = subtitle
            window.titleVisibility = .visible
            window.toolbarStyle = .unified
            window.titlebarSeparatorStyle = .line
        }
    }

    @MainActor
    final class Coordinator {
        var onClose: () -> Void
        private weak var observedWindow: NSWindow?
        private var closeObservation: NSObjectProtocol?

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func observe(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            stopObserving()
            observedWindow = window
            window.setFrameAutosaveName(AppWindowID.addTorrentReview)
            closeObservation = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onClose()
                }
            }
        }

        func stopObserving() {
            if let closeObservation {
                NotificationCenter.default.removeObserver(closeObservation)
            }
            closeObservation = nil
            observedWindow = nil
        }

        deinit {
            if let closeObservation {
                NotificationCenter.default.removeObserver(closeObservation)
            }
        }
    }
}

private extension AppLocaleOverride {
    var swiftUILocale: Locale {
        guard let localeIdentifier else {
            return .autoupdatingCurrent
        }

        return Locale(identifier: localeIdentifier)
    }
}

private struct ShatlApplicationAppearanceModifier: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        content
            .onAppear {
                ShatlApplicationAppearance.apply(theme)
            }
            .onChange(of: theme) { _, newTheme in
                ShatlApplicationAppearance.apply(newTheme)
            }
    }
}

private enum ShatlApplicationAppearance {
    static func apply(_ theme: AppTheme) {
        NSApp.appearance = theme.nsAppearance
    }
}

private extension AppTheme {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}
