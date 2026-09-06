// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Combine
import Foundation

/// The main store is the single source of truth for the UI.
@MainActor
final class AppStore: ObservableObject, ShatlTerminationPreparing, ShatlUserAttentionHandling {
    private static let logger = ShatlLog.appStore
    private static let traceLogger = ShatlLog.trace
    private static let restoreProgressRegressionTolerance = 0.02

    private struct TransitionTraceContext {
        let operationID: String
        let action: String
        let startedAtUptimeNs: UInt64
        var slowTask: Task<Void, Never>?
        var stalledTask: Task<Void, Never>?
    }

    struct TorrentNavigationAvailability: Equatable {
        var canOpen = false
        var canReveal = false
    }

    @Published var torrents: [TorrentRecord]
    @Published var selectedTorrentID: UUID?
    @Published var expandedTorrentID: UUID?
    @Published var preferences: AppPreferences {
        didSet {
            if oldValue.canSendAnonymousUsageStatistics && !preferences.canSendAnonymousUsageStatistics {
                clearUsageTelemetryActiveState()
            }
            preferencesStore?.save(preferences)
            ShatlFileLogger.shared.setEnabled(preferences.isLoggingEnabled)
            ShatlDiskDiagnosticsLog.setEnabled(preferences.isDiskDiagnosticsLoggingEnabled)
            ShatlMetricAnimationDiagnosticsLog.setEnabled(
                preferences.isMetricAnimationDiagnosticsLoggingEnabled
            )
            ShatlSnapshotDiagnosticsLog.setEnabled(preferences.isSnapshotDiagnosticsLoggingEnabled)
            ShatlAddTorrentReviewDiagnosticsLog.setEnabled(
                preferences.isAddTorrentReviewDiagnosticsLoggingEnabled
            )
        }
    }

    private func clearUsageTelemetryActiveState() {
        usageTelemetrySendTask?.cancel()
        usageTelemetrySendTask = nil

        do {
            _ = try usageTelemetryCoordinator?.setStatisticsEnabled(
                false,
                localeIdentifier: usageTelemetryLocaleIdentifier,
                appVersion: appVersion
            )
        } catch {
            Self.logger.error("Failed to clear usage telemetry state: \(error.localizedDescription)")
        }
    }
    @Published var payloadDeletionAlert: PayloadDeletionAlert?
    @Published var presentedModal: PresentedModal?
    @Published var currentAddTorrentDraft: AddTorrentDraft?
    @Published var isRestoringSession = false
    @Published private(set) var hasLoadedInitialSession: Bool
    @Published private(set) var sessionLoadIssue: SessionLoadIssue?
    @Published private(set) var transitioningTorrentIDs: Set<UUID> = []
    @Published private(set) var selectedTorrentNavigationAvailability = TorrentNavigationAvailability()

    private let engine: any TorrentEngine
    private let preferencesStore: AppPreferencesStore?
    private let sessionStore: SessionStore
    private let torrentArchiveStore: TorrentArchiveStore
    private let bookmarkStore: BookmarkStore
    private let sessionRestoreCoordinator: SessionRestoreCoordinator
    private let diskIssueDetector: DiskIssueDetector
    private let torrentPayloadLocator: TorrentPayloadLocator
    private let torrentPayloadDeletionService: TorrentPayloadDeletionService
    private let externalOpenRouter: ExternalOpenRouter
    private let userEventNotifier: (any TorrentUserEventNotifying)?
    private let userEventBadgeDisplay: (any TorrentUserEventBadgeDisplaying)?
    private let usageTelemetryCoordinator: UsageTelemetryLocalCoordinator?
    private let usageTelemetrySender: (any UsageTelemetrySending)?
    private let launchID = UUID().uuidString

    private var runtimeTask: Task<Void, Never>?
    private var initialSessionLoadTask: Task<SessionLoadResult, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var draftPreparationTask: Task<Void, Never>?
    private var performanceApplyTask: Task<Void, Never>?
    private var usageTelemetrySendTask: Task<Void, Never>?
    private var lastRequestedPerformanceSettings: EnginePerformanceSettings?
    private var didBootstrap = false
    private var didResolveInitialSessionLoad = false
    private var didCompleteRuntimeBootstrap = false
    private var isEngineReady = false
    private var activeRefreshTick = 0
    private var isPreparingForTermination = false
    private var pendingConfirmedTorrent: TorrentRecord?
    private var pendingIncomingURLs: [URL] = []
    /// Torrents that must intentionally ignore engine snapshots.
    /// Prevents delayed polling from resurrecting an already stopped torrent.
    private var detachedTorrentIDs: Set<UUID> = []
    /// Temporary restoration used for manual rechecks of sleeping torrents.
    /// The handle is removed from the engine when the check completes.
    private var temporarilyRestoredRecheckTorrentIDs: Set<UUID> = []
    /// Restores a card to its original sleeping state after a temporary recheck
    /// instead of leaving it in an active runtime state.
    private var temporaryRecheckPostCheckStatusByID: [UUID: TorrentStatus] = [:]
    private var pendingTemporaryRecheckDetachIDs: Set<UUID> = []
    /// Some sleeping states arrive paused while their engine handle is still alive.
    /// Detach such a handle after its first final snapshot so the store and engine
    /// agree that a sleeping torrent has no active handle.
    private var pendingSleepingDetachIDs: Set<UUID> = []
    private var restoreProgressFloorByID: [UUID: Double] = [:]
    private var restoreRecheckRequestedIDs: Set<UUID> = []
    private var transitionTracesByTorrentID: [UUID: TransitionTraceContext] = [:]
    private var allowsUserFacingNotifications = false
    private var isApplicationUserAttentionActive = false
    private var notifiedCompletedTorrentIDs: Set<UUID> = []
    private var notifiedPersistentIssueKeys: Set<PersistentIssueNotificationKey> = []
    private var unreadCompletedTorrentIDs: Set<UUID> = []
    private var unreadPersistentIssueKeys: Set<PersistentIssueNotificationKey> = []

    private struct PersistentIssueNotificationKey: Hashable {
        var torrentID: UUID
        var kind: TorrentPersistentIssue.Kind
    }

    init(
        engine: any TorrentEngine,
        preferencesStore: AppPreferencesStore? = nil,
        sessionStore: SessionStore,
        torrentArchiveStore: TorrentArchiveStore,
        bookmarkStore: BookmarkStore,
        sessionRestoreCoordinator: SessionRestoreCoordinator,
        diskIssueDetector: DiskIssueDetector,
        torrentPayloadLocator: TorrentPayloadLocator,
        torrentPayloadDeletionService: TorrentPayloadDeletionService,
        externalOpenRouter: ExternalOpenRouter,
        userEventNotifier: (any TorrentUserEventNotifying)? = nil,
        userEventBadgeDisplay: (any TorrentUserEventBadgeDisplaying)? = nil,
        usageTelemetryCoordinator: UsageTelemetryLocalCoordinator? = nil,
        usageTelemetrySender: (any UsageTelemetrySending)? = nil,
        torrents: [TorrentRecord] = [],
        preferences: AppPreferences? = nil,
        hasLoadedInitialSession: Bool = false
    ) {
        self.preferencesStore = preferencesStore
        self.engine = engine
        self.sessionStore = sessionStore
        self.torrentArchiveStore = torrentArchiveStore
        self.bookmarkStore = bookmarkStore
        self.sessionRestoreCoordinator = sessionRestoreCoordinator
        self.diskIssueDetector = diskIssueDetector
        self.torrentPayloadLocator = torrentPayloadLocator
        self.torrentPayloadDeletionService = torrentPayloadDeletionService
        self.externalOpenRouter = externalOpenRouter
        self.userEventNotifier = userEventNotifier
        self.userEventBadgeDisplay = userEventBadgeDisplay
        self.usageTelemetryCoordinator = usageTelemetryCoordinator
        self.usageTelemetrySender = usageTelemetrySender
        self.torrents = torrents
        let resolvedHasLoadedInitialSession = hasLoadedInitialSession || !torrents.isEmpty
        self.hasLoadedInitialSession = resolvedHasLoadedInitialSession
        self.sessionLoadIssue = nil
        self.allowsUserFacingNotifications = resolvedHasLoadedInitialSession
        let resolvedPreferences = preferences ?? preferencesStore?.load() ?? .defaultValue
        self.preferences = resolvedPreferences
        ShatlFileLogger.shared.setEnabled(resolvedPreferences.isLoggingEnabled)
        ShatlDiskDiagnosticsLog.setEnabled(resolvedPreferences.isDiskDiagnosticsLoggingEnabled)
        ShatlMetricAnimationDiagnosticsLog.setEnabled(
            resolvedPreferences.isMetricAnimationDiagnosticsLoggingEnabled
        )
        ShatlSnapshotDiagnosticsLog.setEnabled(resolvedPreferences.isSnapshotDiagnosticsLoggingEnabled)
        ShatlAddTorrentReviewDiagnosticsLog.setEnabled(
            resolvedPreferences.isAddTorrentReviewDiagnosticsLoggingEnabled
        )

        externalOpenRouter.attach { [weak self] url in
            self?.handleIncomingURL(url)
        }

        recordUsageTelemetryLaunchIfNeeded()
    }

    deinit {
        runtimeTask?.cancel()
        initialSessionLoadTask?.cancel()
        bootstrapTask?.cancel()
        draftPreparationTask?.cancel()
        performanceApplyTask?.cancel()
        usageTelemetrySendTask?.cancel()
        for context in transitionTracesByTorrentID.values {
            context.slowTask?.cancel()
            context.stalledTask?.cancel()
        }
    }

    var selectedTorrent: TorrentRecord? {
        guard let selectedTorrentID else { return nil }
        return torrents.first(where: { $0.id == selectedTorrentID })
    }

    var torrentRowIDs: [UUID] {
        torrents.map(\.id)
    }

    var bottomTransferChips: [BottomTransferChipPresentation] {
        TorrentPresentation.bottomTransferChips(
            for: torrents,
            mode: preferences.metricsMode,
            localeOverride: preferences.localeOverride
        )
    }

    func torrentRowIDs(matching searchQuery: String) -> [UUID] {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return torrentRowIDs }

        return torrents
            .filter { record in
                record.originalName.localizedCaseInsensitiveContains(normalizedQuery)
                    || record.alias?.localizedCaseInsensitiveContains(normalizedQuery) == true
            }
            .map(\.id)
    }

    func clearHiddenSelection(visibleTorrentIDs: [UUID]) {
        let visibleIDs = Set(visibleTorrentIDs)

        if let selectedTorrentID, !visibleIDs.contains(selectedTorrentID) {
            self.selectedTorrentID = nil
            selectedTorrentNavigationAvailability = TorrentNavigationAvailability()
        }

        if let expandedTorrentID, !visibleIDs.contains(expandedTorrentID) {
            self.expandedTorrentID = nil
        }
    }

    func torrentRecord(for id: UUID) -> TorrentRecord? {
        torrents.first(where: { $0.id == id })
    }

    func rowState(for id: UUID) -> TorrentRowState? {
        guard let record = torrents.first(where: { $0.id == id }) else { return nil }

        let isSelected = selectedTorrentID == record.id
        let isExpanded = expandedTorrentID == record.id
        let errorState = TorrentRowErrorState(record.errorState, localeOverride: preferences.localeOverride)
        let compactTransferMetricSet = errorState == nil
            ? TorrentPresentation.compactTransferMetricSet(
                for: record,
                mode: preferences.metricsMode,
                localeOverride: preferences.localeOverride
            )
            : nil
        let compactMetrics = errorState == nil
            ? TorrentPresentation.compactMetrics(
                for: record,
                mode: preferences.metricsMode,
                localeOverride: preferences.localeOverride
            )
            : []
        let expandedMetrics = errorState == nil && isExpanded
            ? TorrentPresentation.expandedMetrics(
                for: record,
                mode: preferences.metricsMode,
                localeOverride: preferences.localeOverride
            )
            : []
        let expandedMetricGroups = errorState == nil && isExpanded
            ? TorrentPresentation.expandedMetricGroups(
                for: record,
                mode: preferences.metricsMode,
                localeOverride: preferences.localeOverride
            )
            : nil
        let navigationAvailabilityKey = [
            record.id.uuidString,
            errorState?.kind.rawValue ?? "healthy",
            record.canonicalSavePath,
            "\(record.selectedFileCount)",
            "\(record.totalFileCount)",
            record.isFinishedForOpening ? "open-ready" : "open-not-ready",
        ].joined(separator: "|")

        return TorrentRowState(
            id: record.id,
            title: record.displayName,
            originalTitle: record.originalName,
            hasAlias: record.alias?.isEmpty == false,
            status: record.status,
            statusTitle: record.status.localizedTitle(localeOverride: preferences.localeOverride),
            progress: record.progress,
            downloadSpeedBytesPerSecond: record.metrics.downloadSpeedBytesPerSecond,
            uploadSpeedBytesPerSecond: record.metrics.uploadSpeedBytesPerSecond,
            visibleProgressPercent: record.visibleProgressPercent,
            compactTransferMetricSet: compactTransferMetricSet,
            compactMetrics: compactMetrics,
            expandedMetrics: expandedMetrics,
            expandedMetricGroups: expandedMetricGroups,
            metricsMode: preferences.metricsMode,
            colorizesDownloadSpeed: preferences.colorizesDownloadSpeed,
            errorState: errorState,
            isSelected: isSelected,
            isExpanded: isExpanded,
            canToggleRunningState: canToggleRunningState(for: record.id),
            canRemoveFromList: canRemoveFromList(for: record.id),
            canRemoveWithFiles: canRemoveWithFiles(for: record.id),
            navigationAvailabilityKey: navigationAvailabilityKey,
            localeOverride: preferences.localeOverride
        )
    }

    func setPerformanceProfile(_ profile: AppPerformanceProfile) {
        guard preferences.performanceProfile != profile else { return }

        preferences.performanceProfile = profile
        schedulePerformanceSettingsApply()
    }

    func setDefaultDownloadLocation(_ url: URL, bookmarkData: Data?) {
        let normalizedPath = NSString(string: url.path).standardizingPath
        guard preferences.defaultDownloadPath != normalizedPath
                || preferences.defaultDownloadBookmarkData != bookmarkData else { return }

        preferences.defaultDownloadPath = normalizedPath
        preferences.defaultDownloadBookmarkData = bookmarkData
    }

    func setSendsAnonymousUsageStatistics(_ isEnabled: Bool) {
        setUsageStatisticsConsent(isEnabled: isEnabled, hasAnsweredOnboarding: true)
    }

    func answerUsageStatisticsOnboarding(allowStatistics: Bool) {
        setUsageStatisticsConsent(
            isEnabled: allowStatistics,
            hasAnsweredOnboarding: true
        )
    }

    func completeOnboarding() {
        preferences.hasCompletedOnboarding = true
    }

    func setPreferredBrandMark(_ brandMark: ShatlBrandMark) {
        guard preferences.preferredBrandMark != brandMark else { return }
        preferences.preferredBrandMark = brandMark
    }

    private func setUsageStatisticsConsent(isEnabled: Bool, hasAnsweredOnboarding: Bool) {
        guard preferences.sendsAnonymousUsageStatistics != isEnabled
                || preferences.hasAnsweredUsageStatisticsOnboarding != hasAnsweredOnboarding else {
            return
        }

        let payload: UsageTelemetryPayload?
        do {
            payload = try usageTelemetryCoordinator?.setStatisticsEnabled(
                isEnabled && hasAnsweredOnboarding,
                localeIdentifier: usageTelemetryLocaleIdentifier,
                appVersion: appVersion
            )
        } catch {
            Self.logger.error("Failed to update usage telemetry state: \(error.localizedDescription)")
            payload = nil
        }

        preferences.hasAnsweredUsageStatisticsOnboarding = hasAnsweredOnboarding
        preferences.sendsAnonymousUsageStatistics = isEnabled

        if preferences.canSendAnonymousUsageStatistics, let payload {
            sendUsageTelemetryIfNeeded(payload)
        } else {
            usageTelemetrySendTask?.cancel()
            usageTelemetrySendTask = nil
        }
    }

    func ensureUsageTelemetryInspectablePayload() -> URL? {
        do {
            return try usageTelemetryCoordinator?.ensureInspectablePayloadIfAvailable(
                isEnabled: preferences.canSendAnonymousUsageStatistics,
                localeIdentifier: usageTelemetryLocaleIdentifier,
                appVersion: appVersion
            )
        } catch {
            Self.logger.error("Failed to prepare usage telemetry payload: \(error.localizedDescription)")
            return nil
        }
    }

    private var usageTelemetryLocaleIdentifier: String {
        preferences.localeOverride.localeIdentifier
            ?? Locale.current.language.languageCode?.identifier
            ?? Locale.current.identifier
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func recordUsageTelemetryLaunchIfNeeded() {
        guard preferences.canSendAnonymousUsageStatistics else { return }

        do {
            guard let payload = try usageTelemetryCoordinator?.recordLaunchIfEnabled(
                isEnabled: true,
                localeIdentifier: usageTelemetryLocaleIdentifier,
                appVersion: appVersion
            ) else {
                return
            }

            sendUsageTelemetryIfNeeded(payload)
        } catch {
            Self.logger.error("Failed to record usage telemetry launch: \(error.localizedDescription)")
        }
    }

    private func sendUsageTelemetryIfNeeded(_ payload: UsageTelemetryPayload) {
        guard preferences.canSendAnonymousUsageStatistics else { return }
        guard shouldSendUsageTelemetry(payload) else { return }
        guard let usageTelemetrySender else { return }

        usageTelemetrySendTask?.cancel()
        usageTelemetrySendTask = Task { [weak self, usageTelemetrySender] in
            do {
                try await usageTelemetrySender.send(payload)
                await MainActor.run {
                    guard let self else { return }
                    self.preferences.lastUsageStatisticsSentAt = Date()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    Self.logger.error("Failed to send usage telemetry: \(error.localizedDescription)")
                }
            }
        }
    }

    private func shouldSendUsageTelemetry(_ payload: UsageTelemetryPayload) -> Bool {
        guard let lastSentAt = preferences.lastUsageStatisticsSentAt else {
            return true
        }

        return UsageTelemetryWeek.identifier(for: lastSentAt) != payload.week
    }

    func prepareForTermination() async {
        guard !isPreparingForTermination else { return }
        isPreparingForTermination = true

        runtimeTask?.cancel()
        draftPreparationTask?.cancel()
        performanceApplyTask?.cancel()

        if let initialSessionLoadTask {
            let result = await initialSessionLoadTask.value
            _ = await resolveInitialSessionLoad(result)
        }

        guard !didBootstrap || (didCompleteRuntimeBootstrap && sessionLoadIssue == nil) else {
            return
        }

        await refreshActiveSnapshots()
        await checkpointActiveTorrentsForTermination()
        await persistCriticalState()
    }

    /// The toolbar must not offer removal actions for cards with persistent issues.
    var canAddTorrent: Bool {
        guard hasLoadedInitialSession,
              sessionLoadIssue == nil,
              !isPreparingForTermination else {
            return false
        }
        return !didBootstrap || isEngineReady
    }

    var isToolbarRemoveEnabled: Bool {
        guard let selectedTorrent else { return false }
        return selectedTorrent.persistentIssue == nil
            && !isRestoringSession
            && !transitioningTorrentIDs.contains(selectedTorrent.id)
    }

    var isToolbarStartStopEnabled: Bool {
        guard let selectedTorrent else { return false }
        return selectedTorrent.errorState == nil
            && !isRestoringSession
            && !transitioningTorrentIDs.contains(selectedTorrent.id)
    }

    func canToggleRunningState(for id: UUID) -> Bool {
        guard let record = torrents.first(where: { $0.id == id }) else { return false }
        return record.errorState == nil
            && !isRestoringSession
            && !transitioningTorrentIDs.contains(id)
    }

    func canForceRecheck(for id: UUID) -> Bool {
        guard let record = torrents.first(where: { $0.id == id }) else { return false }
        return record.errorState == nil
            && record.status != .checking
            && !isRestoringSession
            && !transitioningTorrentIDs.contains(id)
    }

    func canRemoveFromList(for id: UUID) -> Bool {
        torrents.contains(where: { $0.id == id })
            && !isRestoringSession
            && !transitioningTorrentIDs.contains(id)
    }

    func canRemoveWithFiles(for id: UUID) -> Bool {
        guard let record = torrents.first(where: { $0.id == id }) else { return false }
        return record.errorState == nil
            && !isRestoringSession
            && !transitioningTorrentIDs.contains(id)
    }

    func presentAddTorrentEntry() {
        guard canAddTorrent else { return }
        draftPreparationTask?.cancel()
        currentAddTorrentDraft = nil
        presentedModal = .addTorrentEntry
    }

    func dismissModal() {
        draftPreparationTask?.cancel()
        presentedModal = nil
        currentAddTorrentDraft = nil
    }

    func commitPendingConfirmedTorrent() {
        guard canAddTorrent else { return }
        guard let record = pendingConfirmedTorrent else { return }

        pendingConfirmedTorrent = nil
        insertConfirmedTorrent(record)
        saveCriticalState()

        Task { [weak self] in
            await self?.refreshActiveSnapshots()
        }
    }

    func selectTorrent(id: UUID) {
        selectedTorrentID = id
        refreshSelectedTorrentNavigationAvailability()
    }

    func toggleTorrentSelection(id: UUID) {
        selectedTorrentID = selectedTorrentID == id ? nil : id
        refreshSelectedTorrentNavigationAvailability()
    }

    func clearTorrentSelection() {
        guard selectedTorrentID != nil else { return }
        selectedTorrentID = nil
        selectedTorrentNavigationAvailability = TorrentNavigationAvailability()
    }

    func toggleExpanded(for id: UUID) {
        guard torrents.contains(where: { $0.id == id }) else { return }
        expandedTorrentID = expandedTorrentID == id ? nil : id
    }

    func collapseExpandedTorrent() {
        expandedTorrentID = nil
    }

    func startSelectedTorrent() {
        guard let selectedTorrentID else { return }
        startTorrent(id: selectedTorrentID)
    }

    func startTorrent(id: UUID) {
        guard let record = torrents.first(where: { $0.id == id }),
              canToggleRunningState(for: id) else { return }
        Self.logger.notice("Start requested for torrent id=\(record.id.uuidString) status=\(record.status.rawValue) progress=\(String(format: "%.3f", record.progress))")
        beginTransitionTrace(action: "start", record: record)
        transitioningTorrentIDs.insert(record.id)
        traceTransition(
            torrentID: record.id,
            phase: "transition.lock.acquired",
            level: .notice,
            flush: true,
            extra: recordSnapshotFields(for: record)
        )

        Task { [weak self] in
            guard let self else { return }
            var transitionOutcome = "cancelled"
            defer {
                self.transitioningTorrentIDs.remove(record.id)
                self.endTransitionTrace(torrentID: record.id, outcome: transitionOutcome)
            }

            if record.status.isSleeping {
                self.traceTransition(torrentID: record.id, phase: "validation.begin", extra: [:])
                let validation = await self.diskIssueDetector.validateAfterUserAction(for: record)
                self.applyValidationResult(validation, to: record.id)
                self.traceTransition(
                    torrentID: record.id,
                    phase: "validation.result",
                    level: validation.issue == nil ? .debug : .notice,
                    extra: self.validationFields(for: validation)
                )

                if validation.issue != nil {
                    Self.logger.notice("Start blocked by persistent issue for torrent id=\(record.id.uuidString) issue=\(validation.issue?.kind.rawValue ?? "unknown")")
                    transitionOutcome = "blocked.persistent-issue"
                    await self.persistCriticalState()
                    return
                }

                if record.persistentIssue != nil {
                    self.applyPersistentIssue(nil, to: record.id)
                }
                self.traceTransition(torrentID: record.id, phase: "restore-start.begin", level: .notice, extra: [:])
                await self.restoreAndStart(record: record)
                transitionOutcome = self.torrents.first(where: { $0.id == record.id })?.errorState == nil
                    ? "restore-start.completed"
                    : "restore-start.error"
                return
            }

            do {
                let engineCallStartedAt = DispatchTime.now().uptimeNanoseconds
                self.traceTransition(
                    torrentID: record.id,
                    phase: "engine.start.begin",
                    level: .notice,
                    flush: true,
                    extra: [:]
                )
                try await self.engine.startTorrent(id: record.id)
                self.traceTransition(
                    torrentID: record.id,
                    phase: "engine.start.end",
                    level: .notice,
                    flush: true,
                    extra: ["engineMs": self.elapsedMilliseconds(sinceUptimeNs: engineCallStartedAt)]
                )

                if let index = self.torrents.firstIndex(where: { $0.id == record.id }) {
                    self.detachedTorrentIDs.remove(record.id)
                    self.torrents[index].status = .downloading
                    self.torrents[index].runtimeErrorState = nil
                }

                Self.logger.notice("Direct start succeeded for torrent id=\(record.id.uuidString)")
                transitionOutcome = "succeeded"

                self.saveCriticalState()
                await self.refreshActiveSnapshots()
            } catch {
                let engineError = TorrentEngineError.normalized(from: error)
                Self.logger.error("Direct start failed for torrent id=\(record.id.uuidString) kind=\(engineError.kind.rawValue) reason=\(engineError.debugReason ?? "-")")
                self.traceTransition(
                    torrentID: record.id,
                    phase: "engine.start.failed",
                    level: .error,
                    flush: true,
                    extra: self.engineErrorFields(error)
                )
                if engineError.kind == .torrentNotFound {
                    await self.restoreAndStart(record: record)
                    transitionOutcome = self.torrents.first(where: { $0.id == record.id })?.errorState == nil
                        ? "restore-start.completed"
                        : "restore-start.error"
                } else {
                    self.applyEngineError(error, to: record.id)
                    transitionOutcome = "failed.\(engineError.kind.rawValue)"
                }
            }
        }
    }

    func stopSelectedTorrent() {
        guard let selectedTorrentID else { return }
        stopTorrent(id: selectedTorrentID)
    }

    func stopTorrent(id: UUID) {
        guard canToggleRunningState(for: id) else { return }
        Self.logger.notice("Stop requested for torrent id=\(id.uuidString)")
        if let record = torrents.first(where: { $0.id == id }) {
            beginTransitionTrace(action: "stop", record: record)
        }
        transitioningTorrentIDs.insert(id)
        if let record = torrents.first(where: { $0.id == id }) {
            traceTransition(
                torrentID: id,
                phase: "transition.lock.acquired",
                level: .notice,
                flush: true,
                extra: recordSnapshotFields(for: record)
            )
        }

        Task { [weak self] in
            guard let self else { return }
            var transitionOutcome = "cancelled"
            defer {
                self.transitioningTorrentIDs.remove(id)
                self.endTransitionTrace(torrentID: id, outcome: transitionOutcome)
            }
            guard let currentRecord = self.torrents.first(where: { $0.id == id }) else { return }

            self.traceTransition(torrentID: id, phase: "validation.begin", extra: [:])
            let validation = await self.diskIssueDetector.validateAfterUserAction(for: currentRecord)
            self.applyValidationResult(validation, to: id)
            self.traceTransition(
                torrentID: id,
                phase: "validation.result",
                level: validation.issue == nil ? .debug : .notice,
                extra: self.validationFields(for: validation)
            )

            if validation.issue != nil {
                Self.logger.notice("Stop converted into persistent issue for torrent id=\(id.uuidString) issue=\(validation.issue?.kind.rawValue ?? "unknown")")
                self.detachedTorrentIDs.insert(id)
                transitionOutcome = "converted.persistent-issue"
                await self.persistCriticalState()

                do {
                    let engineCallStartedAt = DispatchTime.now().uptimeNanoseconds
                    self.traceTransition(torrentID: id, phase: "engine.remove.begin", level: .notice, flush: true)
                    try await self.engine.removeTorrent(id: id, deleteData: false)
                    self.traceTransition(
                        torrentID: id,
                        phase: "engine.remove.end",
                        level: .notice,
                        flush: true,
                        extra: ["engineMs": self.elapsedMilliseconds(sinceUptimeNs: engineCallStartedAt)]
                    )
                } catch {
                    let engineError = TorrentEngineError.normalized(from: error)
                    if engineError.kind != .torrentNotFound {
                        self.traceTransition(
                            torrentID: id,
                            phase: "engine.remove.failed",
                            level: .error,
                            flush: true,
                            extra: self.engineErrorFields(error)
                        )
                        self.applyEngineError(error, to: id)
                        transitionOutcome = "failed.\(engineError.kind.rawValue)"
                    } else {
                        self.traceTransition(
                            torrentID: id,
                            phase: "engine.remove.not-found",
                            level: .notice,
                            flush: true,
                            extra: self.engineErrorFields(error)
                        )
                    }
                }

                return
            }

            self.detachedTorrentIDs.insert(id)

            if let index = self.torrents.firstIndex(where: { $0.id == id }) {
                // When a completed torrent merely stops seeding, keep the user-facing
                // state as completed instead of changing it to stopped.
                let nextStatus: TorrentStatus = self.torrents[index].progress >= 1.0
                    || self.torrents[index].status == .seeding
                    || self.torrents[index].status == .completed
                    ? .completed
                    : .stopped

                self.torrents[index].status = nextStatus
                self.torrents[index].runtimeErrorState = nil
                self.torrents[index].metrics.downloadSpeedBytesPerSecond = 0
                self.torrents[index].metrics.uploadSpeedBytesPerSecond = 0
                self.torrents[index].metrics.etaSeconds = nil
                self.torrents[index].metrics.seeds = nil
                self.torrents[index].metrics.peers = nil
            }

            self.traceTransition(
                torrentID: id,
                phase: "state.preengine.applied",
                level: .debug,
                extra: self.transitionStateSnapshot(for: id)
            )
            await self.persistCriticalState()

            do {
                let engineCallStartedAt = DispatchTime.now().uptimeNanoseconds
                self.traceTransition(torrentID: id, phase: "engine.remove.begin", level: .notice, flush: true)
                try await self.engine.removeTorrent(id: id, deleteData: false)
                Self.logger.notice("Stop removal succeeded for torrent id=\(id.uuidString)")
                self.traceTransition(
                    torrentID: id,
                    phase: "engine.remove.end",
                    level: .notice,
                    flush: true,
                    extra: ["engineMs": self.elapsedMilliseconds(sinceUptimeNs: engineCallStartedAt)]
                )
                transitionOutcome = "succeeded"
            } catch {
                let engineError = TorrentEngineError.normalized(from: error)
                if engineError.kind == .torrentNotFound {
                    Self.logger.notice("Stop removal already detached for torrent id=\(id.uuidString) kind=\(engineError.kind.rawValue) reason=\(engineError.debugReason ?? "-")")
                } else {
                    Self.logger.error("Stop removal failed for torrent id=\(id.uuidString) kind=\(engineError.kind.rawValue) reason=\(engineError.debugReason ?? "-")")
                }
                self.traceTransition(
                    torrentID: id,
                    phase: engineError.kind == .torrentNotFound ? "engine.remove.not-found" : "engine.remove.failed",
                    level: engineError.kind == .torrentNotFound ? .notice : .error,
                    flush: true,
                    extra: self.engineErrorFields(error)
                )
                if engineError.kind != .torrentNotFound {
                    self.applyEngineError(error, to: id)
                    transitionOutcome = "failed.\(engineError.kind.rawValue)"
                } else {
                    transitionOutcome = "succeeded.detached"
                }
            }
        }
    }

    func toggleTorrentRunningState(id: UUID) {
        guard let record = torrents.first(where: { $0.id == id }) else { return }
        if record.status.isSleeping {
            startTorrent(id: id)
        } else {
            stopTorrent(id: id)
        }
    }

    func forceRecheckTorrent(id: UUID) {
        guard let record = torrents.first(where: { $0.id == id }),
              canForceRecheck(for: id) else { return }

        Self.logger.notice("Recheck requested for torrent id=\(id.uuidString) status=\(record.status.rawValue)")
        beginTransitionTrace(action: "recheck", record: record)
        transitioningTorrentIDs.insert(id)
        traceTransition(
            torrentID: id,
            phase: "transition.lock.acquired",
            level: .notice,
            flush: true,
            extra: recordSnapshotFields(for: record)
        )

        Task { [weak self] in
            guard let self else { return }
            var transitionOutcome = "cancelled"
            defer {
                self.transitioningTorrentIDs.remove(id)
                self.endTransitionTrace(torrentID: id, outcome: transitionOutcome)
            }
            var restoredTemporaryHandle = false

            self.traceTransition(torrentID: id, phase: "validation.begin", extra: [:])
            let validation = await self.diskIssueDetector.validateAfterUserAction(for: record)
            self.applyValidationResult(validation, to: id)
            self.traceTransition(
                torrentID: id,
                phase: "validation.result",
                level: validation.issue == nil ? .debug : .notice,
                extra: self.validationFields(for: validation)
            )

            if validation.issue != nil {
                Self.logger.notice("Recheck blocked by persistent issue for torrent id=\(id.uuidString) issue=\(validation.issue?.kind.rawValue ?? "unknown")")
                self.detachedTorrentIDs.insert(id)
                transitionOutcome = "blocked.persistent-issue"
                await self.persistCriticalState()

                if record.status.isActive {
                    try? await self.engine.removeTorrent(id: id, deleteData: false)
                }
                return
            }

            do {
                if record.status.isSleeping {
                    self.traceTransition(torrentID: id, phase: "temporary.restore.begin", level: .notice, flush: true)
                    guard let restoreEntry = await self.makeRestoreEntryForUserAction(
                        record: record,
                        shouldStart: true,
                        savePathFailureReason: "Не удалось разрешить путь для проверки торрента."
                    ) else {
                        transitionOutcome = "restore-entry.unavailable"
                        return
                    }

                    do {
                        let restoreStartedAt = DispatchTime.now().uptimeNanoseconds
                        _ = try await self.engine.restoreSession([restoreEntry])
                        self.temporarilyRestoredRecheckTorrentIDs.insert(id)
                        self.temporaryRecheckPostCheckStatusByID[id] = record.status
                        self.detachedTorrentIDs.remove(id)
                        restoredTemporaryHandle = true
                        self.traceTransition(
                            torrentID: id,
                            phase: "temporary.restore.end",
                            level: .notice,
                            flush: true,
                            extra: ["engineMs": self.elapsedMilliseconds(sinceUptimeNs: restoreStartedAt)]
                        )
                    } catch {
                        let engineError = TorrentEngineError.normalized(from: error)
                        guard engineError.kind == .duplicateTorrent else {
                            self.traceTransition(
                                torrentID: id,
                                phase: "temporary.restore.failed",
                                level: .error,
                                flush: true,
                                extra: self.engineErrorFields(error)
                            )
                            throw error
                        }

                        // Auto-stop after download can leave a paused handle alive.
                        // Reuse that handle instead of restoring it, then detach it
                        // from the engine again after the recheck.
                        self.temporarilyRestoredRecheckTorrentIDs.insert(id)
                        self.temporaryRecheckPostCheckStatusByID[id] = record.status
                        self.detachedTorrentIDs.remove(id)
                        restoredTemporaryHandle = true
                        self.traceTransition(
                            torrentID: id,
                            phase: "temporary.restore.reused-handle",
                            level: .notice,
                            flush: true,
                            extra: self.engineErrorFields(error)
                        )
                    }
                }

                do {
                    let recheckStartedAt = DispatchTime.now().uptimeNanoseconds
                    self.traceTransition(torrentID: id, phase: "engine.recheck.begin", level: .notice, flush: true)
                    try await self.engine.forceRecheck(id: id)
                    self.traceTransition(
                        torrentID: id,
                        phase: "engine.recheck.end",
                        level: .notice,
                        flush: true,
                        extra: ["engineMs": self.elapsedMilliseconds(sinceUptimeNs: recheckStartedAt)]
                    )
                } catch {
                    let engineError = TorrentEngineError.normalized(from: error)

                    if engineError.kind == .torrentNotFound, !restoredTemporaryHandle {
                        guard let restoreEntry = await self.makeRestoreEntryForUserAction(
                            record: record,
                            shouldStart: true,
                            savePathFailureReason: "Не удалось разрешить путь для проверки торрента."
                        ) else {
                            transitionOutcome = "restore-entry.unavailable"
                            return
                        }

                        let restoreStartedAt = DispatchTime.now().uptimeNanoseconds
                        _ = try await self.engine.restoreSession([restoreEntry])
                        self.detachedTorrentIDs.remove(id)
                        self.traceTransition(
                            torrentID: id,
                            phase: "temporary.restore.not-found-fallback",
                            level: .notice,
                            flush: true,
                            extra: ["engineMs": self.elapsedMilliseconds(sinceUptimeNs: restoreStartedAt)]
                        )
                        let recheckStartedAt = DispatchTime.now().uptimeNanoseconds
                        try await self.engine.forceRecheck(id: id)
                        self.traceTransition(
                            torrentID: id,
                            phase: "engine.recheck.end",
                            level: .notice,
                            flush: true,
                            extra: ["engineMs": self.elapsedMilliseconds(sinceUptimeNs: recheckStartedAt)]
                        )
                    } else {
                        self.traceTransition(
                            torrentID: id,
                            phase: "engine.recheck.failed",
                            level: .error,
                            flush: true,
                            extra: self.engineErrorFields(error)
                        )
                        throw error
                    }
                }

                self.detachedTorrentIDs.remove(id)

                if let index = self.torrents.firstIndex(where: { $0.id == id }) {
                    self.torrents[index].status = .checking
                    self.torrents[index].runtimeErrorState = nil
                }

                Self.logger.notice("Recheck started for torrent id=\(id.uuidString)")
                transitionOutcome = "started"
                await self.persistCriticalState()
                await self.refreshActiveSnapshots()
            } catch {
                if restoredTemporaryHandle {
                    self.temporarilyRestoredRecheckTorrentIDs.remove(id)
                    self.temporaryRecheckPostCheckStatusByID[id] = nil
                    self.pendingTemporaryRecheckDetachIDs.remove(id)
                    self.detachedTorrentIDs.insert(id)
                    try? await self.engine.removeTorrent(id: id, deleteData: false)
                }
                let engineError = TorrentEngineError.normalized(from: error)
                Self.logger.error("Recheck failed for torrent id=\(id.uuidString) kind=\(engineError.kind.rawValue) reason=\(engineError.debugReason ?? "-")")
                self.applyEngineError(error, to: id)
                transitionOutcome = "failed.\(engineError.kind.rawValue)"
            }
        }
    }

    func removeSelectedTorrent(policy: TorrentRemovalPolicy = .removeFromListOnly) async {
        guard let selectedTorrentID, isToolbarRemoveEnabled else { return }
        await removeTorrent(id: selectedTorrentID, policy: policy)
    }

    func removeSelectedTorrent(deleteData: Bool = false) async {
        await removeSelectedTorrent(policy: deleteData ? .removeFromListAndDeleteFiles : .removeFromListOnly)
    }

    func primaryLocation(for id: UUID) async -> ManagedTorrentLocation? {
        guard let record = torrents.first(where: { $0.id == id }) else { return nil }
        return await torrentPayloadLocator.primaryLocation(for: record)
    }

    func removeTorrent(id: UUID, policy: TorrentRemovalPolicy = .removeFromListOnly) async {
        guard let record = torrents.first(where: { $0.id == id }) else { return }
        let resolvedPolicy: TorrentRemovalPolicy = record.errorState == nil
            ? policy
            : .removeFromListOnly

        detachedTorrentIDs.remove(id)
        clearUnreadUserEvents(for: id)

        // Remove the torrent from durable state first so it cannot return after relaunch.
        torrents.removeAll { $0.id == id }
        if selectedTorrentID == id {
            selectedTorrentID = nil
        }
        if expandedTorrentID == id {
            expandedTorrentID = nil
        }
        refreshSelectedTorrentNavigationAvailability()
        await persistCriticalState(pruneRestoreArtifacts: false)

        var canDeletePayload = false
        do {
            try await engine.removeTorrent(id: id, deleteData: false)
            canDeletePayload = true
        } catch {
            let engineError = TorrentEngineError.normalized(from: error)
            canDeletePayload = engineError.kind == .torrentNotFound

            if engineError.kind == .torrentNotFound {
                Self.logger.notice(
                    "Remove already detached for torrent id=\(id.uuidString) kind=\(engineError.kind.rawValue) reason=\(engineError.debugReason ?? "-")"
                )
            } else {
                Self.logger.error(
                    "Remove failed for torrent id=\(id.uuidString) kind=\(engineError.kind.rawValue) reason=\(engineError.debugReason ?? "-")"
                )
            }
            // Never restore a torrent to the UI after removing its durable state.
            // An auxiliary file may remain on disk, but the record must stay removed.
        }

        if resolvedPolicy == .removeFromListAndDeleteFiles, !canDeletePayload {
            payloadDeletionAlert = PayloadDeletionAlert(
                title: L10n.string("payload_deletion.files_not_deleted.title", localeOverride: preferences.localeOverride, defaultValue: "Файлы не удалены"),
                message: L10n.string(
                    "payload_deletion.engine_stop_failed.message",
                    localeOverride: preferences.localeOverride,
                    defaultValue: "Shatl удалил торрент из списка, но не смог безопасно остановить его в движке перед удалением файлов."
                )
            )
        }

        if resolvedPolicy == .removeFromListAndDeleteFiles, canDeletePayload {
            switch await torrentPayloadDeletionService.deletePayload(for: record) {
            case .deleted(let deletionResult):
                Self.logger.notice(
                    "Payload deletion completed for torrent id=\(id.uuidString) source=\(deletionResult.payloadSource.rawValue) filesDeleted=\(deletionResult.deletedManagedFileCount) missingFiles=\(deletionResult.missingManagedFileCount) failedFiles=\(deletionResult.failedManagedFileCount) directoriesDeleted=\(deletionResult.deletedDirectoryCount) sidecarsDeleted=\(deletionResult.deletedSystemSidecarCount)"
                )
                if deletionResult.failedManagedFileCount > 0 {
                    payloadDeletionAlert = PayloadDeletionAlert(
                        title: L10n.string("payload_deletion.not_all_files_deleted.title", localeOverride: preferences.localeOverride, defaultValue: "Не все файлы удалены"),
                        message: L10n.format(
                            "payload_deletion.partial_failure.message",
                            localeOverride: preferences.localeOverride,
                            defaultValue: "Shatl удалил торрент из списка, но не смог удалить %lld файл(ов) с диска.",
                            deletionResult.failedManagedFileCount
                        )
                    )
                }
            case .unresolved(let failure):
                let inspectedFileCount = failure.inspectedFileCount.map(String.init) ?? "-"
                let savePath = failure.savePath ?? "-"
                Self.logger.notice(
                    "Payload deletion skipped for torrent id=\(id.uuidString) reason=\(failure.reason.rawValue) selectedFileCount=\(failure.selectedFileCount) totalFileCount=\(failure.totalFileCount) inspectedFileCount=\(inspectedFileCount) savePath=\(savePath) archivePath=\(failure.archivePath)"
                )
                ShatlDiskDiagnosticsLog.event(
                    "payload.delete.skipped",
                    fields: [
                        "torrentID": id.uuidString,
                        "reason": failure.reason.rawValue,
                        "selectedFileCount": "\(failure.selectedFileCount)",
                        "totalFileCount": "\(failure.totalFileCount)",
                        "inspectedFileCount": inspectedFileCount,
                        "savePath": savePath,
                        "archivePath": failure.archivePath
                    ]
                )
                payloadDeletionAlert = PayloadDeletionAlert(
                    title: L10n.string("payload_deletion.files_not_deleted.title", localeOverride: preferences.localeOverride, defaultValue: "Файлы не удалены"),
                    message: L10n.string(
                        "payload_deletion.unresolved.message",
                        localeOverride: preferences.localeOverride,
                        defaultValue: "Shatl удалил торрент из списка, но не смог безопасно определить связанные файлы на диске."
                    )
                )
            }
        }

        await torrentArchiveStore.removeArchive(for: id)
        await bookmarkStore.removeBookmark(for: id)
        await persistCriticalState()
    }

    func redownloadTorrent(id: UUID) {
        guard let record = torrents.first(where: { $0.id == id }),
              record.persistentIssue?.kind == .missingContent else { return }

        Task { [weak self] in
            guard let self else { return }

            guard let saveURL = await self.bookmarkStore.resolveURL(
                for: record.id,
                fallbackPath: record.canonicalSavePath
            ) else {
                self.applyPersistentIssue(
                    TorrentPersistentIssue(
                        kind: .savePathUnavailable,
                        detectedAt: Date(),
                        statusBeforeIssue: record.persistentIssue?.statusBeforeIssue ?? record.status,
                        debugReason: "Не удалось разрешить путь для повторной загрузки."
                    ),
                    to: record.id
                )
                self.saveCriticalState()
                return
            }

            await self.redownloadTorrent(record: record, saveURL: saveURL, bookmarkData: nil)
        }
    }

    func redownloadTorrent(id: UUID, toSaveLocation saveURL: URL, bookmarkData: Data?) {
        guard let record = torrents.first(where: { $0.id == id }),
              record.persistentIssue?.kind == .savePathUnavailable else { return }

        Task { [weak self] in
            guard let self else { return }

            await self.redownloadTorrent(record: record, saveURL: saveURL, bookmarkData: bookmarkData)
        }
    }

    func continueFromEntry(with magnet: String) {
        guard canAddTorrent else { return }
        let trimmed = magnet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ShatlErrorCatalog.inlineMagnetValidation(
            for: trimmed,
            localeOverride: preferences.localeOverride
        ) == nil else {
            return
        }

        let source = AddTorrentSource(kind: .magnet, rawValue: trimmed)
        startDraftPreparation(
            for: source,
            suggestedSavePath: preferences.defaultDownloadPath,
            stopAfterDownload: preferences.alwaysStopAfterDownload,
            savePathBookmarkData: preferences.defaultDownloadBookmarkData
        )
    }

    func continueFromTorrentFile(at path: String) {
        guard canAddTorrent else { return }
        let source = AddTorrentSource(kind: .torrentFile, rawValue: path)
        startDraftPreparation(
            for: source,
            suggestedSavePath: preferences.defaultDownloadPath,
            stopAfterDownload: preferences.alwaysStopAfterDownload,
            savePathBookmarkData: preferences.defaultDownloadBookmarkData
        )
    }

    func handleIncomingURL(_ url: URL) {
        if !isReadyToProcessIncomingURLs {
            pendingIncomingURLs.append(url)
            return
        }

        processIncomingURL(url)
    }

    private var isReadyToProcessIncomingURLs: Bool {
        didBootstrap && canAddTorrent
    }

    private func processIncomingURL(_ url: URL) {
        if url.isFileURL {
            handleIncomingTorrentFileURL(url)
            return
        }

        guard url.scheme?.lowercased() == "magnet" else { return }

        startDraftPreparation(
            for: AddTorrentSource(kind: .magnet, rawValue: url.absoluteString),
            suggestedSavePath: preferences.defaultDownloadPath,
            stopAfterDownload: preferences.alwaysStopAfterDownload,
            savePathBookmarkData: preferences.defaultDownloadBookmarkData
        )
    }

    func retryCurrentDraftPreparation() {
        guard let draft = currentAddTorrentDraft else { return }

        startDraftPreparation(
            for: draft.source,
            suggestedSavePath: draft.suggestedSavePath,
            stopAfterDownload: draft.stopAfterDownload,
            alias: draft.alias,
            savePathBookmarkData: draft.savePathBookmarkData
        )
    }

    private func redownloadTorrent(
        record: TorrentRecord,
        saveURL: URL,
        bookmarkData: Data?
    ) async {
        let normalizedSavePath = NSString(string: saveURL.path).standardizingPath
        let baselineFootprint = await diskIssueDetector.captureCurrentFootprint(
            for: record,
            saveURL: URL(fileURLWithPath: normalizedSavePath, isDirectory: true)
        )
        guard let archiveURL = await archivedRestoreURL(for: record) else {
            applyMissingArchivedTorrentError(
                to: record.id,
                debugReason: "Не найден архивный torrent-файл для повторной загрузки."
            )
            return
        }

        let restoreEntry = SessionRestoreEntry(
            torrentID: record.id,
            attemptID: UUID(),
            archivedTorrentPath: archiveURL.path,
            suggestedSavePath: normalizedSavePath,
            selectedFileIndices: record.selectedFileIndices,
            stopAfterDownload: record.stopAfterDownload,
            shouldStart: true
        )

        do {
            let snapshots = try await engine.restoreSession([restoreEntry])
            detachedTorrentIDs.remove(record.id)

            if let index = torrents.firstIndex(where: { $0.id == record.id }) {
                torrents[index].attemptID = restoreEntry.attemptID
                torrents[index].canonicalSavePath = normalizedSavePath
                torrents[index].status = .downloading
                torrents[index].progress = 0
                torrents[index].lastKnownProgress = 0
                torrents[index].materializedSelectionFootprint = baselineFootprint
                torrents[index].persistentIssue = nil
                torrents[index].runtimeErrorState = nil
            }

            if let bookmarkData {
                await bookmarkStore.saveBookmarkData(for: record.id, data: bookmarkData)
            } else if normalizedSavePath != record.canonicalSavePath {
                await bookmarkStore.saveBookmark(for: record.id, url: saveURL)
            }

            applySnapshots(snapshots)
            saveCriticalState()
        } catch {
            applyEngineError(error, to: record.id)
        }
    }

    func confirmDraft() {
        guard canAddTorrent else { return }
        guard let draft = currentAddTorrentDraft else { return }
        guard draft.canConfirmDownload else { return }

        if let infoHash = draft.infoHash,
           torrents.contains(where: { $0.infoHash == infoHash }) {
            presentDuplicateDraft(for: draft)
            return
        }

        Task { [weak self] in
            guard let self else { return }

            do {
                let record = try await self.engine.addTorrent(using: draft)

                do {
                    try await self.persistRestoreArtifacts(for: record, draft: draft)
                } catch {
                    try? await self.engine.removeTorrent(id: record.id, deleteData: false)
                    let errorState = ShatlErrorCatalog.reviewError(
                        for: error,
                        source: draft.source,
                        localeOverride: self.preferences.localeOverride
                    )
                    self.presentInvalidDraft(
                        for: draft.source,
                        errorState: errorState,
                        suggestedSavePath: draft.suggestedSavePath,
                        stopAfterDownload: draft.stopAfterDownload,
                        alias: draft.alias,
                        savePathBookmarkData: draft.savePathBookmarkData
                    )
                    return
                }

                if self.presentedModal != nil {
                    self.pendingConfirmedTorrent = record
                    self.dismissModal()
                } else {
                    self.insertConfirmedTorrent(record)
                    self.saveCriticalState()
                    await self.refreshActiveSnapshots()
                }
            } catch {
                if self.isDuplicateError(error) {
                    self.presentDuplicateDraft(for: draft)
                } else {
                    let errorState = ShatlErrorCatalog.reviewError(
                        for: error,
                        source: draft.source,
                        localeOverride: self.preferences.localeOverride
                    )
                    self.presentInvalidDraft(
                        for: draft.source,
                        errorState: errorState,
                        suggestedSavePath: draft.suggestedSavePath,
                        stopAfterDownload: draft.stopAfterDownload,
                        alias: draft.alias,
                        savePathBookmarkData: draft.savePathBookmarkData
                    )
                }
            }
        }
    }

    func updateDraftAlias(_ alias: String) {
        guard var draft = currentAddTorrentDraft else { return }
        draft.alias = alias
        currentAddTorrentDraft = draft
    }

    func updateDraftSavePath(_ path: String) {
        guard var draft = currentAddTorrentDraft else { return }
        draft.suggestedSavePath = NSString(string: path).standardizingPath
        draft.savePathBookmarkData = nil
        currentAddTorrentDraft = draft
    }

    func updateDraftSaveLocation(_ url: URL, bookmarkData: Data?) {
        guard var draft = currentAddTorrentDraft else { return }
        draft.suggestedSavePath = NSString(string: url.path).standardizingPath
        draft.savePathBookmarkData = bookmarkData
        currentAddTorrentDraft = draft
    }

    func updateDraftStopAfterDownload(_ isEnabled: Bool) {
        guard var draft = currentAddTorrentDraft else { return }
        draft.stopAfterDownload = isEnabled
        currentAddTorrentDraft = draft
    }

    func toggleDraftFileSelection(id: UUID) {
        guard var draft = currentAddTorrentDraft,
              let index = draft.files.firstIndex(where: { $0.id == id }) else { return }

        draft.files[index].isSelected.toggle()
        currentAddTorrentDraft = draft
    }

    /// Explicit selection supports cascading changes across folder branches
    /// in the add-flow file tree.
    func setDraftFileSelection(id: UUID, isSelected: Bool) {
        guard var draft = currentAddTorrentDraft,
              let index = draft.files.firstIndex(where: { $0.id == id }) else { return }

        draft.files[index].isSelected = isSelected
        currentAddTorrentDraft = draft
    }

    func setDraftFolderSelection(path: String, isSelected: Bool) {
        guard var draft = currentAddTorrentDraft else { return }

        let normalizedPath = path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedPath.isEmpty else { return }

        let folderPrefix = normalizedPath + "/"
        var didChangeSelection = false

        for index in draft.files.indices {
            let filePath = draft.files[index].name.replacingOccurrences(of: "\\", with: "/")
            if filePath == normalizedPath || filePath.hasPrefix(folderPrefix) {
                if draft.files[index].isSelected != isSelected {
                    draft.files[index].isSelected = isSelected
                    didChangeSelection = true
                }
            }
        }

        if didChangeSelection {
            currentAddTorrentDraft = draft
        }
    }

    func bootstrapRuntimeState() {
        guard !didBootstrap else { return }
        didBootstrap = true
        isRestoringSession = !torrents.isEmpty

        let loadTask = Task { [sessionStore] in
            await sessionStore.load()
        }
        initialSessionLoadTask = loadTask

        bootstrapTask = Task { [weak self] in
            guard let self else { return }

            let loadResult = await loadTask.value
            guard await self.resolveInitialSessionLoad(loadResult), !self.isPreparingForTermination else {
                return
            }

            do {
                let performanceSettings = self.preferences.enginePerformanceSettings
                self.lastRequestedPerformanceSettings = performanceSettings
                try await self.engine.applyPerformanceSettings(performanceSettings)
                try await self.engine.boot()
                self.isEngineReady = true
            } catch {
                self.isRestoringSession = false
                return
            }

            let startupCheckCandidates = self.torrents.filter { $0.persistentIssue == nil }
            let startupEvaluation = await self.diskIssueDetector.startupCheck(for: startupCheckCandidates)
            _ = self.applyDiskIssueEvaluation(startupEvaluation)
            await self.persistCriticalState()

            if loadResult.snapshot != nil, !self.torrents.isEmpty {
                let restoreCandidates = self.torrents.filter { $0.persistentIssue == nil }
                self.restoreProgressFloorByID = Dictionary(
                    uniqueKeysWithValues: restoreCandidates
                        .filter { $0.status.isActive && max($0.progress, $0.lastKnownProgress) > 0 }
                        .map { ($0.id, max($0.progress, $0.lastKnownProgress)) }
                )
                let restoreResult = await self.sessionRestoreCoordinator.restore(records: restoreCandidates)
                self.applyRestoredPersistentIssues(restoreResult.persistentIssues)
                self.applySnapshots(restoreResult.snapshots)
                let didApplyFallbackStatuses = self.applyRestoreFallbackStatuses(
                    restoreResult.fallbackStatusesByID,
                    restoredSnapshotIDs: Set(restoreResult.snapshots.map(\.id))
                )
                if didApplyFallbackStatuses {
                    await self.persistCriticalState()
                }
            }

            self.startRuntimeLoop()
            await self.reconcileSleepingTorrents()
            self.isRestoringSession = false
            self.allowsUserFacingNotifications = true
            self.didCompleteRuntimeBootstrap = true
            self.flushPendingIncomingURLs()
        }
    }

    private func resolveInitialSessionLoad(_ result: SessionLoadResult) async -> Bool {
        if didResolveInitialSessionLoad {
            return sessionLoadIssue == nil
        }
        didResolveInitialSessionLoad = true

        switch result {
        case .missing:
            break
        case .loaded(let snapshot):
            restoreSnapshot(snapshot)
            isRestoringSession = !snapshot.torrents.isEmpty
        case .failure(let issue):
            sessionLoadIssue = issue
            isRestoringSession = false
        }
        hasLoadedInitialSession = true

        guard sessionLoadIssue == nil else { return false }
        await sessionStore.acceptInitialLoad()
        return true
    }

    private func schedulePerformanceSettingsApply() {
        let settings = preferences.enginePerformanceSettings
        guard settings != lastRequestedPerformanceSettings else { return }

        lastRequestedPerformanceSettings = settings
        performanceApplyTask?.cancel()
        performanceApplyTask = Task { [weak self, settings] in
            guard let self else { return }

            do {
                try await self.engine.applyPerformanceSettings(settings)
            } catch {
                Self.logger.error("Failed to apply performance settings: \(String(describing: error))")
            }
        }
    }

    private func checkpointActiveTorrentsForTermination() async {
        let candidates = torrents.filter {
            $0.persistentIssue == nil
                && $0.status.isActive
                && !detachedTorrentIDs.contains($0.id)
        }
        guard !candidates.isEmpty else { return }

        let progressByID = Dictionary(
            uniqueKeysWithValues: candidates.map {
                ($0.id, max($0.progress, $0.lastKnownProgress))
            }
        )
        let results = await engine.checkpointTorrents(ids: candidates.map(\.id))
        let checkpointedAt = Date()

        for result in results {
            guard case .saved = result.status,
                  let index = torrents.firstIndex(where: { $0.id == result.id }) else {
                continue
            }

            torrents[index].resumeCheckpointedAt = checkpointedAt
            torrents[index].resumeCheckpointProgress = progressByID[result.id]
            torrents[index].lastKnownProgress = max(
                torrents[index].lastKnownProgress,
                progressByID[result.id] ?? torrents[index].progress
            )
        }
    }

    private func startRuntimeLoop() {
        runtimeTask?.cancel()
        runtimeTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.refreshActiveSnapshots()

                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private func refreshActiveSnapshots() async {
        do {
            let snapshots = try await engine.fetchActiveSnapshots()
            applySnapshots(snapshots)
            await detachSleepingHandlesIfNeeded()
            await detachCompletedTemporaryRechecksIfNeeded()
            await detachCompletedTemporaryRechecks(from: snapshots)

            activeRefreshTick += 1
            if activeRefreshTick >= 5 {
                activeRefreshTick = 0
                await sessionStore.saveProgressBatch(from: torrents)
            }
        } catch {
            // Do not surface a separate alert for a background polling failure.
            // A transient engine failure can wait for the next tick.
        }
    }

    private func reconcileSleepingTorrents() async {
        let sleepingRecords = torrents.filter { $0.status.isSleeping && $0.persistentIssue == nil }
        guard !sleepingRecords.isEmpty else { return }

        do {
            let snapshots = try await engine.reconcileSleepingTorrents(sleepingRecords)
            applySnapshots(snapshots)
        } catch {
            // Initial validation of sleeping torrents must not block UI startup.
        }
    }

    private func applySnapshots(_ snapshots: [EngineTorrentSnapshot]) {
        guard !snapshots.isEmpty else { return }

        let snapshotsByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        var shouldRefreshSelectedNavigationAvailability = false

        for index in torrents.indices {
            guard let snapshot = snapshotsByID[torrents[index].id] else { continue }
            traceTransition(
                torrentID: torrents[index].id,
                phase: detachedTorrentIDs.contains(torrents[index].id) ? "snapshot.ignored.detached" : "snapshot.received",
                level: detachedTorrentIDs.contains(torrents[index].id) ? .notice : .debug,
                extra: [
                    "snapshotStatus": snapshot.status.rawValue,
                    "snapshotProgress": progressString(snapshot.progress),
                    "snapshotHasError": boolString(snapshot.errorState != nil)
                ]
            )
            logDiskDiagnosticSync(
                detachedTorrentIDs.contains(torrents[index].id) ? "snapshot.ignored.detached" : "snapshot.received",
                record: torrents[index],
                extra: [
                    "snapshotStatus": snapshot.status.rawValue,
                    "snapshotProgress": progressString(snapshot.progress),
                    "snapshotHasError": boolString(snapshot.errorState != nil)
                ]
            )
            guard !detachedTorrentIDs.contains(torrents[index].id) else { continue }
            let previousStatus = torrents[index].status
            let previousProgress = torrents[index].progress
            let previousMetrics = torrents[index].metrics
            let wasFinishedForOpening = torrents[index].isFinishedForOpening
            let torrentID = torrents[index].id
            let protectsRestoreProgress = shouldProtectRestoreProgress(
                torrentID: torrentID,
                snapshot: snapshot
            )

            let resolvedProgress: Double
            if protectsRestoreProgress,
               let progressFloor = restoreProgressFloorByID[torrentID] {
                resolvedProgress = max(torrents[index].lastKnownProgress, progressFloor, snapshot.progress)
                requestRestoreRecheckIfNeeded(torrentID: torrentID, progressFloor: progressFloor)
            } else if snapshot.status == .checking,
                      torrents[index].lastKnownProgress > snapshot.progress {
                resolvedProgress = torrents[index].lastKnownProgress
            } else {
                resolvedProgress = snapshot.progress
            }
            let resolvedStatus = protectsRestoreProgress ? TorrentStatus.checking : snapshot.status

            if let desiredStatus = temporaryRecheckPostCheckStatusByID[torrents[index].id] {
                if snapshot.status == .checking {
                    torrents[index].status = .checking
                    torrents[index].progress = resolvedProgress
                    torrents[index].metrics = snapshot.metrics
                    torrents[index].runtimeErrorState = snapshot.errorState
                } else {
                    torrents[index].status = desiredStatus
                    torrents[index].progress = resolvedProgress
                    torrents[index].lastKnownProgress = snapshot.progress
                    torrents[index].metrics.downloadSpeedBytesPerSecond = 0
                    torrents[index].metrics.uploadSpeedBytesPerSecond = 0
                    torrents[index].metrics.etaSeconds = nil
                    if desiredStatus.isSleeping {
                        torrents[index].metrics.seeds = nil
                        torrents[index].metrics.peers = nil
                    } else {
                        torrents[index].metrics.seeds = snapshot.metrics.seeds
                        torrents[index].metrics.peers = snapshot.metrics.peers
                    }
                    torrents[index].metrics.uploadedBytes = snapshot.metrics.uploadedBytes
                    torrents[index].metrics.totalBytes = snapshot.metrics.totalBytes
                    torrents[index].metrics.selectedBytes = snapshot.metrics.selectedBytes
                    torrents[index].runtimeErrorState = nil
                    pendingTemporaryRecheckDetachIDs.insert(torrents[index].id)
                }

                logUploadCounterDiagnostics(
                    phase: "snapshot.upload-counters.apply.temporary",
                    torrentID: torrentID,
                    previousStatus: previousStatus,
                    previousMetrics: previousMetrics,
                    snapshot: snapshot,
                    appliedStatus: torrents[index].status,
                    appliedProgress: torrents[index].progress,
                    appliedMetrics: torrents[index].metrics
                )

                if selectedTorrentID == torrentID,
                   wasFinishedForOpening != torrents[index].isFinishedForOpening {
                    shouldRefreshSelectedNavigationAvailability = true
                }
                continue
            }

            torrents[index].status = resolvedStatus
            torrents[index].progress = resolvedProgress
            if snapshot.status != .checking, !protectsRestoreProgress {
                torrents[index].lastKnownProgress = snapshot.progress
            }
            torrents[index].metrics = snapshot.metrics
            torrents[index].runtimeErrorState = snapshot.errorState
            clearRestoreProgressFloorIfSatisfied(torrentID: torrentID, snapshot: snapshot)
            notifyDownloadCompletionIfNeeded(
                torrent: torrents[index],
                previousStatus: previousStatus,
                previousProgress: previousProgress,
                resolvedStatus: resolvedStatus,
                resolvedProgress: resolvedProgress,
                snapshot: snapshot
            )

            logUploadCounterDiagnostics(
                phase: "snapshot.upload-counters.apply",
                torrentID: torrentID,
                previousStatus: previousStatus,
                previousMetrics: previousMetrics,
                snapshot: snapshot,
                appliedStatus: torrents[index].status,
                appliedProgress: torrents[index].progress,
                appliedMetrics: torrents[index].metrics
            )

            if torrents[index].persistentIssue == nil {
                if resolvedStatus == .checking || resolvedStatus.isActive {
                    detachedTorrentIDs.remove(torrents[index].id)
                } else if resolvedStatus.isSleeping {
                    detachedTorrentIDs.insert(torrents[index].id)
                    if previousStatus == .checking || previousStatus.isActive {
                        pendingSleepingDetachIDs.insert(torrents[index].id)
                    }

                    if resolvedStatus == .completed
                        && torrents[index].stopAfterDownload
                        && snapshot.progress >= 1.0
                        && previousStatus.isActive {
                        torrents[index].stopAfterDownload = false
                    }
                }
            }

            traceTransition(
                torrentID: torrents[index].id,
                phase: "snapshot.applied",
                level: .debug,
                extra: [
                    "previousStatus": previousStatus.rawValue,
                    "status": torrents[index].status.rawValue,
                    "progress": progressString(torrents[index].progress),
                    "runtimeError": torrents[index].runtimeErrorState?.title ?? "none"
                ]
            )

            if selectedTorrentID == torrentID,
               wasFinishedForOpening != torrents[index].isFinishedForOpening {
                shouldRefreshSelectedNavigationAvailability = true
            }
        }

        if shouldRefreshSelectedNavigationAvailability {
            refreshSelectedTorrentNavigationAvailability()
        }
    }

    private func shouldProtectRestoreProgress(
        torrentID: UUID,
        snapshot: EngineTorrentSnapshot
    ) -> Bool {
        guard snapshot.errorState == nil,
              snapshot.status != .checking,
              let progressFloor = restoreProgressFloorByID[torrentID] else {
            return false
        }

        return snapshot.progress + Self.restoreProgressRegressionTolerance < progressFloor
    }

    private func requestRestoreRecheckIfNeeded(torrentID: UUID, progressFloor: Double) {
        guard !restoreRecheckRequestedIDs.contains(torrentID) else { return }
        restoreRecheckRequestedIDs.insert(torrentID)

        Self.logger.notice(
            "Restore progress regression detected for torrent id=\(torrentID.uuidString) progressFloor=\(self.progressString(progressFloor)); forcing recheck"
        )

        Task { [weak self] in
            guard let self else { return }

            do {
                try await self.engine.forceRecheck(id: torrentID)
                await self.refreshActiveSnapshots()
            } catch {
                self.restoreProgressFloorByID[torrentID] = nil
                self.restoreRecheckRequestedIDs.remove(torrentID)
                self.applyEngineError(error, to: torrentID)
                await self.persistCriticalState()
            }
        }
    }

    private func clearRestoreProgressFloorIfSatisfied(
        torrentID: UUID,
        snapshot: EngineTorrentSnapshot
    ) {
        guard let progressFloor = restoreProgressFloorByID[torrentID],
              snapshot.status != .checking,
              snapshot.progress + Self.restoreProgressRegressionTolerance >= progressFloor else {
            return
        }

        restoreProgressFloorByID[torrentID] = nil
        restoreRecheckRequestedIDs.remove(torrentID)
    }

    private func restoreSnapshot(_ snapshot: SessionSnapshot) {
        torrents = snapshot.torrents.map {
            let restoredStatus = normalizedRuntimeOnlyErrorStatus(
                status: $0.status,
                progress: $0.progress,
                persistentIssue: $0.persistentIssue
            )
            return TorrentRecord(
                id: $0.torrentID,
                attemptID: $0.attemptID,
                infoHash: $0.infoHash,
                originalName: $0.originalName,
                alias: $0.alias,
                progress: $0.progress,
                status: restoredStatus,
                metrics: TorrentMetrics(),
                canonicalSavePath: $0.canonicalSavePath,
                selectedFileIndices: $0.selectedFileIndices,
                selectedFileRelativePaths: $0.selectedFileRelativePaths ?? [],
                selectedFileCount: $0.selectedFileCount,
                totalFileCount: $0.totalFileCount,
                materializedSelectionFootprint: $0.materializedSelectionFootprint,
                persistentIssue: $0.persistentIssue,
                runtimeErrorState: nil,
                lastKnownProgress: $0.progress,
                resumeCheckpointedAt: $0.resumeCheckpointedAt,
                resumeCheckpointProgress: $0.resumeCheckpointProgress,
                stopAfterDownload: $0.stopAfterDownload
            )
        }

        detachedTorrentIDs = Set(
            snapshot.torrents
                .filter {
                    normalizedRuntimeOnlyErrorStatus(
                        status: $0.status,
                        progress: $0.progress,
                        persistentIssue: $0.persistentIssue
                    ).isSleeping || $0.persistentIssue != nil
                }
                .map(\.torrentID)
        )
        selectedTorrentID = nil
        expandedTorrentID = nil
        refreshSelectedTorrentNavigationAvailability()
    }

    private func saveCriticalState() {
        Task { [weak self] in
            guard let self else { return }
            await self.persistCriticalState()
        }
    }

    private func insertConfirmedTorrent(_ record: TorrentRecord) {
        guard !torrents.contains(where: { $0.id == record.id }) else { return }

        torrents.insert(record, at: 0)
        detachedTorrentIDs.remove(record.id)
    }

    private func persistCriticalState(pruneRestoreArtifacts: Bool = true) async {
        await sessionStore.saveCriticalState(
            from: torrents,
            pruneRestoreArtifacts: pruneRestoreArtifacts
        )
    }

    private func persistRestoreArtifacts(for record: TorrentRecord, draft: AddTorrentDraft) async throws {
        let archiveURL = try await torrentArchiveStore.destinationURL(for: record.id)
        try await engine.exportPreparedTorrent(from: draft.source, to: archiveURL.path)
        if let bookmarkData = draft.savePathBookmarkData {
            await bookmarkStore.saveBookmarkData(for: record.id, data: bookmarkData)
        } else {
            await bookmarkStore.removeBookmark(for: record.id)
        }
    }

    private func makeLoadingDraft(
        for source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool,
        alias: String,
        savePathBookmarkData: Data? = nil
    ) -> AddTorrentDraft {
        AddTorrentDraft(
            source: source,
            originalName: L10n.string("add_torrent.loading_metadata", localeOverride: preferences.localeOverride, defaultValue: "Получение метаданных..."),
            infoHash: nil,
            suggestedSavePath: suggestedSavePath,
            savePathBookmarkData: savePathBookmarkData,
            alias: alias,
            stopAfterDownload: stopAfterDownload,
            files: [],
            reviewState: .loadingMetadata,
            errorState: nil
        )
    }

    private func startDraftPreparation(
        for source: AddTorrentSource,
        suggestedSavePath: String,
        stopAfterDownload: Bool,
        alias: String = "",
        savePathBookmarkData: Data? = nil
    ) {
        guard canAddTorrent else { return }
        draftPreparationTask?.cancel()
        currentAddTorrentDraft = makeLoadingDraft(
            for: source,
            suggestedSavePath: suggestedSavePath,
            stopAfterDownload: stopAfterDownload,
            alias: alias,
            savePathBookmarkData: savePathBookmarkData
        )
        presentedModal = .addTorrentReview

        draftPreparationTask = Task { [weak self] in
            guard let self else { return }

            do {
                var draft = try await self.engine.prepareDraft(
                    from: source,
                    suggestedSavePath: suggestedSavePath,
                    stopAfterDownload: stopAfterDownload
                )

                guard !Task.isCancelled else { return }
                guard self.currentAddTorrentDraft?.source == source else { return }

                draft.alias = alias
                draft.savePathBookmarkData = savePathBookmarkData
                if self.isDuplicateDraft(draft) {
                    self.presentDuplicateDraft(for: draft)
                } else {
                    self.currentAddTorrentDraft = draft
                }
            } catch {
                guard !Task.isCancelled else { return }
                let errorState = ShatlErrorCatalog.reviewError(
                    for: error,
                    source: source,
                    localeOverride: self.preferences.localeOverride
                )
                self.presentInvalidDraft(
                    for: source,
                    errorState: errorState,
                    suggestedSavePath: suggestedSavePath,
                    stopAfterDownload: stopAfterDownload,
                    alias: alias,
                    savePathBookmarkData: savePathBookmarkData
                )
            }
        }
    }

    private func handleIncomingTorrentFileURL(_ url: URL) {
        guard url.pathExtension.lowercased() == "torrent" else { return }

        startDraftPreparation(
            for: AddTorrentSource(kind: .externalOpen, rawValue: url.path),
            suggestedSavePath: preferences.defaultDownloadPath,
            stopAfterDownload: preferences.alwaysStopAfterDownload,
            savePathBookmarkData: preferences.defaultDownloadBookmarkData
        )
    }

    private func presentInvalidDraft(
        for source: AddTorrentSource,
        errorState: TorrentErrorState,
        suggestedSavePath: String,
        stopAfterDownload: Bool,
        alias: String,
        savePathBookmarkData: Data? = nil
    ) {
        currentAddTorrentDraft = AddTorrentDraft(
            source: source,
            originalName: errorState.title,
            infoHash: nil,
            suggestedSavePath: suggestedSavePath,
            savePathBookmarkData: savePathBookmarkData,
            alias: alias,
            stopAfterDownload: stopAfterDownload,
            files: [],
            reviewState: .invalid(message: errorState.message),
            errorState: errorState
        )
        presentedModal = .addTorrentReview
    }

    private func isDuplicateDraft(_ draft: AddTorrentDraft) -> Bool {
        guard let infoHash = draft.infoHash else { return false }
        return torrents.contains(where: { $0.infoHash == infoHash })
    }

    private func presentDuplicateDraft(for draft: AddTorrentDraft) {
        presentInvalidDraft(
            for: draft.source,
            errorState: ShatlErrorCatalog.duplicateDraftError(localeOverride: preferences.localeOverride),
            suggestedSavePath: draft.suggestedSavePath,
            stopAfterDownload: draft.stopAfterDownload,
            alias: draft.alias,
            savePathBookmarkData: draft.savePathBookmarkData
        )
    }

    private func flushPendingIncomingURLs() {
        guard isReadyToProcessIncomingURLs, !pendingIncomingURLs.isEmpty else { return }

        let urls = pendingIncomingURLs
        pendingIncomingURLs.removeAll()

        for url in urls {
            processIncomingURL(url)
        }
    }

    private func beginTransitionTrace(action: String, record: TorrentRecord) {
        guard ShatlFileLogger.shared.loggingEnabled else { return }

        cancelTransitionTrace(for: record.id)

        let operationID = UUID().uuidString
        var context = TransitionTraceContext(
            operationID: operationID,
            action: action,
            startedAtUptimeNs: DispatchTime.now().uptimeNanoseconds
        )
        context.slowTask = makeTransitionWatchdogTask(
            torrentID: record.id,
            operationID: operationID,
            delayNanoseconds: 2_000_000_000,
            phase: "transition.slow",
            level: .notice
        )
        context.stalledTask = makeTransitionWatchdogTask(
            torrentID: record.id,
            operationID: operationID,
            delayNanoseconds: 5_000_000_000,
            phase: "transition.stalled",
            level: .error
        )
        transitionTracesByTorrentID[record.id] = context

        traceTransition(
            torrentID: record.id,
            phase: "request.accepted",
            level: .notice,
            flush: true,
            extra: recordSnapshotFields(for: record)
        )
    }

    private func cancelTransitionTrace(for torrentID: UUID) {
        guard let context = transitionTracesByTorrentID.removeValue(forKey: torrentID) else { return }
        context.slowTask?.cancel()
        context.stalledTask?.cancel()
    }

    private func endTransitionTrace(torrentID: UUID, outcome: String) {
        guard let context = transitionTracesByTorrentID.removeValue(forKey: torrentID) else { return }
        context.slowTask?.cancel()
        context.stalledTask?.cancel()

        var extra = transitionStateSnapshot(for: torrentID)
        extra["outcome"] = outcome
        extra["totalMs"] = elapsedMilliseconds(sinceUptimeNs: context.startedAtUptimeNs)

        emitTransition(
            action: context.action,
            operationID: context.operationID,
            torrentID: torrentID,
            phase: "transition.lock.released",
            level: .notice,
            flush: true,
            extra: extra
        )
    }

    private func traceTransition(
        torrentID: UUID,
        phase: String,
        level: ShatlLogLevel = .debug,
        flush: Bool = false,
        extra: [String: String] = [:]
    ) {
        guard let context = transitionTracesByTorrentID[torrentID] else { return }
        emitTransition(
            action: context.action,
            operationID: context.operationID,
            torrentID: torrentID,
            phase: phase,
            level: level,
            flush: flush,
            extra: extra
        )
    }

    private func emitTransition(
        action: String,
        operationID: String,
        torrentID: UUID,
        phase: String,
        level: ShatlLogLevel,
        flush: Bool,
        extra: [String: String]
    ) {
        guard ShatlFileLogger.shared.loggingEnabled else { return }

        var orderedFields: [(String, String)] = [
            ("launch", launchID),
            ("op", operationID),
            ("torrent", torrentID.uuidString),
            ("action", action),
            ("phase", phase)
        ]

        for key in extra.keys.sorted() {
            guard let value = extra[key] else { continue }
            orderedFields.append((key, value))
        }

        let message = orderedFields
            .map { formatTraceField(key: $0.0, value: $0.1) }
            .joined(separator: " ")

        switch level {
        case .debug:
            flush ? Self.traceLogger.criticalDebug(message) : Self.traceLogger.debug(message)
        case .info:
            flush ? Self.traceLogger.criticalInfo(message) : Self.traceLogger.info(message)
        case .notice:
            flush ? Self.traceLogger.criticalNotice(message) : Self.traceLogger.notice(message)
        case .error:
            flush ? Self.traceLogger.criticalError(message) : Self.traceLogger.error(message)
        }
    }

    private func logUploadCounterDiagnostics(
        phase: String,
        torrentID: UUID,
        previousStatus: TorrentStatus,
        previousMetrics: TorrentMetrics,
        snapshot: EngineTorrentSnapshot,
        appliedStatus: TorrentStatus,
        appliedProgress: Double,
        appliedMetrics: TorrentMetrics
    ) {
        let snapshotUploadSpeed = snapshot.metrics.uploadSpeedBytesPerSecond
        let snapshotUploaded = snapshot.metrics.uploadedBytes
        let appliedUploadSpeed = appliedMetrics.uploadSpeedBytesPerSecond
        let appliedUploaded = appliedMetrics.uploadedBytes
        let suspiciousSnapshot = snapshotUploadSpeed > 0 && snapshotUploaded == 0
        let suspiciousApplied = appliedUploadSpeed > 0 && appliedUploaded == 0
        let uploadSpeedStarted = previousMetrics.uploadSpeedBytesPerSecond == 0 && snapshotUploadSpeed > 0
        let uploadedAppeared = previousMetrics.uploadedBytes == 0 && snapshotUploaded > 0
        let uploadedChanged = previousMetrics.uploadedBytes != snapshotUploaded

        guard suspiciousSnapshot
            || suspiciousApplied
            || uploadSpeedStarted
            || uploadedAppeared
            || uploadedChanged else {
            return
        }

        let fields: [(String, String)] = [
            ("launch", launchID),
            ("torrent", torrentID.uuidString),
            ("phase", phase),
            ("previousStatus", previousStatus.rawValue),
            ("snapshotStatus", snapshot.status.rawValue),
            ("appliedStatus", appliedStatus.rawValue),
            ("snapshotProgress", progressString(snapshot.progress)),
            ("appliedProgress", progressString(appliedProgress)),
            ("previousUploadSpeed", "\(previousMetrics.uploadSpeedBytesPerSecond)"),
            ("previousUploaded", "\(previousMetrics.uploadedBytes)"),
            ("snapshotUploadSpeed", "\(snapshotUploadSpeed)"),
            ("snapshotUploaded", "\(snapshotUploaded)"),
            ("appliedUploadSpeed", "\(appliedUploadSpeed)"),
            ("appliedUploaded", "\(appliedUploaded)"),
            ("willShowUploadedMetric", boolString(appliedUploaded > 0)),
            ("uploadedCounterSuspicious", boolString(suspiciousSnapshot || suspiciousApplied))
        ]

        let message = fields
            .map { formatTraceField(key: $0.0, value: $0.1) }
            .joined(separator: " ")

        if suspiciousSnapshot || suspiciousApplied {
            Self.traceLogger.criticalDebug(message)
        } else {
            Self.traceLogger.debug(message)
        }
    }

    private func makeTransitionWatchdogTask(
        torrentID: UUID,
        operationID: String,
        delayNanoseconds: UInt64,
        phase: String,
        level: ShatlLogLevel
    ) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self else { return }
            guard let context = self.transitionTracesByTorrentID[torrentID],
                  context.operationID == operationID else { return }

            var extra = self.transitionStateSnapshot(for: torrentID)
            extra["totalMs"] = self.elapsedMilliseconds(sinceUptimeNs: context.startedAtUptimeNs)
            self.traceTransition(
                torrentID: torrentID,
                phase: phase,
                level: level,
                flush: true,
                extra: extra
            )
        }
    }

    private func transitionStateSnapshot(for torrentID: UUID) -> [String: String] {
        let record = torrents.first(where: { $0.id == torrentID })
        var fields = recordSnapshotFields(for: record)
        fields["toolbarStartStop"] = boolString(isToolbarStartStopEnabled(for: torrentID))
        fields["toolbarRemove"] = boolString(isToolbarRemoveEnabled(for: torrentID))
        return fields
    }

    private func recordSnapshotFields(for record: TorrentRecord?) -> [String: String] {
        guard let record else {
            return [
                "recordPresent": "0",
                "transitioning": "0",
                "detached": "0",
                "persistentIssue": "none",
                "runtimeError": "none"
            ]
        }

        var fields: [String: String] = [
            "recordPresent": "1",
            "status": record.status.rawValue,
            "progress": progressString(record.progress),
            "transitioning": boolString(transitioningTorrentIDs.contains(record.id)),
            "detached": boolString(detachedTorrentIDs.contains(record.id)),
            "tempRecheck": boolString(temporarilyRestoredRecheckTorrentIDs.contains(record.id)),
            "pendingTempDetach": boolString(pendingTemporaryRecheckDetachIDs.contains(record.id)),
            "pendingSleepingDetach": boolString(pendingSleepingDetachIDs.contains(record.id)),
            "persistentIssue": record.persistentIssue?.kind.rawValue ?? "none",
            "runtimeError": record.runtimeErrorState?.title ?? "none"
        ]

        if let footprint = record.materializedSelectionFootprint {
            fields["materializedSelectedCount"] = "\(footprint.materializedOrdinals.count)"
        }

        return fields
    }

    private func validationFields(for result: DiskIssueValidationResult) -> [String: String] {
        var fields: [String: String] = [
            "issue": result.issue?.kind.rawValue ?? "none"
        ]

        if let footprint = result.footprint {
            fields["materializedSelectedCount"] = "\(footprint.materializedOrdinals.count)"
        }

        if let reason = result.issue?.debugReason, !reason.isEmpty {
            fields["reason"] = reason
        }

        return fields
    }

    private func engineErrorFields(_ error: Error) -> [String: String] {
        let normalized = TorrentEngineError.normalized(from: error)
        var fields: [String: String] = [
            "kind": normalized.kind.rawValue
        ]

        if let reason = normalized.debugReason, !reason.isEmpty {
            fields["reason"] = reason
        }

        return fields
    }

    private func formatTraceField(key: String, value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let needsQuotes = escaped.contains(where: { $0.isWhitespace || $0 == "=" || $0 == "\"" })
        return needsQuotes ? "\(key)=\"\(escaped)\"" : "\(key)=\(escaped)"
    }

    private func progressString(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func boolString(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    private func logDiskDiagnostic(
        _ event: String,
        torrentID: UUID,
        extra: [String: String] = [:]
    ) async {
        guard ShatlDiskDiagnosticsLog.isEnabled else { return }

        guard let record = torrents.first(where: { $0.id == torrentID }) else {
            var fields = baseDiskDiagnosticFields(torrentID: torrentID, record: nil)
            fields.merge(extra) { _, new in new }
            ShatlDiskDiagnosticsLog.event(event, fields: fields)
            return
        }

        await logDiskDiagnostic(event, record: record, extra: extra)
    }

    private func logDiskDiagnostic(
        _ event: String,
        record: TorrentRecord,
        extra: [String: String] = [:]
    ) async {
        guard ShatlDiskDiagnosticsLog.isEnabled else { return }

        var fields = baseDiskDiagnosticFields(torrentID: record.id, record: record)
        let fileState = await diskDiagnosticFileState(for: record)
        fields.merge(fileState) { _, new in new }
        fields.merge(extra) { _, new in new }
        ShatlDiskDiagnosticsLog.event(event, fields: fields)
    }

    private func logDiskDiagnosticSync(
        _ event: String,
        record: TorrentRecord,
        extra: [String: String] = [:]
    ) {
        guard ShatlDiskDiagnosticsLog.isEnabled else { return }

        var fields = baseDiskDiagnosticFields(torrentID: record.id, record: record)
        fields.merge(extra) { _, new in new }
        ShatlDiskDiagnosticsLog.event(event, fields: fields)
    }

    private func baseDiskDiagnosticFields(torrentID: UUID, record: TorrentRecord?) -> [String: String] {
        var fields: [String: String] = [
            "launch": launchID,
            "torrent": torrentID.uuidString,
            "recordPresent": boolString(record != nil)
        ]

        guard let record else { return fields }

        fields["status"] = record.status.rawValue
        fields["progress"] = progressString(record.progress)
        fields["detached"] = boolString(detachedTorrentIDs.contains(record.id))
        fields["transitioning"] = boolString(transitioningTorrentIDs.contains(record.id))
        fields["persistentIssue"] = record.persistentIssue?.kind.rawValue ?? "none"
        fields["persistentStatusBeforeIssue"] = record.persistentIssue?.statusBeforeIssue?.rawValue ?? "none"
        fields["runtimeError"] = record.runtimeErrorState?.title ?? "none"
        fields["savePath"] = record.canonicalSavePath
        fields["selectedFileCount"] = "\(record.selectedFileCount)"
        fields["totalFileCount"] = "\(record.totalFileCount)"

        if let footprint = record.materializedSelectionFootprint {
            fields["recordFootprintCount"] = "\(footprint.materializedOrdinals.count)"
            fields["recordFootprintOrdinals"] = footprint.materializedOrdinals
                .sorted()
                .map(String.init)
                .joined(separator: ",")
        } else {
            fields["recordFootprintCount"] = "nil"
            fields["recordFootprintOrdinals"] = "nil"
        }

        return fields
    }

    private func diskDiagnosticFileState(for record: TorrentRecord) async -> [String: String] {
        guard ShatlDiskDiagnosticsLog.isEnabled else { return [:] }

        var fields: [String: String] = [:]
        guard let saveURL = await bookmarkStore.resolveURL(
            for: record.id,
            fallbackPath: record.canonicalSavePath
        ) else {
            fields["savePathResolved"] = "0"
            return fields
        }

        fields["savePathResolved"] = "1"
        fields["savePathExists"] = boolString(FileManager.default.fileExists(atPath: saveURL.path))

        guard let archiveURL = await archivedRestoreURL(for: record) else {
            fields["archiveExists"] = "0"
            return fields
        }

        fields["archiveExists"] = "1"

        let contentFiles: [TorrentContentFileDescriptor]
        do {
            contentFiles = try await engine.inspectTorrentContents(at: archiveURL.path)
        } catch {
            fields["inspectContents"] = "failed"
            fields.merge(engineErrorFields(error)) { _, new in new }
            return fields
        }

        fields["inspectContents"] = "success"

        let selectedFileIndices = Set(record.selectedFileIndices)
        let selectedFiles = contentFiles
            .filter { selectedFileIndices.contains($0.fileIndex) }
            .sorted { $0.fileIndex < $1.fileIndex }

        var existingPaths: [String] = []
        var missingPaths: [String] = []

        for file in selectedFiles {
            let relativePath = file.relativePath
                .replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let fileURL = saveURL.appendingPathComponent(relativePath, isDirectory: false)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                existingPaths.append(relativePath)
            } else {
                missingPaths.append(relativePath)
            }
        }

        fields["selectedDescriptorCount"] = "\(selectedFiles.count)"
        fields["selectedExistingCount"] = "\(existingPaths.count)"
        fields["selectedMissingCount"] = "\(missingPaths.count)"
        fields["selectedExistingFirst"] = existingPaths.prefix(3).joined(separator: "|")
        fields["selectedMissingFirst"] = missingPaths.prefix(3).joined(separator: "|")

        return fields
    }

    private func scheduleDelayedDiskDiagnosticProbe(
        torrentID: UUID,
        event: String,
        delayNanoseconds: UInt64
    ) {
        guard ShatlDiskDiagnosticsLog.isEnabled else { return }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self else { return }
            await self.logDiskDiagnostic(event, torrentID: torrentID)
        }
    }

    private func elapsedMilliseconds(sinceUptimeNs start: UInt64) -> String {
        let now = DispatchTime.now().uptimeNanoseconds
        let delta = now >= start ? now - start : 0
        return String(delta / 1_000_000)
    }

    private func isToolbarStartStopEnabled(for torrentID: UUID) -> Bool {
        guard let record = torrents.first(where: { $0.id == torrentID }) else { return false }
        return record.errorState == nil
            && !isRestoringSession
            && !transitioningTorrentIDs.contains(record.id)
    }

    private func isToolbarRemoveEnabled(for torrentID: UUID) -> Bool {
        guard let record = torrents.first(where: { $0.id == torrentID }) else { return false }
        return record.persistentIssue == nil
            && !isRestoringSession
            && !transitioningTorrentIDs.contains(record.id)
    }

    private func applyEngineError(_ error: Error, to torrentID: UUID) {
        guard let index = torrents.firstIndex(where: { $0.id == torrentID }) else { return }
        let engineError = TorrentEngineError.normalized(from: error)
        Self.logger.error("Applying runtime error to torrent id=\(torrentID.uuidString) kind=\(engineError.kind.rawValue) reason=\(engineError.debugReason ?? "-")")
        traceTransition(
            torrentID: torrentID,
            phase: "engine.error.applied",
            level: .error,
            flush: true,
            extra: engineErrorFields(error)
        )

        torrents[index].status = .error
        torrents[index].runtimeErrorState = ShatlErrorCatalog.torrentActionError(for: error)
    }

    private func applyRestoredPersistentIssues(_ issues: [UUID: TorrentPersistentIssue]) {
        for (torrentID, issue) in issues {
            guard let index = torrents.firstIndex(where: { $0.id == torrentID }) else { continue }

            torrents[index].persistentIssue = issue
            detachedTorrentIDs.insert(torrentID)
            torrents[index].runtimeErrorState = nil
            restoreProgressFloorByID[torrentID] = nil
            restoreRecheckRequestedIDs.remove(torrentID)
        }
    }

    private func applyRestoreFallbackStatuses(
        _ fallbackStatusesByID: [UUID: TorrentStatus],
        restoredSnapshotIDs: Set<UUID>
    ) -> Bool {
        var didChangeState = false

        for index in torrents.indices {
            let torrentID = torrents[index].id
            guard let fallbackStatus = fallbackStatusesByID[torrentID] else { continue }
            guard !restoredSnapshotIDs.contains(torrentID) else { continue }
            guard torrents[index].persistentIssue == nil else { continue }
            restoreProgressFloorByID[torrentID] = nil
            restoreRecheckRequestedIDs.remove(torrentID)

            if torrents[index].status != fallbackStatus || torrents[index].runtimeErrorState != nil {
                torrents[index].status = fallbackStatus
                torrents[index].runtimeErrorState = nil
                torrents[index].metrics.downloadSpeedBytesPerSecond = 0
                torrents[index].metrics.uploadSpeedBytesPerSecond = 0
                torrents[index].metrics.etaSeconds = nil
                torrents[index].metrics.seeds = nil
                torrents[index].metrics.peers = nil
                detachedTorrentIDs.insert(torrentID)
                didChangeState = true
            }
        }

        return didChangeState
    }

    private func applyDiskIssueEvaluation(
        _ evaluation: DiskIssueEvaluation
    ) -> (newlyErroredActiveTorrentIDs: [UUID], didChangeState: Bool) {
        var newlyErroredActiveTorrentIDs: [UUID] = []
        var didChangeState = false

        for torrentID in evaluation.checkedTorrentIDs {
            guard let index = torrents.firstIndex(where: { $0.id == torrentID }) else { continue }

            if let footprint = evaluation.footprintsByTorrentID[torrentID] {
                if torrents[index].materializedSelectionFootprint != footprint {
                    torrents[index].materializedSelectionFootprint = footprint
                    didChangeState = true
                }
            }

            let hadPersistentIssue = torrents[index].persistentIssue != nil
            let nextIssue = evaluation.issuesByTorrentID[torrentID]
            let wasActiveBeforeIssue = torrents[index].status.isActive
                || torrents[index].persistentIssue?.statusBeforeIssue?.isActive == true

            guard hadPersistentIssue || nextIssue != nil else { continue }

            let previousIssue = torrents[index].persistentIssue
            applyPersistentIssue(nextIssue, to: torrentID)
            if previousIssue != torrents[index].persistentIssue {
                didChangeState = true
            }

            if !hadPersistentIssue, nextIssue != nil, wasActiveBeforeIssue {
                newlyErroredActiveTorrentIDs.append(torrentID)
            }
        }

        return (newlyErroredActiveTorrentIDs, didChangeState)
    }

    private func applyValidationResult(_ result: DiskIssueValidationResult, to torrentID: UUID) {
        guard let index = torrents.firstIndex(where: { $0.id == torrentID }) else { return }

        if let footprint = result.footprint {
            torrents[index].materializedSelectionFootprint = footprint
        }

        if let issue = result.issue {
            applyPersistentIssue(issue, to: torrentID)
        }
    }

    private func applyPersistentIssue(_ issue: TorrentPersistentIssue?, to torrentID: UUID) {
        guard let index = torrents.firstIndex(where: { $0.id == torrentID }) else { return }
        let previousIssue = torrents[index].persistentIssue

        if let issue {
            let normalizedIssue = normalizedPersistentIssue(issue, for: torrents[index])
            torrents[index].persistentIssue = normalizedIssue
            detachedTorrentIDs.insert(torrentID)
            torrents[index].runtimeErrorState = nil
            torrents[index].status = .error
            notifyPersistentIssueIfNeeded(
                torrent: torrents[index],
                previousIssue: previousIssue,
                issue: normalizedIssue
            )
            return
        }

        let restoredStatus = resolvedStatusAfterClearingIssue(for: torrents[index])
        torrents[index].persistentIssue = nil
        torrents[index].status = restoredStatus
        torrents[index].runtimeErrorState = nil

        if restoredStatus.isSleeping {
            detachedTorrentIDs.insert(torrentID)
        } else {
            detachedTorrentIDs.remove(torrentID)
        }
        notifiedPersistentIssueKeys = Set(
            notifiedPersistentIssueKeys.filter { $0.torrentID != torrentID }
        )
        clearUnreadUserEvents(for: torrentID)
    }

    private func notifyDownloadCompletionIfNeeded(
        torrent: TorrentRecord,
        previousStatus: TorrentStatus,
        previousProgress: Double,
        resolvedStatus: TorrentStatus,
        resolvedProgress: Double,
        snapshot: EngineTorrentSnapshot
    ) {
        if resolvedProgress < 1.0 {
            notifiedCompletedTorrentIDs.remove(torrent.id)
            return
        }

        guard allowsUserFacingNotifications,
              previousStatus == .downloading,
              previousProgress < 1.0,
              snapshot.errorState == nil,
              resolvedProgress >= 1.0,
              resolvedStatus == .seeding || resolvedStatus == .completed,
              !notifiedCompletedTorrentIDs.contains(torrent.id) else {
            return
        }

        notifiedCompletedTorrentIDs.insert(torrent.id)
        registerUnreadCompletionIfNeeded(torrentID: torrent.id)
        userEventNotifier?.notify(
            .downloadCompleted(
                torrentID: torrent.id,
                torrentTitle: torrent.displayName,
                localeOverride: preferences.localeOverride
            ),
            badgeCount: userEventBadgeCount
        )
    }

    private func notifyPersistentIssueIfNeeded(
        torrent: TorrentRecord,
        previousIssue: TorrentPersistentIssue?,
        issue: TorrentPersistentIssue
    ) {
        guard allowsUserFacingNotifications,
              previousIssue?.kind != issue.kind else {
            return
        }

        let notificationKey = PersistentIssueNotificationKey(
            torrentID: torrent.id,
            kind: issue.kind
        )
        guard !notifiedPersistentIssueKeys.contains(notificationKey) else { return }

        let errorState = ShatlErrorCatalog.persistentIssueState(for: issue)
        guard let rowErrorState = TorrentRowErrorState(
            errorState,
            localeOverride: preferences.localeOverride
        ) else {
            return
        }

        notifiedPersistentIssueKeys.insert(notificationKey)
        registerUnreadPersistentIssueIfNeeded(notificationKey)
        userEventNotifier?.notify(
            .persistentIssue(
                torrentID: torrent.id,
                issueKind: issue.kind,
                torrentTitle: torrent.displayName,
                issueTitle: rowErrorState.title,
                issueMessage: rowErrorState.message,
                localeOverride: preferences.localeOverride
            ),
            badgeCount: userEventBadgeCount
        )
    }

    func setApplicationUserAttentionActive(_ isActive: Bool) {
        isApplicationUserAttentionActive = isActive
        if isActive {
            clearUserEventBadge()
        }
    }

    func clearUserEventBadge() {
        guard !unreadCompletedTorrentIDs.isEmpty || !unreadPersistentIssueKeys.isEmpty else {
            updateUserEventBadge()
            return
        }

        unreadCompletedTorrentIDs.removeAll()
        unreadPersistentIssueKeys.removeAll()
        updateUserEventBadge()
    }

    private func registerUnreadCompletionIfNeeded(torrentID: UUID) {
        guard !isApplicationUserAttentionActive else { return }
        unreadCompletedTorrentIDs.insert(torrentID)
        updateUserEventBadge()
    }

    private func registerUnreadPersistentIssueIfNeeded(_ key: PersistentIssueNotificationKey) {
        guard !isApplicationUserAttentionActive else { return }
        unreadPersistentIssueKeys.insert(key)
        updateUserEventBadge()
    }

    private func clearUnreadUserEvents(for torrentID: UUID) {
        unreadCompletedTorrentIDs.remove(torrentID)
        unreadPersistentIssueKeys = Set(
            unreadPersistentIssueKeys.filter { $0.torrentID != torrentID }
        )
        updateUserEventBadge()
    }

    private var userEventBadgeCount: Int {
        unreadCompletedTorrentIDs.count + unreadPersistentIssueKeys.count
    }

    private func updateUserEventBadge() {
        userEventBadgeDisplay?.setBadgeCount(userEventBadgeCount)
    }

    private func restoreAndStart(record: TorrentRecord) async {
        Self.logger.notice("Restore-start requested for torrent id=\(record.id.uuidString) status=\(record.status.rawValue) progress=\(String(format: "%.3f", record.progress))")
        traceTransition(torrentID: record.id, phase: "restore.resolve-save-path.begin", level: .debug)
        guard let saveURL = await bookmarkStore.resolveURL(
            for: record.id,
            fallbackPath: record.canonicalSavePath
        ) else {
            Self.logger.error("Restore-start failed to resolve save path for torrent id=\(record.id.uuidString)")
            traceTransition(
                torrentID: record.id,
                phase: "restore.resolve-save-path.failed",
                level: .error,
                flush: true,
                extra: ["reason": "save-path-unavailable"]
            )
            applyPersistentIssue(
                TorrentPersistentIssue(
                    kind: .savePathUnavailable,
                    detectedAt: Date(),
                    statusBeforeIssue: record.persistentIssue?.statusBeforeIssue ?? record.status,
                    debugReason: "Не удалось разрешить путь для запуска торрента."
                ),
                to: record.id
            )
            saveCriticalState()
            return
        }

        traceTransition(
            torrentID: record.id,
            phase: "restore.resolve-save-path.end",
            level: .debug,
            extra: ["savePath": saveURL.path]
        )

        guard let archiveURL = await archivedRestoreURL(for: record) else {
            Self.logger.error("Restore-start failed because archived torrent is missing for torrent id=\(record.id.uuidString)")
            traceTransition(
                torrentID: record.id,
                phase: "restore.archive-missing",
                level: .error,
                flush: true,
                extra: [:]
            )
            applyMissingArchivedTorrentError(
                to: record.id,
                debugReason: "Не найден архивный torrent-файл для запуска торрента."
            )
            return
        }

        let restoreEntry = SessionRestoreEntry(
            torrentID: record.id,
            attemptID: record.attemptID,
            archivedTorrentPath: archiveURL.path,
            suggestedSavePath: saveURL.path,
            selectedFileIndices: record.selectedFileIndices,
            stopAfterDownload: record.stopAfterDownload,
            shouldStart: true
        )

        let retryDelays: [UInt64] = [0, 150_000_000, 300_000_000]
        var lastError: Error?

        for delay in retryDelays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }

            do {
                Self.logger.notice("Restore-start attempt for torrent id=\(record.id.uuidString) delayNs=\(delay)")
                let restoreStartedAt = DispatchTime.now().uptimeNanoseconds
                traceTransition(
                    torrentID: record.id,
                    phase: "restore.attempt.begin",
                    level: .notice,
                    flush: true,
                    extra: ["delayNs": "\(delay)"]
                )
                let snapshots = try await engine.restoreSession([restoreEntry])
                detachedTorrentIDs.remove(record.id)
                applySnapshots(snapshots)

                if let index = torrents.firstIndex(where: { $0.id == record.id }) {
                    torrents[index].runtimeErrorState = nil
                }

                Self.logger.notice("Restore-start succeeded for torrent id=\(record.id.uuidString)")
                traceTransition(
                    torrentID: record.id,
                    phase: "restore.attempt.end",
                    level: .notice,
                    flush: true,
                    extra: ["engineMs": elapsedMilliseconds(sinceUptimeNs: restoreStartedAt)]
                )
                await persistCriticalState()
                return
            } catch {
                let engineError = TorrentEngineError.normalized(from: error)
                lastError = error
                Self.logger.error("Restore-start failed for torrent id=\(record.id.uuidString) kind=\(engineError.kind.rawValue) reason=\(engineError.debugReason ?? "-")")
                traceTransition(
                    torrentID: record.id,
                    phase: "restore.attempt.failed",
                    level: .error,
                    flush: true,
                    extra: engineErrorFields(error).merging(["delayNs": "\(delay)"]) { current, _ in current }
                )

                if engineError.kind == .duplicateTorrent {
                    do {
                        let directStartStartedAt = DispatchTime.now().uptimeNanoseconds
                        try await engine.startTorrent(id: record.id)
                        detachedTorrentIDs.remove(record.id)

                        if let index = torrents.firstIndex(where: { $0.id == record.id }) {
                            torrents[index].status = record.progress >= 1.0 ? .seeding : .downloading
                            torrents[index].runtimeErrorState = nil
                        }

                        Self.logger.notice("Restore-start reused existing handle for torrent id=\(record.id.uuidString)")
                        traceTransition(
                            torrentID: record.id,
                            phase: "restore.reused-existing-handle",
                            level: .notice,
                            flush: true,
                            extra: ["engineMs": elapsedMilliseconds(sinceUptimeNs: directStartStartedAt)]
                        )
                        await persistCriticalState()
                        await refreshActiveSnapshots()
                        return
                    } catch {
                        let directStartError = TorrentEngineError.normalized(from: error)
                        Self.logger.error("Restore-start duplicate fallback failed for torrent id=\(record.id.uuidString) kind=\(directStartError.kind.rawValue) reason=\(directStartError.debugReason ?? "-")")
                        traceTransition(
                            torrentID: record.id,
                            phase: "restore.reused-existing-handle.failed",
                            level: .error,
                            flush: true,
                            extra: engineErrorFields(error)
                        )
                    }
                }

                guard engineError.kind == .duplicateTorrent else {
                    break
                }
            }
        }

        if let lastError {
            applyEngineError(lastError, to: record.id)
        }
    }

    private func normalizedPersistentIssue(
        _ issue: TorrentPersistentIssue,
        for record: TorrentRecord
    ) -> TorrentPersistentIssue {
        if issue.statusBeforeIssue != nil {
            return issue
        }

        return TorrentPersistentIssue(
            kind: issue.kind,
            detectedAt: issue.detectedAt,
            statusBeforeIssue: record.persistentIssue?.statusBeforeIssue ?? inferredHealthyStatus(for: record),
            debugReason: issue.debugReason
        )
    }

    private func resolvedStatusAfterClearingIssue(for record: TorrentRecord) -> TorrentStatus {
        if let previousStatus = record.persistentIssue?.statusBeforeIssue {
            if previousStatus == .error {
                return legacyRecoveredStatus(for: record)
            }
            return previousStatus
        }

        return inferredHealthyStatus(for: record)
    }

    private func inferredHealthyStatus(for record: TorrentRecord) -> TorrentStatus {
        record.progress >= 1.0 ? .completed : .stopped
    }

    private func legacyRecoveredStatus(for record: TorrentRecord) -> TorrentStatus {
        guard record.persistentIssue?.kind == .savePathUnavailable else {
            return inferredHealthyStatus(for: record)
        }

        if record.progress >= 1.0 {
            return .completed
        }

        return .downloading
    }

    private func normalizedRuntimeOnlyErrorStatus(
        status: TorrentStatus,
        progress: Double,
        persistentIssue: TorrentPersistentIssue?
    ) -> TorrentStatus {
        guard persistentIssue == nil, status == .error else {
            return status
        }

        return progress >= 1.0 ? .completed : .stopped
    }

    private func isDuplicateError(_ error: Error) -> Bool {
        TorrentEngineError.normalized(from: error).kind == .duplicateTorrent
    }

    private func archivedRestoreURL(for record: TorrentRecord) async -> URL? {
        let archiveURL = await torrentArchiveStore
            .resolveArchiveURL(relativePath: torrentArchiveStore.relativeArchivePath(for: record.id))

        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            return nil
        }

        return archiveURL
    }

    private func applyMissingArchivedTorrentError(to torrentID: UUID, debugReason: String) {
        guard let index = torrents.firstIndex(where: { $0.id == torrentID }) else { return }

        let engineError = TorrentEngineError(kind: .torrentNotFound, debugReason: debugReason)
        torrents[index].persistentIssue = nil
        torrents[index].status = .error
        torrents[index].runtimeErrorState = ShatlErrorCatalog.torrentActionError(for: engineError)
        detachedTorrentIDs.insert(torrentID)
    }

    private func makeRestoreEntryForUserAction(
        record: TorrentRecord,
        shouldStart: Bool,
        savePathFailureReason: String
    ) async -> SessionRestoreEntry? {
        traceTransition(torrentID: record.id, phase: "restore-entry.resolve-save-path.begin", level: .debug)
        guard let saveURL = await bookmarkStore.resolveURL(
            for: record.id,
            fallbackPath: record.canonicalSavePath
        ) else {
            traceTransition(
                torrentID: record.id,
                phase: "restore-entry.resolve-save-path.failed",
                level: .error,
                flush: true,
                extra: ["reason": savePathFailureReason]
            )
            applyPersistentIssue(
                TorrentPersistentIssue(
                    kind: .savePathUnavailable,
                    detectedAt: Date(),
                    statusBeforeIssue: record.persistentIssue?.statusBeforeIssue ?? record.status,
                    debugReason: savePathFailureReason
                ),
                to: record.id
            )
            saveCriticalState()
            return nil
        }

        traceTransition(
            torrentID: record.id,
            phase: "restore-entry.resolve-save-path.end",
            level: .debug,
            extra: ["savePath": saveURL.path]
        )

        guard let archiveURL = await archivedRestoreURL(for: record) else {
            traceTransition(
                torrentID: record.id,
                phase: "restore-entry.archive-missing",
                level: .error,
                flush: true,
                extra: [:]
            )
            applyMissingArchivedTorrentError(
                to: record.id,
                debugReason: "Не найден архивный torrent-файл для пользовательского действия."
            )
            return nil
        }

        return SessionRestoreEntry(
            torrentID: record.id,
            attemptID: record.attemptID,
            archivedTorrentPath: archiveURL.path,
            suggestedSavePath: saveURL.path,
            selectedFileIndices: record.selectedFileIndices,
            stopAfterDownload: record.stopAfterDownload,
            shouldStart: shouldStart
        )
    }

    private func detachCompletedTemporaryRechecks(from snapshots: [EngineTorrentSnapshot]) async {
        let completedTemporaryIDs = snapshots
            .filter { temporarilyRestoredRecheckTorrentIDs.contains($0.id) && $0.status.isSleeping }
            .map(\.id)

        guard !completedTemporaryIDs.isEmpty else { return }

        for torrentID in completedTemporaryIDs {
            temporarilyRestoredRecheckTorrentIDs.remove(torrentID)
            detachedTorrentIDs.insert(torrentID)
            traceTransition(torrentID: torrentID, phase: "temporary.detach.begin", level: .notice, flush: true)
            try? await engine.removeTorrent(id: torrentID, deleteData: false)
            traceTransition(torrentID: torrentID, phase: "temporary.detach.end", level: .notice, flush: true)
        }

        await persistCriticalState()
    }

    private func detachCompletedTemporaryRechecksIfNeeded() async {
        let completedTemporaryIDs = Array(pendingTemporaryRecheckDetachIDs)
        guard !completedTemporaryIDs.isEmpty else { return }

        for torrentID in completedTemporaryIDs {
            pendingTemporaryRecheckDetachIDs.remove(torrentID)
            temporarilyRestoredRecheckTorrentIDs.remove(torrentID)
            temporaryRecheckPostCheckStatusByID[torrentID] = nil
            detachedTorrentIDs.insert(torrentID)
            traceTransition(torrentID: torrentID, phase: "temporary.detach.begin", level: .notice, flush: true)
            try? await engine.removeTorrent(id: torrentID, deleteData: false)
            traceTransition(torrentID: torrentID, phase: "temporary.detach.end", level: .notice, flush: true)
        }

        await persistCriticalState()
    }

    private func detachSleepingHandlesIfNeeded() async {
        let sleepingIDs = Array(pendingSleepingDetachIDs)
        guard !sleepingIDs.isEmpty else { return }

        for torrentID in sleepingIDs {
            pendingSleepingDetachIDs.remove(torrentID)
            detachedTorrentIDs.insert(torrentID)

            do {
                traceTransition(torrentID: torrentID, phase: "sleeping.detach.begin", level: .notice, flush: true)
                try await engine.removeTorrent(id: torrentID, deleteData: false)
                traceTransition(torrentID: torrentID, phase: "sleeping.detach.end", level: .notice, flush: true)
            } catch {
                let engineError = TorrentEngineError.normalized(from: error)
                if engineError.kind != .torrentNotFound {
                    traceTransition(
                        torrentID: torrentID,
                        phase: "sleeping.detach.failed",
                        level: .error,
                        flush: true,
                        extra: engineErrorFields(error)
                    )
                    applyEngineError(error, to: torrentID)
                } else {
                    traceTransition(
                        torrentID: torrentID,
                        phase: "sleeping.detach.not-found",
                        level: .notice,
                        flush: true,
                        extra: engineErrorFields(error)
                    )
                }
            }
        }

        await persistCriticalState()
    }

    private func refreshSelectedTorrentNavigationAvailability() {
        let selectedID = selectedTorrentID

        guard let selectedID else {
            selectedTorrentNavigationAvailability = TorrentNavigationAvailability()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let location = await self.primaryLocation(for: selectedID)
            guard self.selectedTorrentID == selectedID else { return }

            self.selectedTorrentNavigationAvailability = TorrentNavigationAvailability(
                canOpen: location?.openItemURL != nil,
                canReveal: location != nil
            )
        }
    }
}
