// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var addTorrentEntryAlert: TorrentErrorState?
    @State private var isOnboardingPresented = false
    @State private var didEvaluateInitialOnboardingPresentation = false
    @State private var didRequestNativeNotificationAuthorization = false

    private enum ContentMode: Equatable {
        case loadingInitialSession
        case empty
        case list
    }

    private var contentMode: ContentMode {
        guard store.hasLoadedInitialSession else { return .loadingInitialSession }
        return store.torrents.isEmpty ? .empty : .list
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
            contentView

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
                        isDisabled: false
                    ) {
                        store.presentAddTorrentEntry()
                    }
                }

                if contentMode == .list {
                    let selectedTorrentIsSleeping = store.selectedTorrent?.status.isSleeping == true

                    ShatlToolbarButton(
                        title: L10n.string(
                            selectedTorrentIsSleeping ? "toolbar.start" : "toolbar.stop",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: selectedTorrentIsSleeping ? "Пуск" : "Стоп"
                        ),
                        systemImage: selectedTorrentIsSleeping ? "play" : "stop",
                        isDisabled: !store.isToolbarStartStopEnabled
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
                        isDisabled: !store.isToolbarRemoveEnabled
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
    private var contentView: some View {
        ZStack(alignment: .topLeading) {
            switch contentMode {
            case .loadingInitialSession:
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            case .empty:
                EmptyStateView(onEntryValidationError: presentAddTorrentEntryAlert)
                    .transition(ShatlMotion.mainContent)
                    .zIndex(1)
            case .list:
                TorrentListView(searchText: searchText)
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
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .animation(ShatlMotion.mainContentMode, value: chips)
        .animation(ShatlMotion.mainContentMode, value: showsRestoreChip)
    }

    private var showsRestoreChip: Bool {
        store.isRestoringSession
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
