import AppKit
import SwiftUI

struct ShatlSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: SettingsTab = .downloads

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
                            overlaysSelectionMark: true
                        ) {
                            store.setPerformanceProfile(profile)
                        } content: {
                            PerformanceProfileDemo(profile: profile)
                        }
                    }
                }

                ShatlSettingsParameterCaption(
                    localizedLines: [
                        "settings.downloads.performance.caption.main",
                        "settings.downloads.performance.caption.economical",
                    ]
                )
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

    private var performanceProfileBinding: Binding<AppPerformanceProfile> {
        Binding(
            get: { store.preferences.performanceProfile },
            set: { store.setPerformanceProfile($0) }
        )
    }

    private var defaultDownloadFolderName: String {
        let url = URL(fileURLWithPath: store.preferences.defaultDownloadPath, isDirectory: true)
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? store.preferences.defaultDownloadPath : name
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

private enum SettingsTab {
    case downloads
    case appearance
    case data
    case about
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

                DataCollectionInfo(
                    isAnimationEnabled: store.preferences.sendsAnonymousUsageStatistics
                )
                    .opacity(store.preferences.sendsAnonymousUsageStatistics ? 1 : 0.25)
            }

            ShatlSettingsParameterCaption(localizedText: "settings.data.caption")
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
    let isAnimationEnabled: Bool
    let style: DataCollectionInfoStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var accentState: ShatlAccentState
    @State private var highlightedItem: DataCollectionItem?
    @State private var nextHighlightGroup = DataCollectionGroup.collects
    @State private var highlightTask: Task<Void, Never>?

    private let highlightAnimation = Animation.easeInOut(duration: 0.6)

    init(
        isAnimationEnabled: Bool = true,
        style: DataCollectionInfoStyle = .settings
    ) {
        self.isAnimationEnabled = isAnimationEnabled
        self.style = style
    }

    var body: some View {
        HStack(alignment: .top, spacing: style == .onboarding ? 0 : 10) {
            DataCollectionCard(
                group: .collects,
                highlightedItem: highlightedItem,
                usesStaticSemanticColors: usesStaticSemanticColors
            )
            .padding(.horizontal, style == .onboarding ? 16 : 0)

            DataCollectionCard(
                group: .doesNotCollect,
                highlightedItem: highlightedItem,
                usesStaticSemanticColors: usesStaticSemanticColors
            )
            .padding(.horizontal, style == .onboarding ? 16 : 0)
        }
        .frame(width: style == .onboarding ? 376 : nil)
        .onAppear {
            startHighlighting()
        }
        .onDisappear {
            stopHighlighting()
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            if reduceMotion {
                stopHighlighting()
            } else {
                startHighlighting()
            }
        }
        .onChange(of: isAnimationEnabled) { _, isAnimationEnabled in
            if isAnimationEnabled {
                startHighlighting()
            } else {
                stopHighlighting()
            }
        }
        .onChange(of: accentState.isUsingAppAccent) { _, isUsingAppAccent in
            if isUsingAppAccent {
                stopHighlighting()
            } else {
                startHighlighting()
            }
        }
    }

    private var usesStaticSemanticColors: Bool {
        style == .onboarding || accentState.isUsingAppAccent
    }

    private func startHighlighting() {
        guard style == .settings,
              !accentState.isUsingAppAccent,
              isAnimationEnabled,
              !reduceMotion,
              highlightTask == nil else {
            return
        }

        highlightTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }

                let group = nextHighlightGroup
                let item = group.items.randomElement()

                await MainActor.run {
                    withAnimation(highlightAnimation) {
                        highlightedItem = item
                    }
                    nextHighlightGroup = group.opposite
                }

                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(highlightAnimation) {
                        highlightedItem = nil
                    }
                }
            }
        }
    }

    private func stopHighlighting() {
        highlightTask?.cancel()
        highlightTask = nil
        highlightedItem = nil
    }
}

private struct DataCollectionCard: View {
    let group: DataCollectionGroup
    let highlightedItem: DataCollectionItem?
    let usesStaticSemanticColors: Bool

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
                        isHighlighted: highlightedItem == item,
                        usesStaticSemanticColors: usesStaticSemanticColors
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DataCollectionChecklistItem: View {
    let item: DataCollectionItem
    let isHighlighted: Bool
    let usesStaticSemanticColors: Bool

    private var iconColor: Color {
        usesStaticSemanticColors
            ? item.group.semanticIconColor
            : item.group.animatedIconColor(isHighlighted: isHighlighted)
    }

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

private enum DataCollectionGroup: CaseIterable {
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
            [.torrentData, .linkData, .fileData]
        }
    }

    var opposite: DataCollectionGroup {
        switch self {
        case .collects:
            .doesNotCollect
        case .doesNotCollect:
            .collects
        }
    }

    var symbolName: String {
        switch self {
        case .collects:
            "checkmark.circle"
        case .doesNotCollect:
            "xmark.circle"
        }
    }

    var semanticIconColor: Color {
        switch self {
        case .collects:
            Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
        case .doesNotCollect:
            Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
        }
    }

    func animatedIconColor(isHighlighted: Bool) -> Color {
        switch self {
        case .collects:
            isHighlighted ? Color(hex: 0x22C55E) : ShatlColor.typographyTertiary
        case .doesNotCollect:
            isHighlighted ? Color(hex: 0xF97316) : ShatlColor.typographyTertiary
        }
    }
}

private enum DataCollectionItem: CaseIterable, Identifiable {
    case launchCount
    case appVersion
    case interfaceLanguage
    case torrentData
    case linkData
    case fileData

    var id: Self { self }

    var group: DataCollectionGroup {
        switch self {
        case .launchCount, .appVersion, .interfaceLanguage:
            .collects
        case .torrentData, .linkData, .fileData:
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
        case .torrentData:
            "settings.data.does_not_collect.torrent_data"
        case .linkData:
            "settings.data.does_not_collect.link_data"
        case .fileData:
            "settings.data.does_not_collect.file_data"
        }
    }
}

private struct AboutSettingsTab: View {
    @EnvironmentObject private var store: AppStore

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

                    ShatlButton(localizedTitle: "settings.about.check_updates", role: .borderedNeutral) {}
                }

                ShatlSettingsParameterDivider()

                ShatlSettingsToggleRow(
                    localizedTitle: "settings.about.check_for_updates_automatically",
                    isOn: binding(for: \.checkForUpdates)
                )

                ShatlSettingsParameterDivider()

                ShatlSettingsToggleRow(
                    localizedTitle: "settings.about.install_updates_automatically",
                    isOn: binding(for: \.automaticallyInstallUpdates),
                    isEnabled: store.preferences.checkForUpdates
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
        .animation(ShatlMotion.cardState, value: store.preferences.checkForUpdates)
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

    private func binding<Value>(for keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { store.preferences[keyPath: keyPath] },
            set: { store.preferences[keyPath: keyPath] = $0 }
        )
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

private struct PerformanceProfileDemo: View {
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
            : Color(red: 55 / 255, green: 65 / 255, blue: 81 / 255).opacity(0.08)
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
        accentState.isUsingAppAccent
            ? AnyShapeStyle(ShatlColor.performanceSpeedometerGradient)
            : AnyShapeStyle(neutralProgressColor)
    }

    private var neutralProgressColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.24)
            : Color(red: 55.0 / 255.0, green: 65.0 / 255.0, blue: 81.0 / 255.0).opacity(0.26)
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
    @State private var activeDance: ThemeButtonDance?
    @State private var lastDance: ThemeButtonDance?
    @State private var themeDanceTask: Task<Void, Never>?
    @State private var metricPreviewPulseTrigger = 0
    @State private var isMetricsInfoPresented = false

    private let themeDanceColorAnimation: Animation = .easeInOut(duration: 0.6)

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
        .onAppear {
            startThemeDance()
        }
        .onChange(of: accentState.isUsingAppAccent) { _, isUsingAppAccent in
            if isUsingAppAccent {
                stopThemeDance()
            } else {
                startThemeDance()
            }
        }
        .onDisappear {
            stopThemeDance()
        }
    }

    private var previewCardContainer: some View {
        VStack(spacing: 8) {
            TorrentCardPreviewView(
                localeOverride: store.preferences.localeOverride,
                metricsMode: store.preferences.metricsMode,
                initiallyExpanded: true,
                centersExpandedCard: true,
                allowsExpansionToggle: false,
                showsExpansionToggle: false,
                pulsesMetricSetOutlines: false,
                metricSetOutlineFlashTrigger: metricPreviewPulseTrigger,
                progressBarFillColorOverride: accentState.isUsingAppAccent ? nil : ShatlColor.typographyTertiary,
                usesProductionProgressColors: accentState.isUsingAppAccent,
                cardBackgroundColorOverride: colorScheme == .dark ? ShatlColor.cardDefault : nil,
                cardOutlineColorOverride: colorScheme == .light ? ShatlColor.outlinePrimary : nil,
                shadowStyle: .settings,
                cardWidth: nil
            )
            .padding(.horizontal, 28)

            Label("settings.appearance.preview", systemImage: "play.display")
            .shatlTypography(ShatlTypography.groupSemibold)
            .foregroundStyle(ShatlColor.typographySecondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private var metricsModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShatlSettingsParameter {
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
                        imageContainerHeight: 84
                    ) {
                        store.preferences.theme = theme
                    } content: {
                        ThemeAppearanceDemo(
                            theme: theme,
                            activeDance: activeDance
                        )
                    }
                }
            }
        }
    }

    private func selectMetricsMode(_ mode: MetricsPresentationMode) {
        store.preferences.metricsMode = mode
        metricPreviewPulseTrigger += 1
    }

    private var simplifiedMetricsModeBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.metricsMode == .simplified },
            set: { selectMetricsMode($0 ? .simplified : .detailed) }
        )
    }

    private func startThemeDance() {
        guard !accentState.isUsingAppAccent, themeDanceTask == nil else { return }

        themeDanceTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }

                let nextDance = ThemeButtonDance.random(excluding: lastDance)
                await MainActor.run {
                    withAnimation(themeDanceColorAnimation) {
                        activeDance = nextDance
                    }
                    lastDance = nextDance
                }

                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(themeDanceColorAnimation) {
                        activeDance = nil
                    }
                }
            }
        }
    }

    private func stopThemeDance() {
        themeDanceTask?.cancel()
        themeDanceTask = nil
        activeDance = nil
    }

}

private struct ShatlSettingsControlVerticalDivider: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(ShatlColor.outlineTertiary)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
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
    let activeDance: ThemeButtonDance?

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var accentState: ShatlAccentState

    var body: some View {
        ZStack {
            themePreviewShadow

            ZStack {
                Image(theme.settingsCardAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)

                ShatlWindowButtonCloseShape()
                    .fill(buttonColor(.close))

                ShatlWindowButtonMinimizeShape()
                    .fill(buttonColor(.minimize))

                ShatlWindowButtonExpandShape()
                    .fill(buttonColor(.expand))
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

    private func buttonColor(_ button: ThemeWindowButton) -> Color {
        if accentState.isUsingAppAccent {
            return button.signalColor
        }

        guard activeDance == ThemeButtonDance(theme: theme, button: button) else {
            return button.baseColor(theme: theme, colorScheme: colorScheme)
        }

        return button.signalColor
    }
}

private struct ThemeButtonDance: Equatable {
    let theme: AppTheme
    let button: ThemeWindowButton

    static func random(excluding excludedDance: ThemeButtonDance?) -> ThemeButtonDance {
        let availableDances = allCases.filter { dance in
            guard let excludedDance else { return true }
            return dance.theme != excludedDance.theme && dance.colorKind != excludedDance.colorKind
        }
        return availableDances.randomElement() ?? allCases[0]
    }

    private var colorKind: ThemeButtonDanceColorKind {
        button.danceColorKind
    }

    private static var allCases: [ThemeButtonDance] {
        AppTheme.allCases.flatMap { theme in
            ThemeWindowButton.allCases.map { button in
                ThemeButtonDance(theme: theme, button: button)
            }
        }
    }
}

private enum ThemeWindowButton: CaseIterable {
    case close
    case minimize
    case expand

    var danceColorKind: ThemeButtonDanceColorKind {
        switch self {
        case .close:
            .red
        case .minimize:
            .yellow
        case .expand:
            .green
        }
    }

    func baseColor(theme: AppTheme, colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark || theme == .dark {
            return Color(hex: 0x9CA3AF)
        }

        return Color(hex: 0xD1D5DB)
    }

    var signalColor: Color {
        switch self {
        case .close:
            Color(red: 255.0 / 255.0, green: 92.0 / 255.0, blue: 96.0 / 255.0)
        case .minimize:
            Color(red: 250.0 / 255.0, green: 200.0 / 255.0, blue: 0.0 / 255.0)
        case .expand:
            Color(red: 53.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0)
        }
    }
}

private enum ThemeButtonDanceColorKind {
    case red
    case yellow
    case green
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

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private struct PerformanceProfileSlider: NSViewRepresentable {
    @Binding var profile: AppPerformanceProfile
    var isEnabled: Bool

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: profile.sliderValue,
            minValue: 0,
            maxValue: 2,
            target: context.coordinator,
            action: #selector(Coordinator.sliderChanged(_:))
        )
        slider.numberOfTickMarks = AppPerformanceProfile.allCases.count
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.isContinuous = false
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        slider.doubleValue = profile.sliderValue
        slider.isEnabled = isEnabled
        context.coordinator.profile = $profile
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(profile: $profile)
    }

    final class Coordinator: NSObject {
        var profile: Binding<AppPerformanceProfile>

        init(profile: Binding<AppPerformanceProfile>) {
            self.profile = profile
        }

        @objc func sliderChanged(_ sender: NSSlider) {
            profile.wrappedValue = AppPerformanceProfile.fromSliderValue(sender.doubleValue)
        }
    }
}
