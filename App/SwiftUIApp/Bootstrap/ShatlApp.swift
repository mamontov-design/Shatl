import AppKit
import SwiftUI

@main
struct ShatlApp: App {
    @NSApplicationDelegateAdaptor(ShatlAppDelegate.self) private var appDelegate
    @StateObject private var store: AppStore
    @StateObject private var accentState = ShatlAccentState()

    init() {
        #if DEBUG
        if Self.isRunningInsideXcodePreview {
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

    #if DEBUG
    private static var isRunningInsideXcodePreview: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }
    #endif

    var body: some Scene {
        // Shatl must have exactly one main window.
        // WindowGroup can create new scene instances, but external torrent or magnet
        // opening would then produce multiple unwanted windows.
        Window("Shatl", id: "main") {
            MainWindowView()
                .environmentObject(store)
                .environmentObject(accentState)
                .environment(\.locale, store.preferences.localeOverride.swiftUILocale)
                .shatlTypographyProfile(localeOverride: store.preferences.localeOverride)
                .modifier(ShatlApplicationAppearanceModifier(theme: store.preferences.theme))
                .onAppear {
                    appDelegate.terminationHandler = store
                    appDelegate.userAttentionHandler = store
                    store.setApplicationUserAttentionActive(NSApp.isActive)
                }
                .frame(minWidth:440, minHeight: 440)
        }
        .defaultSize(width: 496, height: 440)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            ShatlCommands(store: store)
        }

        Settings {
            ShatlSettingsView()
                .environmentObject(store)
                .environmentObject(accentState)
                .environment(\.locale, store.preferences.localeOverride.swiftUILocale)
                .shatlTypographyProfile(localeOverride: store.preferences.localeOverride)
                .modifier(ShatlApplicationAppearanceModifier(theme: store.preferences.theme))
                // Release width: 440.
                .frame(width: 440)
        }
        .windowResizability(.contentSize)
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
