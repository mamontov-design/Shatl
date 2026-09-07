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
    @Environment(\.openSettings) private var openSettings
    @State private var searchText = ""
    @State private var addTorrentEntryAlert: TorrentErrorState?
    @State private var isOnboardingPresented = false
    @State private var restoreStatusPhase = SessionRestoreStatusPhase.hidden
    @State private var isRestoreStatusSpinnerActive = false
    @State private var showsRestoreCompletionIcon = false
    @State private var showsRestoreCompletionText = false
    @State private var restoreStatusShownAt: Date?
    @State private var restoreStatusTask: Task<Void, Never>?
    @State private var didEvaluateInitialOnboardingPresentation = false
    @State private var didRequestNativeNotificationAuthorization = false
    @State private var showsEmptySessionConfirmation = false

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
            VStack(spacing: 0) {
                if restoreStatusPhase.isVisible {
                    SessionRestoreStatusBar(
                        isSpinnerActive: isRestoreStatusSpinnerActive,
                        showsCompletionIcon: showsRestoreCompletionIcon,
                        showsCompletionText: showsRestoreCompletionText,
                        localeOverride: store.preferences.localeOverride
                    )
                    .transition(restoreStatusTransition)
                    .zIndex(1)
                }

                if store.showsSessionBackupWarning,
                   store.hasLoadedInitialSession,
                   store.sessionLoadIssue == nil {
                    SessionBackupWarningBar(
                        status: store.sessionBackupStatus,
                        localeOverride: store.preferences.localeOverride,
                        openSettings: openSessionSettings,
                        dismiss: store.dismissSessionBackupWarning
                    )
                    .transition(restoreStatusTransition)
                    .zIndex(1)
                }

                contentView(
                    bottomListPadding: bottomListPadding(chips: bottomTransferChips)
                )
            }

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
        .onChange(of: store.isRestoringSession, initial: true) { _, isRestoringSession in
            updateRestoreStatus(isRestoringSession: isRestoringSession)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shatlPresentDebugOnboarding)) { _ in
            isOnboardingPresented = true
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
        .confirmationDialog(
            Text("session.recovery.empty.confirm.title"),
            isPresented: $showsEmptySessionConfirmation,
            titleVisibility: .visible
        ) {
            Button("session.recovery.empty.confirm.action", role: .destructive) {
                store.openWithEmptyDownloadList()
            }
            Button("common.cancel", role: .cancel) { }
        } message: {
            Text("session.recovery.empty.confirm.message")
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
    private func contentView(bottomListPadding: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            switch contentMode {
            case .loadingInitialSession:
                SessionLoadBlockingView(issue: nil, localeOverride: store.preferences.localeOverride)
                    .transition(.opacity)
            case .sessionLoadFailure(let issue):
                SessionLoadBlockingView(
                    issue: issue,
                    localeOverride: store.preferences.localeOverride,
                    openEmptyList: { showsEmptySessionConfirmation = true }
                )
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
        .padding(.horizontal, bottomChipEdgePadding)
        .padding(.bottom, bottomChipEdgePadding)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .animation(ShatlMotion.mainContentMode, value: chips)
    }

    private var bottomChipEdgePadding: CGFloat {
        if #available(macOS 27.0, *) {
            return ShatlBottomChipLayout.modernEdgePadding
        }

        return ShatlBottomChipLayout.legacyEdgePadding
    }

    private func bottomListPadding(chips: [BottomTransferChipPresentation]) -> CGFloat {
        if #available(macOS 27.0, *), !chips.isEmpty {
            return ShatlBottomChipLayout.modernListBottomPadding
        }

        return ShatlBottomChipLayout.standardListBottomPadding
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

    private func openSessionSettings() {
        openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .shatlOpenSessionSettings, object: nil)
        }
    }
}

private struct SessionBackupWarningBar: View {
    let status: SessionBackupStatus
    let localeOverride: AppLocaleOverride
    let openSettings: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .shatlTypography(ShatlTypography.bodyRegular)
                .foregroundStyle(ShatlColor.typographyPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ShatlButton(
                    localizedTitle: "session.backup.warning.open_settings",
                    role: .borderedColored,
                    fillsWidth: true,
                    action: openSettings
                )

                ShatlButton(
                    localizedTitle: "common.close",
                    role: .borderedNeutral,
                    fillsWidth: true,
                    action: dismiss
                )
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShatlColor.neonBlue.opacity(0.16))
        .animation(ShatlMotion.cardState, value: status)
    }

    private var message: String {
        let key: String
        if case .stale(_, let issue) = status {
            switch issue {
            case .outOfDate:
                key = "session.backup.warning.out_of_date"
            case .folderUnavailable:
                key = "session.backup.warning.folder_unavailable"
            case .permissionDenied:
                key = "session.backup.warning.permission_denied"
            case .insufficientSpace:
                key = "session.backup.warning.insufficient_space"
            case .invalidBackup:
                key = "session.backup.warning.invalid_backup"
            case .unknown:
                key = "session.backup.warning.unknown"
            }
        } else {
            key = "session.backup.warning.unknown"
        }
        return L10n.string(key, localeOverride: localeOverride)
    }
}

private struct SessionLoadBlockingView: View {
    @EnvironmentObject private var store: AppStore

    let issue: SessionLoadIssue?
    let localeOverride: AppLocaleOverride
    var openEmptyList: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ShatlColor.backgroundSecondary)

            VStack(spacing: issue == nil ? 12 : 10) {
                Image(systemName: issue == nil ? "tray.and.arrow.up" : "exclamationmark.triangle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(issue == nil ? ShatlColor.typographySecondary : ShatlColor.neonBlue)

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

                if issue != nil {
                    if let backupDetails {
                        Text(backupDetailsText(backupDetails))
                            .shatlTypography(ShatlTypography.bodyRegular)
                            .foregroundStyle(ShatlColor.typographySecondary)
                            .multilineTextAlignment(.center)

                        ShatlButton(
                            localizedTitle: "session.recovery.restore_backup",
                            role: .borderedColored,
                            isDisabled: store.isResolvingSessionRecovery,
                            fillsWidth: true,
                            lineLimit: 2
                        ) {
                            store.restoreDownloadListFromBackup()
                        }
                    }

                    ShatlButton(
                        localizedTitle: "session.recovery.open_empty",
                        role: backupDetails == nil ? .borderedColored : .borderedNeutral,
                        isDisabled: store.isResolvingSessionRecovery,
                        fillsWidth: true
                    ) {
                        openEmptyList?()
                    }

                    if let backupAvailabilityMessage {
                        Text(backupAvailabilityMessage)
                            .shatlTypography(ShatlTypography.bodyRegular)
                            .foregroundStyle(ShatlColor.neonBlue)
                            .multilineTextAlignment(.center)
                    }

                    if let recoveryIssueMessage {
                        Text(recoveryIssueMessage)
                            .shatlTypography(ShatlTypography.bodyRegular)
                            .foregroundStyle(ShatlColor.neonBlue)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: 320)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var backupDetails: SessionBackupDetails? {
        switch store.sessionBackupStatus {
        case .current(let details):
            return details
        case .stale(let details, .outOfDate):
            return details
        case .disabled, .notCreated, .stale:
            return nil
        }
    }

    private func backupDetailsText(_ details: SessionBackupDetails) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale(for: localeOverride)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return L10n.format(
            "session.recovery.backup_details",
            localeOverride: localeOverride,
            defaultValue: "Резервная копия: %@ · загрузок: %lld",
            formatter.string(from: details.createdAt),
            details.torrentCount
        )
    }

    private var recoveryIssueMessage: String? {
        guard let issue = store.sessionRecoveryBackupIssue else { return nil }
        let key: String
        switch issue {
        case .outOfDate:
            key = "session.recovery.backup.out_of_date"
        case .folderUnavailable:
            key = "session.recovery.backup.folder_unavailable"
        case .permissionDenied:
            key = "session.recovery.backup.permission_denied"
        case .insufficientSpace:
            key = "session.recovery.backup.insufficient_space"
        case .invalidBackup:
            key = "session.recovery.backup.invalid"
        case .unknown:
            key = "session.recovery.backup.unknown"
        }
        return L10n.string(key, localeOverride: localeOverride)
    }

    private var backupAvailabilityMessage: String? {
        guard backupDetails == nil, store.sessionRecoveryBackupIssue == nil else { return nil }

        let key: String
        switch store.sessionBackupStatus {
        case .disabled:
            key = "session.recovery.backup.disabled"
        case .notCreated:
            key = "session.recovery.backup.not_created"
        case .stale(_, let issue):
            switch issue {
            case .outOfDate:
                return nil
            case .folderUnavailable:
                key = "session.recovery.backup.folder_unavailable"
            case .permissionDenied:
                key = "session.recovery.backup.permission_denied"
            case .insufficientSpace:
                key = "session.recovery.backup.insufficient_space"
            case .invalidBackup:
                key = "session.recovery.backup.invalid"
            case .unknown:
                key = "session.recovery.backup.unknown"
            }
        case .current:
            return nil
        }
        return L10n.string(key, localeOverride: localeOverride)
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
