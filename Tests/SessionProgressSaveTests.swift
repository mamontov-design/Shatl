// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// Runtime ticks write `session.json` only for durable changes, and a new
/// percent is written at most once per progress save interval.
@MainActor
final class SessionProgressSaveTests: XCTestCase {
    func testIdleTicksDoNotWriteSession() async throws {
        let writer = ControllableSessionDataWriter()
        let stopped = makeTestRecord(status: .stopped, progress: 0.3)
        let completed = makeTestRecord(status: .completed, progress: 1)
        let seeding = makeTestRecord(status: .seeding, progress: 1)
        let engine = FakeTorrentEngine()
        await engine.setHandleActive(true, for: seeding.id)
        let bundle = makeTestStoreBundle(
            engine: engine,
            torrents: [stopped, completed, seeding],
            sessionWriteData: { data, url in try writer.write(data, to: url) },
            progressSaveInterval: .zero
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        for tick in 1...5 {
            var metrics = seeding.metrics
            metrics.uploadSpeedBytesPerSecond = Int64(tick * 1_024)
            metrics.uploadedBytes = Int64(tick * 10_240)
            await engine.enqueueActiveSnapshots([
                EngineTorrentSnapshot(id: seeding.id, status: .seeding, progress: 1, metrics: metrics, errorState: nil),
            ])
            await bundle.store.refreshActiveSnapshotsForTesting()
        }
        await engine.setHandleActive(false, for: seeding.id)
        for _ in 1...5 {
            await bundle.store.refreshActiveSnapshotsForTesting()
        }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(writer.writeCount, 0, "Ticks without durable changes wrote the session")
    }

    func testNewPercentsInsideWindowAreWrittenOnceWithLatestProgress() async throws {
        let writer = ControllableSessionDataWriter()
        let record = makeTestRecord(status: .downloading, progress: 0.10)
        let engine = FakeTorrentEngine()
        await engine.setHandleActive(true, for: record.id)
        let bundle = makeTestStoreBundle(
            engine: engine,
            torrents: [record],
            sessionWriteData: { data, url in try writer.write(data, to: url) },
            progressSaveInterval: .seconds(1)
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        // The first new percent after a quiet period is written right away.
        await tick(bundle, engine, record, progress: 0.11)
        let didWriteFirstPercent = await waitForCondition { writer.writeCount == 1 }
        XCTAssertTrue(didWriteFirstPercent)

        await tick(bundle, engine, record, progress: 0.12)
        await tick(bundle, engine, record, progress: 0.13)
        await tick(bundle, engine, record, progress: 0.14)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(writer.writeCount, 1, "Percents inside the window were written one by one")

        let didWriteWindow = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            writer.writeCount == 2
        }
        XCTAssertTrue(didWriteWindow)
        XCTAssertEqual(try persistedRecord(in: bundle).progress, 0.14)

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(writer.writeCount, 2)
    }

    func testStatusChangeIsWrittenAtOnceInsideProgressWindow() async throws {
        let writer = ControllableSessionDataWriter()
        let record = makeTestRecord(status: .downloading, progress: 0.10)
        let engine = FakeTorrentEngine()
        await engine.setHandleActive(true, for: record.id)
        let bundle = makeTestStoreBundle(
            engine: engine,
            torrents: [record],
            sessionWriteData: { data, url in try writer.write(data, to: url) }
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        await tick(bundle, engine, record, progress: 0.11)
        let didWriteFirstPercent = await waitForCondition { writer.writeCount == 1 }
        XCTAssertTrue(didWriteFirstPercent)
        await tick(bundle, engine, record, progress: 0.12)

        await tick(bundle, engine, record, status: .seeding, progress: 1)

        let didWriteStatus = await waitForCondition { writer.writeCount == 2 }
        XCTAssertTrue(didWriteStatus, "A status change waited for the progress window")
        let persisted = try persistedRecord(in: bundle)
        XCTAssertEqual(persisted.status, .seeding)
        XCTAssertEqual(persisted.progress, 1)
    }

    func testTerminationWritesProgressThatWaitsForWindow() async throws {
        let writer = ControllableSessionDataWriter()
        let record = makeTestRecord(status: .downloading, progress: 0.10)
        let engine = FakeTorrentEngine()
        await engine.setHandleActive(true, for: record.id)
        let bundle = makeTestStoreBundle(
            engine: engine,
            torrents: [record],
            sessionWriteData: { data, url in try writer.write(data, to: url) }
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        await tick(bundle, engine, record, progress: 0.11)
        let didWriteFirstPercent = await waitForCondition { writer.writeCount == 1 }
        XCTAssertTrue(didWriteFirstPercent)
        await tick(bundle, engine, record, progress: 0.12)

        let didPrepare = await bundle.store.prepareForTermination()

        XCTAssertTrue(didPrepare)
        XCTAssertEqual(try persistedRecord(in: bundle).progress, 0.12)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(writer.writeCount, 2)
    }

    private func tick(
        _ bundle: TestStoreBundle,
        _ engine: FakeTorrentEngine,
        _ record: TorrentRecord,
        status: TorrentStatus = .downloading,
        progress: Double
    ) async {
        await engine.enqueueActiveSnapshots([
            EngineTorrentSnapshot(id: record.id, status: status, progress: progress, metrics: record.metrics, errorState: nil),
        ])
        await bundle.store.refreshActiveSnapshotsForTesting()
    }

    private func persistedRecord(in bundle: TestStoreBundle) throws -> SessionTorrentRecord {
        let data = try Data(contentsOf: bundle.directories.sessionSnapshotURL)
        let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        return try XCTUnwrap(snapshot.torrents.first)
    }
}
