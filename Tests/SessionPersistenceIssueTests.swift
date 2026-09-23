// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

final class SessionPersistenceIssueTests: XCTestCase {
    func testFailedActionShowsAgainAfterHideButBackgroundFailureStaysHidden() async throws {
        let context = try await makeContext(status: .downloading)
        context.writer.setFailsAllWrites(true)

        await context.store.removeTorrent(id: context.record.id, policy: .removeFromListOnly)
        XCTAssertEqual(context.store.sessionPersistenceIssue?.kind, .removeFromList)

        context.store.hideSessionPersistenceIssue()
        XCTAssertNil(context.store.sessionPersistenceIssue)

        await context.engine.setHandleActive(true, for: context.record.id)
        let shouldTerminate = await context.store.prepareForTermination()
        XCTAssertFalse(shouldTerminate)
        XCTAssertNil(context.store.sessionPersistenceIssue)

        await context.store.removeTorrent(id: context.record.id, policy: .removeFromListOnly)
        XCTAssertEqual(context.store.sessionPersistenceIssue?.kind, .removeFromList)
    }

    func testBackgroundFailureKeepsMoreSpecificActionMessage() async throws {
        let context = try await makeContext(status: .downloading)
        context.writer.setFailsAllWrites(true)

        await context.store.removeTorrent(id: context.record.id, policy: .removeFromListAndDeleteFiles)
        await context.engine.setHandleActive(true, for: context.record.id)
        let shouldTerminate = await context.store.prepareForTermination()

        XCTAssertFalse(shouldTerminate)
        XCTAssertEqual(context.store.sessionPersistenceIssue?.kind, .removeWithFiles)
    }

    func testCheckAgainKeepsMessageWhileStorageFailsAndClearsOnceWritable() async throws {
        let context = try await makeContext(status: .stopped)
        context.writer.setFailsAllWrites(true)
        await context.store.removeTorrent(id: context.record.id, policy: .removeFromListOnly)
        let failedIssue = try XCTUnwrap(context.store.sessionPersistenceIssue)

        context.store.recheckSessionPersistence()
        await context.store.waitForSessionPersistenceCheckForTesting()

        XCTAssertEqual(context.store.sessionPersistenceIssue?.kind, .removeFromList)
        XCTAssertNotEqual(context.store.sessionPersistenceIssue?.id, failedIssue.id)

        context.writer.setFailsAllWrites(false)
        context.store.recheckSessionPersistence()
        await context.store.waitForSessionPersistenceCheckForTesting()

        XCTAssertNil(context.store.sessionPersistenceIssue)
        // Check Again only proves storage works; it never repeats the removal.
        XCTAssertEqual(context.store.torrents.map(\.id), [context.record.id])
    }

    func testUnchangedSaveDoesNotHideMessageWhileStorageStillFails() async throws {
        let context = try await makeContext(status: .stopped)
        context.writer.setFailsAllWrites(true)
        await context.store.removeTorrent(id: context.record.id, policy: .removeFromListOnly)
        XCTAssertEqual(context.store.sessionPersistenceIssue?.kind, .removeFromList)

        // Nothing durable changed, so this commit reports success without writing.
        let shouldTerminate = await context.store.prepareForTermination()
        await context.store.waitForSessionPersistenceCheckForTesting()

        XCTAssertTrue(shouldTerminate)
        XCTAssertEqual(context.store.sessionPersistenceIssue?.kind, .removeFromList)
    }

    private struct Context {
        var store: AppStore
        var engine: FakeTorrentEngine
        var writer: ControllableSessionDataWriter
        var record: TorrentRecord
    }

    private func makeContext(status: TorrentStatus) async throws -> Context {
        let engine = FakeTorrentEngine()
        let writer = ControllableSessionDataWriter()
        let record = makeTestRecord(status: status, progress: 0.42)
        let bundle = makeTestStoreBundle(
            engine: engine,
            torrents: [record],
            sessionWriteData: { data, url in
                try writer.write(data, to: url)
            }
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        let initialSaveOutcome = await bundle.sessionStore.replaceAllRecordsForTesting(from: [record])
        XCTAssertEqual(initialSaveOutcome, .saved)
        return Context(store: bundle.store, engine: engine, writer: writer, record: record)
    }
}
