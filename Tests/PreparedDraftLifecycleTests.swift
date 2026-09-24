// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// The engine keeps the metadata of every prepared draft until the store
/// releases it. These tests prove that nothing stays behind after Review
/// closes or an addition finishes, and that Confirm keeps the metadata alive
/// until add and export are done.
@MainActor
final class PreparedDraftLifecycleTests: XCTestCase {
    func testClosingReviewReleasesPreparedDraft() async throws {
        let (engine, bundle) = await makeStrictBundle()

        bundle.store.continueFromTorrentFile(at: "/tmp/closed.torrent")
        let draftID = try await readyDraftID(in: bundle.store)
        let heldWhileOpen = await engine.heldPreparedDraftIDs()
        XCTAssertEqual(heldWhileOpen, [draftID])

        bundle.store.addTorrentReviewWindowDidClose()

        let didRelease = await waitForAsyncCondition {
            await engine.heldPreparedDraftIDs().isEmpty
        }
        XCTAssertTrue(didRelease)
    }

    func testConfirmedDraftIsHeldUntilAdditionFinishes() async throws {
        let (engine, bundle) = await makeStrictBundle()
        await engine.setAddSuspended(true)

        bundle.store.continueFromTorrentFile(at: "/tmp/confirmed.torrent")
        let draftID = try await readyDraftID(in: bundle.store)
        bundle.store.confirmDraft()
        XCTAssertNil(bundle.store.currentAddTorrentDraft)

        let didStartAdd = await waitForAsyncCondition {
            await engine.addCallCount() == 1
        }
        XCTAssertTrue(didStartAdd)
        // Closing Review on Confirm must not take the metadata from the addition.
        try? await Task.sleep(for: .milliseconds(50))
        let heldDuringAdd = await engine.heldPreparedDraftIDs()
        XCTAssertEqual(heldDuringAdd, [draftID])

        await engine.setAddSuspended(false)
        let didAdd = await waitForCondition {
            bundle.store.torrents.count == 1
        }
        XCTAssertTrue(didAdd, "Add or export lost the draft metadata")
        let didRelease = await waitForAsyncCondition {
            await engine.heldPreparedDraftIDs().isEmpty
        }
        XCTAssertTrue(didRelease)
    }

    func testFailedAdditionReleasesPreparedDraft() async throws {
        let (engine, bundle) = await makeStrictBundle()
        await engine.setAddError(TorrentEngineError(kind: .engineFailure, debugReason: "add failed"))

        bundle.store.continueFromTorrentFile(at: "/tmp/failed.torrent")
        _ = try await readyDraftID(in: bundle.store)
        bundle.store.confirmDraft()

        let didFail = await waitForAsyncCondition {
            await engine.addCallCount() == 1
        }
        XCTAssertTrue(didFail)
        let didRelease = await waitForAsyncCondition {
            await engine.heldPreparedDraftIDs().isEmpty
        }
        XCTAssertTrue(didRelease)
        XCTAssertTrue(bundle.store.torrents.isEmpty)
    }

    func testDuplicateDraftReleasesPreparedMetadata() async throws {
        let existingRecord = makeTestRecord(infoHash: "test-info-hash", status: .stopped, progress: 0)
        let (engine, bundle) = await makeStrictBundle(torrents: [existingRecord])

        bundle.store.continueFromTorrentFile(at: "/tmp/duplicate.torrent")

        let didShowDuplicate = await waitForCondition {
            bundle.store.currentAddTorrentDraft?.errorState?.kind == .duplicateTorrent
        }
        XCTAssertTrue(didShowDuplicate)
        let createdDraftIDs = await engine.createdPreparedDraftIDs()
        XCTAssertEqual(createdDraftIDs.count, 1)
        let didRelease = await waitForAsyncCondition {
            await engine.heldPreparedDraftIDs().isEmpty
        }
        XCTAssertTrue(didRelease)
    }

    func testDraftPreparedAfterReviewClosedIsReleased() async throws {
        let (engine, bundle) = await makeStrictBundle()
        await engine.setPrepareSuspended(true)

        bundle.store.continueFromTorrentFile(at: "/tmp/late.torrent")
        let didStartPrepare = await waitForAsyncCondition {
            await engine.recordedPrepareSources().count == 1
        }
        XCTAssertTrue(didStartPrepare)

        bundle.store.addTorrentReviewWindowDidClose()
        await engine.setPrepareSuspended(false)

        let didPrepareAndRelease = await waitForAsyncCondition {
            let created = await engine.createdPreparedDraftIDs()
            let held = await engine.heldPreparedDraftIDs()
            return created.count == 1 && held.isEmpty
        }
        XCTAssertTrue(didPrepareAndRelease)
        XCTAssertNil(bundle.store.currentAddTorrentDraft)
    }

    func testRetryReleasesReplacedDraft() async throws {
        let (engine, bundle) = await makeStrictBundle()

        bundle.store.continueFromTorrentFile(at: "/tmp/retry.torrent")
        let firstDraftID = try await readyDraftID(in: bundle.store)

        bundle.store.retryCurrentDraftPreparation()
        let didReplace = await waitForCondition {
            guard let draft = bundle.store.currentAddTorrentDraft else { return false }
            return draft.reviewState == .ready && draft.id != firstDraftID
        }
        XCTAssertTrue(didReplace)
        let secondDraftID = try XCTUnwrap(bundle.store.currentAddTorrentDraft?.id)

        let didReleaseFirst = await waitForAsyncCondition {
            await engine.heldPreparedDraftIDs() == [secondDraftID]
        }
        XCTAssertTrue(didReleaseFirst)
    }

    private func makeStrictBundle(
        torrents: [TorrentRecord] = []
    ) async -> (FakeTorrentEngine, TestStoreBundle) {
        let engine = FakeTorrentEngine()
        await engine.setRequiresPreparedDrafts(true)
        let bundle = makeTestStoreBundle(engine: engine, torrents: torrents)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        return (engine, bundle)
    }

    private func readyDraftID(in store: AppStore) async throws -> UUID {
        let isReady = await waitForCondition {
            store.currentAddTorrentDraft?.reviewState == .ready
        }
        XCTAssertTrue(isReady)
        return try XCTUnwrap(store.currentAddTorrentDraft?.id)
    }
}
