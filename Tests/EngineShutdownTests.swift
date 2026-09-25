// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// Shatl used to exit with libtorrent still running: trackers never heard
/// `stopped`, and its threads met process teardown. A decided quit now stops
/// the engine, within a bound that also holds for logout and restart.
final class EngineShutdownTests: XCTestCase {
    func testFinishingTheQuitStopsTheEngine() async {
        let engine = FakeTorrentEngine()
        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        await bundle.store.finishTermination()

        let shutdownCallCount = await engine.shutdownCallCount()
        XCTAssertEqual(shutdownCallCount, 1)
    }

    func testQuitDoesNotWaitForAStuckEngine() async {
        let engine = FakeTorrentEngine()
        await engine.setHangsOnShutdown(true)
        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        let elapsed = await ContinuousClock().measure {
            await bundle.store.finishTermination(timeout: .milliseconds(200))
        }

        XCTAssertLessThan(elapsed, .seconds(2))
    }

    /// The real bridge: stopping a session with a torrent is quick, and the
    /// stopped engine refuses commands instead of starting a new session.
    func testLibtorrentStopsQuicklyAndStartsNothingAfterwards() async throws {
        let fixture = try EngineFixture.make(named: "Shutdown")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories)
        _ = try await engine.restoreSession([fixture.entry])

        let elapsed = await ContinuousClock().measure {
            await engine.shutdown()
        }

        XCTAssertLessThan(elapsed, .seconds(3))
        do {
            _ = try await engine.fetchActiveSnapshots()
            XCTFail("A stopped engine served snapshots")
        } catch {}
        do {
            _ = try await engine.restoreSession([fixture.entry])
            XCTFail("A stopped engine started a new session")
        } catch {}
        let budget = await engine.resourceBudget()
        XCTAssertNil(budget, "A stopped engine still has a session")
    }
}
