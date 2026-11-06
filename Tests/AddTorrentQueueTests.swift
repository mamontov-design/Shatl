// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Combine
import Foundation
import XCTest
@testable import Shatl

/// Several `.torrent` files opened at once wait in one add window, in the
/// order they came: none is lost, "Скачать" shows the next one, and the
/// window closes after the last. Until November 2026 every file but the
/// first was dropped without a word.
@MainActor
final class AddTorrentQueueTests: XCTestCase {
    private func makeBundle(
        router: ExternalOpenRouter? = nil,
        requiresPreparedDrafts: Bool = false
    ) async -> (FakeTorrentEngine, TestStoreBundle) {
        let engine = FakeTorrentEngine()
        await engine.setNamesDraftsBySource(true)
        await engine.setRequiresPreparedDrafts(requiresPreparedDrafts)
        let bundle = if let router {
            makeTestStoreBundle(engine: engine, router: router)
        } else {
            makeTestStoreBundle(engine: engine)
        }
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        return (engine, bundle)
    }

    private func fileURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).torrent")
    }

    private func open(_ names: [String], in store: AppStore) {
        for name in names {
            store.continueFromTorrentFile(at: fileURL(name).path)
        }
    }

    private func waitUntilReady(_ review: AddTorrentReviewModel, count: Int, timeout: UInt64 = 2_000_000_000) async -> Bool {
        await waitForCondition(timeoutNanoseconds: timeout) {
            review.count == count && review.items.allSatisfy { $0.draft.reviewState == .ready }
        }
    }

    private func names(_ review: AddTorrentReviewModel) -> [String] {
        review.items.map(\.draft.originalName)
    }

    // MARK: - Coming in

    func testSeveralFilesOpenedFromFinderWaitInOneWindow() async throws {
        let router = ExternalOpenRouter()
        let (engine, bundle) = await makeBundle(router: router)
        bundle.store.bootstrapRuntimeState()

        router.receive(urls: [fileURL("Alpha"), fileURL("Bravo"), fileURL("Charlie")])

        let review = bundle.store.addTorrentReview
        let isReady = await waitUntilReady(review, count: 3)
        XCTAssertTrue(isReady, "Every file opened together waits in the window")
        XCTAssertEqual(names(review), ["Alpha", "Bravo", "Charlie"])
        XCTAssertEqual(review.position, 1)
        XCTAssertTrue(review.isBatch)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.originalName, "Alpha")
        XCTAssertEqual(bundle.store.presentedModal, .addTorrentReview)
        let readPaths = await engine.recordedPrepareSources().map(\.rawValue)
        XCTAssertEqual(readPaths, ["Alpha", "Bravo", "Charlie"].map { fileURL($0).path })
    }

    func testAFileOpenedWhileTheWindowIsOpenJoinsTheEnd() async throws {
        let (_, bundle) = await makeBundle()
        let review = bundle.store.addTorrentReview
        open(["Alpha"], in: bundle.store)
        let isAlphaReady = await waitUntilReady(review, count: 1)
        XCTAssertTrue(isAlphaReady)
        XCTAssertFalse(review.isBatch)

        open(["Bravo"], in: bundle.store)

        let isReady = await waitUntilReady(review, count: 2)
        XCTAssertTrue(isReady)
        XCTAssertEqual(names(review), ["Alpha", "Bravo"])
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.originalName, "Alpha", "The download on screen stays")
        XCTAssertTrue(review.isBatch)
    }

    /// The window closes a moment after its last download leaves. A file
    /// opened in that moment opens the window anew rather than joining a
    /// queue no window shows.
    func testAFileOpenedAsTheEmptiedWindowClosesOpensItAnew() async throws {
        let (_, bundle) = await makeBundle()
        let review = bundle.store.addTorrentReview
        open(["Alpha"], in: bundle.store)
        let isAlphaReady = await waitUntilReady(review, count: 1)
        XCTAssertTrue(isAlphaReady)
        bundle.store.confirmDraft()
        XCTAssertNil(bundle.store.presentedModal)
        XCTAssertTrue(bundle.store.isAddTorrentReviewWindowActive, "The window is still closing")

        open(["Bravo"], in: bundle.store)

        XCTAssertEqual(bundle.store.presentedModal, .addTorrentReview)
        XCTAssertEqual(review.count, 1)
        XCTAssertFalse(review.isBatch)
        let isReady = await waitUntilReady(review, count: 1)
        XCTAssertTrue(isReady)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.originalName, "Bravo")
    }

    func testTheSameFileTwiceTakesOnePlaceAndIsShown() async throws {
        let (_, bundle) = await makeBundle()
        let review = bundle.store.addTorrentReview
        open(["Alpha", "Bravo", "Alpha"], in: bundle.store)

        let isReady = await waitUntilReady(review, count: 2)
        XCTAssertTrue(isReady)
        XCTAssertEqual(names(review), ["Alpha", "Bravo"])
        XCTAssertEqual(review.position, 1)

        open(["Bravo"], in: bundle.store)
        XCTAssertEqual(review.count, 2)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.originalName, "Bravo")
    }

    // MARK: - Moving between them

    func testArrowsMoveBetweenDownloadsAndStopAtTheEnds() async throws {
        let (_, bundle) = await makeBundle()
        let review = bundle.store.addTorrentReview
        open(["Alpha", "Bravo", "Charlie"], in: bundle.store)
        let isReady = await waitUntilReady(review, count: 3)
        XCTAssertTrue(isReady)

        XCTAssertFalse(review.hasPrevious)
        review.showPrevious()
        XCTAssertEqual(review.position, 1)

        review.showNext()
        review.showNext()
        XCTAssertEqual(review.position, 3)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.originalName, "Charlie")
        XCTAssertFalse(review.hasNext)
        review.showNext()
        XCTAssertEqual(review.position, 3)
    }

    func testEditsStayWithTheirDownload() async throws {
        let (_, bundle) = await makeBundle()
        let review = bundle.store.addTorrentReview
        open(["Alpha", "Bravo"], in: bundle.store)
        let isReady = await waitUntilReady(review, count: 2)
        XCTAssertTrue(isReady)

        bundle.store.updateDraftAlias("First")
        review.showNext()
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.alias, "")
        bundle.store.updateDraftStopAfterDownload(true)
        review.showPrevious()

        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.alias, "First")
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.stopAfterDownload, false)
        XCTAssertEqual(review.items.last?.draft.stopAfterDownload, true)
    }

    // MARK: - Leaving

    func testDownloadingEachShowsTheNextAndClosesTheWindowAfterTheLast() async throws {
        let (_, bundle) = await makeBundle(requiresPreparedDrafts: true)
        let review = bundle.store.addTorrentReview
        open(["Alpha", "Bravo", "Charlie"], in: bundle.store)
        let isReady = await waitUntilReady(review, count: 3)
        XCTAssertTrue(isReady)

        bundle.store.confirmDraft()
        XCTAssertEqual(review.count, 2)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.originalName, "Bravo")
        XCTAssertEqual(bundle.store.presentedModal, .addTorrentReview, "The window stays for the rest")

        bundle.store.confirmDraft()
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.originalName, "Charlie")
        XCTAssertEqual(review.position, 1)
        XCTAssertEqual(review.count, 1)
        XCTAssertTrue(review.isBatch, "The window keeps its count to the last download")

        bundle.store.confirmDraft()
        XCTAssertNil(bundle.store.currentAddTorrentDraft)
        XCTAssertNil(bundle.store.presentedModal)

        let didAddAll = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            bundle.store.torrents.count == 3
        }
        XCTAssertTrue(didAddAll, "Every download kept its prepared metadata until it was added")
        XCTAssertEqual(Set(bundle.store.torrents.map(\.originalName)), ["Alpha", "Bravo", "Charlie"])
    }

    func testDownloadingTheLastInLineShowsTheOneBefore() async throws {
        let (_, bundle) = await makeBundle()
        let review = bundle.store.addTorrentReview
        open(["Alpha", "Bravo", "Charlie"], in: bundle.store)
        let isReady = await waitUntilReady(review, count: 3)
        XCTAssertTrue(isReady)
        review.showNext()
        review.showNext()

        bundle.store.confirmDraft()

        XCTAssertEqual(names(review), ["Alpha", "Bravo"])
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.originalName, "Bravo")
    }

    func testSkippingADownloadLeavesTheOthersAndLetsItsFileGo() async throws {
        let (engine, bundle) = await makeBundle(requiresPreparedDrafts: true)
        let review = bundle.store.addTorrentReview
        open(["Alpha", "Bravo", "Charlie"], in: bundle.store)
        let isReady = await waitUntilReady(review, count: 3)
        XCTAssertTrue(isReady)
        let bravoDraftID = review.items[1].draft.id
        review.showNext()

        bundle.store.skipCurrentDraft()

        XCTAssertEqual(names(review), ["Alpha", "Charlie"])
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.originalName, "Charlie", "The next one is shown")
        let didRelease = await waitForAsyncCondition {
            await !engine.heldPreparedDraftIDs().contains(bravoDraftID)
        }
        XCTAssertTrue(didRelease)
        let held = await engine.heldPreparedDraftIDs()
        XCTAssertEqual(held.count, 2)
        XCTAssertTrue(bundle.store.torrents.isEmpty)

        bundle.store.skipCurrentDraft()
        bundle.store.skipCurrentDraft()
        XCTAssertNil(bundle.store.presentedModal, "The window closes after the last")
    }

    func testClosingTheWindowLetsEveryFileGo() async throws {
        let (engine, bundle) = await makeBundle(requiresPreparedDrafts: true)
        let review = bundle.store.addTorrentReview
        open(["Alpha", "Bravo", "Charlie"], in: bundle.store)
        let isReady = await waitUntilReady(review, count: 3)
        XCTAssertTrue(isReady)

        bundle.store.addTorrentReviewWindowDidClose()

        XCTAssertEqual(review.count, 0)
        XCTAssertFalse(review.isBatch)
        let didRelease = await waitForAsyncCondition {
            await engine.heldPreparedDraftIDs().isEmpty
        }
        XCTAssertTrue(didRelease)
    }

    // MARK: - Many at once

    /// Two hundred files are read one after another, in order, and none of
    /// them off screen draws the add window or the main window.
    func testTwoHundredFilesAreReadWithoutDrawingAWindowForEach() async throws {
        let (engine, bundle) = await makeBundle()
        let review = bundle.store.addTorrentReview
        let names = (1...200).map { String(format: "File%03d", $0) }

        open(names, in: bundle.store)
        XCTAssertEqual(review.count, 200)

        var storePublications = 0
        var reviewPublications = 0
        let storeObservation = bundle.store.objectWillChange.sink { _ in storePublications += 1 }
        let reviewObservation = review.objectWillChange.sink { _ in reviewPublications += 1 }
        defer {
            storeObservation.cancel()
            reviewObservation.cancel()
        }

        let isReady = await waitUntilReady(review, count: 200, timeout: 10_000_000_000)
        XCTAssertTrue(isReady)
        XCTAssertEqual(self.names(review), names)
        let readPaths = await engine.recordedPrepareSources().map(\.rawValue)
        XCTAssertEqual(readPaths, names.map { fileURL($0).path })
        XCTAssertEqual(storePublications, 0, "Files read for the add window drew the main window")
        XCTAssertLessThanOrEqual(reviewPublications, 1, "Only the download on screen is drawn as it is read")
    }
}
