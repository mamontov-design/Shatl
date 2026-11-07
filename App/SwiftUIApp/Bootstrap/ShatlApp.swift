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
                usageTelemetrySender: environment.usageTelemetrySender,
                physicalNetworkMonitor: environment.physicalNetworkMonitor
            )
        )
    }

    var body: some Scene {
        // Shatl must have exactly one main window.
        // WindowGroup can create new scene instances, but external torrent or magnet
        // opening would then produce multiple unwanted windows.
        Window("Shatl", id: AppWindowID.main) {
            // The 440 × 448 minimum belongs to the list's content, not to
            // the onboarding: see `MainWindowView`.
            mainWindowContent
                .windowFullScreenBehavior(.disabled)
        }
        .defaultSize(width: 440, height: 448)
        // The window follows its content: the onboarding's fixed size keeps
        // it fixed, the list stretches it from 440 × 448.
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            ShatlCommands(store: store)
        }

        // Opened only by the add flow: no item in the Window menu, which would
        // open a review window with no draft that closes itself at once.
        Window("add_torrent.title", id: AppWindowID.addTorrentReview) {
            AddTorrentReviewWindowRoot()
                .environmentObject(store)
                .environmentObject(accentState)
                .environment(\.locale, store.preferences.localeOverride.swiftUILocale)
                .shatlTypographyProfile(localeOverride: store.preferences.localeOverride)
                .modifier(ShatlApplicationAppearanceModifier(theme: store.preferences.theme))
                .shatlMonochromeAppearance(store.preferences.usesMonochromeAppearance)
                .environment(\.shatlUsesSystemAccent, accentState.usesSystemAccent)
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
        .commandsRemoved()
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
                .shatlMonochromeAppearance(store.preferences.usesMonochromeAppearance)
                .environment(\.shatlUsesSystemAccent, accentState.usesSystemAccent)
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
                .environmentObject(updaterController)
                .environment(\.locale, store.preferences.localeOverride.swiftUILocale)
                .shatlTypographyProfile(localeOverride: store.preferences.localeOverride)
                .modifier(ShatlApplicationAppearanceModifier(theme: store.preferences.theme))
                .shatlMonochromeAppearance(store.preferences.usesMonochromeAppearance)
                .environment(\.shatlUsesSystemAccent, accentState.usesSystemAccent)
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

    var body: some View {
        AddTorrentReviewWindowContent(review: store.addTorrentReview)
    }
}

/// The subtitle names the draft, so the window watches the add window's
/// model; see `AddTorrentReviewModel`.
private struct AddTorrentReviewWindowContent: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var review: AddTorrentReviewModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        AddTorrentReviewView()
            // SwiftUI keeps the scene's title in step; on macOS 26 it also
            // cleared a subtitle set only through AppKit, leaving the room
            // for it empty. Given here too, the torrent's name stays.
            .navigationTitle(reviewWindowTitle)
            .navigationSubtitle(reviewWindowSubtitle)
            // Outside the review itself, which a message disables: the
            // arrows lead away from a message too.
            .toolbar {
                if review.isBatch {
                    ToolbarItem(placement: .navigation) {
                        downloadNavigation
                    }
                }
            }
            // The files are shown from under a cover of this colour; see
            // `AddTorrentReviewView`.
            .containerBackground(ShatlColor.backgroundAddWindow, for: .window)
            .background {
                AddTorrentReviewWindowChromeConfigurator(
                    title: reviewWindowTitle,
                    subtitle: reviewWindowSubtitle,
                    shouldClose: reviewWindowShouldClose,
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

    private var reviewWindowTitle: String {
        review.isBatch
            ? L10n.string(
                "add_torrent.title.several",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Добавление нескольких загрузок"
            )
            : L10n.string(
                "add_torrent.title",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Добавление загрузки"
            )
    }

    /// One download needs no subtitle: its name heads the file tree, and the
    /// message in the window says when it is still read. Several say which
    /// one is on screen (the owner's decision, November 2026). A subtitle
    /// that came and went would move the title up and down.
    private var reviewWindowSubtitle: String {
        guard review.isBatch else { return "" }
        // The last one waiting, not a bare "1 of 1": it says why the title
        // still speaks of several while one is shown.
        if review.count == 1 {
            return L10n.string(
                "add_torrent.review.one_left",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Осталась одна загрузка"
            )
        }
        return L10n.format(
            "add_torrent.review.position",
            localeOverride: store.preferences.localeOverride,
            defaultValue: "%lld / %lld",
            review.position,
            review.count
        )
    }

    /// Previous and next download, in one group as Finder's back and
    /// forward, but with arrows rather than chevrons: they move through the
    /// downloads waiting here, not back through what was seen.
    private var downloadNavigation: some View {
        let localeOverride = store.preferences.localeOverride
        let previousTitle = L10n.string(
            "add_torrent.review.previous",
            localeOverride: localeOverride,
            defaultValue: "Предыдущая загрузка"
        )
        let nextTitle = L10n.string(
            "add_torrent.review.next",
            localeOverride: localeOverride,
            defaultValue: "Следующая загрузка"
        )
        return ControlGroup {
            Button {
                review.showPrevious()
            } label: {
                Label(previousTitle, systemImage: "arrow.backward")
            }
            .help(previousTitle)
            .disabled(!review.hasPrevious)

            Button {
                review.showNext()
            } label: {
                Label(nextTitle, systemImage: "arrow.forward")
            }
            .help(nextTitle)
            .disabled(!review.hasNext)
        }
        .controlGroupStyle(.navigation)
    }

    private func finishReviewWindowClosure() {
        store.addTorrentReviewWindowDidClose()
    }

    /// The close button and ⌘W ask first when closing would lose work —
    /// downloads still waiting, or a choice of files made here; see
    /// `AddTorrentReviewModel.ClosingLoss`. The window stays while the
    /// question is on screen, and the answer closes it, keeps it, or saves
    /// what waits to the list first.
    private func reviewWindowShouldClose(_ window: NSWindow) -> Bool {
        guard let loss = review.closingLoss else { return true }
        Task { @MainActor in
            let answer = await AddTorrentCloseQuestion.ask(
                about: loss,
                localeOverride: store.preferences.localeOverride,
                window: window
            )
            switch answer {
            case .goBack:
                break
            case .saveToList:
                // The focus leaves before the window does; see
                // `AddTorrentReviewWindowFocus`.
                window.makeFirstResponder(nil)
                store.saveWaitingDraftsToList()
            case .close:
                window.makeFirstResponder(nil)
                store.dismissModal()
            }
        }
        return false
    }
}

private struct AddTorrentReviewWindowChromeConfigurator: NSViewRepresentable {
    let title: String
    let subtitle: String
    let shouldClose: (NSWindow) -> Bool
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(shouldClose: shouldClose, onClose: onClose)
    }

    func makeNSView(context: Context) -> ChromeNSView {
        let view = ChromeNSView()
        view.coordinator = context.coordinator
        view.title = title
        view.subtitle = subtitle
        return view
    }

    func updateNSView(_ nsView: ChromeNSView, context: Context) {
        context.coordinator.shouldClose = shouldClose
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
        var shouldClose: (NSWindow) -> Bool
        var onClose: () -> Void
        private weak var observedWindow: NSWindow?
        private var closeObservation: NSObjectProtocol?

        init(shouldClose: @escaping (NSWindow) -> Bool, onClose: @escaping () -> Void) {
            self.shouldClose = shouldClose
            self.onClose = onClose
        }

        func observe(_ window: NSWindow) {
            guardClosing(of: window)
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

        /// The close button and ⌘W ask this coordinator first; see
        /// `AddTorrentReviewWindowCloseGuard`. Run each time the window is
        /// laid out, so a delegate SwiftUI sets anew is wrapped as well.
        private func guardClosing(of window: NSWindow) {
            AddTorrentReviewWindowCloseGuard.install(on: window) { [weak self] window in
                self?.shouldClose(window) ?? true
            }
        }

        isolated deinit {
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
