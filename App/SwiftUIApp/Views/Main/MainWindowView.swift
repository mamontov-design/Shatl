// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var addTorrentEntryAlert: TorrentErrorState?
    @State private var isOnboardingPresented = false
    @State private var isRestoreIndicatorPreviewPresented = false
    @State private var restoreIndicatorPreviewTask: Task<Void, Never>?
    @State private var didEvaluateInitialOnboardingPresentation = false
    @State private var didRequestNativeNotificationAuthorization = false

    private enum ContentMode: Equatable {
        case loadingInitialSession
        case sessionLoadFailure(SessionLoadIssue)
        case empty
        case list
    }

    private var contentMode: ContentMode {
        guard store.hasLoadedInitialSession else { return .loadingInitialSession }
        if let issue = store.sessionLoadIssue {
            return .sessionLoadFailure(issue)
        }
        return store.torrents.isEmpty ? .empty : .list
    }

    private var showsBlockedToolbarControls: Bool {
        switch contentMode {
        case .loadingInitialSession, .sessionLoadFailure:
            true
        case .empty, .list:
            false
        }
    }

    private var activeAlert: Binding<MainWindowAlert?> {
        Binding {
            if let addTorrentEntryAlert {
                return .addTorrentEntry(addTorrentEntryAlert)
            }

            if let payloadDeletionAlert = store.payloadDeletionAlert {
                return .payloadDeletion(payloadDeletionAlert)
            }

            return nil
        } set: { newValue in
            if newValue == nil {
                addTorrentEntryAlert = nil
                store.payloadDeletionAlert = nil
            }
        }
    }

    var body: some View {
        let bottomTransferChips = store.bottomTransferChips

        ZStack(alignment: .bottom) {
            contentView(
                bottomListPadding: bottomListPadding(chips: bottomTransferChips)
            )

            bottomInfoChipLayer(chips: bottomTransferChips)
        }
        .background(WindowChromeConfigurator(isTitleVisible: contentMode != .empty))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if contentMode != .empty {
                    ShatlToolbarButton(
                        title: L10n.string(
                            "toolbar.add",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: "Добавить"
                        ),
                        systemImage: "plus",
                        isDisabled: !store.canAddTorrent
                    ) {
                        store.presentAddTorrentEntry()
                    }
                }

                if contentMode == .list || showsBlockedToolbarControls {
                    let selectedTorrentIsSleeping = store.selectedTorrent?.status.isSleeping == true

                    ShatlToolbarButton(
                        title: L10n.string(
                            selectedTorrentIsSleeping ? "toolbar.start" : "toolbar.stop",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: selectedTorrentIsSleeping ? "Пуск" : "Стоп"
                        ),
                        systemImage: selectedTorrentIsSleeping ? "play" : "stop",
                        isDisabled: contentMode != .list || !store.isToolbarStartStopEnabled
                    ) {
                        if selectedTorrentIsSleeping {
                            store.startSelectedTorrent()
                        } else {
                            store.stopSelectedTorrent()
                        }
                    }

                    ShatlToolbarButton(
                        title: L10n.string(
                            "toolbar.delete",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: "Удалить"
                        ),
                        systemImage: "trash",
                        role: .destructive,
                        isDisabled: contentMode != .list || !store.isToolbarRemoveEnabled
                    ) {
                        presentToolbarRemovalDialog()
                    }
                }
            }
        }
        .modifier(
            SearchToolbarModifier(
                isVisible: contentMode == .list,
                searchText: $searchText,
                prompt: L10n.string(
                    "toolbar.search",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Поиск"
                )
            )
        )
        .onChange(of: store.torrents.isEmpty) { _, isEmpty in
            if isEmpty {
                searchText = ""
            }
        }
        .onChange(of: store.hasLoadedInitialSession) { _, hasLoadedInitialSession in
            guard hasLoadedInitialSession else { return }
            presentInitialOnboardingIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shatlPresentDebugOnboarding)) { _ in
            isOnboardingPresented = true
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .shatlPresentRestoreIndicatorPreview)
        ) { _ in
            presentRestoreIndicatorPreview()
        }
        .environment(\.shatlAnimationMode, store.preferences.animationMode)
        .animation(ShatlMotion.mainContentMode, value: contentMode)
        .sheet(
            item: $store.presentedModal,
            onDismiss: {
                withAnimation(ShatlMotion.mainContentMode) {
                    store.commitPendingConfirmedTorrent()
                }
            }
        ) { modal in
            switch modal {
            case .addTorrentEntry:
                AddTorrentEntryView(
                    placement: .modal,
                    onValidationError: presentAddTorrentEntryAlert
                )
                    .environmentObject(store)
            case .addTorrentReview:
                AddTorrentReviewView()
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $isOnboardingPresented) {
            OnboardingFlowView(
                localeOverride: store.preferences.localeOverride,
                defaultDownloadPath: store.preferences.defaultDownloadPath,
                metricsMode: store.preferences.metricsMode,
                theme: store.preferences.theme,
                onClose: {
                    completeOnboarding()
                },
                onEnableUsageStatistics: {
                    store.answerUsageStatisticsOnboarding(allowStatistics: true)
                },
                onChangeDownloadFolder: {
                    presentDefaultDownloadFolderPicker()
                },
                onMetricsModeChange: { metricsMode in
                    store.preferences.metricsMode = metricsMode
                },
                onThemeChange: { theme in
                    store.preferences.theme = theme
                }
            )
            .environment(
                \.locale,
                L10n.locale(for: store.preferences.localeOverride)
            )
            .shatlTypographyProfile(localeOverride: store.preferences.localeOverride)
        }
        .alert(item: activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(
                    Text(
                        L10n.string(
                            "common.ok",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: "ОК"
                        )
                    )
                )
            )
        }
        .onAppear {
            store.bootstrapRuntimeState()
            requestNativeNotificationAuthorizationIfNeeded()
            presentInitialOnboardingIfNeeded()
        }
    }

    @ViewBuilder
    private func contentView(bottomListPadding: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            switch contentMode {
            case .loadingInitialSession:
                SessionLoadBlockingView(issue: nil, localeOverride: store.preferences.localeOverride)
                    .transition(.opacity)
            case .sessionLoadFailure(let issue):
                SessionLoadBlockingView(issue: issue, localeOverride: store.preferences.localeOverride)
                    .transition(.opacity)
            case .empty:
                EmptyStateView(onEntryValidationError: presentAddTorrentEntryAlert)
                    .transition(ShatlMotion.mainContent)
                    .zIndex(1)
            case .list:
                TorrentListView(
                    searchText: searchText,
                    bottomContentPadding: bottomListPadding
                )
                    .transition(ShatlMotion.mainContent)
                    .zIndex(0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func bottomInfoChipLayer(chips: [BottomTransferChipPresentation]) -> some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom) {
                if let downloadChip = chips.first(where: { $0.kind == .download }) {
                    ShatlInfoBottomSpeedChip(item: downloadChip.item)
                        .transition(ShatlMotion.appearFromTop)
                }

                Spacer(minLength: 0)

                if let uploadChip = chips.first(where: { $0.kind == .upload }) {
                    ShatlInfoBottomSpeedChip(item: uploadChip.item)
                        .transition(ShatlMotion.appearFromTop)
                }
            }

            if showsRestoreChip {
                ShatlInfoBottomRestoreChip(
                    title: L10n.string(
                        "session.restore.in_progress",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Восстановление сессии…"
                    )
                )
                    .transition(ShatlMotion.appearFromTop)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, bottomChipEdgePadding)
        .padding(.bottom, bottomChipEdgePadding)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .animation(ShatlMotion.mainContentMode, value: chips)
        .animation(ShatlMotion.mainContentMode, value: showsRestoreChip)
    }

    private var showsRestoreChip: Bool {
        store.isRestoringSession || isRestoreIndicatorPreviewPresented
    }

    private var bottomChipEdgePadding: CGFloat {
        if #available(macOS 27.0, *) {
            return ShatlBottomChipLayout.modernEdgePadding
        }

        return ShatlBottomChipLayout.legacyEdgePadding
    }

    private func bottomListPadding(chips: [BottomTransferChipPresentation]) -> CGFloat {
        if #available(macOS 27.0, *), (!chips.isEmpty || showsRestoreChip) {
            return ShatlBottomChipLayout.modernListBottomPadding
        }

        return ShatlBottomChipLayout.standardListBottomPadding
    }

    private func presentRestoreIndicatorPreview() {
        restoreIndicatorPreviewTask?.cancel()
        isRestoreIndicatorPreviewPresented = true

        restoreIndicatorPreviewTask = Task {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            isRestoreIndicatorPreviewPresented = false
        }
    }

    private func presentAddTorrentEntryAlert(_ errorState: TorrentErrorState) {
        addTorrentEntryAlert = errorState
    }

    private func presentToolbarRemovalDialog() {
        guard let record = store.selectedTorrent else { return }

        Task {
            guard let policy = await TorrentRemovalDialogPresenter.presentRemovalChoice(
                for: record,
                allowsDeleteWithFiles: record.errorState == nil,
                localeOverride: store.preferences.localeOverride
            ) else {
                return
            }

            await store.removeTorrent(id: record.id, policy: policy)
        }
    }

    private func presentInitialOnboardingIfNeeded() {
        guard store.hasLoadedInitialSession, store.sessionLoadIssue == nil else { return }
        guard !didEvaluateInitialOnboardingPresentation else { return }

        didEvaluateInitialOnboardingPresentation = true

        if !store.preferences.hasCompletedOnboarding {
            isOnboardingPresented = true
        }
    }

    private func completeOnboarding() {
        store.completeOnboarding()
        isOnboardingPresented = false
    }

    private func requestNativeNotificationAuthorizationIfNeeded() {
        guard !didRequestNativeNotificationAuthorization else { return }

        didRequestNativeNotificationAuthorization = true
        Task {
            _ = await MacNotificationAuthorizationRequester.requestNativeAuthorization()
        }
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

private struct SessionLoadBlockingView: View {
    let issue: SessionLoadIssue?
    let localeOverride: AppLocaleOverride

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            VStack(spacing: 10) {
                Image(systemName: issue == nil ? "progress.indicator" : "exclamationmark.triangle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(issue == nil ? ShatlColor.accent : ShatlColor.neonBlue)
                    .symbolEffect(.rotate.byLayer, options: .repeat(.continuous), isActive: issue == nil)

                Text(title)
                    .shatlTypography(ShatlTypography.bodySemibold)
                    .foregroundStyle(ShatlColor.typographyPrimary)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .shatlTypography(ShatlTypography.bodyRegular)
                        .foregroundStyle(ShatlColor.typographySecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 320)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        guard let issue else {
            return L10n.string(
                "session.load.in_progress.title",
                localeOverride: localeOverride,
                defaultValue: "Подготовка сессии…"
            )
        }

        switch issue {
        case .unreadable, .missingWithRecoveryArtifacts:
            return L10n.string(
                "session.load.failure.title",
                localeOverride: localeOverride,
                defaultValue: "Не удалось восстановить список загрузок"
            )
        case .unsupportedVersion:
            return L10n.string(
                "session.load.unsupported.title",
                localeOverride: localeOverride,
                defaultValue: "Не удалось открыть сохранённую сессию"
            )
        }
    }

    private var message: String? {
        guard let issue else { return nil }

        switch issue {
        case .unreadable:
            return L10n.string(
                "session.load.unreadable.message",
                localeOverride: localeOverride,
                defaultValue: "Shatl не смог прочитать сохранённую сессию. Загруженные с прошлого запуска файлы остались на диске."
            )
        case .missingWithRecoveryArtifacts:
            return L10n.string(
                "session.load.missing.message",
                localeOverride: localeOverride,
                defaultValue: "Shatl не нашёл сохранённый список. Загруженные с прошлого запуска файлы остались на диске."
            )
        case .unsupportedVersion:
            return L10n.string(
                "session.load.unsupported.message",
                localeOverride: localeOverride,
                defaultValue: "Сессия создана другой версией Shatl и пока не может быть открыта. Загруженные с прошлого запуска файлы остались на диске."
            )
        }
    }
}

private struct ShatlToolbarButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .disabled(isDisabled)
        .animation(ShatlMotion.toolbarState, value: isDisabled)
        .animation(ShatlMotion.toolbarSymbolReplace, value: systemImage)
    }
}

private enum MainWindowAlert: Identifiable {
    case addTorrentEntry(TorrentErrorState)
    case payloadDeletion(PayloadDeletionAlert)

    var id: String {
        switch self {
        case let .addTorrentEntry(errorState):
            "add-torrent-entry-\(errorState.id.uuidString)"
        case let .payloadDeletion(alert):
            "payload-deletion-\(alert.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case let .addTorrentEntry(errorState):
            errorState.title
        case let .payloadDeletion(alert):
            alert.title
        }
    }

    var message: String {
        switch self {
        case let .addTorrentEntry(errorState):
            errorState.message
        case let .payloadDeletion(alert):
            alert.message
        }
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    let isTitleVisible: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureChrome(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureChrome(from: nsView)
    }

    private func configureChrome(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            ShatlAppDelegate.configureWindowChrome(window)
            window.titleVisibility = isTitleVisible ? .visible : .hidden
        }
    }
}

private struct SearchToolbarModifier: ViewModifier {
    let isVisible: Bool
    @Binding var searchText: String
    let prompt: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if isVisible {
            content
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: Text(prompt)
                )
                .searchToolbarBehavior(.automatic)
        } else {
            content
        }
    }
}
