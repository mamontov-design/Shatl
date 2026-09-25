// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// The 1 Hz tick used to rebuild every card and, for each one, scan the whole
/// list three times: 1000 downloads cost about 107 ms of the main thread per
/// second in an optimized build. Cards are now rebuilt only when their inputs
/// change, and lookups by ID use an index.
final class TorrentRowCacheTests: XCTestCase {
    func testOneActiveDownloadRebuildsOnlyItsCard() {
        let (store, activeID) = makeStore(count: 1_000)
        let buildsBefore = store.recordRowStateBuildCountForTesting

        store.applySnapshotsForTesting([downloadingSnapshot(id: activeID, tick: 1)])
        store.applySnapshotsForTesting([downloadingSnapshot(id: activeID, tick: 2)])

        XCTAssertEqual(store.recordRowStateBuildCountForTesting - buildsBefore, 2)
        XCTAssertEqual(store.torrentRowPresentationModel(for: activeID)?.state, store.rowState(for: activeID))
    }

    func testSelectionAndExpansionRebuildOnlyTheCardsTheyTouch() {
        let (store, activeID) = makeStore(count: 1_000)
        let otherID = store.torrents[500].id
        let buildsBefore = store.recordRowStateBuildCountForTesting

        store.selectedTorrentID = activeID
        store.selectedTorrentID = otherID
        store.expandedTorrentID = otherID

        XCTAssertEqual(store.recordRowStateBuildCountForTesting - buildsBefore, 4)
    }

    func testSharedSettingRebuildsEveryCard() {
        let (store, _) = makeStore(count: 1_000)
        let buildsBefore = store.recordRowStateBuildCountForTesting

        store.preferences.metricsMode = store.preferences.metricsMode == .simplified ? .detailed : .simplified

        XCTAssertEqual(store.recordRowStateBuildCountForTesting - buildsBefore, 1_000)
    }

    /// Guards the cache: after every kind of change each card equals a card
    /// built from scratch. A missed input would leave a stale card, for
    /// example a Start button that never turns back on.
    func testCachedCardsMatchCardsBuiltFromScratch() async {
        let records = [
            makeTestRecord(originalName: "Downloading", status: .downloading, progress: 0.2),
            makeTestRecord(originalName: "Seeding", status: .seeding, progress: 1),
            makeTestRecord(originalName: "Stopped", status: .stopped, progress: 0.5),
            makeTestRecord(originalName: "Completed", status: .completed, progress: 1),
            makeTestRecord(
                originalName: "Broken",
                status: .error,
                progress: 0.3,
                runtimeErrorState: ShatlErrorCatalog.runtimeSnapshotError(debugReason: "test")
            ),
        ]
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: records)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }
        let store = bundle.store
        let downloadingID = records[0].id
        let stoppedID = records[2].id

        assertCardsAreFresh(store, "initial")

        store.applySnapshotsForTesting([downloadingSnapshot(id: downloadingID, tick: 1)])
        assertCardsAreFresh(store, "tick")
        store.selectedTorrentID = stoppedID
        assertCardsAreFresh(store, "selection")
        store.expandedTorrentID = downloadingID
        assertCardsAreFresh(store, "expansion")
        store.preferences.metricsMode = store.preferences.metricsMode == .simplified ? .detailed : .simplified
        assertCardsAreFresh(store, "metrics mode")
        store.preferences.colorizesDownloadSpeed.toggle()
        assertCardsAreFresh(store, "speed colors")
        store.preferences.localeOverride = store.preferences.localeOverride == .english ? .russian : .english
        assertCardsAreFresh(store, "language")
        store.isRestoringSession = true
        assertCardsAreFresh(store, "restoring")
        store.isRestoringSession = false
        assertCardsAreFresh(store, "restored")

        store.stopTorrent(id: downloadingID)
        XCTAssertEqual(store.torrentRowPresentationModel(for: downloadingID)?.state.canToggleRunningState, false)
        assertCardsAreFresh(store, "stop in progress")
        let didFinishStop = await waitForCondition { store.transitioningTorrentIDs.isEmpty }
        XCTAssertTrue(didFinishStop)
        assertCardsAreFresh(store, "stop finished")

        store.torrents.removeAll { $0.id == stoppedID }
        assertCardsAreFresh(store, "removal")
        XCTAssertNil(store.torrentRowPresentationModel(for: stoppedID))
    }

    /// 1000 and 2000 downloads: the tick must grow with the list at most
    /// linearly. Quadratic growth made 2000 about 400 times dearer than 100.
    func testTickCostGrowsLinearlyWithTheList() {
        let smallCost = minimumTickCost(count: 100)
        let largeCost = minimumTickCost(count: 2_000)

        XCTAssertLessThan(
            largeCost / max(smallCost, 0.000_001),
            60,
            "100 downloads: \(smallCost * 1_000) ms, 2000 downloads: \(largeCost * 1_000) ms"
        )
    }

    // MARK: - Helpers

    private func makeStore(count: Int) -> (AppStore, UUID) {
        var records = (1..<count).map {
            makeTestRecord(originalName: "Stopped \($0)", status: .stopped, progress: 0.5)
        }
        let active = makeTestRecord(originalName: "Active", status: .downloading, progress: 0.1)
        records.insert(active, at: 0)
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: records)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }
        return (bundle.store, active.id)
    }

    private func downloadingSnapshot(id: UUID, tick: Int) -> EngineTorrentSnapshot {
        var metrics = TorrentMetrics()
        metrics.downloadSpeedBytesPerSecond = 1_000_000 + Int64(tick) * 1_000
        metrics.etaSeconds = 3_600 - tick
        metrics.totalBytes = 1_000_000_000
        metrics.selectedBytes = 1_000_000_000
        return EngineTorrentSnapshot(
            id: id,
            status: .downloading,
            progress: 0.1 + Double(tick) * 0.0001,
            metrics: metrics,
            errorState: nil
        )
    }

    /// The fastest of several ticks is the steadiest measure on a busy Mac.
    private func minimumTickCost(count: Int) -> Double {
        let (store, activeID) = makeStore(count: count)
        let clock = ContinuousClock()
        return (1...9).map { tick in
            let duration = clock.measure {
                store.applySnapshotsForTesting([downloadingSnapshot(id: activeID, tick: tick)])
            }
            return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }.min() ?? 0
    }

    private func assertCardsAreFresh(
        _ store: AppStore,
        _ step: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for record in store.torrents {
            XCTAssertEqual(
                store.torrentRowPresentationModel(for: record.id)?.state,
                store.rowState(for: record.id),
                "\(step): stale card for \(record.originalName)",
                file: file,
                line: line
            )
        }
    }
}
