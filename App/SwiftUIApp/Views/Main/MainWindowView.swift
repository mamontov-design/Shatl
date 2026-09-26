// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

nonisolated enum SessionRestoreStatusPhase: Equatable, Sendable {
    case hidden
    case restoring
    case restored

    var isVisible: Bool {
        self != .hidden
    }
}

nonisolated enum SessionRestoreStatusTiming {
    static let revealDelay: TimeInterval = 1
    static let minimumVisibleDuration: TimeInterval = 2
    static let completionHoldDuration: TimeInterval = 1
    static let spinnerStopDuration: TimeInterval = 0.25
    static let iconReplacementDuration: TimeInterval = 0.36

    static func completionVisibilityDuration(visibleFor elapsed: TimeInterval) -> TimeInterval {
        max(completionHoldDuration, minimumVisibleDuration - max(0, elapsed))
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var addTorrentEntryAlert: TorrentErrorState?
    @State private var isOnboardingPresented = false
    @State private var restoreStatusPhase = SessionRestoreStatusPhase.hidden
    @State private var isRestoreStatusSpinnerActive = false
    @State private var showsRestoreCompletionIcon = false
    @State private var showsRestoreCompletionText = false
    @State private var restoreStatusShownAt: Date?
    @State private var restoreStatusTask: Task<Void, Never>?
    @State private var displayedSessionPersistenceIssue: SessionPersistenceIssue?
    @State private var isCheckingSessionPersistence = false
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
        return store.torrentRowIDs.isEmpty ? .empty : .list
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

    private var isAddTorrentEntryPresented: Binding<Bool> {
        Binding(
            get: { store.presentedModal == .addTorrentEntry },
            set: { isPresented in
                if !isPresented, store.presentedModal == .addTorrentEntry {
                    store.dismissModal()
                }
            }
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if let displayedSessionPersistenceIssue {
                    sessionPersistenceMessageBar(for: displayedSessionPersistenceIssue)
                        .transition(restoreStatusTransition)
                        .zIndex(1)
                } else if restoreStatusPhase.isVisible {
                    SessionRestoreStatusBar(
                        isSpinnerActive: isRestoreStatusSpinnerActive,
                        showsCompletionIcon: showsRestoreCompletionIcon,
                        showsCompletionText: showsRestoreCompletionText,
                        localeOverride: store.preferences.localeOverride
                    )
                    .transition(restoreStatusTransition)
                    .zIndex(1)
                }

                contentView
            }

            TorrentTransferSummaryLayer(model: store.torrentTransferSummary)
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
        .onChange(of: store.torrentRowIDs.isEmpty) { _, isEmpty in
            if isEmpty {
                searchText = ""
            }
        }
        .onChange(of: store.hasLoadedInitialSession) { _, hasLoadedInitialSession in
            guard hasLoadedInitialSession else { return }
            presentInitialOnboardingIfNeeded()
        }
        .onChange(of: store.isRestoringSession, initial: true) { _, isRestoringSession in
            updateRestoreStatus(isRestoringSession: isRestoringSession)
        }
        .onChange(of: store.sessionPersistenceIssue, initial: true) { _, newIssue in
            updateSessionPersistenceMessage(to: newIssue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shatlPresentDebugOnboarding)) { _ in
            isOnboardingPresented = true
        }
        .onChange(of: store.addTorrentReviewWindowRequestID, initial: true) { _, requestID in
            guard requestID > 0, store.isAddTorrentReviewWindowActive else { return }
            Task { @MainActor in
                await Task.yield()
                openWindow(id: AppWindowID.addTorrentReview)
            }
        }
        .animation(ShatlMotion.mainContentMode, value: contentMode)
        .sheet(isPresented: isAddTorrentEntryPresented) {
            AddTorrentEntryView(
                placement: .modal,
                onValidationError: presentAddTorrentEntryAlert
            )
                .environmentObject(store)
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
        .onDisappear {
            restoreStatusTask?.cancel()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        ZStack(alignment: .topLeading) {
            switch contentMode {
            case .loadingInitialSession:
                SessionLoadBlockingView(issue: nil, localeOverride: store.preferences.localeOverride)
                    .transition(.opacity)
            case .sessionLoadFailure(let issue):
                SessionLoadBlockingView(
                    issue: issue,
                    localeOverride: store.preferences.localeOverride
                )
                    .transition(.opacity)
            case .empty:
                EmptyStateView(onEntryValidationError: presentAddTorrentEntryAlert)
                    .transition(ShatlMotion.mainContent)
                    .zIndex(1)
            case .list:
                TorrentListViewport(
                    summaryVisibility: store.torrentTransferSummary.visibility,
                    searchText: searchText
                )
                    .transition(ShatlMotion.mainContent)
                    .zIndex(0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var restoreStatusTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .move(edge: .top).combined(with: .opacity)
    }

    private func updateRestoreStatus(isRestoringSession: Bool) {
        if isRestoringSession {
            beginRestoreStatusDelay()
        } else {
            completeVisibleRestoreStatus()
        }
    }

    private func beginRestoreStatusDelay() {
        restoreStatusTask?.cancel()
        restoreStatusShownAt = nil
        setRestoreStatusPhase(.hidden)

        restoreStatusTask = Task {
            do {
                try await Task.sleep(for: .seconds(SessionRestoreStatusTiming.revealDelay))
            } catch {
                return
            }

            guard !Task.isCancelled,
                  store.isRestoringSession,
                  store.hasLoadedInitialSession,
                  store.sessionLoadIssue == nil else {
                return
            }

            restoreStatusShownAt = Date()
            setRestoreStatusPhase(.restoring)
        }
    }

    private func completeVisibleRestoreStatus() {
        restoreStatusTask?.cancel()
        guard restoreStatusPhase == .restoring else {
            restoreStatusShownAt = nil
            setRestoreStatusPhase(.hidden)
            return
        }

        stopRestoreStatusSpinner()

        restoreStatusTask = Task {
            do {
                try await Task.sleep(for: .seconds(SessionRestoreStatusTiming.spinnerStopDuration))
            } catch {
                return
            }

            guard !Task.isCancelled, restoreStatusPhase == .restoring else { return }
            withAnimation(ShatlMotion.sessionRestoreStatusContent) {
                showsRestoreCompletionIcon = true
            }

            do {
                try await Task.sleep(
                    for: .seconds(SessionRestoreStatusTiming.iconReplacementDuration)
                )
            } catch {
                return
            }

            guard !Task.isCancelled, restoreStatusPhase == .restoring else { return }
            withAnimation(ShatlMotion.sessionRestoreStatusContent) {
                showsRestoreCompletionText = true
                restoreStatusPhase = .restored
            }

            let visibleFor = restoreStatusShownAt.map { Date().timeIntervalSince($0) } ?? 0
            let completionDuration = SessionRestoreStatusTiming.completionVisibilityDuration(
                visibleFor: visibleFor
            )

            do {
                try await Task.sleep(for: .seconds(completionDuration))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            restoreStatusShownAt = nil
            setRestoreStatusPhase(.hidden)
        }
    }

    private func setRestoreStatusPhase(_ phase: SessionRestoreStatusPhase) {
        if phase == .restoring {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isRestoreStatusSpinnerActive = true
                showsRestoreCompletionIcon = false
                showsRestoreCompletionText = false
            }
        } else if phase == .hidden {
            isRestoreStatusSpinnerActive = false
        }

        withAnimation(ShatlMotion.sessionRestoreStatusBar) {
            restoreStatusPhase = phase
        }
    }

    private func stopRestoreStatusSpinner() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isRestoreStatusSpinnerActive = false
        }
    }

    private func updateSessionPersistenceMessage(to newIssue: SessionPersistenceIssue?) {
        // A successful Check Again hides the bar itself after the minimum busy time.
        if newIssue == nil, isCheckingSessionPersistence { return }

        if displayedSessionPersistenceIssue == nil, newIssue != nil {
            isCheckingSessionPersistence = false
        }

        // Only appearing and disappearing animate; a new text stays in place.
        if (displayedSessionPersistenceIssue == nil) != (newIssue == nil) {
            withAnimation(ShatlMotion.sessionRestoreStatusBar) {
                displayedSessionPersistenceIssue = newIssue
            }
        } else {
            displayedSessionPersistenceIssue = newIssue
        }

        // VoiceOver reads alerts on its own, but not an inline line message.
        if let newIssue {
            AccessibilityNotification.Announcement(
                "\(sessionPersistenceTitle). \(sessionPersistenceMessage(for: newIssue.kind))"
            ).post()
        }
    }

    private func sessionPersistenceMessageBar(for issue: SessionPersistenceIssue) -> some View {
        ShatlLineMessageBar(
            title: sessionPersistenceTitle,
            message: sessionPersistenceMessage(for: issue.kind),
            primaryButtonTitle: L10n.string(
                "session.persistence.line.check_again",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Проверить снова"
            ),
            primaryBusyTitle: L10n.string(
                "session.persistence.line.checking",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Проверка…"
            ),
            isPrimaryBusy: isCheckingSessionPersistence,
            closeButtonTitle: L10n.string(
                "session.persistence.line.hide",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Скрыть"
            ),
            primaryAction: checkSessionPersistenceAgain,
            closeAction: { store.hideSessionPersistenceIssue() }
        )
    }

    private func checkSessionPersistenceAgain() {
        guard !isCheckingSessionPersistence else { return }
        isCheckingSessionPersistence = true

        Task {
            let clock = ContinuousClock()
            let startedAt = clock.now
            await store.recheckSessionPersistence()

            // The check takes milliseconds; a minimum busy time avoids a flicker.
            let remaining = ShatlMotion.busyButtonMinimumDuration - startedAt.duration(to: clock.now)
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            }

            if store.sessionPersistenceIssue == nil {
                // The bar leaves while its button still reads "Checking…".
                withAnimation(ShatlMotion.sessionRestoreStatusBar) {
                    displayedSessionPersistenceIssue = nil
                }
            } else {
                isCheckingSessionPersistence = false
            }
        }
    }

    private var sessionPersistenceTitle: String {
        L10n.string(
            "session.persistence.save_failed.title",
            localeOverride: store.preferences.localeOverride,
            defaultValue: "Не удалось сохранить состояние загрузок"
        )
    }

    private func sessionPersistenceMessage(for kind: SessionPersistenceIssue.Kind) -> String {
        let localeOverride = store.preferences.localeOverride
        switch kind {
        case .background:
            return L10n.string(
                "session.persistence.background_failed.message",
                localeOverride: localeOverride,
                defaultValue: "Shatl не может записать данные на диск. Проверьте свободное место и доступ к диску, затем нажмите «Проверить снова»."
            )
        case .stop:
            return L10n.string(
                "session.persistence.stop_failed.message",
                localeOverride: localeOverride,
                defaultValue: "Загрузка не остановлена: Shatl не может записать данные на диск. Проверьте свободное место и доступ к диску, затем повторите действие."
            )
        case .removeFromList:
            return L10n.string(
                "session.persistence.remove_from_list_failed.message",
                localeOverride: localeOverride,
                defaultValue: "Торрент не удалён из списка: Shatl не может записать данные на диск. Проверьте свободное место и доступ к диску, затем повторите действие."
            )
        case .removeWithFiles:
            return L10n.string(
                "session.persistence.remove_with_files_failed.message",
                localeOverride: localeOverride,
                defaultValue: "Торрент и его файлы не удалены: Shatl не может записать данные на диск. Проверьте свободное место и доступ к диску, затем повторите действие."
            )
        case .redownload:
            return L10n.string(
                "session.persistence.redownload_failed.message",
                localeOverride: localeOverride,
                defaultValue: "Повторная загрузка не начата: Shatl не может записать данные на диск. Проверьте свободное место и доступ к диску, затем повторите действие."
            )
        }
    }

    private func presentAddTorrentEntryAlert(_ errorState: TorrentErrorState) {
        addTorrentEntryAlert = errorState
    }

    private func presentToolbarRemovalDialog() {
        guard let selectedTorrentID = store.selectedTorrentID else { return }

        if let shortDisplayName = store.pendingAdditionShortDisplayName(for: selectedTorrentID) {
            Task {
                guard await TorrentRemovalDialogPresenter.confirmCancelPendingAddition(
                    named: shortDisplayName,
                    localeOverride: store.preferences.localeOverride
                ) else {
                    return
                }
                if store.isPendingAddition(id: selectedTorrentID) {
                    store.cancelPendingAddition(id: selectedTorrentID)
                } else {
                    await store.removeTorrent(
                        id: selectedTorrentID,
                        policy: .removeFromListOnly
                    )
                }
            }
            return
        }

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

private struct TorrentListViewport: View {
    @ObservedObject var summaryVisibility: TorrentTransferSummaryVisibilityModel
    let searchText: String

    var body: some View {
        TorrentListView(
            searchText: searchText,
            bottomContentPadding: bottomListPadding
        )
    }

    private var bottomListPadding: CGFloat {
        if #available(macOS 27.0, *), summaryVisibility.hasChips {
            return ShatlBottomChipLayout.modernListBottomPadding
        }

        return ShatlBottomChipLayout.standardListBottomPadding
    }
}

private struct TorrentTransferSummaryLayer: View {
    @ObservedObject var model: TorrentTransferSummaryModel

    var body: some View {
        HStack(alignment: .bottom) {
            if let downloadChip = model.chips.first(where: { $0.kind == .download }) {
                ShatlInfoBottomSpeedChip(item: downloadChip.item)
                    .transition(ShatlMotion.appearFromTop)
            }

            Spacer(minLength: 0)

            if let uploadChip = model.chips.first(where: { $0.kind == .upload }) {
                ShatlInfoBottomSpeedChip(item: uploadChip.item)
                    .transition(ShatlMotion.appearFromTop)
            }
        }
        .padding(.horizontal, edgePadding)
        .padding(.bottom, edgePadding)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .animation(ShatlMotion.mainContentMode, value: chipStructureAnimationKey)
    }

    private var chipStructureAnimationKey: [String] {
        model.chips.map(\.kind.id)
    }

    private var edgePadding: CGFloat {
        if #available(macOS 27.0, *) {
            return ShatlBottomChipLayout.modernEdgePadding
        }

        return ShatlBottomChipLayout.legacyEdgePadding
    }
}

/// Reusable inline message shown above the main content, used for session
/// persistence failures that last until storage accepts writes again.
struct ShatlLineMessageBar: View {
    let title: String
    let message: String
    let primaryButtonTitle: String
    var primaryBusyTitle: String?
    /// While the primary action runs, both buttons stay blocked and the close
    /// button looks disabled, so neither can interrupt the running check.
    var isPrimaryBusy = false
    let closeButtonTitle: String
    let primaryAction: () -> Void
    let closeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                .shatlTypography(ShatlTypography.bodySemibold)
                .foregroundStyle(ShatlColor.lineMessageHeadline)

                Text(message)
                    .shatlTypography(ShatlTypography.bodyRegular)
                    .foregroundStyle(ShatlColor.lineMessageCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)

            HStack(spacing: 8) {
                ShatlButton(
                    title: primaryButtonTitle,
                    busyTitle: primaryBusyTitle,
                    isBusy: isPrimaryBusy,
                    role: .lineMessage,
                    action: primaryAction
                )

                ShatlButton(
                    title: closeButtonTitle,
                    role: .lineMessage,
                    isDisabled: isPrimaryBusy,
                    action: closeAction
                )
            }
            // The close button slides with the resizing primary button,
            // like neighbors in the expanded metric row.
            .geometryGroup()
            .animation(ShatlMotion.metricResize, value: isPrimaryBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShatlColor.lineMessageBackground)
        .accessibilityElement(children: .contain)
    }

}

private struct SessionLoadBlockingView: View {
    @EnvironmentObject private var store: AppStore

    let issue: SessionLoadIssue?
    let localeOverride: AppLocaleOverride

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ShatlColor.backgroundSecondary)

            if issue == nil {
                VStack(spacing: 12) {
                    Image(systemName: "tray.and.arrow.up")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(ShatlColor.typographySecondary)

                    Text(title)
                        .shatlTypography(ShatlTypography.bodySemibold)
                        .foregroundStyle(ShatlColor.typographyPrimary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 320)
                .padding(24)
            } else {
                recoveryCard
                    .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recoveryCard: some View {
        ShatlMessageBlockPrimary(
            title: title,
            message: message,
            primaryButton: ShatlMessageBlockPrimaryButton(
                title: L10n.string(
                    "session.recovery.open_empty",
                    localeOverride: localeOverride,
                    defaultValue: "Запуск с пустым списком"
                ),
                role: .borderedColored,
                isDisabled: store.isResolvingSessionRecovery,
                lineLimit: nil
            ) {
                store.openWithEmptyDownloadList()
            }
        )
    }

    private var title: String {
        guard let issue else {
            return L10n.string(
                "session.load.in_progress.title",
                localeOverride: localeOverride,
                defaultValue: "Выполняется восстановление сессии.\nПожалуйста, подождите."
            )
        }

        switch issue {
        case .unreadable, .missingWithRecoveryArtifacts:
            return L10n.string(
                "session.load.failure.title",
                localeOverride: localeOverride,
                defaultValue: "Не удалось восстановить список загрузок."
            )
        case .unsupportedVersion:
            return L10n.string(
                "session.load.unsupported.title",
                localeOverride: localeOverride,
                defaultValue: "Не удалось открыть сохранённую сессию."
            )
        }
    }

    private var message: String? {
        guard let issue else { return nil }

        switch issue {
        case .unreadable, .missingWithRecoveryArtifacts:
            return L10n.string(
                "session.load.unreadable.message",
                localeOverride: localeOverride,
                defaultValue: "При попытке восстановить загрузки произошла ошибка. Загруженные с прошлого запуска файлы остались на диске."
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

private struct SessionRestoreStatusBar: View {
    @EnvironmentObject private var accentState: ShatlAccentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isSpinnerActive: Bool
    let showsCompletionIcon: Bool
    let showsCompletionText: Bool
    let localeOverride: AppLocaleOverride

    var body: some View {
        HStack(spacing: 4) {
            Image(
                systemName: showsCompletionIcon ? "checkmark.circle" : "progress.indicator"
            )
            .shatlTypography(ShatlTypography.metricSemibold)
            .symbolEffect(
                .rotate.byLayer,
                options: .repeat(.continuous),
                isActive: isSpinnerActive
            )
            .symbolEffectsRemoved(!isSpinnerActive)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 14, height: ShatlMetricLayout.contentHeight, alignment: .center)

            statusText
        }
        .geometryGroup()
        .foregroundStyle(statusColor)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(statusColor.opacity(0.16))
        .animation(ShatlMotion.sessionRestoreStatusContent, value: showsCompletionText)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if showsCompletionText {
            return L10n.string(
                "session.restore.completed",
                localeOverride: localeOverride,
                defaultValue: "Сессия восстановлена"
            )
        }

        return L10n.string(
            "session.restore.in_progress",
            localeOverride: localeOverride,
            defaultValue: "Восстановление сессии…"
        )
    }

    private var statusColor: Color {
        accentState.isUsingAppAccent ? ShatlColor.neonBlue : accentState.systemAccentColor
    }

    @ViewBuilder
    private var statusText: some View {
        let text = Text(title)
            .id(showsCompletionText)
            .shatlTypography(ShatlTypography.metricSemibold)
            .multilineTextAlignment(.center)

        if reduceMotion {
            text.transition(.opacity)
        } else {
            text.transition(.blurReplace)
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
