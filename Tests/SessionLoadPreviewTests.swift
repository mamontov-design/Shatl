// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

#if DEBUG
/// The Debug menu shows the message for a list saved by another version over
/// the real list. Its "Start with an empty list" must never reach the list.
@MainActor
final class SessionLoadPreviewTests: XCTestCase {
    func testEmptyListButtonOnlyEndsTheDebugPreview() async throws {
        let record = makeTestRecord()
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.bootstrapRuntimeState()
        let finishedBootstrap = await waitForCondition {
            bundle.store.hasLoadedInitialSession && !bundle.store.isRestoringSession
        }
        XCTAssertTrue(finishedBootstrap)

        bundle.store.toggleUnsupportedSessionPreviewForDebug()
        XCTAssertEqual(
            bundle.store.debugSessionLoadIssuePreview,
            .unsupportedVersion(found: SessionSnapshot.currentSchemaVersion + 1)
        )
        XCTAssertNil(bundle.store.sessionLoadIssue)

        bundle.store.openWithEmptyDownloadList()

        XCTAssertNil(bundle.store.debugSessionLoadIssuePreview)
        XCTAssertFalse(bundle.store.isResolvingSessionRecovery)
        XCTAssertEqual(bundle.store.torrents.map(\.id), [record.id])
    }

    func testMenuItemEndsThePreviewToo() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: [makeTestRecord()])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.bootstrapRuntimeState()
        let finishedBootstrap = await waitForCondition {
            bundle.store.hasLoadedInitialSession && !bundle.store.isRestoringSession
        }
        XCTAssertTrue(finishedBootstrap)

        bundle.store.toggleUnsupportedSessionPreviewForDebug()
        XCTAssertNotNil(bundle.store.debugSessionLoadIssuePreview)
        bundle.store.toggleUnsupportedSessionPreviewForDebug()
        XCTAssertNil(bundle.store.debugSessionLoadIssuePreview)
    }
}
#endif
