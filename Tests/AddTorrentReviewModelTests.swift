// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Combine
import Foundation
import XCTest
@testable import Shatl

/// The add window's draft lives in its own model. What changes while the
/// window is in use — a file read, a file ticked, a letter of the alias —
/// must reach the add window alone: the main window draws its whole list
/// anew on every change the store publishes.
@MainActor
final class AddTorrentReviewModelTests: XCTestCase {
    func testEditingTheDraftReachesTheAddWindowAlone() async throws {
        let bundle = makeBundle(engine: FakeTorrentEngine())

        bundle.store.continueFromTorrentFile(at: "/tmp/quiet.torrent")
        let isReady = await waitForCondition {
            bundle.store.currentAddTorrentDraft?.reviewState == .ready
        }
        XCTAssertTrue(isReady)
        let fileID = try XCTUnwrap(bundle.store.currentAddTorrentDraft?.files.first?.id)

        let counts = PublicationCounts(store: bundle.store)
        defer { counts.cancel() }

        bundle.store.updateDraftAlias("Q")
        bundle.store.updateDraftStopAfterDownload(true)
        bundle.store.setDraftFileSelection(id: fileID, isSelected: false)
        bundle.store.updateDraftSaveLocation(
            URL(fileURLWithPath: "/tmp/elsewhere", isDirectory: true),
            bookmarkData: nil
        )

        XCTAssertEqual(counts.store, 0, "A draft edit drew the main window anew")
        XCTAssertEqual(counts.review, 4)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.alias, "Q")
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.stopAfterDownload, true)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.selectedFileCount, 0)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.suggestedSavePath, "/tmp/elsewhere")
    }

    func testADraftReadWhileTheWindowIsOpenReachesTheAddWindowAlone() async throws {
        let engine = FakeTorrentEngine()
        await engine.setPrepareSuspended(true)
        let bundle = makeBundle(engine: engine)

        bundle.store.continueFromTorrentFile(at: "/tmp/slow.torrent")
        XCTAssertTrue(bundle.store.isAddTorrentReviewWindowActive)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.reviewState, .loadingMetadata)
        let isReading = await waitForAsyncCondition {
            await engine.recordedPrepareSources().count == 1
        }
        XCTAssertTrue(isReading)

        let counts = PublicationCounts(store: bundle.store)
        defer { counts.cancel() }

        await engine.setPrepareSuspended(false)
        let isReady = await waitForCondition {
            bundle.store.currentAddTorrentDraft?.reviewState == .ready
        }

        XCTAssertTrue(isReady)
        XCTAssertEqual(counts.store, 0, "A file read drew the main window anew")
        XCTAssertGreaterThan(counts.review, 0)
    }

    func testUnchangedSelectionPublishesNothing() async throws {
        let bundle = makeBundle(engine: FakeTorrentEngine())

        bundle.store.continueFromTorrentFile(at: "/tmp/same.torrent")
        let isReady = await waitForCondition {
            bundle.store.currentAddTorrentDraft?.reviewState == .ready
        }
        XCTAssertTrue(isReady)
        let draft = try XCTUnwrap(bundle.store.currentAddTorrentDraft)
        let fileID = try XCTUnwrap(draft.files.first?.id)

        let counts = PublicationCounts(store: bundle.store)
        defer { counts.cancel() }

        // The file is ticked already, and the folder holds nothing.
        bundle.store.setDraftFileSelection(id: fileID, isSelected: true)
        bundle.store.setDraftFolderSelection(path: "Missing", isSelected: false)

        XCTAssertEqual(counts.review, 0)
        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.fileSelectionRevision, draft.fileSelectionRevision)
    }

    private func makeBundle(engine: FakeTorrentEngine) -> TestStoreBundle {
        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        return bundle
    }
}

/// Counts what the store and the add window's model publish.
@MainActor
private final class PublicationCounts {
    private(set) var store = 0
    private(set) var review = 0
    private var observations: [AnyCancellable] = []

    init(store appStore: AppStore) {
        observations.append(appStore.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.store += 1 }
        })
        observations.append(appStore.addTorrentReview.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.review += 1 }
        })
    }

    func cancel() {
        observations.forEach { $0.cancel() }
    }
}
