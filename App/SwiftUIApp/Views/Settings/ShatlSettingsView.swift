// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

struct ShatlSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: SettingsTab = .downloads
    @State private var animatesPortStatusDot = false

    var body: some View {
        TabView(selection: $selectedTab) {
            downloadsTab
                .tabItem {
                    Label("settings.tab.downloads", systemImage: "arrow.up.and.down")
                }
                .tag(SettingsTab.downloads)

            appearanceTab
                .tabItem {
                    Label("settings.tab.appearance", systemImage: "bubbles.and.sparkles")
                }
                .tag(SettingsTab.appearance)

            dataTab
                .tabItem {
                    Label("settings.tab.data", systemImage: "chart.bar")
                }
                .tag(SettingsTab.data)

            aboutTab
                .tabItem {
                    Label("settings.tab.about", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)

            #if DEBUG
            debugTab
                .tabItem {
                    Label("settings.tab.debug", systemImage: "ladybug")
                }
                .tag(SettingsTab.debug)
            #endif
        }
        .onAppear {
            selectedTab = .downloads
        }
    }

    private var downloadsTab: some View {
        VStack(spacing: 8) {
            ShatlSettingsParameterHeader(localizedTitle: "settings.downloads.performance.section")

            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(AppPerformanceProfile.allCases) { profile in
                        ShatlSettingsInputCard(
                            localizedTitle: profile.settingsTitleKey,
                            isSelected: store.preferences.performanceProfile == profile,
                            imageContainerHeight: 100,
                            imageContentVerticalPadding: 26,
                            overlaysSelectionMark: true,
                            // Halo saves the battery.
                            titleSymbol: profile == .economical ? "leaf.fill" : nil,
                            titleSymbolColor: ShatlColor.haloLeaf
                        ) {
                            store.setPerformanceProfile(profile)
                        } content: {
                            ShatlPerformanceProfileSpeedometer(profile: profile)
                        }
                    }
                }

                VStack(spacing: 4) {
                    ShatlSettingsParameterCaption(
                        localizedLines: [
                            "settings.downloads.performance.caption.main",
                            "settings.downloads.performance.caption.economical",
                        ]
                    )

                    #if DEBUG
                    EngineResourceBudgetCaption()
                    #endif
                }
            }

            ShatlSettingsParameterHeader(localizedTitle: "settings.downloads.folder.section")

            ShatlSettingsParameter {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(defaultDownloadFolderName)
                            .shatlTypography(ShatlTypography.bodyRegular)
                            .foregroundStyle(ShatlColor.typographyPrimary)
                            .lineLimit(1)

                        Text(store.preferences.defaultDownloadPath)
                            .shatlTypography(ShatlTypography.bodyRegular)
                            .foregroundStyle(ShatlColor.typographySecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ShatlButton(localizedTitle: "common.change", role: .borderedNeutral) {
                        presentDefaultDownloadFolderPicker()
                    }
                }
            }

            ShatlSettingsParameterHeader(localizedTitle: "settings.downloads.network.section")

            ShatlSettingsParameter {
                ShatlSettingsToggleRow(
                    localizedTitle: "settings.downloads.network.port_forwarding",
                    isOn: Binding(
                        get: { store.preferences.opensRouterPortAutomatically },
                        set: { store.setOpensRouterPortAutomatically($0) }
                    ),
                    statusDot: portStatusDot,
                    animatesStatusDot: animatesPortStatusDot
                )
            }
            .task {
                // The first answer puts the dot in place; later ones animate.
                await store.refreshPortForwardingIndicator()
                animatesPortStatusDot = true
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    await store.refreshPortForwardingIndicator()
                }
            }
            .onDisappear {
                animatesPortStatusDot = false
            }

            VStack(spacing: 4) {
                ShatlSettingsParameterCaption(localizedText: "settings.downloads.network.port_forwarding.caption")

                #if DEBUG
                if store.preferences.opensRouterPortAutomatically {
                    PortMappingStatusCaption()
                }
                #endif
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 16)
        .animation(ShatlMotion.cardState, value: store.preferences.performanceProfile)
    }

    private var appearanceTab: some View {
        AppearanceSettingsTab()
    }

    private var aboutTab: some View {
        AboutSettingsTab()
    }

    private var dataTab: some View {
        DataSettingsTab()
    }

    #if DEBUG
    private var debugTab: some View {
        VStack(spacing: 8) {
            ShatlSettingsParameterHeader(localizedTitle: "settings.localization.section")

            ShatlSettingsParameter {
                Picker(
                    selection: binding(for: \.localeOverride)
                ) {
                    ForEach(AppLocaleOverride.allCases) { localeOverride in
                        Text(LocalizedStringKey(localeOverride.settingsTitleKey))
                            .tag(localeOverride)
                    }
                } label: {
                    Text("settings.localization.app_language")
                        .shatlTypography(ShatlTypography.bodyRegular)
                        .foregroundStyle(ShatlColor.typographyPrimary)
                }
                .pickerStyle(.radioGroup)
            }

            ShatlSettingsParameterCaption(localizedText: "settings.localization.caption")

            ShatlSettingsParameterHeader(localizedTitle: "settings.debug.logging.section")

            ShatlSettingsParameter {
                ShatlSettingsToggleRow(
                    localizedTitle: "settings.debug.logging.app",
                    isOn: binding(for: \.isLoggingEnabled)
                )

                ShatlSettingsParameterDivider()

                ShatlSettingsToggleRow(
                    localizedTitle: "settings.debug.logging.disk_diagnostics",
                    isOn: binding(for: \.isDiskDiagnosticsLoggingEnabled)
                )

                ShatlSettingsParameterDivider()

                ShatlSettingsToggleRow(
                    localizedTitle: "settings.debug.logging.metric_animation_diagnostics",
                    isOn: binding(for: \.isMetricAnimationDiagnosticsLoggingEnabled)
                )

                ShatlSettingsParameterDivider()

                ShatlSettingsToggleRow(
                    localizedTitle: "settings.debug.logging.snapshot_diagnostics",
                    isOn: binding(for: \.isSnapshotDiagnosticsLoggingEnabled)
                )

                ShatlSettingsParameterDivider()

                ShatlSettingsToggleRow(
                    localizedTitle: "settings.debug.logging.add_torrent_review_diagnostics",
                    isOn: binding(for: \.isAddTorrentReviewDiagnosticsLoggingEnabled)
                )

                ShatlSettingsParameterDivider()

                ShatlSettingsToggleRow(
                    localizedTitle: "settings.debug.logging.card_layout_diagnostics",
                    isOn: binding(for: \.isCardLayoutDiagnosticsLoggingEnabled)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 16)
    }

    private func binding<Value>(for keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { store.preferences[keyPath: keyPath] },
            set: { store.preferences[keyPath: keyPath] = $0 }
        )
    }
    #endif

    private var portStatusDot: ShatlSettingsStatusDot? {
        let localeOverride = store.preferences.localeOverride
        switch store.portForwardingIndicator {
        case .hidden:
            return nil
        case .checking:
            return ShatlSettingsStatusDot(
                color: ShatlColor.portStatusChecking,
                description: L10n.string("settings.downloads.network.port_status.checking", localeOverride: localeOverride)
            )
        case .open:
            return ShatlSettingsStatusDot(
                color: ShatlColor.portStatusOpen,
                description: L10n.string("settings.downloads.network.port_status.open", localeOverride: localeOverride)
            )
        case .closed:
            return ShatlSettingsStatusDot(
                color: ShatlColor.portStatusClosed,
                description: L10n.string("settings.downloads.network.port_status.closed", localeOverride: localeOverride)
            )
        }
    }

    /// As Finder names it: "Загрузки", not the "Downloads" on disk, as the
    /// add window shows it.
    private var defaultDownloadFolderName: String {
        let path = store.preferences.defaultDownloadPath
        let name = ShatlErrorCatalog.folderDisplayName(forPath: path)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? path : name
    }

    private func presentDefaultDownloadFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.string("common.choose", localeOverride: store.preferences.localeOverride)

        if FileManager.default.fileExists(atPath: store.preferences.defaultDownloadPath) {
            panel.directoryURL = URL(fileURLWithPath: store.preferences.defaultDownloadPath, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        store.setDefaultDownloadLocation(url, bookmarkData: bookmarkData)
    }
}

#if DEBUG
/// Debug builds only: the open-file limit the engine runs within, what the
/// profile gets under it and how many descriptors are open, refreshed every
/// 2 s while the Downloads tab is shown.
private struct EngineResourceBudgetCaption: View {
    @EnvironmentObject private var store: AppStore
    @State private var budget: EngineResourceBudget?

    var body: some View {
        ShatlSettingsParameterCaption(text: text)
            .task {
                while !Task.isCancelled {
                    budget = await store.engineResourceBudget()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
    }

    private var text: String {
        let localeOverride = store.preferences.localeOverride
        guard let budget else {
            return L10n.string("settings.debug.performance.engine_not_started", localeOverride: localeOverride)
        }

        let locale = L10n.locale(for: localeOverride)
        func number(_ value: Int) -> String {
            value.formatted(.number.locale(locale))
        }

        if budget.isReduced {
            return L10n.format(
                "settings.debug.performance.budget_reduced",
                localeOverride: localeOverride,
                defaultValue: "%1$@ %2$@ %3$@ %4$@ %5$@ %6$@ %7$@",
                number(budget.openFileLimit),
                number(budget.initialOpenFileLimit),
                number(budget.connectionsLimit),
                number(budget.requestedConnectionsLimit),
                number(budget.filePoolSize),
                number(budget.requestedFilePoolSize),
                number(budget.openFileCount)
            )
        }

        return L10n.format(
            "settings.debug.performance.budget",
            localeOverride: localeOverride,
            defaultValue: "%1$@ %2$@ %3$@ %4$@ %5$@",
            number(budget.openFileLimit),
            number(budget.initialOpenFileLimit),
            number(budget.connectionsLimit),
            number(budget.filePoolSize),
            number(budget.openFileCount)
        )
    }
}
#endif

#if DEBUG
/// Debug builds only: whether the router opened a port, refreshed every 2 s
/// while the Downloads tab is shown.
private struct PortMappingStatusCaption: View {
    @EnvironmentObject private var store: AppStore
    @State private var status: EnginePortMappingStatus?

    var body: some View {
        ShatlSettingsParameterCaption(text: text)
            .task {
                while !Task.isCancelled {
                    status = await store.enginePortMappingStatus()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
    }

    private var text: String {
        let localeOverride = store.preferences.localeOverride
        switch status {
        case nil, .off:
            return L10n.string("settings.debug.performance.engine_not_started", localeOverride: localeOverride)
        case .mapped(let externalPort, let transport):
            return L10n.format(
                "settings.debug.network.port.mapped",
                localeOverride: localeOverride,
                defaultValue: "%1$@ %2$@",
                String(externalPort),
                transport
            )
        case .searching(_, let lastError):
            guard PortForwardingIndicator(isEnabled: true, status: status) == .closed else {
                return L10n.string("settings.debug.network.port.searching", localeOverride: localeOverride)
            }
            return L10n.format(
                "settings.debug.network.port.failed",
                localeOverride: localeOverride,
                defaultValue: "%1$@ %2$@",
                lastError?.transport ?? "—",
                lastError?.reason ?? "—"
            )
        }
    }
}
#endif

private enum SettingsTab {
    case downloads
    case appearance
    case data
    case about
    #if DEBUG
    case debug
    #endif
}

private struct DataSettingsTab: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 8) {
            ShatlSettingsParameterHeader(localizedTitle: "settings.data.section")

            ShatlSettingsParameter {
                ShatlSettingsToggleRow(
                    localizedTitle: "settings.data.help_development",
                    isOn: Binding(
                        get: { store.preferences.sendsAnonymousUsageStatistics },
                        set: { store.setSendsAnonymousUsageStatistics($0) }
                    )
                )

                ShatlSettingsParameterDivider()

                DataCollectionInfo()
                    .opacity(store.preferences.sendsAnonymousUsageStatistics ? 1 : 0.25)
            }

            ShatlSettingsParameterCaption(
                localizedLines: [
                    "settings.data.caption",
                    "settings.data.caption.technical",
                ]
            )
                .padding(.bottom, 8)

            ShatlSettingsParameter {
                sentDataRow

                ShatlSettingsParameterDivider()

                Text(statusText)
                    .shatlTypography(ShatlTypography.bodyRegular)
                    .foregroundStyle(ShatlColor.typographyPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 16)
        .animation(ShatlMotion.cardState, value: store.preferences.sendsAnonymousUsageStatistics)
        .animation(ShatlMotion.cardState, value: store.preferences.lastUsageStatisticsSentAt)
    }

    private var sentDataRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("settings.data.sent_data")
                    .shatlTypography(ShatlTypography.bodyRegular)
                    .foregroundStyle(ShatlColor.typographyPrimary)
                    .opacity(store.preferences.sendsAnonymousUsageStatistics ? 1 : 0.5)
                    .fixedSize(horizontal: false, vertical: true)

                Text("settings.data.sent_data.description")
                    .shatlTypography(ShatlTypography.bodyRegular)
                    .foregroundStyle(ShatlColor.typographySecondary)
                    .opacity(store.preferences.sendsAnonymousUsageStatistics ? 1 : 0.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ShatlButton(
                localizedTitle: "settings.data.sent_data.show",
                role: .borderedNeutral,
                isDisabled: !store.preferences.sendsAnonymousUsageStatistics
            ) {
                revealInspectablePayload()
            }
        }
    }

    private var statusText: String {
        let status = UsageTelemetrySendStatusFormatter.status(
            lastSentAt: store.preferences.lastUsageStatisticsSentAt,
            isEnabled: store.preferences.sendsAnonymousUsageStatistics
        )
        let localeOverride = store.preferences.localeOverride

        switch status {
        case .neverSent(let isEnabled):
            if isEnabled {
                return L10n.string(
                    "settings.data.status.never_sent.enabled",
                    localeOverride: localeOverride
                )
            }

            return L10n.string(
                "settings.data.status.never_sent.disabled",
                localeOverride: localeOverride
            )
        case .sentToday(let isEnabled):
            return statusString(
                isEnabled: isEnabled,
                enabledKey: "settings.data.status.sent_today.enabled",
                disabledKey: "settings.data.status.sent_today.disabled"
            )
        case .sentYesterday(let isEnabled):
            return statusString(
                isEnabled: isEnabled,
                enabledKey: "settings.data.status.sent_yesterday.enabled",
                disabledKey: "settings.data.status.sent_yesterday.disabled"
            )
        case .sentTwoDaysAgo(let isEnabled):
            return statusString(
                isEnabled: isEnabled,
                enabledKey: "settings.data.status.sent_two_days_ago.enabled",
                disabledKey: "settings.data.status.sent_two_days_ago.disabled"
            )
        case .sentEarlier(let daysAgo, let date, let isEnabled):
            let relativeDate = relativeDateText(daysAgo: daysAgo)
            let dayAndMonth = dayAndMonthText(for: date)
            let key = isEnabled
                ? "settings.data.status.sent_earlier.enabled"
                : "settings.data.status.sent_earlier.disabled"

            return L10n.format(
                key,
                localeOverride: localeOverride,
                defaultValue: "%@ (%@)",
                relativeDate,
                dayAndMonth
            )
        }
    }

    private func statusString(isEnabled: Bool, enabledKey: String, disabledKey: String) -> String {
        L10n.string(
            isEnabled ? enabledKey : disabledKey,
            localeOverride: store.preferences.localeOverride
        )
    }

    private func relativeDateText(daysAgo: Int) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale(for: store.preferences.localeOverride)
        formatter.unitsStyle = .full
        return formatter.localizedString(from: DateComponents(day: -daysAgo))
    }

    private func dayAndMonthText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale(for: store.preferences.localeOverride)
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter.string(from: date)
    }

    private func revealInspectablePayload() {
        guard let url = store.ensureUsageTelemetryInspectablePayload() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

enum DataCollectionInfoStyle {
    case settings
    case onboarding
}

struct DataCollectionInfo: View {
    let style: DataCollectionInfoStyle

    @EnvironmentObject private var accentState: ShatlAccentState

    init(style: DataCollectionInfoStyle = .settings) {
        self.style = style
    }

    var body: some View {
        HStack(alignment: .top, spacing: style == .onboarding ? 16 : 10) {
            DataCollectionCard(
                group: .collects,
                iconColor: collectsIconColor
            )

            DataCollectionCard(
                group: .doesNotCollect,
                iconColor: doesNotCollectIconColor
            )
        }
        .frame(maxWidth: style == .onboarding ? .infinity : nil)
    }

    private var collectsIconColor: Color {
        accentState.isUsingAppAccent
            ? ShatlColor.neonBlue
            : accentState.systemAccentColor
    }

    private var doesNotCollectIconColor: Color {
        accentState.isUsingAppAccent
            ? ShatlColor.neonBlue
            : ShatlColor.slate
    }
}

private struct DataCollectionCard: View {
    let group: DataCollectionGroup
    let iconColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(group.titleKey))
                .shatlTypography(ShatlTypography.bodySemibold)
                .foregroundStyle(ShatlColor.typographyPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.items) { item in
                    DataCollectionChecklistItem(
                        item: item,
                        iconColor: iconColor
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DataCollectionChecklistItem: View {
    let item: DataCollectionItem
    let iconColor: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Image(systemName: item.group.symbolName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(iconColor)
                .frame(width: 16, alignment: .center)

            Text(LocalizedStringKey(item.titleKey))
                .shatlTypography(ShatlTypography.bodyRegular)
                .foregroundStyle(ShatlColor.typographyPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum DataCollectionGroup: CaseIterable {
    case collects
    case doesNotCollect

    var titleKey: String {
        switch self {
        case .collects:
            "settings.data.collects.title"
        case .doesNotCollect:
            "settings.data.does_not_collect.title"
        }
    }

    var items: [DataCollectionItem] {
        switch self {
        case .collects:
            [.launchCount, .appVersion, .interfaceLanguage]
        case .doesNotCollect:
            [.torrentsAndLinks, .fileNamesAndPaths, .fileContents]
        }
    }

    var symbolName: String {
        switch self {
        case .collects:
            "checkmark.circle.fill"
        case .doesNotCollect:
            "xmark.circle"
        }
    }

}

/// Each fits one line of its column in Settings, 169 pt in every language:
/// `StatisticsCopyTests`.
enum DataCollectionItem: CaseIterable, Identifiable {
    case launchCount
    case appVersion
    case interfaceLanguage
    case torrentsAndLinks
    case fileNamesAndPaths
    case fileContents

    var id: Self { self }

    var group: DataCollectionGroup {
        switch self {
        case .launchCount, .appVersion, .interfaceLanguage:
            .collects
        case .torrentsAndLinks, .fileNamesAndPaths, .fileContents:
            .doesNotCollect
        }
    }

    var titleKey: String {
        switch self {
        case .launchCount:
            "settings.data.collects.launch_count"
        case .appVersion:
            "settings.data.collects.app_version"
        case .interfaceLanguage:
            "settings.data.collects.interface_language"
        case .torrentsAndLinks:
            "settings.data.does_not_collect.torrents_and_links"
        case .fileNamesAndPaths:
            "settings.data.does_not_collect.file_names_and_paths"
        case .fileContents:
            "settings.data.does_not_collect.file_contents"
        }
    }
}

private struct AboutSettingsTab: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var updaterController: ShatlUpdaterController

    var body: some View {
        VStack(spacing: 8) {
            aboutWordmarkContainer

            ShatlSettingsParameter {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.about.application_version")
                            .shatlTypography(ShatlTypography.bodyRegular)
                            .foregroundStyle(ShatlColor.typographyPrimary)
                            .lineLimit(1)

                        Text(appVersion)
                            .shatlTypography(ShatlTypography.bodyRegular)
                            .foregroundStyle(ShatlColor.typographySecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ShatlButton(
                        localizedTitle: "settings.about.check_updates",
                        role: .borderedNeutral,
                        isDisabled: !updaterController.canCheckForUpdates
                    ) {
                        updaterController.checkForUpdates()
                    }
                }

                ShatlSettingsParameterDivider()

                ShatlSettingsToggleRow(
                    localizedTitle: "settings.about.check_for_updates_automatically",
                    isOn: Binding(
                        get: { updaterController.automaticallyChecksForUpdates },
                        set: { updaterController.setAutomaticallyChecksForUpdates($0) }
                    )
                )

                ShatlSettingsParameterDivider()

                ShatlSettingsToggleRow(
                    localizedTitle: "settings.about.install_updates_automatically",
                    isOn: Binding(
                        get: { updaterController.automaticallyInstallsUpdates },
                        set: { updaterController.setAutomaticallyInstallsUpdates($0) }
                    ),
                    isEnabled: updaterController.allowsAutomaticUpdates
                )
            }

            ShatlSettingsParameterHeader(localizedTitle: "settings.about.contact_section")

            ShatlSettingsParameter {
                HStack(spacing: 16) {
                    Text("settings.about.contact_row")
                        .shatlTypography(ShatlTypography.bodyRegular)
                        .foregroundStyle(ShatlColor.typographyPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    ShatlButton(localizedTitle: "settings.about.write", role: .borderedNeutral) {
                        composeFeedbackEmail()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 16)
        .animation(
            ShatlMotion.cardState,
            value: updaterController.automaticallyChecksForUpdates
        )
    }

    private var aboutWordmarkContainer: some View {
        VStack(alignment: .center, spacing: 12) {
            ShatlWordmark(
                renderingMode: .glass,
                selection: Binding(
                    get: { store.preferences.preferredBrandMark },
                    set: { store.setPreferredBrandMark($0) }
                )
            )

            Text("settings.about.logo.caption")
                .shatlTypography(ShatlTypography.bodyRegular)
                .foregroundStyle(ShatlColor.typographySecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func composeFeedbackEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "mamontov.design@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Shatl App Feedback"),
        ]

        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}

private extension AppPerformanceProfile {
    var settingsTitleKey: String {
        switch self {
        case .economical:
            "settings.downloads.performance.profile.economical"
        case .balanced:
            "settings.downloads.performance.profile.balanced"
        case .maximum:
            "settings.downloads.performance.profile.maximum"
        }
    }

    var speedometerLevel: ShatlPerformanceSpeedometerLevel {
        switch self {
        case .economical:
            .oneOfThree
        case .balanced:
            .twoOfThree
        case .maximum:
            .threeOfThree
        }
    }
}

struct ShatlPerformanceProfileSpeedometer: View {
    private enum Layout {
        static let speedometerSize: CGFloat = 48
    }

    let profile: AppPerformanceProfile

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var accentState: ShatlAccentState
    @State private var isWiggling = false

    var body: some View {
        ZStack {
            ShatlPerformanceSpeedometerTrackShape()
                .fill(trackColor)
                .frame(width: Layout.speedometerSize, height: Layout.speedometerSize)

            progressLayer

            ShatlPerformanceSpeedometerArrowShape(level: profile.speedometerLevel)
                .fill(ShatlColor.typographyPrimary, style: FillStyle(eoFill: true))
                .frame(width: Layout.speedometerSize, height: Layout.speedometerSize)
                .rotationEffect(.degrees(arrowRotation), anchor: .center)
                .shatlShadow(ShatlShadow.speedometerArrow)
                .animation(arrowAnimation, value: isWiggling)
        }
        .frame(width: Layout.speedometerSize, height: Layout.speedometerSize)
        .onAppear {
            isWiggling = !reduceMotion
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            isWiggling = !reduceMotion
        }
    }

    private var trackColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color(red: 63 / 255, green: 63 / 255, blue: 70 / 255).opacity(0.08)
    }

    private var progressLayer: some View {
        Rectangle()
            .fill(progressFillStyle)
            .frame(width: Layout.speedometerSize, height: Layout.speedometerSize)
            .mask {
                ShatlPerformanceSpeedometerProgressShape(level: profile.speedometerLevel)
                    .fill(Color.white)
                    .frame(width: Layout.speedometerSize, height: Layout.speedometerSize)
            }
    }

    private var progressFillStyle: AnyShapeStyle {
        guard accentState.isUsingAppAccent else {
            return AnyShapeStyle(accentState.systemAccentColor)
        }

        return AnyShapeStyle(
            AngularGradient(
                gradient: Gradient(stops: progressGradientStops),
                center: .center,
                startAngle: .degrees(90),
                endAngle: .degrees(450)
            )
        )
    }

    private var progressGradientStops: [Gradient.Stop] {
        let lighterPurple = Color(red: 190 / 255, green: 154 / 255, blue: 255 / 255)
        let darkerPurple = Color(red: 136 / 255, green: 95 / 255, blue: 255 / 255)

        return colorScheme == .dark
            ? [
                Gradient.Stop(color: darkerPurple, location: 0.08),
                Gradient.Stop(color: lighterPurple, location: 0.92),
            ]
            : [
                Gradient.Stop(color: lighterPurple, location: 0.08),
                Gradient.Stop(color: darkerPurple, location: 0.92),
            ]
    }

    private var arrowRotation: Double {
        guard !reduceMotion else { return 0 }
        return isWiggling ? 6 : -6
    }

    private var arrowAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
    }

}

private struct AppearanceSettingsTab: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var accentState: ShatlAccentState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var metricPreviewPulseTrigger = 0
    @State private var downloadSpeedPreviewPulseTrigger = 0
    @State private var isMetricsInfoPresented = false
    @State private var previewFocus: TorrentCardPreviewFocus?
    @State private var previewFocusReleaseTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 8) {
            previewCardContainer

            VStack(spacing: 8) {
                metricsModeSection
                themeSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(.top, 0)
        .onDisappear {
            previewFocusReleaseTask?.cancel()
            previewFocus = nil
        }
    }

    private var previewCardContainer: some View {
        VStack(spacing: 8) {
            TorrentCardPreviewView(
                localeOverride: store.preferences.localeOverride,
                metricsMode: store.preferences.metricsMode,
                colorizesDownloadSpeed: store.preferences.colorizesDownloadSpeed,
                downloadSpeedOutlineFlashTrigger: downloadSpeedPreviewPulseTrigger,
                initiallyExpanded: true,
                centersExpandedCard: true,
                allowsExpansionToggle: false,
                showsExpansionToggle: false,
                pulsesMetricSetOutlines: false,
                metricSetOutlineFlashTrigger: metricPreviewPulseTrigger,
                // The app's accent, or the one chosen in macOS.
                metricSetOutlineFlashColor: ShatlColor.accent,
                progressBarFillColorOverride: accentState.isUsingAppAccent ? nil : ShatlColor.typographyTertiary,
                usesProductionProgressColors: true,
                cardBackgroundColorOverride: colorScheme == .dark ? ShatlColor.cardDefault : nil,
                cardOutlineColorOverride: colorScheme == .light ? ShatlColor.outlinePrimary : nil,
                shadowStyle: .settings,
                cardWidth: nil,
                focus: previewFocus
            )
            .padding(.horizontal, 28)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
        // With the tab's spacing, 24 pt down to the toggles.
        .padding(.bottom, 16)
    }

    private var metricsModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShatlSettingsParameter {
                ShatlSettingsToggleRow(
                    localizedTitle: "settings.appearance.speed_colors.toggle",
                    isOn: Binding(
                        get: { store.preferences.colorizesDownloadSpeed },
                        set: {
                            store.preferences.colorizesDownloadSpeed = $0
                            downloadSpeedPreviewPulseTrigger += 1
                            focusPreview(on: .downloadSpeed)
                        }
                    )
                )

                ShatlSettingsParameterDivider()

                HStack(spacing: 16) {
                    Text("settings.appearance.metrics.toggle")
                        .shatlTypography(ShatlTypography.bodyRegular)
                        .foregroundStyle(ShatlColor.typographyPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        Button {
                            isMetricsInfoPresented = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(.tint)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(Text("settings.appearance.metrics.info.help"))
                        .accessibilityLabel(Text("settings.appearance.metrics.info.help"))
                        .popover(isPresented: $isMetricsInfoPresented) {
                            MetricsPresentationInfoPopover()
                        }

                        ShatlSettingsControlVerticalDivider()

                        Toggle("", isOn: simplifiedMetricsModeBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                }
            }

            ShatlSettingsParameterCaption(localizedText: "settings.appearance.metrics.caption")
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShatlSettingsParameterHeader(localizedTitle: "settings.appearance.theme.section")

            HStack(alignment: .top, spacing: 8) {
                ForEach(AppTheme.allCases) { theme in
                    ShatlSettingsInputCard(
                        localizedTitle: theme.settingsTitleKey,
                        isSelected: store.preferences.theme == theme,
                        imageContainerHeight: 74
                    ) {
                        store.preferences.theme = theme
                    } content: {
                        ThemeAppearanceDemo(
                            theme: theme
                        )
                    }
                }
            }
        }
    }

    private func selectMetricsMode(_ mode: MetricsPresentationMode) {
        store.preferences.metricsMode = mode
        metricPreviewPulseTrigger += 1
        focusPreview(on: .metrics)
    }

    /// Keeps the changed part of the preview sharp and blurs the rest while
    /// it flashes and four seconds after; every toggle starts the wait again.
    /// None with Reduce Motion, as there is no flash then either.
    private func focusPreview(on focus: TorrentCardPreviewFocus) {
        guard !reduceMotion else { return }

        previewFocus = focus
        previewFocusReleaseTask?.cancel()
        previewFocusReleaseTask = Task { @MainActor in
            try? await Task.sleep(for: ShatlMotion.previewFocusHold)
            guard !Task.isCancelled else { return }
            previewFocus = nil
        }
    }

    private var simplifiedMetricsModeBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.metricsMode == .simplified },
            set: { selectMetricsMode($0 ? .simplified : .detailed) }
        )
    }

}

private struct ShatlSettingsControlVerticalDivider: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(ShatlColor.outlineTertiary)
            .frame(width: 2, height: 16)
    }
}

private struct MetricsPresentationInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.appearance.metrics.popover.title")
                .shatlTypography(ShatlTypography.bodySemibold)
                .foregroundStyle(ShatlColor.typographyPrimary)
                .fixedSize(horizontal: false, vertical: true)

            popoverText("settings.appearance.metrics.popover.precision")
            popoverText("settings.appearance.metrics.popover.eta")
            popoverText("settings.appearance.metrics.popover.unchanged")
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
    }

    private func popoverText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .shatlTypography(ShatlTypography.bodyRegular)
            .foregroundStyle(ShatlColor.typographySecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThemeAppearanceDemo: View {
    let theme: AppTheme

    @EnvironmentObject private var accentState: ShatlAccentState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            themePreviewShadow

            ZStack {
                Image(theme.settingsCardAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)

                ShatlWindowButtonCloseShape()
                    .fill(accentState.isUsingAppAccent
                        ? Color(red: 244.0 / 255.0, green: 63.0 / 255.0, blue: 94.0 / 255.0)
                        : buttonColor)

                ShatlWindowButtonMinimizeShape()
                    .fill(accentState.isUsingAppAccent
                        ? Color(red: 234.0 / 255.0, green: 179.0 / 255.0, blue: 8.0 / 255.0)
                        : buttonColor)

                ShatlWindowButtonExpandShape()
                    .fill(accentState.isUsingAppAccent
                        ? Color(red: 34.0 / 255.0, green: 197.0 / 255.0, blue: 94.0 / 255.0)
                        : buttonColor)
            }
            .frame(width: 76, height: 76)
        }
        .frame(width: 110, height: 76)
        .frame(width: 110, height: 76, alignment: .top)
    }

    @ViewBuilder
    private var themePreviewShadow: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

        if colorScheme == .light {
            shape
                .fill(Color.white)
                .frame(width: 74, height: 74)
                .shatlShadow(ShatlShadow.themePreview)
        } else {
            shape
                .fill(Color.clear)
                .frame(width: 74, height: 74)
                .shatlShadow(ShatlShadow.themePreview)
        }
    }

    private var buttonColor: Color {
        if theme == .dark {
            return Color(
                red: 113.0 / 255.0,
                green: 113.0 / 255.0,
                blue: 122.0 / 255.0
            )
        }

        return Color(
            red: 212.0 / 255.0,
            green: 212.0 / 255.0,
            blue: 216.0 / 255.0
        )
    }
}

private extension AppTheme {
    var settingsTitleKey: String {
        switch self {
        case .system:
            "settings.appearance.theme.system"
        case .light:
            "settings.appearance.theme.light"
        case .dark:
            "settings.appearance.theme.dark"
        }
    }
}

private extension AppLocaleOverride {
    var settingsTitleKey: String {
        switch self {
        case .system:
            "settings.localization.language.system"
        case .english:
            "settings.localization.language.english"
        case .russian:
            "settings.localization.language.russian"
        case .german:
            "settings.localization.language.german"
        case .spanish:
            "settings.localization.language.spanish"
        case .french:
            "settings.localization.language.french"
        case .japanese:
            "settings.localization.language.japanese"
        case .simplifiedChinese:
            "settings.localization.language.simplified_chinese"
        }
    }
}

private extension AppTheme {
    var settingsCardAssetName: String {
        switch self {
        case .system:
            "settingsCardImageThemeAuto"
        case .light:
            "settingsCardImageThemeLight"
        case .dark:
            "settingsCardImageThemeDark"
        }
    }
}
