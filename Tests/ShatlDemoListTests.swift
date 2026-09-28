// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// The Debug demo list: every preset plays the same made-up list each time,
/// with the agreed mix of downloads, and its engine keeps them moving without
/// ever finishing one.
final class ShatlDemoListTests: XCTestCase {
    func testPresetsHaveTheirCounts() {
        let counts = ShatlDemoPreset.allCases.map { ($0.activeCount, $0.inactiveCount) }
        XCTAssertEqual(counts.map(\.0), [5, 25, 50, 75, 100, 5, 10, 15, 20])
        XCTAssertEqual(counts.map(\.1), [0, 0, 0, 0, 0, 10, 15, 25, 50])
        XCTAssertEqual(ShatlDemoPreset.mixed10and15.logName, "10+15")
    }

    func testAPresetBuildsTheSameListEveryTime() {
        let first = DemoListFactory.plans(for: .mixed15and25)
        let second = DemoListFactory.plans(for: .mixed15and25)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first.map(\.id), DemoListFactory.plans(for: .mixed10and15).map(\.id))
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
    }

    func testInactiveDownloadsShareOutEvenly() {
        let plans = DemoListFactory.plans(for: .mixed15and25)
        let statuses = Dictionary(grouping: plans, by: \.status).mapValues(\.count)

        XCTAssertEqual(statuses[.downloading], 15)
        XCTAssertEqual(statuses[.seeding], 9)
        XCTAssertEqual(statuses[.completed], 8)
        XCTAssertEqual(statuses[.stopped], 8)
        // Mixed in, not active first and inactive after.
        XCTAssertNotEqual(plans.prefix(15).map(\.status), Array(repeating: .downloading, count: 15))
    }

    func testActiveDownloadsLeaveHoursToGo() {
        for plan in DemoListFactory.plans(for: .active100) {
            let remainingBytes = Double(plan.totalBytes) * (1 - plan.progress)
            XCTAssertGreaterThanOrEqual(remainingBytes / plan.baseDownloadSpeed, 7_200, plan.name)
        }
    }

    func testEngineReportsOnlyActiveDownloadsAndNeverFinishesOne() async {
        let plans = DemoListFactory.plans(for: .mixed10and15)
        let engine = DemoTorrentEngine(plans: plans, seed: 1)
        let activeIDs = Set(plans.filter { $0.status == .downloading || $0.status == .seeding }.map(\.id))

        var sawSpeedLevels: Set<TransferSpeedLevel> = []
        for _ in 0..<600 {
            let snapshots = await engine.advance(bySeconds: 60)
            XCTAssertEqual(Set(snapshots.map(\.id)), activeIDs)
            for snapshot in snapshots where snapshot.status == .downloading {
                XCTAssertLessThan(snapshot.progress, 1)
                XCTAssertGreaterThan(snapshot.metrics.downloadSpeedBytesPerSecond, 0)
                sawSpeedLevels.insert(TransferSpeedLevel(bytesPerSecond: snapshot.metrics.downloadSpeedBytesPerSecond))
            }
        }
        // Speeds waver across several levels, as real ones do.
        XCTAssertGreaterThanOrEqual(sawSpeedLevels.count, 3)
    }

    func testStoppedDownloadStaysStillUntilStarted() async throws {
        let plans = DemoListFactory.plans(for: .mixed5and10)
        let stopped = try XCTUnwrap(plans.first { $0.status == .stopped })
        let engine = DemoTorrentEngine(plans: plans, seed: 1)

        let before = await engine.advance(bySeconds: 1)
        XCTAssertFalse(before.contains { $0.id == stopped.id })

        try await engine.startTorrent(id: stopped.id)
        let after = await engine.advance(bySeconds: 1)
        XCTAssertEqual(after.first { $0.id == stopped.id }?.status, .downloading)
    }
}
