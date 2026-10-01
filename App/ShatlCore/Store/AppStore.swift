// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Combine
import Foundation

enum OnboardingPresentation: Equatable {
    case hidden
    case firstLaunch
    case debug

    var isPresented: Bool {
        self != .hidden
    }
}

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

    private struct PendingTorrentAddition {
        let id: UUID
        let attemptID: UUID
        let draft: AddTorrentDraft
        let shortDisplayName: String
        let presentationStartedAt: ContinuousClock.Instant
    }

    private struct DeferredAddTorrentFailure {
        let draft: AddTorrentDraft
        let errorState: TorrentErrorState
    }

    struct TorrentNavigationAvailability: Equatable {
        var canOpen = false
        var canReveal = false
    }

    var torrents: [TorrentRecord] {
        willSet {
            guard !suppressesTorrentChangePublication, newValue != torrents else { return }
            objectWillChange.send()
        }
        didSet {
            guard oldValue != torrents else { return }
            updateTorrentIndex(previous: oldValue)
            refreshTorrentPresentations()
        }
    }
    @Published var selectedTorrentID: UUID? {
        didSet {
            guard oldValue != selectedTorrentID else { return }
            refreshTorrentPresentations()
        }
    }
    @Published var expandedTorrentID: UUID? {
        didSet {
            guard oldValue != expandedTorrentID else { return }
            refreshTorrentPresentations()
        }
    }
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
            ShatlCardLayoutDiagnosticsLog.setEnabled(preferences.isCardLayoutDiagnosticsLoggingEnabled)
            ShatlSnapshotDiagnosticsLog.setEnabled(preferences.isSnapshotDiagnosticsLoggingEnabled)
            ShatlAddTorrentReviewDiagnosticsLog.setEnabled(
                preferences.isAddTorrentReviewDiagnosticsLoggingEnabled
            )
            refreshTorrentPresentations()
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
    @Published private(set) var sessionPersistenceIssue: SessionPersistenceIssue?
    /// Refreshed only while Settings shows it: `refreshPortForwardingIndicator`.
    @Published private(set) var portForwardingIndicator: PortForwardingIndicator = .hidden
    @Published var presentedModal: PresentedModal?
    @Published private(set) var addTorrentReviewWindowRequestID = 0
    @Published private(set) var isAddTorrentReviewWindowActive = false
    @Published var currentAddTorrentDraft: AddTorrentDraft? {
        didSet {
            guard let oldValue, oldValue.id != currentAddTorrentDraft?.id else { return }
            releasePreparedDraftUnlessAdding(oldValue.id)
        }
    }
    @Published var isRestoringSession = false {
        didSet {
            guard oldValue != isRestoringSession else { return }
            refreshTorrentPresentations()
        }
    }
    @Published private(set) var hasLoadedInitialSession: Bool
    @Published private(set) var sessionLoadIssue: SessionLoadIssue?
    @Published private(set) var isResolvingSessionRecovery = false
    /// A first-launch or Debug onboarding owns the main window until it finishes.
    @Published private(set) var onboardingPresentation = OnboardingPresentation.hidden
    @Published private(set) var transitioningTorrentIDs: Set<UUID> = [] {
        didSet {
            guard oldValue != transitioningTorrentIDs else { return }
            refreshTorrentPresentations()
        }
    }
    @Published private(set) var selectedTorrentNavigationAvailability = TorrentNavigationAvailability()

    let torrentTransferSummary = TorrentTransferSummaryModel()
    /// What the cards leave out with many downloads running; see
    /// `CardSimplificationLevel`. The speed chips read it too.
    @Published private(set) var cardSimplification = CardSimplificationLevel.full
    private var automaticCardSimplification = CardSimplificationLevel.full

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
    private var usageTelemetryWeekMonitorTask: Task<Void, Never>?
    private let usageTelemetryWeekCheckInterval: Duration
    private var sessionPersistenceCheckTask: Task<Void, Never>?
    private var sessionPersistenceIssueGeneration = 0
    private var isSessionPersistenceIssueHidden = false
    private var lastRequestedPerformanceSettings: EnginePerformanceSettings?
    private var didBootstrap = false
    private var didResolveInitialSessionLoad = false
    private var didCompleteRuntimeBootstrap = false
    private var isEngineReady = false
    private var lastPersistedProgressBucketByID: [UUID: Int] = [:]
    private let progressSaveInterval: Duration
    private var progressSaveTask: Task<Void, Never>?
    private var lastProgressSaveAt: ContinuousClock.Instant?
    private var isPreparingForTermination = false
    private var pendingTorrentAdditions: [PendingTorrentAddition] = []
    private var pendingTorrentAdditionTasks: [UUID: Task<Void, Never>] = [:]
    private var cancelledPendingTorrentAdditionIDs: Set<UUID> = []
    private var deferredAddTorrentFailures: [DeferredAddTorrentFailure] = []
    private static let minimumPendingAdditionPresentationDuration = Duration.milliseconds(600)
    private var pendingIncomingURLs: [URL] = []
    /// Torrents that must intentionally ignore engine snapshots.
    /// Prevents delayed polling from resurrecting an already stopped torrent.
    private var detachedTorrentIDs: Set<UUID> = []
    /// The speed icons each torrent shows, kept between updates so an icon
    /// does not flicker at a threshold. See `TransferSpeedLevel`.
    private var transferSpeedLevels: [UUID: TransferSpeedLevels] = [:]
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
    private var suppressesTorrentChangePublication = false
    private var torrentRowPresentationModelsByID: [UUID: TorrentRowPresentationModel] = [:]
    /// What each record card was last built from. The 1 Hz tick rebuilds only
    /// cards whose inputs changed, not the whole list.
    private var torrentRowInputsByID: [UUID: TorrentRowInputs] = [:]
    /// Positions in `torrents`, so lookups by ID do not scan the list.
    private var torrentIndexByID: [UUID: Int] = [:]
    #if DEBUG
    private(set) var recordRowStateBuildCountForTesting = 0
    #endif

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
        hasLoadedInitialSession: Bool = false,
        progressSaveInterval: Duration = .seconds(30),
        usageTelemetryWeekCheckInterval: Duration = .seconds(3600)
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
        self.progressSaveInterval = progressSaveInterval
        self.usageTelemetryWeekCheckInterval = usageTelemetryWeekCheckInterval
        self.torrents = torrents
        self.torrentIndexByID = Self.makeTorrentIndex(torrents)
        self.lastPersistedProgressBucketByID = Dictionary(
            uniqueKeysWithValues: torrents.map {
                ($0.id, Self.progressPersistenceBucket(for: max($0.progress, $0.lastKnownProgress)))
            }
        )
        let resolvedHasLoadedInitialSession = hasLoadedInitialSession || !torrents.isEmpty
        self.hasLoadedInitialSession = resolvedHasLoadedInitialSession
        self.sessionLoadIssue = nil
        self.allowsUserFacingNotifications = resolvedHasLoadedInitialSession
        let resolvedPreferences = preferences ?? preferencesStore?.load() ?? .defaultValue
        self.preferences = resolvedPreferences
        self.portForwardingIndicator = PortForwardingIndicator(
            isEnabled: resolvedPreferences.opensRouterPortAutomatically,
            status: nil
        )
        ShatlFileLogger.shared.setEnabled(resolvedPreferences.isLoggingEnabled)
        ShatlDiskDiagnosticsLog.setEnabled(resolvedPreferences.isDiskDiagnosticsLoggingEnabled)
        ShatlMetricAnimationDiagnosticsLog.setEnabled(
            resolvedPreferences.isMetricAnimationDiagnosticsLoggingEnabled
        )
        ShatlCardLayoutDiagnosticsLog.setEnabled(resolvedPreferences.isCardLayoutDiagnosticsLoggingEnabled)
        ShatlSnapshotDiagnosticsLog.setEnabled(resolvedPreferences.isSnapshotDiagnosticsLoggingEnabled)
        ShatlAddTorrentReviewDiagnosticsLog.setEnabled(
            resolvedPreferences.isAddTorrentReviewDiagnosticsLoggingEnabled
        )
        refreshTorrentPresentations()

        externalOpenRouter.attach { [weak self] url in
            self?.handleIncomingURL(url)
        }

        recordUsageTelemetryLaunchIfNeeded()
        startUsageTelemetryWeekMonitor()
    }

    deinit {
        runtimeTask?.cancel()
        initialSessionLoadTask?.cancel()
        bootstrapTask?.cancel()
        draftPreparationTask?.cancel()
        performanceApplyTask?.cancel()
        usageTelemetrySendTask?.cancel()
        usageTelemetryWeekMonitorTask?.cancel()
        progressSaveTask?.cancel()
        for task in pendingTorrentAdditionTasks.values {
            task.cancel()
        }
        for context in transitionTracesByTorrentID.values {
            context.slowTask?.cancel()
            context.stalledTask?.cancel()
        }
    }

    var selectedTorrent: TorrentRecord? {
        guard let selectedTorrentID else { return nil }
        return torrentRecord(for: selectedTorrentID)
    }

    var torrentRowIDs: [UUID] {
        let pendingIDs = Set(pendingTorrentAdditions.map(\.id))
        return pendingTorrentAdditions.map(\.id) + torrents.compactMap {
            pendingIDs.contains($0.id) ? nil : $0.id
        }
    }

    var bottomTransferChips: [BottomTransferChipPresentation] {
        TorrentPresentation.bottomTransferChips(
            for: torrents,
            mode: preferences.metricsMode,
            localeOverride: preferences.localeOverride
        )
    }

    func torrentRowPresentationModel(for id: UUID) -> TorrentRowPresentationModel? {
        torrentRowPresentationModelsByID[id]
    }

    func torrentRowIDs(matching searchQuery: String) -> [UUID] {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return torrentRowIDs }

        let matchingPendingIDs = pendingTorrentAdditions
            .filter { addition in
                addition.draft.originalName.localizedCaseInsensitiveContains(normalizedQuery)
                    || addition.draft.alias.localizedCaseInsensitiveContains(normalizedQuery)
            }
            .map(\.id)
        let pendingIDs = Set(pendingTorrentAdditions.map(\.id))
        let matchingTorrentIDs = torrents
            .filter { record in
                !pendingIDs.contains(record.id)
                    && (record.originalName.localizedCaseInsensitiveContains(normalizedQuery)
                        || record.alias?.localizedCaseInsensitiveContains(normalizedQuery) == true)
            }
            .map(\.id)
        return matchingPendingIDs + matchingTorrentIDs
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
        torrentIndex(for: id).map { torrents[$0] }
    }

    private func torrentIndex(for id: UUID) -> Int? {
        guard let index = torrentIndexByID[id], torrents.indices.contains(index), torrents[index].id == id else {
            return nil
        }
        return index
    }

    private func updateTorrentIndex(previous: [TorrentRecord]) {
        // A snapshot tick changes records in place and keeps their order.
        let keepsOrder = previous.count == torrents.count
            && zip(previous, torrents).allSatisfy { $0.id == $1.id }
        if !keepsOrder {
            torrentIndexByID = Self.makeTorrentIndex(torrents)
        }
    }

    /// The first record wins for a repeated ID, as a linear search would find it.
    private static func makeTorrentIndex(_ torrents: [TorrentRecord]) -> [UUID: Int] {
        Dictionary(torrents.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func isPendingAddition(id: UUID) -> Bool {
        pendingTorrentAdditions.contains(where: { $0.id == id })
    }

    func pendingAdditionShortDisplayName(for id: UUID) -> String? {
        pendingTorrentAdditions.first(where: { $0.id == id })?.shortDisplayName
    }

    /// Built from scratch, bypassing the card cache.
    func rowState(for id: UUID) -> TorrentRowState? {
        if let record = torrentRecord(for: id) {
            return Self.makeRowState(
                rowInputSources(pendingIDs: Set(pendingTorrentAdditions.map(\.id))).inputs(for: record)
            )
        }
        guard let addition = pendingTorrentAdditions.first(where: { $0.id == id }) else {
            return nil
        }

        return makeRowState(for: addition)
    }

    private func makeRowState(for addition: PendingTorrentAddition) -> TorrentRowState {
        TorrentRowState(
            id: addition.id,
            title: L10n.format(
                "torrent.card.adding_title",
                localeOverride: preferences.localeOverride,
                defaultValue: "Загрузка «%@» в процессе добавления…",
                addition.shortDisplayName
            ),
            originalTitle: addition.draft.originalName,
            hasAlias: addition.draft.alias.isEmpty == false,
            status: .downloading,
            statusTitle: L10n.string(
                "torrent.status.adding",
                localeOverride: preferences.localeOverride,
                defaultValue: "Добавляется…"
            ),
            progress: 0,
            hasActiveTransfer: false,
            compactTransferMetricSet: nil,
            expandedMetricGroups: nil,
            metricsMode: preferences.metricsMode,
            colorizesDownloadSpeed: preferences.colorizesDownloadSpeed,
            enablesCardLayoutDiagnostics: ShatlCardLayoutDiagnosticsLog.isEnabled,
            enablesMetricAnimationDiagnostics: ShatlMetricAnimationDiagnosticsLog.isEnabled,
            errorState: nil,
            isSelected: selectedTorrentID == addition.id,
            isExpanded: false,
            canToggleRunningState: false,
            canRemoveFromList: !isRestoringSession,
            canRemoveWithFiles: false,
            navigationAvailabilityKey: "pending-addition|\(addition.id.uuidString)",
            localeOverride: preferences.localeOverride,
            isPendingAddition: true,
            canExpand: false
        )
    }

    private static func shortenedPendingDisplayName(for draft: AddTorrentDraft) -> String {
        let alias = draft.alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceName = alias.isEmpty ? draft.originalName : alias
        guard sourceName.count > 30 else { return sourceName }

        return String(sourceName.prefix(29)) + "…"
    }

    /// Everything a record card shows besides its record. `makeRowState`
    /// sees nothing else, so the cache below cannot miss an input.
    private struct TorrentRowInputs: Equatable {
        struct Shared: Equatable {
            var metricsMode: MetricsPresentationMode
            var colorizesDownloadSpeed: Bool
            var localeOverride: AppLocaleOverride
            var enablesCardLayoutDiagnostics: Bool
            var enablesMetricAnimationDiagnostics: Bool
            var isRestoringSession: Bool
            var simplification: CardSimplificationLevel
        }

        var record: TorrentRecord
        var speedLevels: TransferSpeedLevels?
        var isSelected: Bool
        var isExpanded: Bool
        var isTransitioning: Bool
        var isPendingAddition: Bool
        var shared: Shared
    }

    private var sharedRowInputs: TorrentRowInputs.Shared {
        TorrentRowInputs.Shared(
            metricsMode: preferences.metricsMode,
            colorizesDownloadSpeed: preferences.colorizesDownloadSpeed,
            localeOverride: preferences.localeOverride,
            enablesCardLayoutDiagnostics: ShatlCardLayoutDiagnosticsLog.isEnabled,
            enablesMetricAnimationDiagnostics: ShatlMetricAnimationDiagnosticsLog.isEnabled,
            isRestoringSession: isRestoringSession,
            simplification: cardSimplification
        )
    }

    /// The store-wide values every card reads, taken once per refresh:
    /// reading a `@Published` property per card would cost more than the card.
    private struct RowInputSources {
        var selectedTorrentID: UUID?
        var expandedTorrentID: UUID?
        var transitioningTorrentIDs: Set<UUID>
        var pendingIDs: Set<UUID>
        var speedLevels: [UUID: TransferSpeedLevels]
        var shared: TorrentRowInputs.Shared

        func inputs(for record: TorrentRecord) -> TorrentRowInputs {
            TorrentRowInputs(
                record: record,
                speedLevels: speedLevels[record.id],
                isSelected: selectedTorrentID == record.id,
                isExpanded: expandedTorrentID == record.id,
                isTransitioning: transitioningTorrentIDs.contains(record.id),
                isPendingAddition: pendingIDs.contains(record.id),
                shared: shared
            )
        }
    }

    private func rowInputSources(pendingIDs: Set<UUID>) -> RowInputSources {
        RowInputSources(
            selectedTorrentID: selectedTorrentID,
            expandedTorrentID: expandedTorrentID,
            transitioningTorrentIDs: transitioningTorrentIDs,
            pendingIDs: pendingIDs,
            speedLevels: transferSpeedLevels,
            shared: sharedRowInputs
        )
    }

    private static func makeRowState(_ inputs: TorrentRowInputs) -> TorrentRowState {
        let record = inputs.record
        let shared = inputs.shared
        let errorState = TorrentRowErrorState(
            record.errorState,
            saveFolderPath: record.canonicalSavePath,
            localeOverride: shared.localeOverride
        )
        let compactTransferMetricSet = errorState == nil
            ? TorrentPresentation.compactTransferMetricSet(
                for: record,
                mode: shared.metricsMode,
                localeOverride: shared.localeOverride,
                speedLevels: inputs.speedLevels
            )
            : nil
        let expandedMetricGroups = errorState == nil && inputs.isExpanded
            ? TorrentPresentation.expandedMetricGroups(
                for: record,
                mode: shared.metricsMode,
                localeOverride: shared.localeOverride,
                speedLevels: inputs.speedLevels
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
            statusTitle: record.status.localizedTitle(localeOverride: shared.localeOverride),
            progress: presentedProgress(for: record),
            hasActiveTransfer: hasActiveTransfer(for: record),
            compactTransferMetricSet: compactTransferMetricSet,
            expandedMetricGroups: expandedMetricGroups,
            metricsMode: shared.metricsMode,
            colorizesDownloadSpeed: shared.colorizesDownloadSpeed,
            enablesCardLayoutDiagnostics: shared.enablesCardLayoutDiagnostics,
            enablesMetricAnimationDiagnostics: shared.enablesMetricAnimationDiagnostics,
            errorState: errorState,
            isSelected: inputs.isSelected,
            isExpanded: inputs.isExpanded,
            canToggleRunningState: canToggleRunningState(
                record,
                isRestoringSession: shared.isRestoringSession,
                isTransitioning: inputs.isTransitioning
            ),
            canRemoveFromList: canRemoveFromList(
                isPendingAddition: inputs.isPendingAddition,
                isRestoringSession: shared.isRestoringSession,
                isTransitioning: inputs.isTransitioning
            ),
            canRemoveWithFiles: canRemoveWithFiles(
                record,
                isRestoringSession: shared.isRestoringSession,
                isTransitioning: inputs.isTransitioning
            ),
            navigationAvailabilityKey: navigationAvailabilityKey,
            localeOverride: shared.localeOverride,
            simplification: shared.simplification
        )
    }

    private func refreshTorrentPresentations() {
        updateCardSimplification()
        let pendingIDs = Set(pendingTorrentAdditions.map(\.id))
        let currentIDs = Set(torrents.map(\.id)).union(pendingIDs)
        if torrentRowPresentationModelsByID.count != currentIDs.count
            || torrentRowPresentationModelsByID.keys.contains(where: { !currentIDs.contains($0) }) {
            torrentRowPresentationModelsByID = torrentRowPresentationModelsByID.filter {
                currentIDs.contains($0.key)
            }
            torrentRowInputsByID = torrentRowInputsByID.filter { currentIDs.contains($0.key) }
        }

        for addition in pendingTorrentAdditions {
            let state = makeRowState(for: addition)
            if let model = torrentRowPresentationModelsByID[addition.id] {
                model.update(state: state)
            } else {
                torrentRowPresentationModelsByID[addition.id] = TorrentRowPresentationModel(state: state)
            }
        }

        let sources = rowInputSources(pendingIDs: pendingIDs)
        for record in torrents {
            let inputs = sources.inputs(for: record)
            // A record still listed as a pending addition shares its model with
            // the pending card built above, so it is always rebuilt over it.
            if !inputs.isPendingAddition,
               torrentRowInputsByID[record.id] == inputs,
               torrentRowPresentationModelsByID[record.id] != nil {
                continue
            }

            #if DEBUG
            recordRowStateBuildCountForTesting += 1
            #endif
            let state = Self.makeRowState(inputs)
            if let model = torrentRowPresentationModelsByID[record.id] {
                model.update(state: state)
            } else {
                torrentRowPresentationModelsByID[record.id] = TorrentRowPresentationModel(state: state)
            }
            torrentRowInputsByID[record.id] = inputs
        }

        let chips = bottomTransferChips
        torrentTransferSummary.update(chips: chips)
    }

    /// Before the rows: the level enters every card through its inputs.
    private func updateCardSimplification() {
        automaticCardSimplification = CardSimplificationLevel.level(
            activeDownloads: CardSimplificationLevel.activeDownloadCount(in: torrents),
            previous: automaticCardSimplification
        )
        if cardSimplification != automaticCardSimplification {
            cardSimplification = automaticCardSimplification
        }
    }

    private static func presentedProgress(for record: TorrentRecord) -> Double {
        let clampedProgress = min(max(record.progress, 0), 1)
        if record.status == .completed || record.status == .seeding {
            return 1
        }

        let percent = Int((clampedProgress * 100).rounded(.down))
        return Double(percent) / 100
    }

    private static func hasActiveTransfer(for record: TorrentRecord) -> Bool {
        switch record.status {
        case .downloading:
            record.metrics.downloadSpeedBytesPerSecond > 0
        case .seeding:
            record.progress >= 1 && record.metrics.uploadSpeedBytesPerSecond > 1
        case .stopped, .completed, .error, .checking:
            false
        }
    }

    func setPerformanceProfile(_ profile: AppPerformanceProfile) {
        guard preferences.performanceProfile != profile else { return }

        preferences.performanceProfile = profile
        schedulePerformanceSettingsApply()
    }

    func setOpensRouterPortAutomatically(_ isEnabled: Bool) {
        guard preferences.opensRouterPortAutomatically != isEnabled else { return }

        preferences.opensRouterPortAutomatically = isEnabled
        // The dot answers the switch at once: grey while the router is asked.
        portForwardingIndicator = PortForwardingIndicator(isEnabled: isEnabled, status: nil)
        schedulePerformanceSettingsApply()
    }

    /// Asks the engine what the router answered. Settings calls it while the
    /// Downloads tab is shown; the last answer stays, so the dot is in place
    /// when the tab opens again.
    func refreshPortForwardingIndicator() async {
        let isEnabled = preferences.opensRouterPortAutomatically
        let status = isEnabled ? await engine.portMappingStatus() : nil
        // The switch may have moved while the engine answered.
        guard isEnabled == preferences.opensRouterPortAutomatically else { return }

        let indicator = PortForwardingIndicator(isEnabled: isEnabled, status: status)
        if indicator != portForwardingIndicator {
            portForwardingIndicator = indicator
        }
    }

    #if DEBUG
    /// Debug Settings shows the engine's open-file limit and how many files are open.
    func engineResourceBudget() async -> EngineResourceBudget? {
        await engine.resourceBudget()
    }

    /// Debug Settings shows whether the router opened a port.
    func enginePortMappingStatus() async -> EnginePortMappingStatus? {
        await engine.portMappingStatus()
    }
    #endif

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
        onboardingPresentation = .hidden
    }

    func presentInitialOnboardingIfNeeded() {
        guard hasLoadedInitialSession,
              sessionLoadIssue == nil,
              !preferences.hasCompletedOnboarding else {
            return
        }
        onboardingPresentation = .firstLaunch
    }

    func presentDebugOnboarding() {
        onboardingPresentation = .debug
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
                    self.preferences.lastUsageStatisticsSentAt = self.usageTelemetryCoordinator?.currentDate ?? Date()
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

        let lastSentWeek = usageTelemetryCoordinator?.weekIdentifier(for: lastSentAt)
            ?? UsageTelemetryWeek.identifier(for: lastSentAt)
        return lastSentWeek != payload.week
    }

    /// Shatl often keeps running for weeks, so a new week is reported even
    /// without a launch. The check runs apart from the 1 Hz loop, and its
    /// continuous-clock sleep fires right away when the Mac wakes after the
    /// deadline.
    private func startUsageTelemetryWeekMonitor() {
        guard usageTelemetryCoordinator != nil, usageTelemetrySender != nil else { return }

        let interval = usageTelemetryWeekCheckInterval
        usageTelemetryWeekMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval, tolerance: interval / 6)
                guard !Task.isCancelled, let self else { return }
                self.sendUsageTelemetryForNewWeekIfNeeded()
            }
        }
    }

    private func sendUsageTelemetryForNewWeekIfNeeded() {
        guard preferences.canSendAnonymousUsageStatistics,
              let usageTelemetryCoordinator else { return }

        // Already reported this week: nothing to read or send.
        if let lastSentAt = preferences.lastUsageStatisticsSentAt,
           usageTelemetryCoordinator.weekIdentifier(for: lastSentAt)
            == usageTelemetryCoordinator.weekIdentifier(for: usageTelemetryCoordinator.currentDate) {
            return
        }

        do {
            guard let payload = try usageTelemetryCoordinator.currentWeekPayloadIfEnabled(
                isEnabled: true,
                localeIdentifier: usageTelemetryLocaleIdentifier,
                appVersion: appVersion
            ) else {
                return
            }

            sendUsageTelemetryIfNeeded(payload)
        } catch {
            Self.logger.error("Failed to prepare weekly usage telemetry: \(error.localizedDescription)")
        }
    }

    func prepareForTermination() async -> Bool {
        guard !isPreparingForTermination else { return false }
        isPreparingForTermination = true

        let shouldResumeRuntimeLoop = runtimeTask != nil
        runtimeTask?.cancel()
        runtimeTask = nil
        // The final commit below writes the latest progress itself.
        progressSaveTask?.cancel()
        progressSaveTask = nil

        if let initialSessionLoadTask {
            let result = await initialSessionLoadTask.value
            _ = await resolveInitialSessionLoad(result)
        }

        let additionTasks = Array(pendingTorrentAdditionTasks.values)
        for task in additionTasks {
            await task.value
        }

        guard !didBootstrap || (didCompleteRuntimeBootstrap && sessionLoadIssue == nil) else {
            return true
        }

        await refreshActiveSnapshots()
        let candidateTorrents = await checkpointedTorrentsForTermination()
        let saveOutcome = await commitCriticalState(candidateTorrents)
        guard saveOutcome == .saved else {
            // The app delegate owns the follow-up: it asks whether to retry,
            // stay open, or quit with the last committed session on disk.
            isPreparingForTermination = false
            if shouldResumeRuntimeLoop {
                startRuntimeLoop()
            }
            return false
        }

        torrents = candidateTorrents
        draftPreparationTask?.cancel()
        performanceApplyTask?.cancel()
        return true
    }

    /// Stops libtorrent once the quit is decided. The engine caps its own wait;
    /// this cap also covers a command still running on the engine, so a
    /// logout or restart is never held up for long.
    func finishTermination() async {
        await finishTermination(timeout: .seconds(3))
    }

    func finishTermination(timeout: Duration) async {
        runtimeTask?.cancel()
        runtimeTask = nil
        let engine = engine
        let gate = ResumeOnce()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gate.continuation = continuation
            Task {
                await engine.shutdown()
                gate.resume()
            }
            Task {
                try? await Task.sleep(for: timeout)
                gate.resume()
            }
        }
    }

    /// Lets whichever finishes first, the shutdown or the timeout, end the wait.
    private final class ResumeOnce {
        var continuation: CheckedContinuation<Void, Never>?

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }

    /// The toolbar must not offer removal actions for cards with persistent issues.
    var canAddTorrent: Bool {
        guard hasLoadedInitialSession,
              sessionLoadIssue == nil,
              !onboardingPresentation.isPresented,
              !isPreparingForTermination else {
            return false
        }
        return !didBootstrap || isEngineReady
    }

    var isToolbarRemoveEnabled: Bool {
        guard !onboardingPresentation.isPresented else { return false }
        if let selectedTorrentID, isPendingAddition(id: selectedTorrentID) {
            return !isRestoringSession
        }
        guard let selectedTorrent else { return false }
        return selectedTorrent.persistentIssue == nil
            && !isRestoringSession
            && !transitioningTorrentIDs.contains(selectedTorrent.id)
    }

    var isToolbarStartStopEnabled: Bool {
        guard !onboardingPresentation.isPresented, let selectedTorrent else { return false }
        return selectedTorrent.errorState == nil
            && !isRestoringSession
            && !transitioningTorrentIDs.contains(selectedTorrent.id)
    }

    func canToggleRunningState(for id: UUID) -> Bool {
        guard !onboardingPresentation.isPresented, let record = torrentRecord(for: id) else { return false }
        return Self.canToggleRunningState(
            record,
            isRestoringSession: isRestoringSession,
            isTransitioning: transitioningTorrentIDs.contains(id)
        )
    }

    func canRemoveFromList(for id: UUID) -> Bool {
        guard !onboardingPresentation.isPresented else { return false }
        let isPendingAddition = isPendingAddition(id: id)
        guard isPendingAddition || torrentIndex(for: id) != nil else { return false }
        return Self.canRemoveFromList(
            isPendingAddition: isPendingAddition,
            isRestoringSession: isRestoringSession,
            isTransitioning: transitioningTorrentIDs.contains(id)
        )
    }

    func canRemoveWithFiles(for id: UUID) -> Bool {
        guard !onboardingPresentation.isPresented, let record = torrentRecord(for: id) else { return false }
        return Self.canRemoveWithFiles(
            record,
            isRestoringSession: isRestoringSession,
            isTransitioning: transitioningTorrentIDs.contains(id)
        )
    }

    private static func canToggleRunningState(
        _ record: TorrentRecord,
        isRestoringSession: Bool,
        isTransitioning: Bool
    ) -> Bool {
        record.errorState == nil && !isRestoringSession && !isTransitioning
    }

    private static func canRemoveFromList(
        isPendingAddition: Bool,
        isRestoringSession: Bool,
        isTransitioning: Bool
    ) -> Bool {
        isPendingAddition ? !isRestoringSession : !isRestoringSession && !isTransitioning
    }

    private static func canRemoveWithFiles(
        _ record: TorrentRecord,
        isRestoringSession: Bool,
        isTransitioning: Bool
    ) -> Bool {
        record.errorState == nil && !isRestoringSession && !isTransitioning
    }

    func presentAddTorrentEntry() {
        guard canAddTorrent else { return }
        if isAddTorrentReviewWindowActive {
            requestAddTorrentReviewWindowActivation()
            return
        }
        draftPreparationTask?.cancel()
        currentAddTorrentDraft = nil
        presentedModal = .addTorrentEntry
    }

    func requestAddTorrentReviewWindowActivation() {
        guard isAddTorrentReviewWindowActive else { return }
        addTorrentReviewWindowRequestID &+= 1
    }

    func addTorrentReviewWindowDidClose() {
        isAddTorrentReviewWindowActive = false
        if presentedModal == .addTorrentReview {
            dismissModal()
        }

        if !deferredAddTorrentFailures.isEmpty {
            let deferredAddTorrentFailure = deferredAddTorrentFailures.removeFirst()
            presentInvalidDraft(
                for: deferredAddTorrentFailure.draft.source,
                errorState: deferredAddTorrentFailure.errorState,
                suggestedSavePath: deferredAddTorrentFailure.draft.suggestedSavePath,
                stopAfterDownload: deferredAddTorrentFailure.draft.stopAfterDownload,
                alias: deferredAddTorrentFailure.draft.alias,
                savePathBookmarkData: deferredAddTorrentFailure.draft.savePathBookmarkData
            )
        }
    }

    func dismissModal() {
        draftPreparationTask?.cancel()
        presentedModal = nil
        currentAddTorrentDraft = nil
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

    func cancelPendingAddition(id: UUID) {
        guard pendingTorrentAdditions.contains(where: { $0.id == id }) else { return }

        cancelledPendingTorrentAdditionIDs.insert(id)
        pendingTorrentAdditionTasks[id]?.cancel()
        removePendingTorrentAdditionFromPresentation(id: id)
    }

    func collapseExpandedTorrent() {
        expandedTorrentID = nil
    }

    /// Closes this card only: another one may have opened meanwhile.
    func collapseExpanded(for id: UUID) {
        guard expandedTorrentID == id else { return }
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
            guard let validationRecord = self.torrents.first(where: { $0.id == id }) else { return }

            self.traceTransition(torrentID: id, phase: "validation.begin", extra: [:])
            let validation = await self.diskIssueDetector.validateAfterUserAction(for: validationRecord)
            self.traceTransition(
                torrentID: id,
                phase: "validation.result",
                level: validation.issue == nil ? .debug : .notice,
                extra: self.validationFields(for: validation)
            )

            guard let currentIndex = self.torrents.firstIndex(where: { $0.id == id }) else { return }
            var candidateRecord = self.torrents[currentIndex]
            if let footprint = validation.footprint {
                candidateRecord.materializedSelectionFootprint = footprint
            }

            if let issue = validation.issue {
                candidateRecord.persistentIssue = self.normalizedPersistentIssue(
                    issue,
                    for: candidateRecord
                )
                candidateRecord.runtimeErrorState = nil
                candidateRecord.status = .error
            } else {
                // When a completed torrent merely stops seeding, keep the user-facing
                // state as completed instead of changing it to stopped.
                candidateRecord.status = candidateRecord.progress >= 1.0
                    || candidateRecord.status == .seeding
                    || candidateRecord.status == .completed
                    ? .completed
                    : .stopped
                candidateRecord.runtimeErrorState = nil
                candidateRecord.metrics.downloadSpeedBytesPerSecond = 0
                candidateRecord.metrics.uploadSpeedBytesPerSecond = 0
                candidateRecord.metrics.etaSeconds = nil
                candidateRecord.metrics.seeds = nil
                candidateRecord.metrics.peers = nil
            }

            var candidateTorrents = self.torrents
            candidateTorrents[currentIndex] = candidateRecord
            self.traceTransition(
                torrentID: id,
                phase: "session.commit.begin",
                level: .notice,
                flush: true
            )
            let sessionSaveOutcome = await self.commitCriticalState(candidateTorrents)
            guard sessionSaveOutcome == .saved else {
                Self.logger.error(
                    "Stop blocked because the session could not be committed for torrent id=\(id.uuidString) outcome=\(String(describing: sessionSaveOutcome))"
                )
                self.traceTransition(
                    torrentID: id,
                    phase: "session.commit.failed",
                    level: .error,
                    flush: true,
                    extra: ["outcome": String(describing: sessionSaveOutcome)]
                )
                self.reportSessionPersistenceFailure(.stop)
                transitionOutcome = "blocked.session-commit"
                return
            }
            self.traceTransition(
                torrentID: id,
                phase: "session.commit.end",
                level: .notice,
                flush: true
            )

            if validation.issue != nil {
                self.applyValidationResult(validation, to: id)
                Self.logger.notice("Stop converted into persistent issue for torrent id=\(id.uuidString) issue=\(validation.issue?.kind.rawValue ?? "unknown")")
                self.detachedTorrentIDs.insert(id)
                transitionOutcome = "converted.persistent-issue"

                do {
                    let engineCallStartedAt = DispatchTime.now().uptimeNanoseconds
                    self.traceTransition(torrentID: id, phase: "engine.remove.begin", level: .notice, flush: true)
                    try await self.engine.removeTorrent(id: id)
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
                self.torrents[index] = candidateRecord
            }

            self.traceTransition(
                torrentID: id,
                phase: "state.preengine.applied",
                level: .debug,
                extra: self.transitionStateSnapshot(for: id)
            )
            do {
                let engineCallStartedAt = DispatchTime.now().uptimeNanoseconds
                self.traceTransition(torrentID: id, phase: "engine.remove.begin", level: .notice, flush: true)
                try await self.engine.removeTorrent(id: id)
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

    func removeSelectedTorrent(policy: TorrentRemovalPolicy = .removeFromListOnly) async {
        guard let selectedTorrentID, isToolbarRemoveEnabled else { return }
        await removeTorrent(id: selectedTorrentID, policy: policy)
    }

    func primaryLocation(for id: UUID) async -> ManagedTorrentLocation? {
        guard let record = torrentRecord(for: id) else { return nil }
        return await torrentPayloadLocator.primaryLocation(for: record)
    }

    func removeTorrent(id: UUID, policy: TorrentRemovalPolicy = .removeFromListOnly) async {
        guard let record = torrents.first(where: { $0.id == id }),
              !transitioningTorrentIDs.contains(id) else {
            return
        }
        let resolvedPolicy: TorrentRemovalPolicy = record.errorState == nil
            ? policy
            : .removeFromListOnly

        transitioningTorrentIDs.insert(id)
        defer { transitioningTorrentIDs.remove(id) }

        let sessionSaveOutcome = await sessionStore.commitRemoval(torrentID: id)
        recordSessionSaveOutcome(sessionSaveOutcome)
        guard sessionSaveOutcome == .saved else {
            Self.logger.error(
                "Remove blocked because the session could not be committed for torrent id=\(id.uuidString) outcome=\(String(describing: sessionSaveOutcome))"
            )
            reportSessionPersistenceFailure(
                resolvedPolicy == .removeFromListAndDeleteFiles ? .removeWithFiles : .removeFromList
            )
            return
        }

        detachedTorrentIDs.remove(id)
        clearUnreadUserEvents(for: id)

        // Remove the torrent from durable state first so it cannot return after relaunch.
        torrents.removeAll { $0.id == id }
        lastPersistedProgressBucketByID[id] = nil
        if selectedTorrentID == id {
            selectedTorrentID = nil
        }
        if expandedTorrentID == id {
            expandedTorrentID = nil
        }
        refreshSelectedTorrentNavigationAvailability()

        var canDeletePayload = false
        do {
            try await engine.removeTorrent(id: id)
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
                    "Payload deletion completed for torrent id=\(id.uuidString) source=\(deletionResult.payloadSource.rawValue) filesDeleted=\(deletionResult.deletedManagedFileCount) missingFiles=\(deletionResult.missingManagedFileCount) failedFiles=\(deletionResult.failedManagedFileCount) unsafeFiles=\(deletionResult.unsafeManagedFileCount) directoriesDeleted=\(deletionResult.deletedDirectoryCount) sidecarsDeleted=\(deletionResult.deletedSystemSidecarCount) failedDirectoryCleanup=\(deletionResult.failedDirectoryCleanupCount) unsafeCleanupItems=\(deletionResult.unsafeCleanupItemCount)"
                )
                let failedItemCount = deletionResult.failedManagedFileCount
                    + deletionResult.unsafeManagedFileCount
                if failedItemCount > 0 {
                    payloadDeletionAlert = PayloadDeletionAlert(
                        title: L10n.string("payload_deletion.not_all_files_deleted.title", localeOverride: preferences.localeOverride, defaultValue: "Не все файлы удалены"),
                        message: L10n.format(
                            L10n.pluralKey(
                                "payload_deletion.partial_failure.message",
                                count: failedItemCount,
                                localeOverride: preferences.localeOverride
                            ),
                            localeOverride: preferences.localeOverride,
                            defaultValue: "Shatl удалил торрент из списка, но не смог удалить часть файлов с диска: %lld.",
                            failedItemCount
                        )
                    )
                } else if deletionResult.failedDirectoryCleanupCount > 0
                            || deletionResult.unsafeCleanupItemCount > 0 {
                    payloadDeletionAlert = PayloadDeletionAlert(
                        title: L10n.string("payload_deletion.not_all_files_deleted.title", localeOverride: preferences.localeOverride, defaultValue: "Не все файлы удалены"),
                        message: L10n.string(
                            "payload_deletion.cleanup_failure.message",
                            localeOverride: preferences.localeOverride,
                            defaultValue: "Файлы торрента удалены, но Shatl оставил некоторые папки или служебные файлы, потому что их нельзя было безопасно очистить."
                        )
                    )
                }
            case .unsafe(let failure):
                Self.logger.notice(
                    "Payload deletion refused for torrent id=\(id.uuidString) unsafeIssueCount=\(failure.issues.count)"
                )
                payloadDeletionAlert = PayloadDeletionAlert(
                    title: L10n.string("payload_deletion.files_not_deleted.title", localeOverride: preferences.localeOverride, defaultValue: "Файлы не удалены"),
                    message: L10n.string(
                        "payload_deletion.safety_refused.message",
                        localeOverride: preferences.localeOverride,
                        defaultValue: "Shatl удалил торрент из списка, но оставил файлы: путь или тип объекта больше не соответствует данным торрента."
                    )
                )
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

        await diskIssueDetector.forgetTrackedFiles(for: id)
        await sessionStore.finalizeRemovalArtifacts(torrentID: id)
    }

    func redownloadTorrent(id: UUID) {
        guard let record = torrents.first(where: { $0.id == id }),
              record.persistentIssue?.kind == .missingContent,
              !transitioningTorrentIDs.contains(id) else { return }

        transitioningTorrentIDs.insert(id)

        Task { [weak self] in
            guard let self else { return }
            defer { self.transitioningTorrentIDs.remove(id) }

            guard let saveURL = await self.bookmarkStore.resolveURL(
                for: record.id,
                fallbackPath: record.canonicalSavePath
            ) else {
                let issue = TorrentPersistentIssue(
                    kind: .savePathUnavailable,
                    detectedAt: Date(),
                    statusBeforeIssue: record.persistentIssue?.statusBeforeIssue ?? record.status,
                    debugReason: "Не удалось разрешить путь для повторной загрузки."
                )
                guard await self.commitPersistentIssue(issue, to: record.id) else {
                    self.reportSessionPersistenceFailure(.redownload)
                    return
                }

                self.applyPersistentIssue(issue, to: record.id)
                return
            }

            await self.redownloadTorrent(record: record, saveURL: saveURL, bookmarkData: nil)
        }
    }

    func redownloadTorrent(id: UUID, toSaveLocation saveURL: URL, bookmarkData: Data?) {
        guard let record = torrents.first(where: { $0.id == id }),
              record.persistentIssue?.kind == .savePathUnavailable,
              !transitioningTorrentIDs.contains(id) else { return }

        transitioningTorrentIDs.insert(id)

        Task { [weak self] in
            guard let self else { return }
            defer { self.transitioningTorrentIDs.remove(id) }

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
        // An external URL cannot explain why no visible add flow appears while
        // first-run onboarding owns the window, so deliberately discard it.
        guard !onboardingPresentation.isPresented else { return }

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
            savePathBookmarkData: draft.savePathBookmarkData,
            replacesCurrentReview: true
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
            var candidateRecord = record
            candidateRecord.attemptID = restoreEntry.attemptID
            candidateRecord.canonicalSavePath = normalizedSavePath
            candidateRecord.status = .downloading
            candidateRecord.progress = 0
            candidateRecord.lastKnownProgress = 0
            candidateRecord.materializedSelectionFootprint = baselineFootprint
            candidateRecord.persistentIssue = nil
            candidateRecord.runtimeErrorState = nil

            let saveOutcome = await sessionStore.commitAttemptTransition(
                candidateRecord,
                replacingAttemptID: record.attemptID
            )
            recordSessionSaveOutcome(saveOutcome)
            guard saveOutcome == .saved else {
                detachedTorrentIDs.insert(record.id)
                do {
                    try await engine.removeTorrent(id: record.id)
                } catch {
                    let engineError = TorrentEngineError.normalized(from: error)
                    if engineError.kind != .torrentNotFound {
                        Self.logger.error(
                            "Redownload rollback failed for torrent id=\(record.id.uuidString) kind=\(engineError.kind.rawValue) reason=\(engineError.debugReason ?? "-")"
                        )
                    }
                }
                reportSessionPersistenceFailure(.redownload)
                return
            }

            detachedTorrentIDs.remove(record.id)
            if let index = torrents.firstIndex(where: { $0.id == record.id }) {
                torrents[index] = candidateRecord
            }
            if let bookmarkData {
                await bookmarkStore.saveBookmarkData(for: record.id, data: bookmarkData)
            } else if normalizedSavePath != record.canonicalSavePath {
                await bookmarkStore.saveBookmark(for: record.id, url: saveURL)
            }

            applySnapshots(snapshots)
        } catch {
            applyEngineError(error, to: record.id)
        }
    }

    private func commitPersistentIssue(
        _ issue: TorrentPersistentIssue,
        to torrentID: UUID
    ) async -> Bool {
        guard let index = torrents.firstIndex(where: { $0.id == torrentID }) else {
            return false
        }

        var candidateRecord = torrents[index]
        candidateRecord.persistentIssue = normalizedPersistentIssue(issue, for: candidateRecord)
        candidateRecord.runtimeErrorState = nil
        candidateRecord.status = .error
        var candidateTorrents = torrents
        candidateTorrents[index] = candidateRecord
        return await commitCriticalState(candidateTorrents) == .saved
    }

    func confirmDraft() {
        guard canAddTorrent else { return }
        guard let draft = currentAddTorrentDraft else { return }
        guard draft.canConfirmDownload else { return }

        if isDuplicateDraft(draft) {
            presentDuplicateDraft(for: draft)
            return
        }

        let addition = PendingTorrentAddition(
            id: UUID(),
            attemptID: UUID(),
            draft: draft,
            shortDisplayName: Self.shortenedPendingDisplayName(for: draft),
            presentationStartedAt: ContinuousClock().now
        )
        insertPendingTorrentAddition(addition)
        dismissModal()

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performPendingTorrentAddition(addition)
            // The addition has owned the prepared metadata since Confirm.
            await self.engine.releasePreparedDraft(id: addition.draft.id)
        }
        pendingTorrentAdditionTasks[addition.id] = task
    }

    /// The Review draft owns its prepared metadata until it is replaced or
    /// closed. A confirmed draft hands it over to its pending addition instead.
    private func releasePreparedDraftUnlessAdding(_ draftID: UUID) {
        guard !pendingTorrentAdditions.contains(where: { $0.draft.id == draftID }) else { return }
        releasePreparedDraft(draftID)
    }

    private func releasePreparedDraft(_ draftID: UUID) {
        Task { [engine] in
            await engine.releasePreparedDraft(id: draftID)
        }
    }

    private func performPendingTorrentAddition(_ addition: PendingTorrentAddition) async {
        guard let addLease = await sessionStore.beginAdd(torrentID: addition.id) else {
            handlePendingAdditionFailure(
                TorrentEngineError(
                    kind: .engineFailure,
                    debugReason: "Не удалось зарезервировать новую загрузку в сессии."
                ),
                addition: addition
            )
            finishPendingTorrentAddition(id: addition.id)
            return
        }

        guard !isPendingAdditionCancelled(id: addition.id) else {
            await sessionStore.abortAdd(addLease)
            finishPendingTorrentAddition(id: addition.id)
            return
        }

        var addedRecord: TorrentRecord?
        do {
            let record = try await engine.addTorrent(
                using: addition.draft,
                recordID: addition.id,
                attemptID: addition.attemptID
            )
            addedRecord = record

            guard !isPendingAdditionCancelled(id: addition.id) else {
                await rollbackCancelledPendingAddition(record: record, lease: addLease, isCommitted: false)
                finishPendingTorrentAddition(id: addition.id)
                return
            }

            try await persistRestoreArtifacts(for: record, draft: addition.draft)

            guard !isPendingAdditionCancelled(id: addition.id) else {
                await rollbackCancelledPendingAddition(record: record, lease: addLease, isCommitted: false)
                finishPendingTorrentAddition(id: addition.id)
                return
            }

            let saveOutcome = await sessionStore.commitAdd(record, lease: addLease)
            recordSessionSaveOutcome(saveOutcome)
            guard saveOutcome == .saved else {
                let persistenceError = TorrentEngineError(
                    kind: .engineFailure,
                    debugReason: "Не удалось сохранить новую загрузку в сессии."
                )
                throw persistenceError
            }

            await waitForMinimumPendingAdditionPresentation(addition)

            guard !isPendingAdditionCancelled(id: addition.id) else {
                await rollbackCancelledPendingAddition(record: record, lease: addLease, isCommitted: true)
                finishPendingTorrentAddition(id: addition.id)
                return
            }

            completePendingTorrentAddition(with: record)
            finishPendingTorrentAddition(id: addition.id)
            await refreshActiveSnapshots()
        } catch {
            if let addedRecord {
                try? await engine.removeTorrent(id: addedRecord.id)
            }
            await sessionStore.abortAdd(addLease)

            if !isPendingAdditionCancelled(id: addition.id) {
                handlePendingAdditionFailure(error, addition: addition)
            }
            finishPendingTorrentAddition(id: addition.id)
        }
    }

    private func waitForMinimumPendingAdditionPresentation(
        _ addition: PendingTorrentAddition
    ) async {
        let elapsed = addition.presentationStartedAt.duration(to: ContinuousClock().now)
        let remaining = Self.minimumPendingAdditionPresentationDuration - elapsed
        guard remaining > .zero else { return }

        try? await Task.sleep(for: remaining)
    }

    private func rollbackCancelledPendingAddition(
        record: TorrentRecord,
        lease: SessionAddLease,
        isCommitted: Bool
    ) async {
        if isCommitted {
            let removalOutcome = await sessionStore.commitRemoval(torrentID: record.id)
            recordSessionSaveOutcome(removalOutcome)
            guard removalOutcome == .saved else {
                Self.logger.error(
                    "Pending add cancellation could not be committed for torrent id=\(record.id.uuidString) outcome=\(String(describing: removalOutcome))"
                )
                completePendingTorrentAddition(with: record)
                return
            }
        } else {
            await sessionStore.abortAdd(lease)
        }

        try? await engine.removeTorrent(id: record.id)
        if isCommitted {
            await sessionStore.finalizeRemovalArtifacts(torrentID: record.id)
        }
    }

    private func insertPendingTorrentAddition(_ addition: PendingTorrentAddition) {
        objectWillChange.send()
        pendingTorrentAdditions.insert(addition, at: 0)
        refreshTorrentPresentations()
    }

    private func completePendingTorrentAddition(with record: TorrentRecord) {
        insertConfirmedTorrent(record)
        removePendingTorrentAdditionFromPresentation(id: record.id)
    }

    private func removePendingTorrentAdditionFromPresentation(id: UUID) {
        guard pendingTorrentAdditions.contains(where: { $0.id == id }) else { return }
        objectWillChange.send()
        pendingTorrentAdditions.removeAll { $0.id == id }
        if selectedTorrentID == id, !torrents.contains(where: { $0.id == id }) {
            selectedTorrentID = nil
            selectedTorrentNavigationAvailability = TorrentNavigationAvailability()
        }
        refreshTorrentPresentations()
    }

    private func finishPendingTorrentAddition(id: UUID) {
        pendingTorrentAdditionTasks[id] = nil
        cancelledPendingTorrentAdditionIDs.remove(id)
    }

    private func isPendingAdditionCancelled(id: UUID) -> Bool {
        Task.isCancelled || cancelledPendingTorrentAdditionIDs.contains(id)
    }

    private func handlePendingAdditionFailure(_ error: Error, addition: PendingTorrentAddition) {
        removePendingTorrentAdditionFromPresentation(id: addition.id)
        let errorState = isDuplicateError(error)
            ? ShatlErrorCatalog.duplicateDraftError(
                torrentName: addition.draft.originalName,
                localeOverride: preferences.localeOverride
            )
            : ShatlErrorCatalog.reviewError(
                for: error,
                source: addition.draft.source,
                localeOverride: preferences.localeOverride
            )
        if isAddTorrentReviewWindowActive {
            deferredAddTorrentFailures.append(
                DeferredAddTorrentFailure(
                    draft: addition.draft,
                    errorState: errorState
                )
            )
            return
        }

        presentInvalidDraft(
            for: addition.draft.source,
            errorState: errorState,
            suggestedSavePath: addition.draft.suggestedSavePath,
            stopAfterDownload: addition.draft.stopAfterDownload,
            alias: addition.draft.alias,
            savePathBookmarkData: addition.draft.savePathBookmarkData
        )
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
        draft.fileSelectionRevision &+= 1
        currentAddTorrentDraft = draft
    }

    /// Explicit selection supports cascading changes across folder branches
    /// in the add-flow file tree.
    func setDraftFileSelection(id: UUID, isSelected: Bool) {
        guard var draft = currentAddTorrentDraft,
              let index = draft.files.firstIndex(where: { $0.id == id }),
              draft.files[index].isSelected != isSelected else { return }

        draft.files[index].isSelected = isSelected
        draft.fileSelectionRevision &+= 1
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
            draft.fileSelectionRevision &+= 1
            currentAddTorrentDraft = draft
        }
    }

    func bootstrapRuntimeState() {
        guard !didBootstrap else { return }
        didBootstrap = true
        isRestoringSession = !torrents.isEmpty

        let expectsExistingSession = preferences.hasCompletedOnboarding
        let loadTask = Task { [sessionStore] in
            await sessionStore.load(expectsExistingSession: expectsExistingSession)
        }
        initialSessionLoadTask = loadTask

        bootstrapTask = Task { [weak self] in
            guard let self else { return }

            let loadResult = await loadTask.value
            guard await self.resolveInitialSessionLoad(loadResult), !self.isPreparingForTermination else {
                return
            }

            await self.completeRuntimeBootstrap(shouldRestoreSession: loadResult.snapshot != nil)
        }
    }

    private func completeRuntimeBootstrap(shouldRestoreSession: Bool) async {
        guard !isPreparingForTermination else { return }

        guard await sessionStore.reconcileOrphanedArtifacts() == .saved else {
            return
        }

        do {
            let performanceSettings = preferences.enginePerformanceSettings
            lastRequestedPerformanceSettings = performanceSettings
            try await engine.applyPerformanceSettings(performanceSettings)
            try await engine.boot()
            isEngineReady = true
        } catch {
            isRestoringSession = false
            return
        }

        let startupCheckCandidates = torrents.filter { $0.persistentIssue == nil }
        let startupEvaluation = await diskIssueDetector.startupCheck(for: startupCheckCandidates)
        _ = applyDiskIssueEvaluation(startupEvaluation)
        await persistCriticalState()

        if shouldRestoreSession, !torrents.isEmpty {
            let restoreCandidates = torrents.filter { $0.persistentIssue == nil }
            restoreProgressFloorByID = Dictionary(
                uniqueKeysWithValues: restoreCandidates
                    .filter { $0.status.isActive && max($0.progress, $0.lastKnownProgress) > 0 }
                    .map { ($0.id, max($0.progress, $0.lastKnownProgress)) }
            )
            let restoreResult = await sessionRestoreCoordinator.restore(records: restoreCandidates)
            applyRestoredPersistentIssues(restoreResult.persistentIssues)
            applySnapshots(restoreResult.snapshots)
            let didApplyFallbackStatuses = applyRestoreFallbackStatuses(
                restoreResult.fallbackStatusesByID,
                restoredSnapshotIDs: Set(restoreResult.snapshots.map(\.id))
            )
            if didApplyFallbackStatuses {
                await persistCriticalState()
            }
        }

        startRuntimeLoop()
        await reconcileSleepingTorrents()
        isRestoringSession = false
        allowsUserFacingNotifications = true
        didCompleteRuntimeBootstrap = true
        flushPendingIncomingURLs()
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

    func openWithEmptyDownloadList() {
        guard sessionLoadIssue != nil, !isResolvingSessionRecovery else { return }
        isResolvingSessionRecovery = true

        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.sessionStore.discardFailedSessionAndCreateEmpty()
            guard outcome == .saved else {
                self.isResolvingSessionRecovery = false
                return
            }

            self.torrents = []
            self.lastPersistedProgressBucketByID = [:]
            self.sessionLoadIssue = nil
            self.selectedTorrentID = nil
            self.expandedTorrentID = nil
            self.isResolvingSessionRecovery = false
            await self.completeRuntimeBootstrap(shouldRestoreSession: false)
        }
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

    private func checkpointedTorrentsForTermination() async -> [TorrentRecord] {
        var checkpointedTorrents = torrents
        let candidates = checkpointedTorrents.filter {
            $0.persistentIssue == nil
                && $0.status.isActive
                && !detachedTorrentIDs.contains($0.id)
        }
        guard !candidates.isEmpty else { return checkpointedTorrents }

        let progressByID = Dictionary(
            uniqueKeysWithValues: candidates.map {
                ($0.id, max($0.progress, $0.lastKnownProgress))
            }
        )
        let results = await engine.checkpointTorrents(ids: candidates.map(\.id))
        let checkpointedAt = Date()

        for result in results {
            guard case .saved = result.status,
                  let index = checkpointedTorrents.firstIndex(where: { $0.id == result.id }) else {
                continue
            }

            checkpointedTorrents[index].resumeCheckpointedAt = checkpointedAt
            checkpointedTorrents[index].resumeCheckpointProgress = progressByID[result.id]
            checkpointedTorrents[index].lastKnownProgress = max(
                checkpointedTorrents[index].lastKnownProgress,
                progressByID[result.id] ?? checkpointedTorrents[index].progress
            )
        }

        return checkpointedTorrents
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
        var updatedTorrents = torrents
        var shouldRefreshSelectedNavigationAvailability = false
        var durableChange = DurableSnapshotChange.none
        var speedLevels = transferSpeedLevels

        for index in updatedTorrents.indices {
            guard let snapshot = snapshotsByID[updatedTorrents[index].id] else { continue }
            traceTransition(
                torrentID: updatedTorrents[index].id,
                phase: detachedTorrentIDs.contains(updatedTorrents[index].id) ? "snapshot.ignored.detached" : "snapshot.received",
                level: detachedTorrentIDs.contains(updatedTorrents[index].id) ? .notice : .debug,
                extra: [
                    "snapshotStatus": snapshot.status.rawValue,
                    "snapshotProgress": progressString(snapshot.progress),
                    "snapshotHasError": boolString(snapshot.errorState != nil)
                ]
            )
            logDiskDiagnosticSync(
                detachedTorrentIDs.contains(updatedTorrents[index].id) ? "snapshot.ignored.detached" : "snapshot.received",
                record: updatedTorrents[index],
                extra: [
                    "snapshotStatus": snapshot.status.rawValue,
                    "snapshotProgress": progressString(snapshot.progress),
                    "snapshotHasError": boolString(snapshot.errorState != nil)
                ]
            )
            guard !detachedTorrentIDs.contains(updatedTorrents[index].id) else { continue }
            let previousStatus = updatedTorrents[index].status
            let previousProgress = updatedTorrents[index].progress
            let previousMetrics = updatedTorrents[index].metrics
            let wasFinishedForOpening = updatedTorrents[index].isFinishedForOpening
            let torrentID = updatedTorrents[index].id
            let protectsRestoreProgress = shouldProtectRestoreProgress(
                torrentID: torrentID,
                snapshot: snapshot
            )

            let resolvedProgress: Double
            if protectsRestoreProgress,
               let progressFloor = restoreProgressFloorByID[torrentID] {
                resolvedProgress = max(updatedTorrents[index].lastKnownProgress, progressFloor, snapshot.progress)
                requestRestoreRecheckIfNeeded(torrentID: torrentID, progressFloor: progressFloor)
            } else if snapshot.status == .checking,
                      updatedTorrents[index].lastKnownProgress > snapshot.progress {
                resolvedProgress = updatedTorrents[index].lastKnownProgress
            } else {
                resolvedProgress = snapshot.progress
            }
            let resolvedStatus = protectsRestoreProgress ? TorrentStatus.checking : snapshot.status

            updatedTorrents[index].status = resolvedStatus
            updatedTorrents[index].progress = resolvedProgress
            if snapshot.status != .checking, !protectsRestoreProgress {
                updatedTorrents[index].lastKnownProgress = snapshot.progress
            }
            updatedTorrents[index].metrics = snapshot.metrics
            // A torrent that stopped or finished starts its icons afresh.
            let previousSpeedLevels = resolvedStatus == previousStatus ? speedLevels[torrentID] : nil
            speedLevels[torrentID] = (previousSpeedLevels ?? TransferSpeedLevels()).following(snapshot.metrics)
            updatedTorrents[index].runtimeErrorState = snapshot.errorState
            clearRestoreProgressFloorIfSatisfied(torrentID: torrentID, snapshot: snapshot)
            notifyDownloadCompletionIfNeeded(
                torrent: updatedTorrents[index],
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
                appliedStatus: updatedTorrents[index].status,
                appliedProgress: updatedTorrents[index].progress,
                appliedMetrics: updatedTorrents[index].metrics
            )

            if updatedTorrents[index].persistentIssue == nil {
                if resolvedStatus == .checking || resolvedStatus.isActive {
                    detachedTorrentIDs.remove(updatedTorrents[index].id)
                } else if resolvedStatus.isSleeping {
                    detachedTorrentIDs.insert(updatedTorrents[index].id)
                    if previousStatus == .checking || previousStatus.isActive {
                        pendingSleepingDetachIDs.insert(updatedTorrents[index].id)
                    }

                    if resolvedStatus == .completed
                        && updatedTorrents[index].stopAfterDownload
                        && snapshot.progress >= 1.0
                        && previousStatus.isActive {
                        updatedTorrents[index].stopAfterDownload = false
                    }
                }
            }

            traceTransition(
                torrentID: updatedTorrents[index].id,
                phase: "snapshot.applied",
                level: .debug,
                extra: [
                    "previousStatus": previousStatus.rawValue,
                    "status": updatedTorrents[index].status.rawValue,
                    "progress": progressString(updatedTorrents[index].progress),
                    "runtimeError": updatedTorrents[index].runtimeErrorState?.title ?? "none"
                ]
            )

            if selectedTorrentID == torrentID,
               wasFinishedForOpening != updatedTorrents[index].isFinishedForOpening {
                shouldRefreshSelectedNavigationAvailability = true
            }
            durableChange = max(
                durableChange,
                registerDurableSnapshotChange(previousStatus: previousStatus, record: updatedTorrents[index])
            )
        }

        if speedLevels.count > updatedTorrents.count {
            let torrentIDs = Set(updatedTorrents.map(\.id))
            speedLevels = speedLevels.filter { torrentIDs.contains($0.key) }
        }
        // Before the records, whose change rebuilds the cards.
        transferSpeedLevels = speedLevels
        if updatedTorrents != torrents {
            suppressesTorrentChangePublication = true
            torrents = updatedTorrents
            suppressesTorrentChangePublication = false
        }
        if shouldRefreshSelectedNavigationAvailability {
            refreshSelectedTorrentNavigationAvailability()
        }
        switch durableChange {
        case .none:
            break
        case .progress:
            scheduleProgressSave()
        case .status:
            saveCriticalState()
        }
    }

    #if DEBUG
    func applySnapshotsForTesting(_ snapshots: [EngineTorrentSnapshot]) {
        applySnapshots(snapshots)
    }

    /// Runs one tick of the runtime loop without waiting for its timer.
    func refreshActiveSnapshotsForTesting() async {
        await refreshActiveSnapshots()
    }
    #endif

    private enum DurableSnapshotChange: Comparable {
        case none
        case progress
        case status
    }

    private func registerDurableSnapshotChange(
        previousStatus: TorrentStatus,
        record: TorrentRecord
    ) -> DurableSnapshotChange {
        let bucket = Self.progressPersistenceBucket(for: max(record.progress, record.lastKnownProgress))
        let previousBucket = lastPersistedProgressBucketByID[record.id]
        let didChangeStatus = previousStatus != record.status
        guard didChangeStatus || previousBucket != bucket else { return .none }
        lastPersistedProgressBucketByID[record.id] = bucket
        return didChangeStatus ? .status : .progress
    }

    /// A new percent is written at most once per `progressSaveInterval`, while
    /// status changes and user actions still save at once. The save reads
    /// `torrents` when it runs, so it always writes the latest progress.
    private func scheduleProgressSave() {
        guard progressSaveTask == nil, !isPreparingForTermination else { return }

        let delay = lastProgressSaveAt.map { max(.zero, $0 + progressSaveInterval - .now) } ?? .zero
        progressSaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.progressSaveTask = nil
            self.lastProgressSaveAt = .now
            await self.persistCriticalState()
        }
    }

    private static func progressPersistenceBucket(for progress: Double) -> Int {
        Int((min(max(progress, 0), 1) * 100).rounded(.down))
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
        lastPersistedProgressBucketByID = Dictionary(
            uniqueKeysWithValues: torrents.map {
                ($0.id, Self.progressPersistenceBucket(for: max($0.progress, $0.lastKnownProgress)))
            }
        )

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
        lastPersistedProgressBucketByID[record.id] = Self.progressPersistenceBucket(
            for: max(record.progress, record.lastKnownProgress)
        )
        detachedTorrentIDs.remove(record.id)
    }

    private func persistCriticalState() async {
        _ = await commitCriticalState(torrents)
    }

    private func commitCriticalState(_ records: [TorrentRecord]) async -> SessionSaveOutcome {
        let outcome = await sessionStore.updateExisting(from: records)
        recordSessionSaveOutcome(outcome)
        return outcome
    }

    /// Hides the line message until storage recovers. A later failed user
    /// action shows it again, because that action did not happen.
    func hideSessionPersistenceIssue() {
        guard sessionPersistenceIssue != nil else { return }
        sessionPersistenceIssue = nil
        isSessionPersistenceIssueHidden = true
    }

    /// Backs Check Again and returns whether session storage accepts writes again.
    @discardableResult
    func recheckSessionPersistence() async -> Bool {
        guard sessionPersistenceIssue != nil else { return true }
        scheduleSessionPersistenceCheck(refreshesIssueOnFailure: true)
        await sessionPersistenceCheckTask?.value
        return sessionPersistenceIssue == nil
    }

    #if DEBUG
    func waitForSessionPersistenceCheckForTesting() async {
        await sessionPersistenceCheckTask?.value
    }
    #endif

    /// A failed user action always surfaces, even after the message was hidden.
    private func reportSessionPersistenceFailure(_ kind: SessionPersistenceIssue.Kind) {
        sessionPersistenceIssueGeneration += 1
        isSessionPersistenceIssueHidden = false
        sessionPersistenceIssue = SessionPersistenceIssue(kind: kind)
    }

    private func recordSessionSaveOutcome(_ outcome: SessionSaveOutcome) {
        switch outcome {
        case .saved:
            noteSessionSaveSucceeded()
        case .failed:
            // Background saves keep a more specific action message and respect Hide.
            guard sessionPersistenceIssue == nil, !isSessionPersistenceIssueHidden else { return }
            sessionPersistenceIssueGeneration += 1
            sessionPersistenceIssue = SessionPersistenceIssue(kind: .background)
        case .blocked:
            // A blocked initial load already has its own recovery screen.
            break
        }
    }

    private func noteSessionSaveSucceeded() {
        guard sessionPersistenceIssue != nil || isSessionPersistenceIssueHidden else { return }
        scheduleSessionPersistenceCheck(refreshesIssueOnFailure: false)
    }

    /// A `.saved` commit may skip the write when nothing changed, so the
    /// message is cleared only after `verifyWritable()` really writes. The
    /// check runs outside the caller so it never splits a user transition.
    private func scheduleSessionPersistenceCheck(refreshesIssueOnFailure: Bool) {
        guard sessionPersistenceCheckTask == nil else { return }
        let generation = sessionPersistenceIssueGeneration
        sessionPersistenceCheckTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.sessionStore.verifyWritable()
            self.sessionPersistenceCheckTask = nil
            guard generation == self.sessionPersistenceIssueGeneration else { return }

            if outcome == .saved {
                self.sessionPersistenceIssue = nil
                self.isSessionPersistenceIssueHidden = false
            } else if refreshesIssueOnFailure {
                // A new identity lets the line message announce the failed check.
                self.sessionPersistenceIssue?.id = UUID()
            }
        }
    }

    private func persistRestoreArtifacts(for record: TorrentRecord, draft: AddTorrentDraft) async throws {
        let archiveURL = try await torrentArchiveStore.destinationURL(for: record.id)
        try await engine.exportPreparedTorrent(draftID: draft.id, to: archiveURL.path)
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
        savePathBookmarkData: Data? = nil,
        replacesCurrentReview: Bool = false
    ) {
        guard canAddTorrent else { return }
        if isAddTorrentReviewWindowActive, !replacesCurrentReview {
            requestAddTorrentReviewWindowActivation()
            return
        }
        draftPreparationTask?.cancel()
        currentAddTorrentDraft = makeLoadingDraft(
            for: source,
            suggestedSavePath: suggestedSavePath,
            stopAfterDownload: stopAfterDownload,
            alias: alias,
            savePathBookmarkData: savePathBookmarkData
        )
        presentAddTorrentReviewWindow()

        draftPreparationTask = Task { [weak self] in
            guard let self else { return }

            do {
                var draft = try await self.engine.prepareDraft(
                    from: source,
                    suggestedSavePath: suggestedSavePath,
                    stopAfterDownload: stopAfterDownload
                )

                guard !Task.isCancelled,
                      self.currentAddTorrentDraft?.source == source else {
                    // Review was closed or moved on while the metadata loaded.
                    self.releasePreparedDraft(draft.id)
                    return
                }

                draft.alias = alias
                draft.savePathBookmarkData = savePathBookmarkData
                if self.isDuplicateDraft(draft) {
                    self.releasePreparedDraft(draft.id)
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
        presentAddTorrentReviewWindow()
    }

    private func presentAddTorrentReviewWindow() {
        isAddTorrentReviewWindowActive = true
        presentedModal = .addTorrentReview
        addTorrentReviewWindowRequestID &+= 1
    }

    private func isDuplicateDraft(_ draft: AddTorrentDraft) -> Bool {
        guard let infoHash = draft.infoHash else { return false }
        return torrents.contains(where: { $0.infoHash == infoHash })
            || pendingTorrentAdditions.contains(where: { $0.draft.infoHash == infoHash })
    }

    private func presentDuplicateDraft(for draft: AddTorrentDraft) {
        presentInvalidDraft(
            for: draft.source,
            errorState: ShatlErrorCatalog.duplicateDraftError(
                torrentName: draft.originalName,
                localeOverride: preferences.localeOverride
            ),
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
        extra: @autoclosure () -> [String: String] = [:]
    ) {
        guard let context = transitionTracesByTorrentID[torrentID] else { return }
        emitTransition(
            action: context.action,
            operationID: context.operationID,
            torrentID: torrentID,
            phase: phase,
            level: level,
            flush: flush,
            extra: extra()
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
        guard ShatlFileLogger.shared.loggingEnabled else { return }

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
        extra: @autoclosure () -> [String: String] = [:]
    ) {
        guard ShatlDiskDiagnosticsLog.isEnabled else { return }

        var fields = baseDiskDiagnosticFields(torrentID: record.id, record: record)
        fields.merge(extra()) { _, new in new }
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

        let notification = ShatlErrorCatalog.persistentIssueNotification(
            for: issue.kind,
            localeOverride: preferences.localeOverride
        )

        notifiedPersistentIssueKeys.insert(notificationKey)
        registerUnreadPersistentIssueIfNeeded(notificationKey)
        userEventNotifier?.notify(
            .persistentIssue(
                torrentID: torrent.id,
                issueKind: issue.kind,
                torrentTitle: torrent.displayName,
                issueTitle: notification.title,
                issueMessage: notification.body,
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

        let progressFloor = max(record.progress, record.lastKnownProgress)
        restoreRecheckRequestedIDs.remove(record.id)
        restoreProgressFloorByID[record.id] = progressFloor > 0 ? progressFloor : nil

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

        restoreProgressFloorByID[record.id] = nil
        restoreRecheckRequestedIDs.remove(record.id)
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

    private func detachSleepingHandlesIfNeeded() async {
        let sleepingIDs = Array(pendingSleepingDetachIDs)
        guard !sleepingIDs.isEmpty else { return }

        for torrentID in sleepingIDs {
            pendingSleepingDetachIDs.remove(torrentID)
            detachedTorrentIDs.insert(torrentID)

            do {
                traceTransition(torrentID: torrentID, phase: "sleeping.detach.begin", level: .notice, flush: true)
                try await engine.removeTorrent(id: torrentID)
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
