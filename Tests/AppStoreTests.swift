// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

@MainActor
final class AppStoreTests: XCTestCase {
    func testCompleteOnboardingPersistsPreferenceFlag() {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        XCTAssertFalse(bundle.store.preferences.hasCompletedOnboarding)

        bundle.store.completeOnboarding()

        XCTAssertTrue(bundle.store.preferences.hasCompletedOnboarding)
    }

    func testTorrentSelectionIsManualAndToggleable() {
        let engine = FakeTorrentEngine()
        let first = makeTestRecord(originalName: "First")
        let second = makeTestRecord(originalName: "Second")
        let bundle = makeTestStoreBundle(engine: engine, torrents: [first, second])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        XCTAssertNil(bundle.store.selectedTorrentID)

        bundle.store.toggleTorrentSelection(id: first.id)
        XCTAssertEqual(bundle.store.selectedTorrentID, first.id)

        bundle.store.toggleTorrentSelection(id: first.id)
        XCTAssertNil(bundle.store.selectedTorrentID)

        bundle.store.toggleTorrentSelection(id: second.id)
        XCTAssertEqual(bundle.store.selectedTorrentID, second.id)

        bundle.store.clearTorrentSelection()
        XCTAssertNil(bundle.store.selectedTorrentID)
    }

    func testConfirmDraftDoesNotAutomaticallySelectAddedTorrent() async {
        let engine = FakeTorrentEngine()
        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.currentAddTorrentDraft = AddTorrentDraft(
            source: AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/test.torrent"),
            originalName: "New Torrent",
            infoHash: "new-info-hash",
            suggestedSavePath: "/tmp",
            alias: "",
            stopAfterDownload: false,
            files: [
                AddTorrentFileOption(name: "A.bin", sizeBytes: 100, fileIndex: 0, isSelected: true),
            ],
            reviewState: .ready,
            errorState: nil
        )

        bundle.store.confirmDraft()

        let didAddTorrent = await waitForCondition {
            bundle.store.torrents.count == 1
        }

        XCTAssertTrue(didAddTorrent)
        XCTAssertNil(bundle.store.selectedTorrentID)
    }

    func testConfirmDraftFromModalCommitsTorrentOnlyAfterDismissCallback() async {
        let engine = FakeTorrentEngine()
        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.presentedModal = .addTorrentReview
        bundle.store.currentAddTorrentDraft = AddTorrentDraft(
            source: AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/test.torrent"),
            originalName: "New Torrent",
            infoHash: "new-info-hash",
            suggestedSavePath: "/tmp",
            alias: "",
            stopAfterDownload: false,
            files: [
                AddTorrentFileOption(name: "A.bin", sizeBytes: 100, fileIndex: 0, isSelected: true),
            ],
            reviewState: .ready,
            errorState: nil
        )

        bundle.store.confirmDraft()

        let didDismissModal = await waitForCondition {
            bundle.store.presentedModal == nil
        }

        XCTAssertTrue(didDismissModal)
        XCTAssertTrue(bundle.store.torrents.isEmpty)

        bundle.store.commitPendingConfirmedTorrent()

        XCTAssertEqual(bundle.store.torrents.count, 1)
        XCTAssertNil(bundle.store.selectedTorrentID)
    }

    func testRemovingSelectedTorrentClearsSelectionInsteadOfSelectingNextTorrent() async {
        let engine = FakeTorrentEngine()
        let first = makeTestRecord(originalName: "First")
        let second = makeTestRecord(originalName: "Second")
        let bundle = makeTestStoreBundle(engine: engine, torrents: [first, second])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.selectTorrent(id: first.id)
        await bundle.store.removeTorrent(id: first.id, policy: .removeFromListOnly)

        XCTAssertNil(bundle.store.selectedTorrentID)
        XCTAssertEqual(bundle.store.torrents.map(\.id), [second.id])
    }

    func testSavePathUnavailableErrorOffersAnotherFolderRecovery() {
        let issue = TorrentPersistentIssue(
            kind: .savePathUnavailable,
            detectedAt: Date(),
            statusBeforeIssue: .downloading,
            debugReason: nil
        )

        let errorState = ShatlErrorCatalog.persistentIssueState(for: issue)

        XCTAssertEqual(errorState.message, "Shatl не смог открыть папку сохранения. Выберите другую папку для загрузки или удалите торрент из списка")
        XCTAssertEqual(errorState.recoveryOptions, [.chooseAnotherFolder, .removeFromList])
    }

    func testDownloadCompletionSendsNotificationOnceWithBadgeCount() async {
        let engine = FakeTorrentEngine()
        let notifier = SpyTorrentUserEventNotifier()
        let record = makeTestRecord(status: .downloading, progress: 0.99)

        await engine.setHandleActive(true, for: record.id)
        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .seeding,
                progress: 1.0,
                metrics: TorrentMetrics(),
                errorState: nil
            )
        ])
        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .seeding,
                progress: 1.0,
                metrics: TorrentMetrics(),
                errorState: nil
            )
        ])

        let bundle = makeTestStoreBundle(
            engine: engine,
            torrents: [record],
            userEventNotifier: notifier
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.startTorrent(id: record.id)
        let didNotify = await waitForCondition {
            notifier.notifications.count == 1
        }
        bundle.store.startTorrent(id: record.id)
        _ = await waitForCondition {
            bundle.store.torrents.first?.status == .seeding
        }

        XCTAssertTrue(didNotify)
        XCTAssertEqual(
            notifier.notifications,
            [
                .downloadCompleted(
                    torrentID: record.id,
                    torrentTitle: record.displayName,
                    localeOverride: .system
                )
            ]
        )
        XCTAssertEqual(notifier.badgeCounts, [1])
    }

    func testDownloadCompletionUpdatesSystemBadgeWhileApplicationIsInactiveAndClearsOnActivation() async {
        let engine = FakeTorrentEngine()
        let badgeDisplay = SpyTorrentUserEventBadgeDisplay()
        let record = makeTestRecord(status: .downloading, progress: 0.99)

        await engine.setHandleActive(true, for: record.id)
        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .seeding,
                progress: 1.0,
                metrics: TorrentMetrics(),
                errorState: nil
            )
        ])

        let bundle = makeTestStoreBundle(
            engine: engine,
            torrents: [record],
            userEventBadgeDisplay: badgeDisplay
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.setApplicationUserAttentionActive(false)
        bundle.store.startTorrent(id: record.id)
        let didBadge = await waitForCondition {
            badgeDisplay.badgeCounts.last == 1
        }

        bundle.store.setApplicationUserAttentionActive(true)

        XCTAssertTrue(didBadge)
        XCTAssertEqual(badgeDisplay.badgeCounts.last, 0)
    }

    func testDownloadCompletionDoesNotUpdateSystemBadgeWhileApplicationIsActive() async {
        let engine = FakeTorrentEngine()
        let badgeDisplay = SpyTorrentUserEventBadgeDisplay()
        let record = makeTestRecord(status: .downloading, progress: 0.99)

        await engine.setHandleActive(true, for: record.id)
        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .seeding,
                progress: 1.0,
                metrics: TorrentMetrics(),
                errorState: nil
            )
        ])

        let bundle = makeTestStoreBundle(
            engine: engine,
            torrents: [record],
            userEventBadgeDisplay: badgeDisplay
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.setApplicationUserAttentionActive(true)
        bundle.store.startTorrent(id: record.id)
        _ = await waitForCondition {
            bundle.store.torrents.first?.status == .seeding
        }

        XCTAssertFalse(badgeDisplay.badgeCounts.contains(1))
        XCTAssertEqual(badgeDisplay.badgeCounts.last, 0)
    }

    func testSavePathUnavailableSendsPersistentIssueNotification() async {
        let engine = FakeTorrentEngine()
        let notifier = SpyTorrentUserEventNotifier()
        let record = makeTestRecord(
            savePath: "/tmp/ShatlMissingSavePath-\(UUID().uuidString)",
            status: .stopped,
            progress: 0.4
        )

        let bundle = makeTestStoreBundle(
            engine: engine,
            torrents: [record],
            userEventNotifier: notifier
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.startTorrent(id: record.id)
        let didNotify = await waitForCondition {
            notifier.notifications.count == 1
        }

        XCTAssertTrue(didNotify)
        if case .persistentIssue(let torrentID, let issueKind, let torrentTitle, let issueTitle, _, _) = notifier.notifications.first {
            XCTAssertEqual(torrentID, record.id)
            XCTAssertEqual(issueKind, .savePathUnavailable)
            XCTAssertEqual(torrentTitle, record.displayName)
            XCTAssertEqual(issueTitle, "Папка загрузки недоступна")
            XCTAssertEqual(notifier.badgeCounts, [1])
        } else {
            XCTFail("Expected persistent issue notification")
        }
    }

    func testConfirmDraftDoesNotStartWhenNoFilesAreSelected() async {
        let engine = FakeTorrentEngine()
        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.currentAddTorrentDraft = AddTorrentDraft(
            source: AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/test.torrent"),
            originalName: "Partial Torrent",
            infoHash: "empty-selection",
            suggestedSavePath: "/tmp",
            alias: "",
            stopAfterDownload: false,
            files: [
                AddTorrentFileOption(name: "A.bin", sizeBytes: 100, fileIndex: 0, isSelected: false),
                AddTorrentFileOption(name: "B.bin", sizeBytes: 200, fileIndex: 1, isSelected: false),
            ],
            reviewState: .ready,
            errorState: nil
        )

        bundle.store.confirmDraft()

        let addCallCount = await engine.addCallCount()

        XCTAssertEqual(addCallCount, 0)
        XCTAssertTrue(bundle.store.torrents.isEmpty)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.selectedFileIndices, [])
    }

    func testConfirmDraftForSleepingDuplicateShowsInlineDraftErrorInsteadOfAlert() async {
        let engine = FakeTorrentEngine()
        let existingRecord = makeTestRecord(
            infoHash: "duplicate-info-hash",
            status: .completed,
            progress: 1.0
        )
        let bundle = makeTestStoreBundle(engine: engine, torrents: [existingRecord])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.currentAddTorrentDraft = AddTorrentDraft(
            source: AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/test.torrent"),
            originalName: "Duplicate Torrent",
            infoHash: "duplicate-info-hash",
            suggestedSavePath: "/tmp",
            alias: "",
            stopAfterDownload: false,
            files: [
                AddTorrentFileOption(name: "A.bin", sizeBytes: 100, fileIndex: 0, isSelected: true),
            ],
            reviewState: .ready,
            errorState: nil
        )

        bundle.store.confirmDraft()

        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.reviewState, duplicateDraftReviewState)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.errorState?.kind, .duplicateTorrent)
        XCTAssertEqual(bundle.store.torrents.count, 1)
    }

    func testConfirmDraftDuplicateFromEngineShowsInlineDraftErrorInsteadOfAlert() async {
        let engine = FakeTorrentEngine()
        await engine.setAddError(TorrentEngineError(kind: .duplicateTorrent, debugReason: "engine duplicate"))

        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.currentAddTorrentDraft = AddTorrentDraft(
            source: AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/test.torrent"),
            originalName: "Duplicate Torrent",
            infoHash: "duplicate-info-hash",
            suggestedSavePath: "/tmp",
            alias: "",
            stopAfterDownload: false,
            files: [
                AddTorrentFileOption(name: "A.bin", sizeBytes: 100, fileIndex: 0, isSelected: true),
            ],
            reviewState: .ready,
            errorState: nil
        )

        bundle.store.confirmDraft()

        let didApplyDuplicate = await waitForCondition {
            bundle.store.currentAddTorrentDraft?.errorState?.kind == .duplicateTorrent
        }

        XCTAssertTrue(didApplyDuplicate)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.reviewState, duplicateDraftReviewState)
        XCTAssertTrue(bundle.store.torrents.isEmpty)
    }

    func testSleepingMagnetDuplicateShowsInlineDraftErrorAfterPreparation() async throws {
        let engine = FakeTorrentEngine()
        let existingRecord = makeTestRecord(
            infoHash: "test-info-hash",
            status: .stopped,
            progress: 0.0
        )
        let bundle = makeTestStoreBundle(engine: engine, torrents: [existingRecord])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.bootstrapRuntimeState()

        let finishedBootstrap = await waitForCondition {
            !bundle.store.isRestoringSession
        }
        XCTAssertTrue(finishedBootstrap)

        let magnetURL = try XCTUnwrap(URL(string: "magnet:?xt=urn:btih:abcdef1234567890"))
        bundle.store.handleIncomingURL(magnetURL)

        let didApplyDuplicate = await waitForCondition {
            bundle.store.currentAddTorrentDraft?.errorState?.kind == .duplicateTorrent
        }

        XCTAssertTrue(didApplyDuplicate)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.reviewState, duplicateDraftReviewState)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.source.kind, .magnet)
        XCTAssertEqual(bundle.store.torrents.count, 1)
    }

    func testBufferedExternalMagnetDuplicateWaitsForBootstrapAndShowsInlineError() async throws {
        let engine = FakeTorrentEngine()
        let router = ExternalOpenRouter()
        let magnetURL = try XCTUnwrap(URL(string: "magnet:?xt=urn:btih:abcdef1234567890"))
        router.receive(urls: [magnetURL])

        let bundle = makeTestStoreBundle(engine: engine, router: router)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let existingRecord = makeTestRecord(
            infoHash: "test-info-hash",
            status: .stopped,
            progress: 0.0
        )
        await bundle.sessionStore.saveCriticalState(from: [existingRecord])

        bundle.store.bootstrapRuntimeState()

        let didApplyDuplicate = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            !bundle.store.isRestoringSession
                && bundle.store.currentAddTorrentDraft?.errorState?.kind == .duplicateTorrent
        }

        XCTAssertTrue(didApplyDuplicate)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.reviewState, duplicateDraftReviewState)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.source.kind, .magnet)
        XCTAssertEqual(bundle.store.torrents.count, 1)
    }

    func testBufferedExternalTorrentDuplicateWaitsForBootstrapAndShowsInlineError() async throws {
        let engine = FakeTorrentEngine()
        let router = ExternalOpenRouter()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalDuplicate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let torrentURL = tempRoot.appendingPathComponent("Example.torrent", isDirectory: false)
        try Data("dummy".utf8).write(to: torrentURL, options: .atomic)
        router.receive(urls: [torrentURL])

        let bundle = makeTestStoreBundle(engine: engine, router: router)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let existingRecord = makeTestRecord(
            infoHash: "test-info-hash",
            status: .stopped,
            progress: 0.0
        )
        await bundle.sessionStore.saveCriticalState(from: [existingRecord])

        bundle.store.bootstrapRuntimeState()

        let didApplyDuplicate = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            !bundle.store.isRestoringSession
                && bundle.store.currentAddTorrentDraft?.errorState?.kind == .duplicateTorrent
        }

        XCTAssertTrue(didApplyDuplicate)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.reviewState, duplicateDraftReviewState)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.source.kind, .externalOpen)
        XCTAssertEqual(bundle.store.torrents.count, 1)
    }

    func testBufferedExternalMagnetStartsReviewFlow() async throws {
        let engine = FakeTorrentEngine()
        let router = ExternalOpenRouter()
        let magnetURL = try XCTUnwrap(URL(string: "magnet:?xt=urn:btih:abcdef1234567890"))

        router.receive(urls: [magnetURL])
        let bundle = makeTestStoreBundle(engine: engine, router: router)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.bootstrapRuntimeState()

        let didLoadDraft = await waitForCondition {
            !bundle.store.isRestoringSession
                && bundle.store.currentAddTorrentDraft?.reviewState == .ready
        }

        XCTAssertTrue(didLoadDraft)
        XCTAssertEqual(bundle.store.presentedModal, .addTorrentReview)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.source.kind, .magnet)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.source.rawValue, magnetURL.absoluteString)
        let preparedSources = await engine.recordedPrepareSources()
        XCTAssertEqual(preparedSources.first?.kind, .magnet)
    }

    func testBufferedExternalTorrentFileUsesExternalSourceKind() async throws {
        let engine = FakeTorrentEngine()
        let router = ExternalOpenRouter()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalOpen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let torrentURL = tempRoot.appendingPathComponent("Example.torrent", isDirectory: false)
        try Data("dummy".utf8).write(to: torrentURL, options: .atomic)

        router.receive(urls: [torrentURL])
        let bundle = makeTestStoreBundle(engine: engine, router: router)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.bootstrapRuntimeState()

        let didLoadDraft = await waitForCondition {
            !bundle.store.isRestoringSession
                && bundle.store.currentAddTorrentDraft?.reviewState == .ready
        }

        XCTAssertTrue(didLoadDraft)
        XCTAssertEqual(bundle.store.presentedModal, .addTorrentReview)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.source.kind, .externalOpen)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.source.rawValue, torrentURL.path)
        let preparedSources = await engine.recordedPrepareSources()
        XCTAssertEqual(preparedSources.first?.kind, .externalOpen)
    }

    func testDefaultDownloadBookmarkDataPropagatesToNewDraft() async throws {
        let engine = FakeTorrentEngine()
        let bundle = makeTestStoreBundle(engine: engine)
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DefaultDownloadBookmark-\(UUID().uuidString)", isDirectory: true)
        let bookmarkData = Data("default-folder-bookmark".utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        bundle.store.setDefaultDownloadLocation(saveRoot, bookmarkData: bookmarkData)
        bundle.store.continueFromEntry(with: "magnet:?xt=urn:btih:abcdef1234567890")

        let didLoadDraft = await waitForCondition {
            bundle.store.currentAddTorrentDraft?.reviewState == .ready
        }

        XCTAssertTrue(didLoadDraft)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.suggestedSavePath, saveRoot.path)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.savePathBookmarkData, bookmarkData)
    }

    func testToggleExpandedAllowsOnlyOneExpandedTorrent() async {
        let engine = FakeTorrentEngine()
        let firstRecord = makeTestRecord(id: UUID(), originalName: "First")
        let secondRecord = makeTestRecord(id: UUID(), originalName: "Second")
        let bundle = makeTestStoreBundle(engine: engine, torrents: [firstRecord, secondRecord])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.toggleExpanded(for: firstRecord.id)
        XCTAssertEqual(bundle.store.expandedTorrentID, firstRecord.id)

        bundle.store.toggleExpanded(for: secondRecord.id)
        XCTAssertEqual(bundle.store.expandedTorrentID, secondRecord.id)

        bundle.store.toggleExpanded(for: secondRecord.id)
        XCTAssertNil(bundle.store.expandedTorrentID)
    }

    func testToggleExpandedIgnoresMissingTorrentID() async {
        let engine = FakeTorrentEngine()
        let record = makeTestRecord()
        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.toggleExpanded(for: record.id)
        bundle.store.toggleExpanded(for: UUID())

        XCTAssertEqual(bundle.store.expandedTorrentID, record.id)
    }

    func testRemoveExpandedTorrentClearsExpandedState() async {
        let engine = FakeTorrentEngine()
        let record = makeTestRecord()
        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.toggleExpanded(for: record.id)
        await bundle.store.removeTorrent(id: record.id, policy: .removeFromListOnly)

        XCTAssertNil(bundle.store.expandedTorrentID)
    }

    func testRowStateBuildsExpandedMetricsOnlyForExpandedTorrent() async {
        let engine = FakeTorrentEngine()
        var firstRecord = makeTestRecord(
            id: UUID(),
            originalName: "First",
            status: .downloading,
            progress: 0.5
        )
        firstRecord.metrics = TorrentMetrics(
            downloadSpeedBytesPerSecond: 1_024,
            uploadSpeedBytesPerSecond: 512,
            etaSeconds: 60,
            seeds: 2,
            peers: 4,
            uploadedBytes: 2_048,
            totalBytes: 8_192,
            selectedBytes: 8_192
        )
        var secondRecord = makeTestRecord(
            id: UUID(),
            originalName: "Second",
            status: .downloading,
            progress: 0.25
        )
        secondRecord.metrics = TorrentMetrics(
            downloadSpeedBytesPerSecond: 2_048,
            uploadSpeedBytesPerSecond: 1_024,
            etaSeconds: 120,
            seeds: 3,
            peers: 5,
            uploadedBytes: 4_096,
            totalBytes: 16_384,
            selectedBytes: 16_384
        )
        let bundle = makeTestStoreBundle(engine: engine, torrents: [firstRecord, secondRecord])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.toggleExpanded(for: secondRecord.id)

        let firstRow = bundle.store.rowState(for: firstRecord.id)
        let secondRow = bundle.store.rowState(for: secondRecord.id)

        XCTAssertEqual(bundle.store.torrentRowIDs, [firstRecord.id, secondRecord.id])
        XCTAssertFalse(firstRow?.compactMetrics.isEmpty ?? true)
        XCTAssertEqual(firstRow?.expandedMetrics, [])
        XCTAssertNil(firstRow?.expandedMetricGroups)
        XCTAssertFalse(secondRow?.expandedMetrics.isEmpty ?? false)
        XCTAssertNotNil(secondRow?.expandedMetricGroups)
    }

    func testSpeedColorPreferenceInvalidatesRowWithoutChangingMetrics() throws {
        let record = makeTestRecord(status: .downloading, progress: 0.5)
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: [record])
        defer { try? FileManager.default.removeItem(at: bundle.rootURL) }
        let before = try XCTUnwrap(bundle.store.rowState(for: record.id))
        bundle.store.preferences.colorizesDownloadSpeed = true
        let after = try XCTUnwrap(bundle.store.rowState(for: record.id))
        XCTAssertFalse(before.colorizesDownloadSpeed)
        XCTAssertTrue(after.colorizesDownloadSpeed)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(before.compactTransferMetricSet, after.compactTransferMetricSet)
        bundle.store.preferences.colorizesDownloadSpeed = false
        XCTAssertEqual(bundle.store.rowState(for: record.id), before)
    }

    func testRowStateCarriesMetricsModePreference() async {
        let record = makeTestRecord(status: .downloading, progress: 0.5)
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.preferences.metricsMode = .detailed

        XCTAssertEqual(bundle.store.rowState(for: record.id)?.metricsMode, .detailed)
    }

    func testRowStateNavigationAvailabilityKeyChangesWhenTorrentBecomesOpenable() async {
        let torrentID = UUID()
        let downloadingRecord = makeTestRecord(
            id: torrentID,
            status: .downloading,
            progress: 0.5
        )
        let completedRecord = makeTestRecord(
            id: torrentID,
            status: .completed,
            progress: 1.0
        )
        let downloadingBundle = makeTestStoreBundle(
            engine: FakeTorrentEngine(),
            torrents: [downloadingRecord]
        )
        let completedBundle = makeTestStoreBundle(
            engine: FakeTorrentEngine(),
            torrents: [completedRecord]
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: downloadingBundle.rootURL)
            try? FileManager.default.removeItem(at: completedBundle.rootURL)
        }

        XCTAssertNotEqual(
            downloadingBundle.store.rowState(for: torrentID)?.navigationAvailabilityKey,
            completedBundle.store.rowState(for: torrentID)?.navigationAvailabilityKey
        )
    }

    func testPerformanceProfileChangeAppliesEngineSettings() async {
        let engine = FakeTorrentEngine()
        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.setPerformanceProfile(.maximum)

        let didApplyMaximum = await waitForAsyncCondition {
            await engine.recordedPerformanceSettings().last == EnginePerformanceSettings(mode: .maximum)
        }

        XCTAssertTrue(didApplyMaximum)
        XCTAssertEqual(bundle.store.preferences.performanceProfile, .maximum)
    }

    func testPrepareForTerminationCheckpointsOnlyActiveTorrentsAndPersistsResumeMetadata() async throws {
        let engine = FakeTorrentEngine()
        let activeRecord = makeTestRecord(status: .downloading, progress: 0.42)
        let sleepingRecord = makeTestRecord(status: .stopped, progress: 0.18)
        let bundle = makeTestStoreBundle(engine: engine, torrents: [activeRecord, sleepingRecord])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        await engine.setHandleActive(true, for: activeRecord.id)

        await bundle.store.prepareForTermination()

        let checkpointedIDs = await engine.recordedCheckpointedTorrentIDs()
        XCTAssertEqual(checkpointedIDs, [activeRecord.id])

        let snapshot = await bundle.sessionStore.load().snapshot
        let persistedActiveRecord = snapshot?.torrents.first { $0.torrentID == activeRecord.id }
        let persistedSleepingRecord = snapshot?.torrents.first { $0.torrentID == sleepingRecord.id }

        XCTAssertEqual(persistedActiveRecord?.resumeCheckpointProgress, 0.42)
        XCTAssertNotNil(persistedActiveRecord?.resumeCheckpointedAt)
        XCTAssertNil(persistedSleepingRecord?.resumeCheckpointProgress)
        XCTAssertNil(persistedSleepingRecord?.resumeCheckpointedAt)
    }

    func testRemoveTorrentPersistsDeletionAndCleansRestoreArtifacts() async throws {
        let engine = FakeTorrentEngine()
        await engine.setRemoveError(TorrentEngineError(kind: .engineFailure, debugReason: "remove failed"))

        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoveOnly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(savePath: saveRoot.path)
        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        await bundle.sessionStore.saveCriticalState(from: [record])

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)

        let saveURL = URL(fileURLWithPath: record.canonicalSavePath, isDirectory: true)
        try FileManager.default.createDirectory(at: saveURL, withIntermediateDirectories: true)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveURL)

        let bookmarkURL = bundle.directories.bookmarksDirectoryURL
            .appendingPathComponent("\(record.id.uuidString).bookmark", isDirectory: false)

        await bundle.store.removeTorrent(id: record.id, policy: .removeFromListOnly)

        let snapshot = await bundle.sessionStore.load().snapshot
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.directories.sessionSnapshotURL.path))
        XCTAssertTrue(try XCTUnwrap(snapshot).torrents.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bookmarkURL.path))
        let removeCalls = await engine.recordedRemoveCalls()
        XCTAssertEqual(removeCalls, [RemovedTorrentCall(id: record.id, deleteData: false)])
    }

    func testRemoveTorrentWithFilesDeletesManagedPayloadAndUsesEngineWithoutDeleteData() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Movie.mkv", sizeBytes: 4_096, fileIndex: 0),
        ])

        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemovePayload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let payloadFileURL = saveRoot.appendingPathComponent("Movie.mkv", isDirectory: false)
        try Data("payload".utf8).write(to: payloadFileURL, options: .atomic)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .completed,
            progress: 1.0
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        await bundle.sessionStore.saveCriticalState(from: [record])
        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        await bundle.store.removeTorrent(id: record.id, policy: .removeFromListAndDeleteFiles)

        let snapshot = await bundle.sessionStore.load().snapshot
        XCTAssertTrue(snapshot?.torrents.isEmpty ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))

        let bookmarkURL = bundle.directories.bookmarksDirectoryURL
            .appendingPathComponent("\(record.id.uuidString).bookmark", isDirectory: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bookmarkURL.path))

        let removeCalls = await engine.recordedRemoveCalls()
        XCTAssertEqual(removeCalls, [RemovedTorrentCall(id: record.id, deleteData: false)])
    }

    func testRemoveTorrentWithFilesDowngradesToRemoveOnlyForRuntimeError() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Movie.mkv", sizeBytes: 4_096, fileIndex: 0),
        ])

        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoveRuntimeError-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let payloadFileURL = saveRoot.appendingPathComponent("Movie.mkv", isDirectory: false)
        try Data("payload".utf8).write(to: payloadFileURL, options: .atomic)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .error,
            progress: 0.42,
            runtimeErrorState: ShatlErrorCatalog.torrentActionError(
                for: TorrentEngineError(kind: .torrentNotFound, debugReason: "Missing archive")
            )
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        await bundle.sessionStore.saveCriticalState(from: [record])
        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        await bundle.store.removeTorrent(id: record.id, policy: .removeFromListAndDeleteFiles)

        let snapshot = await bundle.sessionStore.load().snapshot
        XCTAssertTrue(snapshot?.torrents.isEmpty ?? true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))

        let bookmarkURL = bundle.directories.bookmarksDirectoryURL
            .appendingPathComponent("\(record.id.uuidString).bookmark", isDirectory: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bookmarkURL.path))

        let removeCalls = await engine.recordedRemoveCalls()
        XCTAssertEqual(removeCalls, [RemovedTorrentCall(id: record.id, deleteData: false)])
    }

    func testRemoveTorrentWithFilesShowsAlertWhenPayloadCannotBeResolved() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemovePayloadUnresolved-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let payloadFileURL = saveRoot.appendingPathComponent("Movie.mkv", isDirectory: false)
        try Data("payload".utf8).write(to: payloadFileURL, options: .atomic)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileRelativePaths: [],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .completed,
            progress: 1.0
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        await bundle.sessionStore.saveCriticalState(from: [record])
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        await bundle.store.removeTorrent(id: record.id, policy: .removeFromListAndDeleteFiles)

        XCTAssertTrue(bundle.store.torrents.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadFileURL.path))
        XCTAssertEqual(
            bundle.store.payloadDeletionAlert?.title,
            L10n.string(
                "payload_deletion.files_not_deleted.title",
                localeOverride: bundle.store.preferences.localeOverride,
                defaultValue: "Файлы не удалены"
            )
        )
    }

    func testStartSelectedCompletedTorrentWithMissingContentAppliesPersistentIssue() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Season 3/Episode 01.mkv", sizeBytes: 1_024, fileIndex: 0),
        ])

        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingContent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .completed,
            progress: 1.0
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        bundle.store.selectTorrent(id: record.id)
        bundle.store.startSelectedTorrent()

        let didSetIssue = await waitForCondition {
            bundle.store.selectedTorrent?.persistentIssue?.kind == .missingContent
        }

        XCTAssertTrue(didSetIssue)
        XCTAssertEqual(bundle.store.selectedTorrent?.status, .error)
        let restoreCalls = await engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCalls, 0)
    }

    func testStopSelectedSeedingTorrentWithMissingContentAppliesPersistentIssue() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Movie.mkv", sizeBytes: 4_096, fileIndex: 0),
        ])

        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingContent-Stop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .seeding,
            progress: 1.0
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        bundle.store.selectTorrent(id: record.id)
        bundle.store.stopSelectedTorrent()

        let didSetIssue = await waitForCondition {
            bundle.store.selectedTorrent?.persistentIssue?.kind == .missingContent
        }

        XCTAssertTrue(didSetIssue)
        XCTAssertEqual(bundle.store.selectedTorrent?.status, .error)
    }

    func testStartIsBlockedWhileStopTransitionIsStillRunning() async throws {
        let engine = FakeTorrentEngine()
        await engine.setRemoveDelay(nanoseconds: 300_000_000)

        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("StartAfterStop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            status: .downloading,
            progress: 0.25
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let saveURL = URL(fileURLWithPath: record.canonicalSavePath, isDirectory: true)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveURL)

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        try Data("partial payload".utf8).write(
            to: saveRoot.appendingPathComponent("test-file.bin", isDirectory: false),
            options: .atomic
        )

        bundle.store.selectTorrent(id: record.id)
        bundle.store.stopSelectedTorrent()

        let didEnterTransition = await waitForCondition {
            bundle.store.transitioningTorrentIDs.contains(record.id)
                && bundle.store.selectedTorrent?.status == .stopped
        }
        XCTAssertTrue(didEnterTransition)
        XCTAssertFalse(bundle.store.isToolbarStartStopEnabled)

        bundle.store.startSelectedTorrent()

        try? await Task.sleep(nanoseconds: 50_000_000)
        let restoreCallsDuringStop = await engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCallsDuringStop, 0)

        let didFinishStop = await waitForCondition(timeoutNanoseconds: 1_000_000_000) {
            !bundle.store.transitioningTorrentIDs.contains(record.id)
        }
        XCTAssertTrue(didFinishStop)

        bundle.store.startSelectedTorrent()

        let didRestoreAfterStop = await waitForCondition {
            bundle.store.selectedTorrent?.status == .downloading
        }
        XCTAssertTrue(didRestoreAfterStop)

        let restoreCallsAfterStop = await engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCallsAfterStop, 1)
    }

    func testRestoreAndStartRetriesTemporaryDuplicateAfterStop() async throws {
        let engine = FakeTorrentEngine()
        await engine.setRestoreSessionErrors([
            TorrentEngineError(kind: .duplicateTorrent, debugReason: "temporary duplicate"),
        ])

        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoreAndStart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            status: .stopped,
            progress: 0.0
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let saveURL = URL(fileURLWithPath: record.canonicalSavePath, isDirectory: true)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveURL)

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)

        bundle.store.selectTorrent(id: record.id)
        bundle.store.startSelectedTorrent()

        let didStart = await waitForCondition(timeoutNanoseconds: 1_500_000_000) {
            bundle.store.selectedTorrent?.status == .downloading
                && bundle.store.selectedTorrent?.runtimeErrorState == nil
        }

        XCTAssertTrue(didStart)
        let restoreCalls = await engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCalls, 2)
    }

    func testStoreLoadsPersistedPreferencesOnInitialization() async throws {
        let engine = FakeTorrentEngine()
        let suiteName = "AppStorePreferences-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Не удалось создать isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let preferencesStore = AppPreferencesStore(userDefaults: defaults)
        var savedPreferences = AppPreferences.defaultValue
        savedPreferences.isLoggingEnabled = true
        savedPreferences.alwaysStopAfterDownload = true
        preferencesStore.save(savedPreferences)

        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
            defaults.removePersistentDomain(forName: suiteName)
            ShatlFileLogger.shared.setEnabled(false)
        }

        let store = AppStore(
            engine: engine,
            preferencesStore: preferencesStore,
            sessionStore: bundle.sessionStore,
            torrentArchiveStore: bundle.archiveStore,
            bookmarkStore: bundle.bookmarkStore,
            sessionRestoreCoordinator: SessionRestoreCoordinator(
                engine: engine,
                archiveStore: bundle.archiveStore,
                bookmarkStore: bundle.bookmarkStore
            ),
            diskIssueDetector: DiskIssueDetector(
                engine: engine,
                archiveStore: bundle.archiveStore,
                bookmarkStore: bundle.bookmarkStore
            ),
            torrentPayloadLocator: bundle.payloadLocator,
            torrentPayloadDeletionService: bundle.payloadDeletionService,
            externalOpenRouter: ExternalOpenRouter()
        )

        XCTAssertEqual(store.preferences, savedPreferences)
        XCTAssertTrue(ShatlFileLogger.shared.loggingEnabled)
    }

    func testForceRecheckRestoresSleepingTorrentBeforeChecking() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForceRecheck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        let payloadFileURL = saveRoot.appendingPathComponent("test-file.bin", isDirectory: false)
        try Data("payload".utf8).write(to: payloadFileURL, options: .atomic)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .stopped,
            progress: 0.4
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        bundle.store.forceRecheckTorrent(id: record.id)

        let didEnterChecking = await waitForCondition {
            bundle.store.torrents.first?.status == .checking
        }

        XCTAssertTrue(didEnterChecking)
        let recheckCallIDs = await engine.recordedRecheckCallIDs()
        XCTAssertEqual(recheckCallIDs, [record.id])
        let restoreCalls = await engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCalls, 1)
        let restoreEntries = await engine.recordedRestoreSessionEntries()
        XCTAssertEqual(restoreEntries.last?.torrentID, record.id)
        XCTAssertEqual(restoreEntries.last?.shouldStart, true)
    }

    func testForceRecheckReturnsSleepingTorrentToStoppedAfterCheckCompletes() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForceRecheck-Stopped-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        let payloadFileURL = saveRoot.appendingPathComponent("test-file.bin", isDirectory: false)
        try Data("payload".utf8).write(to: payloadFileURL, options: .atomic)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .stopped,
            progress: 0.4
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        bundle.store.bootstrapRuntimeState()

        let didBootstrap = await waitForCondition {
            !bundle.store.isRestoringSession
        }
        XCTAssertTrue(didBootstrap)

        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .checking,
                progress: 0.4,
                metrics: TorrentMetrics(),
                errorState: nil
            ),
        ])
        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .downloading,
                progress: 0.4,
                metrics: TorrentMetrics(
                    downloadSpeedBytesPerSecond: 2_048,
                    uploadSpeedBytesPerSecond: 512,
                    etaSeconds: 120,
                    seeds: 4,
                    peers: 9,
                    uploadedBytes: 8_192,
                    totalBytes: 16_384,
                    selectedBytes: 16_384
                ),
                errorState: nil
            ),
        ])

        bundle.store.forceRecheckTorrent(id: record.id)

        let didReturnToStopped = await waitForCondition(timeoutNanoseconds: 2_500_000_000) {
            !bundle.store.transitioningTorrentIDs.contains(record.id)
                && bundle.store.torrents.first?.status == .stopped
                && bundle.store.torrents.first?.runtimeErrorState == nil
        }
        XCTAssertTrue(didReturnToStopped)
        XCTAssertNil(bundle.store.torrents.first?.metrics.seeds)
        XCTAssertNil(bundle.store.torrents.first?.metrics.peers)
        XCTAssertEqual(bundle.store.torrents.first?.metrics.downloadSpeedBytesPerSecond, 0)
        XCTAssertEqual(bundle.store.torrents.first?.metrics.uploadSpeedBytesPerSecond, 0)
        XCTAssertEqual(bundle.store.torrents.first?.metrics.uploadedBytes, 8_192)
        XCTAssertEqual(bundle.store.torrents.first?.metrics.totalBytes, 16_384)

        let didDetachTemporaryHandle = await waitForAsyncCondition(timeoutNanoseconds: 2_500_000_000) {
            let removeCalls = await engine.recordedRemoveCalls()
            return removeCalls.contains(RemovedTorrentCall(id: record.id, deleteData: false))
        }
        XCTAssertTrue(didDetachTemporaryHandle)
    }

    func testForceRecheckReturnsCompletedTorrentToCompletedAfterCheckCompletes() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForceRecheck-Completed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        let payloadFileURL = saveRoot.appendingPathComponent("test-file.bin", isDirectory: false)
        try Data("payload".utf8).write(to: payloadFileURL, options: .atomic)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .completed,
            progress: 1.0
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)

        bundle.store.bootstrapRuntimeState()

        let didBootstrap = await waitForCondition {
            !bundle.store.isRestoringSession
        }
        XCTAssertTrue(didBootstrap)

        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .checking,
                progress: 1.0,
                metrics: TorrentMetrics(),
                errorState: nil
            ),
        ])
        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .seeding,
                progress: 1.0,
                metrics: TorrentMetrics(
                    downloadSpeedBytesPerSecond: 1_024,
                    uploadSpeedBytesPerSecond: 256,
                    etaSeconds: 30,
                    seeds: 6,
                    peers: 11,
                    uploadedBytes: 12_288,
                    totalBytes: 32_768,
                    selectedBytes: 32_768
                ),
                errorState: nil
            ),
        ])

        bundle.store.forceRecheckTorrent(id: record.id)

        let didReturnToCompleted = await waitForCondition(timeoutNanoseconds: 2_500_000_000) {
            !bundle.store.transitioningTorrentIDs.contains(record.id)
                && bundle.store.torrents.first?.status == .completed
                && bundle.store.torrents.first?.runtimeErrorState == nil
        }
        XCTAssertTrue(didReturnToCompleted)
        XCTAssertNil(bundle.store.torrents.first?.metrics.seeds)
        XCTAssertNil(bundle.store.torrents.first?.metrics.peers)
        XCTAssertEqual(bundle.store.torrents.first?.metrics.downloadSpeedBytesPerSecond, 0)
        XCTAssertEqual(bundle.store.torrents.first?.metrics.uploadSpeedBytesPerSecond, 0)
        XCTAssertEqual(bundle.store.torrents.first?.metrics.uploadedBytes, 12_288)
        XCTAssertEqual(bundle.store.torrents.first?.metrics.totalBytes, 32_768)

        let didDetachTemporaryHandle = await waitForAsyncCondition(timeoutNanoseconds: 2_500_000_000) {
            let removeCalls = await engine.recordedRemoveCalls()
            return removeCalls.contains(RemovedTorrentCall(id: record.id, deleteData: false))
        }
        XCTAssertTrue(didDetachTemporaryHandle)
    }

    func testCompletedStopAfterDownloadSnapshotDetachesHiddenHandle() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("StopAfterDownload-Detach-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0, 3, 7],
            selectedFileCount: 3,
            totalFileCount: 16,
            status: .downloading,
            progress: 0.99,
            stopAfterDownload: true
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        await engine.setHandleActive(true, for: record.id)

        bundle.store.bootstrapRuntimeState()

        let didBootstrap = await waitForCondition {
            !bundle.store.isRestoringSession
        }
        XCTAssertTrue(didBootstrap)

        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .completed,
                progress: 1.0,
                metrics: TorrentMetrics(totalBytes: 16_000, selectedBytes: 3_000),
                errorState: nil
            ),
        ])

        let didBecomeCompleted = await waitForCondition(timeoutNanoseconds: 2_500_000_000) {
            bundle.store.torrents.first?.status == .completed
                && bundle.store.torrents.first?.runtimeErrorState == nil
        }
        XCTAssertTrue(didBecomeCompleted)
        XCTAssertEqual(bundle.store.torrents.first?.stopAfterDownload, false)

        let didDetachHandle = await waitForAsyncCondition(timeoutNanoseconds: 2_500_000_000) {
            let removeCalls = await engine.recordedRemoveCalls()
            return removeCalls.contains(RemovedTorrentCall(id: record.id, deleteData: false))
        }
        XCTAssertTrue(didDetachHandle)
    }

    func testForceRecheckCompletedTorrentReusesExistingHiddenHandleAfterStopAfterDownload() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Recheck-HiddenCompleted-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        let payloadFileURL = saveRoot.appendingPathComponent("Episode 03.mkv", isDirectory: false)
        try Data("payload".utf8).write(to: payloadFileURL, options: .atomic)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [1, 4, 9],
            selectedFileCount: 3,
            totalFileCount: 16,
            status: .completed,
            progress: 1.0,
            stopAfterDownload: true
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)
        await engine.setHandleActive(true, for: record.id)
        await engine.setRestoreSessionErrors([
            TorrentEngineError(kind: .duplicateTorrent, debugReason: "torrent already exists in session")
        ])

        bundle.store.bootstrapRuntimeState()

        let didBootstrap = await waitForCondition {
            !bundle.store.isRestoringSession
        }
        XCTAssertTrue(didBootstrap)

        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .checking,
                progress: 1.0,
                metrics: TorrentMetrics(totalBytes: 16_000, selectedBytes: 3_000),
                errorState: nil
            ),
        ])
        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .completed,
                progress: 1.0,
                metrics: TorrentMetrics(totalBytes: 16_000, selectedBytes: 3_000),
                errorState: nil
            ),
        ])

        bundle.store.forceRecheckTorrent(id: record.id)

        let didReturnToCompleted = await waitForCondition(timeoutNanoseconds: 2_500_000_000) {
            !bundle.store.transitioningTorrentIDs.contains(record.id)
                && bundle.store.torrents.first?.status == .completed
                && bundle.store.torrents.first?.runtimeErrorState == nil
        }
        XCTAssertTrue(didReturnToCompleted)

        let recheckCalls = await engine.recordedRecheckCallIDs()
        XCTAssertEqual(recheckCalls.last, record.id)

        let didDetachTemporaryHandle = await waitForAsyncCondition(timeoutNanoseconds: 2_500_000_000) {
            let removeCalls = await engine.recordedRemoveCalls()
            return removeCalls.contains(RemovedTorrentCall(id: record.id, deleteData: false))
        }
        XCTAssertTrue(didDetachTemporaryHandle)
    }

    func testStartCompletedTorrentReusesExistingHiddenHandleAfterStopAfterDownload() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Start-HiddenCompleted-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [1, 4, 9],
            selectedFileCount: 3,
            totalFileCount: 16,
            status: .completed,
            progress: 1.0,
            stopAfterDownload: true
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)
        await engine.setHandleActive(true, for: record.id)
        await engine.setRestoreSessionErrors([
            TorrentEngineError(kind: .duplicateTorrent, debugReason: "torrent already exists in session")
        ])

        bundle.store.bootstrapRuntimeState()

        let didBootstrap = await waitForCondition {
            !bundle.store.isRestoringSession
        }
        XCTAssertTrue(didBootstrap)

        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .seeding,
                progress: 1.0,
                metrics: TorrentMetrics(totalBytes: 16_000, selectedBytes: 3_000),
                errorState: nil
            ),
        ])

        bundle.store.startTorrent(id: record.id)

        let didBecomeSeeding = await waitForCondition(timeoutNanoseconds: 2_500_000_000) {
            !bundle.store.transitioningTorrentIDs.contains(record.id)
                && bundle.store.torrents.first?.status == .seeding
                && bundle.store.torrents.first?.runtimeErrorState == nil
        }
        XCTAssertTrue(didBecomeSeeding)
    }

    func testConfirmDraftPersistsSelectedSavePathBookmarkData() async throws {
        let engine = FakeTorrentEngine()
        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let bookmarkData = Data("selected-folder-bookmark".utf8)
        bundle.store.currentAddTorrentDraft = AddTorrentDraft(
            source: AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/test.torrent"),
            originalName: "Custom Path Torrent",
            infoHash: "custom-path-info-hash",
            suggestedSavePath: "/Users/example/Movies",
            savePathBookmarkData: bookmarkData,
            alias: "",
            stopAfterDownload: false,
            files: [
                AddTorrentFileOption(
                    name: "movie.mkv",
                    sizeBytes: 1_024,
                    fileIndex: 0,
                    isSelected: true
                ),
            ],
            reviewState: .ready,
            errorState: nil
        )

        bundle.store.confirmDraft()

        let didInsertTorrent = await waitForCondition(timeoutNanoseconds: 1_000_000_000) {
            !bundle.store.torrents.isEmpty
        }
        XCTAssertTrue(didInsertTorrent)

        guard let torrentID = bundle.store.torrents.first?.id else {
            XCTFail("После confirmDraft торрент не появился в store")
            return
        }

        let bookmarkFileURL = bundle.directories.bookmarksDirectoryURL
            .appendingPathComponent("\(torrentID.uuidString).bookmark")
        let persistedData = try Data(contentsOf: bookmarkFileURL)
        XCTAssertEqual(persistedData, bookmarkData)
    }

    func testBootstrapKeepsMissingContentForIncompleteSingleFileIssue() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Movie.mkv", sizeBytes: 4_096, fileIndex: 0),
        ])

        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Bootstrap-MissingContent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .error,
            progress: 0.4,
            persistentIssue: TorrentPersistentIssue(
                kind: .missingContent,
                detectedAt: Date(),
                statusBeforeIssue: .stopped,
                debugReason: "Не найден выбранный файл: Movie.mkv"
            )
        )

        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)
        await bundle.sessionStore.saveCriticalState(from: [record])

        bundle.store.bootstrapRuntimeState()

        let finishedRestore = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            !bundle.store.isRestoringSession && bundle.store.torrents.count == 1
        }

        XCTAssertTrue(finishedRestore)
        XCTAssertEqual(bundle.store.torrents.first?.persistentIssue?.kind, .missingContent)
        XCTAssertEqual(bundle.store.torrents.first?.status, .error)
        let restoreCalls = await engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCalls, 0)
    }

    func testBootstrapDoesNotRestoreSeedingTorrentWhenSelectedFileIsMissing() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Season 3/Episode 01.mkv", sizeBytes: 1_024, fileIndex: 0),
        ])

        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Bootstrap-SeedingMissing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            status: .seeding,
            progress: 1.0
        )

        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)
        await bundle.sessionStore.saveCriticalState(from: [record])

        bundle.store.bootstrapRuntimeState()

        let finishedRestore = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            !bundle.store.isRestoringSession && bundle.store.torrents.count == 1
        }

        XCTAssertTrue(finishedRestore)
        XCTAssertEqual(bundle.store.torrents.first?.persistentIssue?.kind, .missingContent)
        XCTAssertEqual(bundle.store.torrents.first?.status, .error)
        let restoreCalls = await engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCalls, 0)
    }

    func testRuntimeSnapshotErrorStaysRuntimeErrorWhenSavePathDisappearsDuringRuntime() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeSavePathUnavailable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            status: .downloading,
            progress: 0.2
        )
        try Data("partial payload".utf8).write(
            to: saveRoot.appendingPathComponent("test-file.bin", isDirectory: false),
            options: .atomic
        )

        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)
        await bundle.sessionStore.saveCriticalState(from: [record])

        bundle.store.bootstrapRuntimeState()

        let finishedBootstrap = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            !bundle.store.isRestoringSession && bundle.store.torrents.count == 1
        }
        XCTAssertTrue(finishedBootstrap)

        try FileManager.default.removeItem(at: saveRoot)
        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .error,
                progress: 0.2,
                metrics: record.metrics,
                errorState: ShatlErrorCatalog.runtimeSnapshotError(debugReason: "No such file or directory")
            ),
        ])

        let didApplyRuntimeError = await waitForCondition(timeoutNanoseconds: 5_000_000_000) {
            guard let updatedRecord = bundle.store.torrents.first else { return false }
            return updatedRecord.persistentIssue == nil
                && updatedRecord.runtimeErrorState?.kind == .engineFailure
                && updatedRecord.status == .error
        }

        XCTAssertTrue(didApplyRuntimeError, "record: \(String(describing: bundle.store.torrents.first))")

    }

    func testRuntimeSnapshotErrorRemainsRuntimeErrorWhenSavePathIsStillReachable() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeEngineError-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            status: .downloading,
            progress: 0.2
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)
        await engine.setHandleActive(true, for: record.id)

        bundle.store.bootstrapRuntimeState()

        let finishedBootstrap = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            !bundle.store.isRestoringSession
        }
        XCTAssertTrue(finishedBootstrap)

        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .error,
                progress: 0.2,
                metrics: record.metrics,
                errorState: ShatlErrorCatalog.runtimeSnapshotError(debugReason: "storage generic failure")
            ),
        ])

        let didApplyRuntimeError = await waitForCondition(timeoutNanoseconds: 2_500_000_000) {
            guard let updatedRecord = bundle.store.torrents.first else { return false }
            return updatedRecord.persistentIssue == nil
                && updatedRecord.runtimeErrorState?.kind == .engineFailure
                && updatedRecord.status == .error
        }

        XCTAssertTrue(didApplyRuntimeError)
        let removeCalls = await engine.recordedRemoveCalls()
        XCTAssertTrue(removeCalls.isEmpty)
    }

    func testBootstrapNormalizesLegacyRuntimeOnlyErrorSnapshotToSleepingStatus() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyRuntimeSnapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        try bundle.directories.ensureSessionDirectories()
        let legacyRecord = SessionTorrentRecord(
            torrentID: UUID(),
            attemptID: UUID(),
            infoHash: "legacy-runtime-error",
            originalName: "Legacy Runtime Error",
            alias: nil,
            status: .error,
            progress: 0.38,
            canonicalSavePath: saveRoot.path,
            stopAfterDownload: false,
            selectedFileIndices: [0],
            selectedFileCount: 1,
            totalFileCount: 1,
            archivedTorrentRelativePath: "Torrents/legacy.torrent",
            materializedSelectionFootprint: nil,
            persistentIssue: nil
        )
        let legacySnapshot = SessionSnapshot(
            schemaVersion: 3,
            savedAt: Date(),
            torrents: [legacyRecord]
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(legacySnapshot)
        try data.write(to: bundle.directories.sessionSnapshotURL, options: .atomic)

        bundle.store.bootstrapRuntimeState()

        let finishedBootstrap = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            !bundle.store.isRestoringSession && bundle.store.torrents.count == 1
        }

        XCTAssertTrue(finishedBootstrap)
        XCTAssertEqual(bundle.store.torrents.first?.status, .stopped)
        XCTAssertNil(bundle.store.torrents.first?.errorState)
        XCTAssertNil(bundle.store.torrents.first?.persistentIssue)
    }

    func testBootstrapKeepsRecoveredSavePathUnavailableForIncompleteMultiFile() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Season 1/Episode 01.mkv", sizeBytes: 1_024, fileIndex: 0),
            TorrentContentFileDescriptor(relativePath: "Season 1/Episode 02.mkv", sizeBytes: 1_024, fileIndex: 1),
        ])

        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecoveredSavePath-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: saveRoot.appendingPathComponent("Season 1", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("episode".utf8).write(
            to: saveRoot.appendingPathComponent("Season 1/Episode 01.mkv", isDirectory: false),
            options: .atomic
        )

        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let record = makeTestRecord(
            savePath: saveRoot.path,
            selectedFileIndices: [0, 1],
            selectedFileCount: 2,
            totalFileCount: 2,
            status: .error,
            progress: 0.42,
            materializedSelectionFootprint: MaterializedSelectionFootprint(
                selectedFileCount: 2,
                materializedOrdinals: Set([0, 1])
            ),
            persistentIssue: TorrentPersistentIssue(
                kind: .savePathUnavailable,
                detectedAt: Date(),
                statusBeforeIssue: .error,
                debugReason: "Disk was detached"
            )
        )

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)
        await bundle.sessionStore.saveCriticalState(from: [record])

        bundle.store.bootstrapRuntimeState()

        let finishedBootstrap = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            !bundle.store.isRestoringSession && bundle.store.torrents.count == 1
        }

        XCTAssertTrue(finishedBootstrap)
        XCTAssertEqual(bundle.store.torrents.first?.persistentIssue?.kind, .savePathUnavailable)
        XCTAssertEqual(bundle.store.torrents.first?.status, .error)
        let restoreCalls = await engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCalls, 0)
    }

    func testRuntimeSavePathUnavailablePreservesPreviousActiveStatusWhenErrorSnapshotArrives() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Season 1/Episode 01.mkv", sizeBytes: 1_024, fileIndex: 0),
        ])

        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimePreviousStatus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: saveRoot.path,
            status: .downloading,
            progress: 0.2
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)
        await engine.setHandleActive(true, for: record.id)
        try FileManager.default.removeItem(at: saveRoot)
        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(
                id: record.id,
                status: .error,
                progress: 0.2,
                metrics: record.metrics,
                errorState: ShatlErrorCatalog.runtimeSnapshotError(debugReason: "No such file or directory")
            ),
        ])

        bundle.store.bootstrapRuntimeState()

        let finishedBootstrap = await waitForCondition(timeoutNanoseconds: 2_500_000_000) {
            !bundle.store.isRestoringSession
        }
        XCTAssertTrue(finishedBootstrap)

        let didApplyPersistentIssue = await waitForCondition(timeoutNanoseconds: 2_500_000_000) {
            bundle.store.torrents.first?.persistentIssue?.kind == .savePathUnavailable
        }
        XCTAssertTrue(didApplyPersistentIssue)
        XCTAssertEqual(bundle.store.torrents.first?.persistentIssue?.statusBeforeIssue, .downloading)
    }

    func testSavePathUnavailableCanRedownloadToAnotherFolder() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "test-file.bin", sizeBytes: 1_024, fileIndex: 0),
        ])

        let oldSaveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OldUnavailableSavePath-\(UUID().uuidString)", isDirectory: true)
        let newSaveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewRedownloadSavePath-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: newSaveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: oldSaveRoot.path,
            status: .error,
            progress: 0.42,
            persistentIssue: TorrentPersistentIssue(
                kind: .savePathUnavailable,
                detectedAt: Date(),
                statusBeforeIssue: .downloading,
                debugReason: "External disk unavailable"
            )
        )
        let oldAttemptID = record.attemptID

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: oldSaveRoot)
            try? FileManager.default.removeItem(at: newSaveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)

        bundle.store.redownloadTorrent(id: record.id, toSaveLocation: newSaveRoot, bookmarkData: nil)

        let didStart = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            bundle.store.torrents.first?.persistentIssue == nil
        }

        XCTAssertTrue(didStart)
        let updatedRecord = try XCTUnwrap(bundle.store.torrents.first)
        XCTAssertEqual(updatedRecord.canonicalSavePath, newSaveRoot.path)
        XCTAssertNotEqual(updatedRecord.attemptID, oldAttemptID)
        XCTAssertEqual(updatedRecord.status, .downloading)
        XCTAssertEqual(updatedRecord.progress, 0)
        XCTAssertEqual(updatedRecord.lastKnownProgress, 0)

        let restoreEntries = await engine.recordedRestoreSessionEntries()
        XCTAssertEqual(restoreEntries.count, 1)
        XCTAssertEqual(restoreEntries.first?.suggestedSavePath, newSaveRoot.path)
        XCTAssertEqual(restoreEntries.first?.selectedFileIndices, record.selectedFileIndices)
    }

    func testSavePathUnavailableRedownloadToAnotherFolderFailureKeepsOldIssueAndPath() async throws {
        let engine = FakeTorrentEngine()
        await engine.setRestoreSessionErrors([
            TorrentEngineError(kind: .engineFailure, debugReason: "restore failed")
        ])

        let oldSaveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OldFailedSavePath-\(UUID().uuidString)", isDirectory: true)
        let newSaveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewFailedSavePath-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: newSaveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            savePath: oldSaveRoot.path,
            status: .error,
            progress: 0.42,
            persistentIssue: TorrentPersistentIssue(
                kind: .savePathUnavailable,
                detectedAt: Date(),
                statusBeforeIssue: .downloading,
                debugReason: "External disk unavailable"
            )
        )
        let oldAttemptID = record.attemptID

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: oldSaveRoot)
            try? FileManager.default.removeItem(at: newSaveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)

        bundle.store.redownloadTorrent(id: record.id, toSaveLocation: newSaveRoot, bookmarkData: nil)

        let didAttemptRestore = await waitForAsyncCondition(timeoutNanoseconds: 2_000_000_000) {
            await engine.restoreSessionCallCount() == 1
        }

        XCTAssertTrue(didAttemptRestore)
        let updatedRecord = try XCTUnwrap(bundle.store.torrents.first)
        XCTAssertEqual(updatedRecord.persistentIssue?.kind, .savePathUnavailable)
        XCTAssertEqual(updatedRecord.canonicalSavePath, oldSaveRoot.path)
        XCTAssertEqual(updatedRecord.attemptID, oldAttemptID)
    }

    func testBootstrapRestoreFailureForOneActiveTorrentDoesNotBlockHealthyRestore() async throws {
        let engine = FakeTorrentEngine()
        await engine.setRestoreSessionErrors([
            TorrentEngineError(kind: .invalidTorrentFile, debugReason: "broken archive")
        ])

        let firstSaveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoreFailureA-\(UUID().uuidString)", isDirectory: true)
        let secondSaveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoreFailureB-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: firstSaveRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSaveRoot, withIntermediateDirectories: true)

        let failedRecord = makeTestRecord(
            infoHash: "failed-restore",
            savePath: firstSaveRoot.path,
            status: .downloading,
            progress: 0.31
        )
        let healthyRecord = makeTestRecord(
            infoHash: "healthy-restore",
            savePath: secondSaveRoot.path,
            status: .downloading,
            progress: 0.67
        )
        await engine.setRestoreSnapshot(
            EngineTorrentSnapshot(
                id: healthyRecord.id,
                status: .downloading,
                progress: 0.67,
                metrics: TorrentMetrics(),
                errorState: nil,
                resumeDataStatus: .loaded
            ),
            for: healthyRecord.id
        )

        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: firstSaveRoot)
            try? FileManager.default.removeItem(at: secondSaveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        try Data("partial payload".utf8).write(
            to: firstSaveRoot.appendingPathComponent("test-file.bin", isDirectory: false),
            options: .atomic
        )
        try Data("partial payload".utf8).write(
            to: secondSaveRoot.appendingPathComponent("test-file.bin", isDirectory: false),
            options: .atomic
        )

        let failedArchiveURL = try await bundle.archiveStore.destinationURL(for: failedRecord.id)
        try Data("failed archive".utf8).write(to: failedArchiveURL, options: .atomic)
        let healthyArchiveURL = try await bundle.archiveStore.destinationURL(for: healthyRecord.id)
        try Data("healthy archive".utf8).write(to: healthyArchiveURL, options: .atomic)

        await bundle.sessionStore.saveCriticalState(from: [failedRecord, healthyRecord])

        bundle.store.bootstrapRuntimeState()

        let finishedBootstrap = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            !bundle.store.isRestoringSession && bundle.store.torrents.count == 2
        }
        XCTAssertTrue(finishedBootstrap)

        let recordsByID = Dictionary(uniqueKeysWithValues: bundle.store.torrents.map { ($0.id, $0) })
        XCTAssertEqual(recordsByID[failedRecord.id]?.status, .stopped)
        XCTAssertNil(recordsByID[failedRecord.id]?.errorState)
        XCTAssertEqual(recordsByID[healthyRecord.id]?.status, .downloading)
    }

    func testBootstrapStaleRestoreSnapshotDoesNotDropDurableProgressAndForcesRecheck() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("StaleRestore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            infoHash: "stale-restore",
            savePath: saveRoot.path,
            status: .downloading,
            progress: 0.36
        )
        await engine.setRestoreSnapshot(
            EngineTorrentSnapshot(
                id: record.id,
                status: .downloading,
                progress: 0.01,
                metrics: TorrentMetrics(),
                errorState: nil,
                resumeDataStatus: .loaded
            ),
            for: record.id
        )

        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        try Data("partial payload".utf8).write(
            to: saveRoot.appendingPathComponent("test-file.bin", isDirectory: false),
            options: .atomic
        )
        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        await bundle.sessionStore.saveCriticalState(from: [record])

        bundle.store.bootstrapRuntimeState()

        let didForceRecheck = await waitForAsyncCondition(timeoutNanoseconds: 2_000_000_000) {
            await engine.recordedRecheckCallIDs() == [record.id]
        }

        XCTAssertTrue(didForceRecheck)
        XCTAssertEqual(bundle.store.torrents.first?.status, .checking)
        XCTAssertEqual(bundle.store.torrents.first?.progress, 0.36)
        XCTAssertEqual(bundle.store.torrents.first?.lastKnownProgress, 0.36)
    }

    func testBootstrapMissingArchivedTorrentFallsBackToDetachedStatus() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingArchiveBootstrap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            infoHash: "missing-archive-bootstrap",
            savePath: saveRoot.path,
            status: .downloading,
            progress: 0.48
        )

        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        await bundle.sessionStore.saveCriticalState(from: [record])

        bundle.store.bootstrapRuntimeState()

        let finishedBootstrap = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            !bundle.store.isRestoringSession && bundle.store.torrents.count == 1
        }
        XCTAssertTrue(finishedBootstrap)
        XCTAssertEqual(bundle.store.torrents.first?.status, .stopped)
        XCTAssertNil(bundle.store.torrents.first?.errorState)
        let restoreCallCount = await engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCallCount, 0)
    }

    func testStartSleepingTorrentWithoutArchivedTorrentShowsRuntimeErrorWithoutRestoreAttempt() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingArchiveStart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            infoHash: "missing-archive-start",
            savePath: saveRoot.path,
            status: .stopped,
            progress: 0.36
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.startTorrent(id: record.id)

        let didApplyError = await waitForCondition {
            bundle.store.torrents.first?.runtimeErrorState?.kind == .torrentNotFound
        }

        XCTAssertTrue(didApplyError)
        let restoreCallCount = await engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCallCount, 0)
    }

    func testForceRecheckWithoutArchivedTorrentShowsRuntimeErrorWithoutRestoreAttempt() async throws {
        let engine = FakeTorrentEngine()
        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingArchiveRecheck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            infoHash: "missing-archive-recheck",
            savePath: saveRoot.path,
            status: .stopped,
            progress: 0.36
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.forceRecheckTorrent(id: record.id)

        let didApplyError = await waitForCondition {
            bundle.store.torrents.first?.runtimeErrorState?.kind == .torrentNotFound
        }

        XCTAssertTrue(didApplyError)
        let restoreCallCount = await engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCallCount, 0)
    }

    func testRedownloadWithoutArchivedTorrentDoesNotCallRestoreSession() async throws {
        let engine = FakeTorrentEngine()
        await engine.setInspectContents([
            TorrentContentFileDescriptor(relativePath: "Episode.mkv", sizeBytes: 1_024, fileIndex: 0),
        ])

        let saveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingArchiveRedownload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)

        let record = makeTestRecord(
            infoHash: "missing-archive-redownload",
            savePath: saveRoot.path,
            status: .error,
            progress: 0.52,
            persistentIssue: TorrentPersistentIssue(
                kind: .missingContent,
                detectedAt: Date(),
                statusBeforeIssue: .downloading,
                debugReason: "missing file"
            )
        )

        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: saveRoot)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.redownloadTorrent(id: record.id)

        let didApplyError = await waitForCondition {
            bundle.store.torrents.first?.runtimeErrorState?.kind == .torrentNotFound
                && bundle.store.torrents.first?.persistentIssue == nil
        }

        XCTAssertTrue(didApplyError)
        let restoreCallCount = await engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCallCount, 0)
    }

    func testCorruptSessionBlocksBootstrapAddingAndAllPersistencePathsWithoutChangingFiles() async throws {
        let engine = FakeTorrentEngine()
        let router = ExternalOpenRouter()
        let bundle = makeTestStoreBundle(
            engine: engine,
            router: router,
            sessionStoreStartupMode: .requiresInitialLoad
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        try bundle.directories.ensureSessionDirectories()
        let corruptSessionData = Data(#"{"schemaVersion":5,"torrents":["# .utf8)
        try corruptSessionData.write(to: bundle.directories.sessionSnapshotURL, options: .atomic)
        let artifactURLs = try writeSafetyTestArtifacts(in: bundle.directories)
        let originalArtifactData = try artifactURLs.map { try Data(contentsOf: $0) }

        let bufferedMagnet = try XCTUnwrap(URL(string: "magnet:?xt=urn:btih:buffered-before-load"))
        router.receive(urls: [bufferedMagnet])
        bundle.store.bootstrapRuntimeState()

        let didReportFailure = await waitForCondition {
            bundle.store.sessionLoadIssue == .unreadable
        }
        XCTAssertTrue(didReportFailure)
        XCTAssertTrue(bundle.store.hasLoadedInitialSession)
        XCTAssertFalse(bundle.store.canAddTorrent)
        let bootCallCount = await engine.bootCallCount()
        XCTAssertEqual(bootCallCount, 0)

        bundle.store.presentAddTorrentEntry()
        bundle.store.continueFromEntry(with: "magnet:?xt=urn:btih:direct-after-load")
        bundle.store.continueFromTorrentFile(at: "/tmp/blocked.torrent")
        bundle.store.handleIncomingURL(try XCTUnwrap(URL(string: "magnet:?xt=urn:btih:external-after-load")))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(bundle.store.presentedModal)
        XCTAssertNil(bundle.store.currentAddTorrentDraft)
        let preparedSources = await engine.recordedPrepareSources()
        let progressSaveOutcome = await bundle.sessionStore.saveProgressBatch(from: [makeTestRecord()])
        XCTAssertTrue(preparedSources.isEmpty)
        XCTAssertEqual(progressSaveOutcome, .blocked)

        await bundle.store.prepareForTermination()

        XCTAssertEqual(try Data(contentsOf: bundle.directories.sessionSnapshotURL), corruptSessionData)
        for (url, originalData) in zip(artifactURLs, originalArtifactData) {
            XCTAssertEqual(try Data(contentsOf: url), originalData)
        }
    }

    func testMissingSnapshotWithRecoveryArtifactsShowsFailureAndDoesNotCreateNewSnapshot() async throws {
        let engine = FakeTorrentEngine()
        let bundle = makeTestStoreBundle(
            engine: engine,
            sessionStoreStartupMode: .requiresInitialLoad
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        try bundle.directories.ensureSessionDirectories()
        let artifactURL = bundle.directories.resumeDataDirectoryURL
            .appendingPathComponent("orphan.fastresume", isDirectory: false)
        let artifactData = Data("resume must survive".utf8)
        try artifactData.write(to: artifactURL, options: .atomic)

        bundle.store.bootstrapRuntimeState()

        let didReportFailure = await waitForCondition {
            bundle.store.sessionLoadIssue == .missingWithRecoveryArtifacts
        }
        XCTAssertTrue(didReportFailure)
        XCTAssertFalse(bundle.store.canAddTorrent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.directories.sessionSnapshotURL.path))
        XCTAssertEqual(try Data(contentsOf: artifactURL), artifactData)
    }

    func testCleanFirstLaunchCompletesBootstrapAndCreatesValidEmptySession() async throws {
        let engine = FakeTorrentEngine()
        let bundle = makeTestStoreBundle(
            engine: engine,
            sessionStoreStartupMode: .requiresInitialLoad
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        XCTAssertFalse(bundle.store.canAddTorrent)
        bundle.store.bootstrapRuntimeState()

        let didBecomeReady = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            bundle.store.canAddTorrent
        }
        XCTAssertTrue(didBecomeReady)
        XCTAssertNil(bundle.store.sessionLoadIssue)
        let bootCallCount = await engine.bootCallCount()
        XCTAssertEqual(bootCallCount, 1)

        let data = try Data(contentsOf: bundle.directories.sessionSnapshotURL)
        let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        XCTAssertEqual(snapshot.schemaVersion, SessionSnapshot.currentSchemaVersion)
        XCTAssertTrue(snapshot.torrents.isEmpty)
    }

    func testTerminationDuringInitialReadWaitsForResultAndNeverOverwritesSession() async throws {
        let reader = SuspendedSessionReader()
        let engine = FakeTorrentEngine()
        let bundle = makeTestStoreBundle(
            engine: engine,
            sessionStoreStartupMode: .requiresInitialLoad,
            sessionReadData: { url in try await reader.read(url) }
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        try bundle.directories.ensureSessionDirectories()
        let corruptSessionData = Data("truncated during launch".utf8)
        try corruptSessionData.write(to: bundle.directories.sessionSnapshotURL, options: .atomic)

        bundle.store.bootstrapRuntimeState()
        let didStartReading = await waitForAsyncCondition { await reader.didStart() }
        XCTAssertTrue(didStartReading)
        XCTAssertFalse(bundle.store.hasLoadedInitialSession)
        XCTAssertFalse(bundle.store.canAddTorrent)

        let terminationTask = Task { @MainActor in
            await bundle.store.prepareForTermination()
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(bundle.store.hasLoadedInitialSession)
        XCTAssertEqual(try Data(contentsOf: bundle.directories.sessionSnapshotURL), corruptSessionData)

        await reader.release()
        await terminationTask.value

        XCTAssertEqual(bundle.store.sessionLoadIssue, .unreadable)
        let bootCallCount = await engine.bootCallCount()
        XCTAssertEqual(bootCallCount, 0)
        XCTAssertEqual(try Data(contentsOf: bundle.directories.sessionSnapshotURL), corruptSessionData)
    }

    private func writeSafetyTestArtifacts(in directories: ShatlDirectories) throws -> [URL] {
        let urls = [
            directories.archivedTorrentsDirectoryURL.appendingPathComponent("orphan.torrent"),
            directories.bookmarksDirectoryURL.appendingPathComponent("orphan.bookmark"),
            directories.resumeDataDirectoryURL.appendingPathComponent("orphan.fastresume"),
        ]
        for (index, url) in urls.enumerated() {
            try Data("artifact-\(index)".utf8).write(to: url, options: .atomic)
        }
        return urls
    }

    private var duplicateDraftReviewState: AddTorrentReviewState {
        .invalid(message: ShatlErrorCatalog.duplicateDraftError(localeOverride: .system).message)
    }
}
