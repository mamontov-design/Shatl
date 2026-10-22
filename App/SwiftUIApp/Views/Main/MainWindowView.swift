// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// The message about preparing downloads appears only when preparing takes a
/// while, and then stays long enough to be read: a quick launch shows
/// nothing, a slower one never flashes it for an instant. It just leaves when
/// the downloads are ready.
nonisolated enum SessionRestoreStatusTiming {
    static let revealDelay: TimeInterval = 0.5
    static let minimumVisibleDuration: TimeInterval = 2

    static func remainingVisibility(visibleFor elapsed: TimeInterval) -> TimeInterval {
        max(0, minimumVisibleDuration - max(0, elapsed))
    }
}

struct MainWindowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var addTorrentEntryAlert: TorrentErrorState?
    @State private var showsRestoreStatus = false
    @State private var restoreStatusShownAt: Date?
    @State private var restoreStatusTask: Task<Void, Never>?
    @State private var displayedSessionPersistenceIssue: SessionPersistenceIssue?
    @State private var isCheckingSessionPersistence = false
    @State private var didRequestNativeNotificationAuthorization = false
    /// The stage the window shows; it follows `currentStage` one step at a
    /// time, see `MainWindowStageStep`.
    @State private var displayedStage: MainWindowStage?
    @State private var stageChangeTask: Task<Void, Never>?
    /// What the window answers to a download dragged over it; `nil` with no
    /// such drag. While it is set, the drop screen takes the content's place.
    @State private var dropOffer: DraggedDownloadOffer?
    @State private var dropExitTask: Task<Void, Never>?
    /// The content height of the locked onboarding window; until the lock
    /// knows the window, the onboarding takes the height it is given.
    @State private var onboardingContentHeight: CGFloat?

    private var currentStage: MainWindowStage {
        MainWindowStage.current(
            hasLoadedInitialSession: store.hasLoadedInitialSession,
            sessionLoadIssue: displayedSessionLoadIssue,
            hasRows: !store.torrentRowIDs.isEmpty
        )
    }

    private var displayedSessionLoadIssue: SessionLoadIssue? {
        #if DEBUG
        return store.sessionLoadIssue ?? store.debugSessionLoadIssuePreview
        #else
        return store.sessionLoadIssue
        #endif
    }

    private var stage: MainWindowStage {
        displayedStage ?? currentStage
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
        Group {
            if store.onboardingPresentation.isPresented {
                onboardingRoot
            } else {
                regularWindowContent
            }
        }
        .onChange(of: store.hasLoadedInitialSession) { _, hasLoadedInitialSession in
            guard hasLoadedInitialSession else { return }
            store.presentInitialOnboardingIfNeeded()
        }
        .onChange(of: store.onboardingPresentation) { _, presentation in
            guard presentation.isPresented else { return }
            requestNativeNotificationAuthorizationIfNeeded()
        }
        .onChange(of: currentStage, initial: true) { _, targetStage in
            updateDisplayedStage(to: targetStage)
        }
        .onChange(of: store.isRestoringSession, initial: true) { _, isRestoringSession in
            updateRestoreStatus(isRestoringSession: isRestoringSession)
        }
        #if DEBUG
        .onChange(of: store.debugRestoreStatusPreviewRequestID) { _, _ in
            previewRestoreStatusForDebug()
        }
        #endif
        .onChange(of: store.sessionPersistenceIssue, initial: true) { _, newIssue in
            updateSessionPersistenceMessage(to: newIssue)
        }
        .onChange(of: store.addTorrentReviewWindowRequestID, initial: true) { _, requestID in
            guard !store.onboardingPresentation.isPresented,
                  requestID > 0,
                  store.isAddTorrentReviewWindowActive else {
                return
            }
            Task { @MainActor in
                await Task.yield()
                openWindow(id: AppWindowID.addTorrentReview)
            }
        }
        .onAppear {
            store.bootstrapRuntimeState()
            store.presentInitialOnboardingIfNeeded()

            if store.preferences.hasCompletedOnboarding {
                requestNativeNotificationAuthorizationIfNeeded()
            }
        }
        .onDisappear {
            restoreStatusTask?.cancel()
            stageChangeTask?.cancel()
            dropExitTask?.cancel()
        }
    }

    private var regularWindowContent: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if let displayedSessionPersistenceIssue {
                    sessionPersistenceMessageBar(for: displayedSessionPersistenceIssue)
                        .transition(restoreStatusTransition)
                        .zIndex(1)
                } else if showsRestoreStatus {
                    ShatlLineMessageBar(
                        title: L10n.string("session.restore.title", localeOverride: store.preferences.localeOverride),
                        message: L10n.string("session.restore.message", localeOverride: store.preferences.localeOverride)
                    )
                    .transition(restoreStatusTransition)
                    .zIndex(1)
                } else if let selectionCount = store.selectionCountShownInBar {
                    // Above the Halo notice: that one comes back once the
                    // selection is cleared.
                    ShatlSelectionCountBar(
                        count: selectionCount,
                        localeOverride: store.preferences.localeOverride
                    )
                    .transition(restoreStatusTransition)
                    .zIndex(1)
                } else if store.isHaloSpeedNoticeVisible {
                    haloSpeedNoticeBar
                        .transition(restoreStatusTransition)
                        .zIndex(1)
                }

                // The content gives way to the drop screen by fading and
                // stays where it is: taken out of the window, the list would
                // build every card again on its way back. Hidden, it takes no
                // clicks and no drops, or the empty list's link field would
                // catch a dragged link itself.
                contentView
                    .opacity(displayedDropOffer == nil ? 1 : 0)
                    .allowsHitTesting(displayedDropOffer == nil)
                    .overlay {
                        if let displayedDropOffer {
                            MainWindowDropScreen(
                                offer: displayedDropOffer,
                                localeOverride: store.preferences.localeOverride
                            )
                            .transition(stageTransition)
                        }
                    }
                    .animation(ShatlMotion.mainContentMode, value: displayedDropOffer)
            }
            .animation(ShatlMotion.sessionRestoreStatusBar, value: store.isHaloSpeedNoticeVisible)
            .animation(ShatlMotion.sessionRestoreStatusBar, value: store.selectionCountShownInBar != nil)

            TorrentTransferSummaryLayer(model: store.torrentTransferSummary)
                .environment(\.shatlRollsMetricDigits, store.cardSimplification < .lightest)
                .opacity(displayedDropOffer == nil ? 1 : 0)
                .animation(ShatlMotion.mainContentMode, value: displayedDropOffer)
        }
        // In light the list and the empty window stand on a grey ground
        // under the white cards; in dark the window keeps the system's
        // background, tinted by the wallpaper.
        .background {
            if colorScheme == .light {
                ShatlColor.Extra.macosWindowBackground.ignoresSafeArea()
            }
        }
        // Two listeners with one answer. The catcher lies over the content
        // and takes a drag before a system text field under it can; SwiftUI's
        // own drop stays for a drag that reaches the hosting view instead.
        .overlay {
            MainWindowDropCatcher(
                isAvailable: { acceptsDrops },
                onOffer: showDropOffer,
                onDrop: takeDrop
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onDrop(
            of: MainWindowDropLayout.draggedTypes,
            delegate: MainWindowDropDelegate(
                isAvailable: { acceptsDrops },
                onOffer: showDropOffer,
                onDrop: takeDrop
            )
        )
        // The window's smallest size. Here and not on the whole window: the
        // onboarding has a fixed size, and a lower minimum around it left
        // the window resizable between the two.
        .frame(minWidth: 440, minHeight: 440)
        .background(WindowChromeConfigurator(isSearchEnabled: stage.allowsListActions))
        // The same buttons and search in every stage, so the top of the window
        // never changes under a stage transition; what a stage does not allow
        // is only disabled.
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                ShatlToolbarButton(
                    title: L10n.string(
                        "toolbar.add",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Добавить"
                    ),
                    systemImage: "plus",
                    isDisabled: !stage.allowsListActions || !store.canAddTorrent
                ) {
                    store.presentAddTorrentEntry()
                }

                // For several selected downloads: Start while any of them
                // is stopped, Stop once all of them run.
                let startsSelection = store.toolbarRunAction == .start

                ShatlToolbarButton(
                    title: L10n.string(
                        startsSelection ? "toolbar.start" : "toolbar.stop",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: startsSelection ? "Пуск" : "Стоп"
                    ),
                    systemImage: startsSelection ? "play" : "stop",
                    isDisabled: stage != .list || !store.isToolbarStartStopEnabled
                ) {
                    store.toggleSelectedTorrentsRunningState()
                }

                ShatlToolbarButton(
                    title: L10n.string(
                        "toolbar.delete",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Удалить"
                    ),
                    systemImage: "trash",
                    role: .destructive,
                    isDisabled: stage != .list || !store.isToolbarRemoveEnabled
                ) {
                    presentToolbarRemovalDialog()
                }
            }
        }
        .modifier(
            MainWindowSearchModifier(
                isEnabled: stage.allowsListActions,
                searchText: $searchText,
                prompt: L10n.string(
                    "toolbar.search",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Поиск"
                )
            )
        )
        .onChange(of: stage.allowsListActions) { _, allowsListActions in
            if !allowsListActions {
                searchText = ""
            }
        }
        // A download shown from the add window must not stay hidden by a search.
        .onChange(of: store.listRevealRequest) { _, request in
            if request != nil, !searchText.isEmpty {
                searchText = ""
            }
        }
        .sheet(isPresented: isAddTorrentEntryPresented) {
            AddTorrentEntryView(
                placement: .modal,
                onValidationError: presentAddTorrentEntryAlert
            )
                .environmentObject(store)
        }
        .alert(item: activeAlert) { alert in
            let okButton = Text(L10n.string("common.ok", localeOverride: store.preferences.localeOverride))
            // Files left after a deletion can still be found from here.
            if let revealURL = alert.revealURL {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(okButton),
                    secondaryButton: .default(
                        Text(L10n.string("torrent.action.reveal_in_finder", localeOverride: store.preferences.localeOverride))
                    ) {
                        NSWorkspace.shared.activateFileViewerSelecting([revealURL] + alert.additionalRevealURLs)
                    }
                )
            }
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(okButton)
            )
        }
    }

    private var onboardingRoot: some View {
        OnboardingFlowView(
            localeOverride: store.preferences.localeOverride,
            metricsMode: store.preferences.metricsMode,
            onClose: completeOnboarding,
            onEnableUsageStatistics: {
                store.answerUsageStatisticsOnboarding(allowStatistics: true)
            }
        )
        .frame(width: OnboardingWindowLayout.windowSize.width)
        // The height the window lock keeps, so SwiftUI sizes the window the
        // same way. Open-ended, it gave the window back its resizing, and
        // macOS its zoom button, on every animation frame (macOS 26).
        .frame(minHeight: onboardingContentHeight, maxHeight: onboardingContentHeight ?? .infinity)
        .overlay {
            OnboardingWindowSizeLock(
                onWindowClose: completeOnboarding,
                onContentHeightChange: { onboardingContentHeight = $0 }
            )
                .allowsHitTesting(false)
        }
        .environment(\.locale, L10n.locale(for: store.preferences.localeOverride))
        .shatlTypographyProfile(localeOverride: store.preferences.localeOverride)
    }

    @ViewBuilder
    private var contentView: some View {
        ZStack(alignment: .topLeading) {
            switch stage {
            case .loadingSession:
                SessionLoadBlockingView(issue: nil, localeOverride: store.preferences.localeOverride)
                    .transition(stageTransition)
            case .sessionLoadFailure(let issue):
                SessionLoadBlockingView(
                    issue: issue,
                    localeOverride: store.preferences.localeOverride
                )
                    .transition(stageTransition)
            case .empty:
                EmptyStateView(
                    isDragInProgress: displayedDropOffer != nil,
                    onEntryValidationError: presentAddTorrentEntryAlert
                )
                    .transition(stageTransition)
                    .zIndex(1)
            case .list:
                TorrentListViewport(
                    summaryVisibility: store.torrentTransferSummary.visibility,
                    searchText: searchText,
                    onRemoveSelected: presentToolbarRemovalDialog
                )
                    .transition(stageTransition)
                    .zIndex(0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A drop is taken where the add button would work: over the list or
    /// the empty list, with nothing else being added.
    private var acceptsDrops: Bool {
        (stage == .list || stage == .empty) && store.acceptsDraggedDownloads
    }

    private var displayedDropOffer: DraggedDownloadOffer? {
        #if DEBUG
        return dropOffer ?? store.debugDropOfferPreview
        #else
        return dropOffer
        #endif
    }

    private func takeDrop(_ download: DraggedDownload) {
        showDropOffer(nil, afterDelay: false)
        store.addDraggedDownload(download)
    }

    private func showDropOffer(_ offer: DraggedDownloadOffer?) {
        showDropOffer(offer, afterDelay: true)
    }

    /// The drop screen comes at once and goes after a moment, unless the
    /// drag is back by then; a release takes it away at once.
    private func showDropOffer(_ offer: DraggedDownloadOffer?, afterDelay: Bool) {
        dropExitTask?.cancel()
        dropExitTask = nil

        guard offer == nil, afterDelay else {
            dropOffer = offer
            return
        }

        dropExitTask = Task { @MainActor in
            try? await Task.sleep(for: ShatlMotion.dropScreenExitDelay)
            guard !Task.isCancelled else { return }
            dropOffer = nil
        }
    }

    private var stageTransition: AnyTransition {
        reduceMotion ? .opacity : ShatlMotion.mainContent
    }

    /// The only place the stage changes, always in one transaction with one
    /// animation; a newer target cancels a change still waiting.
    private func updateDisplayedStage(to targetStage: MainWindowStage) {
        stageChangeTask?.cancel()
        stageChangeTask = nil

        guard let displayedStage else {
            // The first stage appears as it is, without a transition.
            self.displayedStage = targetStage
            return
        }

        switch MainWindowStageStep.step(from: displayedStage, to: targetStage) {
        case .stay:
            break
        case .switchNow(let stage):
            showStage(stage)
        case .switchAfterCardRemoval(let stage):
            stageChangeTask = Task {
                do {
                    try await Task.sleep(for: .seconds(ShatlMotion.cardListMutationDuration))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                showStage(stage)
            }
        }
    }

    private func showStage(_ stage: MainWindowStage) {
        withAnimation(ShatlMotion.mainContentMode) {
            displayedStage = stage
        }
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
            hideRestoreStatusOnceRead()
        }
    }

    private func beginRestoreStatusDelay() {
        restoreStatusTask?.cancel()
        guard !showsRestoreStatus else { return }

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
            setRestoreStatusVisible(true)
        }
    }

    private func hideRestoreStatusOnceRead() {
        restoreStatusTask?.cancel()
        guard showsRestoreStatus else {
            restoreStatusShownAt = nil
            return
        }

        let visibleFor = restoreStatusShownAt.map { Date().timeIntervalSince($0) } ?? 0
        let remaining = SessionRestoreStatusTiming.remainingVisibility(visibleFor: visibleFor)
        restoreStatusTask = Task {
            if remaining > 0 {
                do {
                    try await Task.sleep(for: .seconds(remaining))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            restoreStatusShownAt = nil
            setRestoreStatusVisible(false)
        }
    }

    #if DEBUG
    /// Plays the message as a launch whose preparation takes three seconds:
    /// it appears after the reveal delay and leaves once read.
    private func previewRestoreStatusForDebug() {
        restoreStatusTask?.cancel()
        restoreStatusTask = Task {
            let preparation: TimeInterval = 3
            do {
                if !showsRestoreStatus {
                    try await Task.sleep(for: .seconds(SessionRestoreStatusTiming.revealDelay))
                    restoreStatusShownAt = Date()
                    setRestoreStatusVisible(true)
                }
                try await Task.sleep(for: .seconds(preparation - SessionRestoreStatusTiming.revealDelay))
            } catch {
                return
            }
            hideRestoreStatusOnceRead()
        }
    }
    #endif

    private func setRestoreStatusVisible(_ isVisible: Bool) {
        withAnimation(ShatlMotion.sessionRestoreStatusBar) {
            showsRestoreStatus = isVisible
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
            buttons: [
                ShatlLineMessageBarButton(
                    title: L10n.string(
                        "session.persistence.line.check_again",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Проверить снова"
                    ),
                    busyTitle: L10n.string(
                        "session.persistence.line.checking",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Проверка…"
                    ),
                    isBusy: isCheckingSessionPersistence,
                    action: checkSessionPersistenceAgain
                ),
                ShatlLineMessageBarButton(
                    title: L10n.string(
                        "session.persistence.line.hide",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Скрыть"
                    ),
                    action: { store.hideSessionPersistenceIssue() }
                ),
            ]
        )
    }

    /// Why speed is limited in Halo, with the way out on a button.
    private var haloSpeedNoticeBar: some View {
        ShatlLineMessageBar(
            title: L10n.string("halo_notice.title", localeOverride: store.preferences.localeOverride),
            message: L10n.string("halo_notice.message", localeOverride: store.preferences.localeOverride),
            buttons: Self.haloSpeedNoticeButtons(
                localeOverride: store.preferences.localeOverride,
                dismiss: { store.dismissHaloSpeedNotice() },
                switchToOrbit: { store.setPerformanceProfile(.balanced) },
                stopShowing: { store.stopShowingHaloSpeedNotice() }
            )
        )
    }

    /// Kept apart so a test can measure them in every language.
    static func haloSpeedNoticeButtons(
        localeOverride: AppLocaleOverride,
        dismiss: @escaping () -> Void = {},
        switchToOrbit: @escaping () -> Void = {},
        stopShowing: @escaping () -> Void = {}
    ) -> [ShatlLineMessageBarButton] {
        [
            ShatlLineMessageBarButton(
                title: L10n.string("halo_notice.got_it", localeOverride: localeOverride),
                action: dismiss
            ),
            ShatlLineMessageBarButton(
                title: L10n.string("halo_notice.switch_to_orbit", localeOverride: localeOverride),
                action: switchToOrbit
            ),
            ShatlLineMessageBarButton(
                title: L10n.string("halo_notice.never_show", localeOverride: localeOverride),
                action: stopShowing
            ),
        ]
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
        TorrentSelectionActions.presentRemovalChoice(in: store)
    }

    private func completeOnboarding() {
        store.completeOnboarding()
    }

    private func requestNativeNotificationAuthorizationIfNeeded() {
        guard !didRequestNativeNotificationAuthorization else { return }

        didRequestNativeNotificationAuthorization = true
        Task {
            _ = await MacNotificationAuthorizationRequester.requestNativeAuthorization()
        }
    }

}

private struct TorrentListViewport: View {
    @ObservedObject var summaryVisibility: TorrentTransferSummaryVisibilityModel
    let searchText: String
    let onRemoveSelected: () -> Void

    var body: some View {
        TorrentListView(
            searchText: searchText,
            bottomContentPadding: bottomListPadding,
            onRemoveSelected: onRemoveSelected
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
        // The upload chip keeps to the right edge, so a wider or narrower
        // number moves its left edge: the row slides it at the chip's own
        // pace. It jumped there at once while the glass was on its way.
        .geometryGroup()
        // Inside the width animation, so a chip that comes or goes keeps
        // its own pace.
        .animation(ShatlMotion.mainContentMode, value: chipStructureAnimationKey)
        .animation(ShatlMotion.metricResize, value: chipWidthAnimationKey)
    }

    private var chipStructureAnimationKey: [String] {
        model.chips.map(\.kind.id)
    }

    private var chipWidthAnimationKey: [MetricItemWidthAnimationSignature] {
        model.chips.map(\.item.widthAnimationSignature)
    }

    private var edgePadding: CGFloat {
        if #available(macOS 27.0, *) {
            return ShatlBottomChipLayout.modernEdgePadding
        }

        return ShatlBottomChipLayout.legacyEdgePadding
    }
}

/// How many downloads are selected and how to clear the selection: one
/// line under the toolbar, the count in the bar's title style and the hint
/// in its text style. The count rolls as it changes.
struct ShatlSelectionCountBar: View {
    let count: Int
    let localeOverride: AppLocaleOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.partSpacing) {
            Text(Self.countText(count, localeOverride: localeOverride))
                .shatlTypography(ShatlTypography.bodySemibold)
                .foregroundStyle(ShatlColor.lineMessageHeadline)
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(count)))
                .fixedSize()

            Text(Self.hintText(localeOverride: localeOverride))
                .shatlTypography(ShatlTypography.bodyRegular)
                .foregroundStyle(ShatlColor.lineMessageCaption)
                .lineLimit(1)
        }
        // The hint follows the count as its width changes.
        .geometryGroup()
        .animation(ShatlMotion.metricResize, value: count)
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShatlColor.lineMessageBackground)
        .accessibilityElement(children: .combine)
    }

    /// The gap of a word space between the two parts.
    static let partSpacing: CGFloat = 4
    /// The same left edge as the text of the other bars.
    static let horizontalPadding: CGFloat = 18

    static func countText(_ count: Int, localeOverride: AppLocaleOverride) -> String {
        L10n.format(
            L10n.pluralKey("selection.bar.count", count: count, localeOverride: localeOverride),
            localeOverride: localeOverride,
            defaultValue: "%lld",
            count
        )
    }

    static func hintText(localeOverride: AppLocaleOverride) -> String {
        L10n.string("selection.bar.hint", localeOverride: localeOverride)
    }
}

/// A button of the line message bar.
struct ShatlLineMessageBarButton: Identifiable {
    var id: String { title }
    let title: String
    var busyTitle: String? = nil
    /// While one button's action runs, it shows its busy title and the
    /// others look disabled, so nothing interrupts it.
    var isBusy = false
    let action: () -> Void
}

/// A message under the toolbar: a title, a short text and, when there is
/// something to do, buttons.
struct ShatlLineMessageBar: View {
    let title: String
    let message: String
    var buttons: [ShatlLineMessageBarButton] = []

    private var isAnyButtonBusy: Bool {
        buttons.contains(where: \.isBusy)
    }

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

            if !buttons.isEmpty {
                HStack(spacing: 8) {
                    ForEach(buttons) { button in
                        ShatlButton(
                            title: button.title,
                            busyTitle: button.busyTitle,
                            isBusy: button.isBusy,
                            role: .lineMessage,
                            isDisabled: isAnyButtonBusy && !button.isBusy,
                            action: button.action
                        )
                    }
                }
                // The other buttons slide with a resizing busy button, like
                // neighbors in the expanded metric row.
                .geometryGroup()
                .animation(ShatlMotion.metricResize, value: isAnyButtonBusy)
            }
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
    @EnvironmentObject private var updaterController: ShatlUpdaterController

    let issue: SessionLoadIssue?
    let localeOverride: AppLocaleOverride
    /// Reading the session usually takes a moment; the message waits so a
    /// quick launch does not flash it.
    @State private var showsLoadingMessage = false

    var body: some View {
        ZStack {
            if issue != nil {
                recoveryCard
            } else if showsLoadingMessage {
                ShatlMessageBlockPrimary(
                    systemImage: "clock.arrow.trianglehead.2.counterclockwise.rotate.90",
                    title: title,
                    message: L10n.string(
                        "session.load.in_progress.message",
                        localeOverride: localeOverride,
                        defaultValue: "Загрузки возвращаются к состоянию на момент закрытия. Подождите, пожалуйста."
                    )
                )
                .transition(.opacity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: issue == nil) {
            guard issue == nil, !showsLoadingMessage else { return }
            do {
                try await Task.sleep(for: ShatlMotion.sessionLoadMessageDelay)
            } catch {
                return
            }
            withAnimation(ShatlMotion.mainContentMode) {
                showsLoadingMessage = true
            }
        }
    }

    @ViewBuilder
    private var recoveryCard: some View {
        if case .unsupportedVersion = issue {
            // The list opens in the latest version: offer it first, from
            // the updater or the site, and the empty list only after it.
            ShatlMessageBlockPrimary(
                title: title,
                message: message,
                primaryButton: ShatlMessageBlockPrimaryButton(
                    title: L10n.string(
                        "settings.about.check_updates",
                        localeOverride: localeOverride,
                        defaultValue: "Проверить обновления…"
                    ),
                    isDisabled: !updaterController.canCheckForUpdates,
                    lineLimit: nil
                ) {
                    updaterController.checkForUpdates()
                },
                secondaryButtons: [
                    ShatlMessageBlockPrimaryButton(
                        title: L10n.string(
                            "session.recovery.open_site",
                            localeOverride: localeOverride,
                            defaultValue: "Скачать с сайта…"
                        ),
                        lineLimit: nil
                    ) {
                        NSWorkspace.shared.open(ShatlLinks.website)
                    },
                    openEmptyListButton,
                ]
            )
        } else {
            ShatlMessageBlockPrimary(
                title: title,
                message: message,
                primaryButton: openEmptyListButton
            )
        }
    }

    private var openEmptyListButton: ShatlMessageBlockPrimaryButton {
        ShatlMessageBlockPrimaryButton(
            title: L10n.string(
                "session.recovery.open_empty",
                localeOverride: localeOverride,
                defaultValue: "Запуск с пустым списком"
            ),
            isDisabled: store.isResolvingSessionRecovery,
            lineLimit: nil
        ) {
            store.openWithEmptyDownloadList()
        }
    }

    private var title: String {
        guard let issue else {
            return L10n.string(
                "session.load.in_progress.title",
                localeOverride: localeOverride,
                defaultValue: "Список загрузок восстанавливается."
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

    var revealURL: URL? {
        switch self {
        case .addTorrentEntry:
            nil
        case let .payloadDeletion(alert):
            alert.revealURL
        }
    }

    /// The files of the other downloads, when several were removed at once.
    var additionalRevealURLs: [URL] {
        switch self {
        case .addTorrentEntry:
            []
        case let .payloadDeletion(alert):
            alert.additionalRevealURLs
        }
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    let isSearchEnabled: Bool

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
            window.titleVisibility = .visible
            MainWindowSearchToolbarItem.setEnabled(isSearchEnabled, in: window)
        }
    }
}
