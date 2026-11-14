// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// The cards take their new numbers on five beats a second, each card on
/// its own beat; while the list rushes no card starts a new change, and
/// once it calms down each takes its newest numbers on its beat of the
/// next second. Anything but numbers shows at once. The store has it
/// conduct only from 25 active downloads.
@MainActor
final class TorrentRowUpdateConductorTests: XCTestCase {
    private final class FakeClock {
        let start = ContinuousClock.now
        var now: ContinuousClock.Instant

        init() { now = start }

        func at(_ seconds: Double) {
            now = start + .seconds(seconds)
        }
    }

    private var clock = FakeClock()

    private func removeAfterTheTest(_ bundle: TestStoreBundle) {
        addTeardownBlock { [rootURL = bundle.rootURL] in
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    private func makeConductor() -> TorrentRowUpdateConductor {
        clock = FakeClock()
        let clock = clock
        return TorrentRowUpdateConductor(now: { clock.now }, schedulesWakes: false)
    }

    /// Card states as the store builds them, for `count` downloads.
    private func makeStates(_ count: Int) throws -> [TorrentRowState] {
        let records = (0..<count).map { makeTestRecord(originalName: "Загрузка \($0)", status: .downloading, progress: 0.4) }
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: records)
        removeAfterTheTest(bundle)
        return try records.map { try XCTUnwrap(bundle.store.rowState(for: $0.id)) }
    }

    private func withProgress(_ state: TorrentRowState, _ progress: Double) -> TorrentRowState {
        var state = state
        state.progress = progress
        return state
    }

    /// Steps the clock from `start` to `end` in steps of `step`, asking the
    /// conductor each time, and says when each card took new numbers.
    private func run(
        _ conductor: TorrentRowUpdateConductor,
        models: [TorrentRowPresentationModel],
        from start: Double,
        to end: Double,
        step: Double = 0.005
    ) -> [UUID: Double] {
        var shown = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0.state) })
        var times: [UUID: Double] = [:]
        var time = start
        while time <= end + 0.000_1 {
            clock.at(time)
            conductor.publishDue()
            for model in models where model.state != shown[model.id] {
                shown[model.id] = model.state
                times[model.id] = times[model.id] ?? time
            }
            time += step
        }
        return times
    }

    func testNewNumbersWaitForTheCardsPointAndAreTheNewest() throws {
        let conductor = makeConductor()
        let state = try XCTUnwrap(makeStates(1).first)
        let model = TorrentRowPresentationModel(state: state)
        conductor.arrange([state.id])

        clock.at(0.2)
        conductor.offer(withProgress(state, 0.41), to: model)
        XCTAssertEqual(model.state.progress, 0.4, "Numbers wait for the card's beat")
        XCTAssertEqual(conductor.waitingCount, 1)
        // Newer numbers replace the waiting ones.
        clock.at(0.5)
        conductor.offer(withProgress(state, 0.42), to: model)

        let times = run(conductor, models: [model], from: 0.5, to: 2)
        XCTAssertEqual(model.state.progress, 0.42)
        XCTAssertEqual(conductor.waitingCount, 0)
        let shownAt = try XCTUnwrap(times[state.id])
        XCTAssertLessThan(shownAt, 1.25, "Within a second of the first numbers")
    }

    func testAnythingButNumbersShowsAtOnceWithTheNewestNumbers() throws {
        let conductor = makeConductor()
        let state = try XCTUnwrap(makeStates(1).first)
        let model = TorrentRowPresentationModel(state: state)
        conductor.arrange([state.id])

        conductor.offer(withProgress(state, 0.41), to: model)
        var stopped = withProgress(state, 0.42)
        stopped.status = .stopped
        conductor.offer(stopped, to: model)

        XCTAssertEqual(model.state, stopped)
        XCTAssertEqual(conductor.waitingCount, 0)
    }

    func testNumbersBackToWhatTheCardShowsWaitForNothing() throws {
        let conductor = makeConductor()
        let state = try XCTUnwrap(makeStates(1).first)
        let model = TorrentRowPresentationModel(state: state)
        conductor.arrange([state.id])

        conductor.offer(withProgress(state, 0.41), to: model)
        conductor.offer(state, to: model)
        XCTAssertEqual(conductor.waitingCount, 0)
    }

    /// Five cards with new numbers in the same moment take them one after
    /// another, spread evenly over the second, in an order of their own.
    func testCardsTakeTheirNumbersOneAfterAnotherOverTheSecond() throws {
        let conductor = makeConductor()
        let states = try makeStates(5)
        let models = states.map { TorrentRowPresentationModel(state: $0) }
        conductor.arrange(states.map(\.id))

        clock.at(3.03)
        for (state, model) in zip(states, models) {
            conductor.offer(withProgress(state, 0.41), to: model)
        }
        let times = run(conductor, models: models, from: 3.03, to: 5)

        XCTAssertEqual(times.count, 5)
        let sorted = times.values.sorted()
        XCTAssertLessThan(try XCTUnwrap(sorted.last) - 3.03, 1.0 + 0.01, "All within the second")
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            XCTAssertEqual(later - earlier, 0.2, accuracy: 0.011, "A fifth of a second apart")
        }
    }

    /// Twelve cards take their numbers on five beats, two or three a beat:
    /// five updates a second, not twelve.
    func testManyCardsShareFiveBeatsASecond() throws {
        let conductor = makeConductor()
        let states = try makeStates(12)
        let models = states.map { TorrentRowPresentationModel(state: $0) }
        conductor.arrange(states.map(\.id))

        clock.at(7.01)
        for (state, model) in zip(states, models) {
            conductor.offer(withProgress(state, 0.41), to: model)
        }
        let times = run(conductor, models: models, from: 7.01, to: 9)

        XCTAssertEqual(times.count, 12)
        let beats = Dictionary(grouping: times.values) { ($0 * 1_000).rounded() }
        XCTAssertEqual(beats.count, 5)
        XCTAssertEqual(beats.values.map(\.count).sorted(), [2, 2, 2, 3, 3])
        let sorted = beats.keys.sorted()
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            XCTAssertEqual((later - earlier) / 1_000, 0.2, accuracy: 0.011)
        }
    }

    func testWhileTheListMovesFastNoCardStartsAChange() throws {
        let conductor = makeConductor()
        let states = try makeStates(4)
        let models = states.map { TorrentRowPresentationModel(state: $0) }
        conductor.arrange(states.map(\.id))

        conductor.setListMovesFast(true)
        clock.at(0.1)
        for (state, model) in zip(states, models) {
            conductor.offer(withProgress(state, 0.41), to: model)
        }
        XCTAssertTrue(run(conductor, models: models, from: 0.1, to: 3).isEmpty, "Nothing while fast")

        // A newer second while still fast: the newest numbers wait.
        for (state, model) in zip(states, models) {
            conductor.offer(withProgress(state, 0.43), to: model)
        }
        clock.at(3.4)
        conductor.setListMovesFast(false)
        let times = run(conductor, models: models, from: 3.4, to: 5)

        XCTAssertEqual(times.count, 4)
        XCTAssertTrue(models.allSatisfy { $0.state.progress == 0.43 }, "The newest numbers, not the first held")
        let sorted = times.values.sorted()
        XCTAssertLessThan(try XCTUnwrap(sorted.last) - 3.4, 1.0 + 0.01)
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            XCTAssertEqual(later - earlier, 0.25, accuracy: 0.011, "Not in one volley")
        }
    }

    func testAStatusChangeShowsAtOnceEvenWhileTheListMovesFast() throws {
        let conductor = makeConductor()
        let state = try XCTUnwrap(makeStates(1).first)
        let model = TorrentRowPresentationModel(state: state)
        conductor.arrange([state.id])
        conductor.setListMovesFast(true)

        var stopped = withProgress(state, 0.41)
        stopped.status = .stopped
        conductor.offer(stopped, to: model)
        XCTAssertEqual(model.state, stopped)
    }

    func testCardsThatLeaveStopWaiting() throws {
        let conductor = makeConductor()
        let states = try makeStates(2)
        let models = states.map { TorrentRowPresentationModel(state: $0) }
        conductor.arrange(states.map(\.id))
        for (state, model) in zip(states, models) {
            conductor.offer(withProgress(state, 0.41), to: model)
        }
        XCTAssertEqual(conductor.waitingCount, 2)

        conductor.arrange([states[0].id])
        XCTAssertEqual(conductor.waitingCount, 1)
    }

    func testWithoutSpreadingEveryStateShowsAtOnce() throws {
        let conductor = TorrentRowUpdateConductor(spreadsNumbers: false, schedulesWakes: false)
        let state = try XCTUnwrap(makeStates(1).first)
        let model = TorrentRowPresentationModel(state: state)
        conductor.offer(withProgress(state, 0.41), to: model)
        XCTAssertEqual(model.state.progress, 0.41)
    }

    /// Switched off, the conductor lets the waiting cards take their numbers
    /// at once, and shows every new state at once.
    func testSwitchedOffTheWaitingCardsTakeTheirNumbersAtOnce() throws {
        let conductor = makeConductor()
        let states = try makeStates(3)
        let models = states.map { TorrentRowPresentationModel(state: $0) }
        conductor.arrange(states.map(\.id))
        for (state, model) in zip(states, models) {
            conductor.offer(withProgress(state, 0.41), to: model)
        }
        XCTAssertEqual(conductor.waitingCount, 3)

        conductor.setConducting(false)
        XCTAssertEqual(conductor.waitingCount, 0)
        XCTAssertTrue(models.allSatisfy { $0.state.progress == 0.41 })

        conductor.offer(withProgress(states[0], 0.42), to: models[0])
        XCTAssertEqual(models[0].state.progress, 0.42)
    }

    private func applyProgress(_ progress: Double, to record: TorrentRecord, in store: AppStore) {
        var metrics = record.metrics
        metrics.downloadSpeedBytesPerSecond = 3 * 1_024 * 1_024
        metrics.etaSeconds = 600
        store.applySnapshotsForTesting([
            EngineTorrentSnapshot(id: record.id, status: .downloading, progress: progress, metrics: metrics, errorState: nil),
        ])
    }

    /// Below the second level of simplification the store shows new numbers
    /// at once, as before the conductor.
    func testWithFewDownloadsTheStoreShowsNewNumbersAtOnce() throws {
        let record = makeTestRecord(status: .downloading, progress: 0.4)
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: [record], spreadsCardNumbers: true)
        removeAfterTheTest(bundle)
        let model = try XCTUnwrap(bundle.store.torrentRowPresentationModel(for: record.id))

        applyProgress(0.45, to: record, in: bundle.store)
        XCTAssertFalse(bundle.store.rowUpdateConductor.isConducting)
        XCTAssertEqual(model.state.progress, 0.45)
    }

    /// From 25 active downloads the store hands the cards' new numbers to
    /// the conductor: a card shows them within a second of the snapshot, not
    /// in the same moment.
    func testFrom25DownloadsTheStoreSpreadsNewNumbersOverTheSecond() async throws {
        let records = (0..<25).map { makeTestRecord(originalName: "Загрузка \($0)", status: .downloading, progress: 0.4) }
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: records, spreadsCardNumbers: true)
        removeAfterTheTest(bundle)
        let model = try XCTUnwrap(bundle.store.torrentRowPresentationModel(for: records[0].id))

        applyProgress(0.45, to: records[0], in: bundle.store)
        XCTAssertEqual(bundle.store.cardSimplification, .lightest)
        XCTAssertTrue(bundle.store.rowUpdateConductor.isConducting)
        XCTAssertEqual(model.state.progress, 0.4, "Not in the same moment")

        let shown = await waitForCondition(timeoutNanoseconds: 1_500_000_000) {
            model.state.progress == 0.45
        }
        XCTAssertTrue(shown, "Within a second")
        XCTAssertNotNil(model.state.compactTransferMetricSet)
    }
}
