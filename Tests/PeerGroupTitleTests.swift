// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// The cells of seeds and peers follow the numbers at once, and a zero is
/// never shown; the title over them names "Сиды и пиры", "Сиды" or "Пиры"
/// and waits for a change to hold: 3 s for a side to come in, 5 s for it to
/// go.
final class PeerGroupTitleTests: XCTestCase {
    private let start = ContinuousClock.now

    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    func testAFirstSampleIsNamedAtOnce() {
        let title = PeerGroupTitle().following(seeds: 4, peers: 0, at: at(0))
        XCTAssertTrue(title.namesSeeds)
        XCTAssertFalse(title.namesPeers)
    }

    func testASideLeavesTheTitleAfterFiveSecondsAtZero() {
        var title = PeerGroupTitle().following(seeds: 4, peers: 2, at: at(0))
        title = title.following(seeds: 4, peers: 0, at: at(1))
        title = title.following(seeds: 4, peers: 0, at: at(5.9))
        XCTAssertTrue(title.namesPeers, "still named before five seconds")
        title = title.following(seeds: 4, peers: 0, at: at(6))
        XCTAssertTrue(title.namesSeeds)
        XCTAssertFalse(title.namesPeers)
    }

    func testABlinkLeavesTheTitleAlone() {
        var title = PeerGroupTitle().following(seeds: 4, peers: 2, at: at(0))
        title = title.following(seeds: 4, peers: 0, at: at(1))
        title = title.following(seeds: 4, peers: 3, at: at(3))
        title = title.following(seeds: 4, peers: 0, at: at(4))
        title = title.following(seeds: 4, peers: 0, at: at(8))
        XCTAssertTrue(title.namesPeers, "the wait starts again after each return")
    }

    func testASideComesIntoTheTitleAfterThreeSeconds() {
        var title = PeerGroupTitle().following(seeds: 4, peers: 0, at: at(0))
        title = title.following(seeds: 4, peers: 2, at: at(1))
        title = title.following(seeds: 4, peers: 2, at: at(3.9))
        XCTAssertFalse(title.namesPeers)
        title = title.following(seeds: 4, peers: 2, at: at(4))
        XCTAssertTrue(title.namesSeeds)
        XCTAssertTrue(title.namesPeers)
    }

    func testAGroupThatComesBackTakesItsTitleAtOnce() {
        var title = PeerGroupTitle().following(seeds: 4, peers: 0, at: at(0))
        title = title.following(seeds: 0, peers: 0, at: at(1))
        XCTAssertFalse(title.namesSeeds)
        title = title.following(seeds: 0, peers: 3, at: at(2))
        XCTAssertFalse(title.namesSeeds)
        XCTAssertTrue(title.namesPeers)
    }

    /// The group's title follows the settled names, and the cells the
    /// numbers: a zero is never a cell.
    func testTheGroupTitleFollowsTheSettledNames() throws {
        var record = makeTestRecord(status: .downloading, progress: 0.4)
        record.metrics.seeds = 4
        record.metrics.peers = 2
        var levels = TransferSpeedLevels().following(record.metrics, at: at(0))

        func group() throws -> MetricGroupPresentation {
            let groups = TorrentPresentation.expandedMetricGroups(
                for: record,
                mode: .detailed,
                localeOverride: .russian,
                speedLevels: levels
            )
            var group = try XCTUnwrap(groups.dynamicGroups.first { $0.id == "peers" })
            // The typograph binds "и" to the next word.
            group.title = group.title.replacingOccurrences(of: "\u{00A0}", with: " ")
            return group
        }

        XCTAssertEqual(try group().title, "Сиды и пиры")

        record.metrics.peers = 0
        levels = levels.following(record.metrics, at: at(1))
        XCTAssertEqual(try group().items.map(\.id), ["seeds"])
        XCTAssertEqual(try group().title, "Сиды и пиры")

        levels = levels.following(record.metrics, at: at(6))
        XCTAssertEqual(try group().title, "Сиды")

        record.metrics.seeds = 0
        record.metrics.peers = 5
        levels = levels.following(record.metrics, at: at(7))
        XCTAssertEqual(try group().items.map(\.id), ["peers"])
        XCTAssertEqual(try group().title, "Сиды", "the seeds wait five seconds to leave")
        levels = levels.following(record.metrics, at: at(10))
        XCTAssertEqual(try group().title, "Сиды и пиры")
        levels = levels.following(record.metrics, at: at(12))
        XCTAssertEqual(try group().title, "Пиры")
    }
}
