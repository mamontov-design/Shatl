// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// Runs the real libtorrent bridge with magnet links whose metadata never
/// arrives, so the engine stays in the waiting phase for the whole test.
final class LibtorrentEngineMagnetMetadataTests: XCTestCase {
    func testEngineServesOtherCommandsWhileMagnetMetadataIsPending() async throws {
        let fixture = try EngineFixture.make(named: "MagnetBusy")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories, metadataTimeout: .seconds(30))
        _ = try await engine.restoreSession([fixture.entry])

        let magnet = startPreparing(Self.unknownMagnet(), in: engine, fixture: fixture)
        defer { magnet.cancel() }
        let isWaiting = await waitForTemporaryTorrentCount(1, in: engine)
        XCTAssertTrue(isWaiting)

        let elapsed = try await ContinuousClock().measure {
            _ = try await engine.fetchActiveSnapshots()
            try await engine.startTorrent(id: fixture.torrentID)
            try await engine.stopTorrent(id: fixture.torrentID)
            _ = await engine.checkpointTorrents(ids: [fixture.torrentID])
        }

        XCTAssertLessThan(elapsed, .seconds(2), "Engine commands waited for magnet metadata")
    }

    func testCancellationEndsWaitingAndRemovesTemporaryTorrent() async throws {
        let fixture = try EngineFixture.make(named: "MagnetCancel")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories, metadataTimeout: .seconds(30))

        let magnet = startPreparing(Self.unknownMagnet(), in: engine, fixture: fixture)
        let isWaiting = await waitForTemporaryTorrentCount(1, in: engine)
        XCTAssertTrue(isWaiting)

        let clock = ContinuousClock()
        let cancelledAt = clock.now
        magnet.cancel()
        do {
            _ = try await magnet.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)")
        }

        XCTAssertLessThan(clock.now - cancelledAt, .seconds(1))
        let temporaryTorrentCount = await engine.temporaryTorrentCount()
        XCTAssertEqual(temporaryTorrentCount, 0)
    }

    func testTimeoutReportsMetadataTimeoutAndRemovesTemporaryTorrent() async throws {
        let fixture = try EngineFixture.make(named: "MagnetTimeout")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories, metadataTimeout: .milliseconds(700))

        do {
            _ = try await startPreparing(Self.unknownMagnet(), in: engine, fixture: fixture).value
            XCTFail("Expected a metadata timeout")
        } catch {
            XCTAssertEqual((error as? TorrentEngineError)?.kind, .metadataTimeout, "Unexpected error: \(error)")
        }

        let temporaryTorrentCount = await engine.temporaryTorrentCount()
        XCTAssertEqual(temporaryTorrentCount, 0)
    }

    func testReopeningSameMagnetRightAfterCancelIsNotADuplicate() async throws {
        let fixture = try EngineFixture.make(named: "MagnetReopen")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories, metadataTimeout: .seconds(2))
        let source = Self.unknownMagnet()

        let closedReview = startPreparing(source, in: engine, fixture: fixture)
        let isWaiting = await waitForTemporaryTorrentCount(1, in: engine)
        XCTAssertTrue(isWaiting)

        // The reopened review may reach the engine before or after the
        // cleanup of the closed one; both orders must behave the same.
        closedReview.cancel()
        let reopenedReview = startPreparing(source, in: engine, fixture: fixture)

        do {
            _ = try await closedReview.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)")
        }
        let isReopenedWaiting = await waitForTemporaryTorrentCount(1, in: engine)
        XCTAssertTrue(isReopenedWaiting, "The closed review removed the reopened one")

        do {
            _ = try await reopenedReview.value
            XCTFail("Expected a metadata timeout")
        } catch {
            XCTAssertEqual((error as? TorrentEngineError)?.kind, .metadataTimeout, "Unexpected error: \(error)")
        }
        let temporaryTorrentCount = await engine.temporaryTorrentCount()
        XCTAssertEqual(temporaryTorrentCount, 0)
    }

    func testStartingRecordWinsOverPendingMagnetOfSameTorrent() async throws {
        let fixture = try EngineFixture.make(named: "MagnetRecordWins")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories, metadataTimeout: .seconds(30))

        let magnet = startPreparing(fixture.magnetSource, in: engine, fixture: fixture)
        defer { magnet.cancel() }
        let isWaiting = await waitForTemporaryTorrentCount(1, in: engine)
        XCTAssertTrue(isWaiting)

        // Start of a sleeping card restores it into the session.
        let snapshots = try await engine.restoreSession([fixture.entry])
        XCTAssertEqual(snapshots.map(\.id), [fixture.torrentID])

        do {
            _ = try await magnet.value
            XCTFail("Expected the review to report a duplicate")
        } catch {
            XCTAssertEqual((error as? TorrentEngineError)?.kind, .duplicateTorrent, "Unexpected error: \(error)")
        }
        let temporaryTorrentCount = await engine.temporaryTorrentCount()
        XCTAssertEqual(temporaryTorrentCount, 0)
    }

    private func startPreparing(
        _ source: AddTorrentSource,
        in engine: LibtorrentEngine,
        fixture: EngineFixture
    ) -> Task<AddTorrentDraft, Error> {
        Task {
            try await engine.prepareDraft(
                from: source,
                suggestedSavePath: fixture.entry.suggestedSavePath,
                stopAfterDownload: false
            )
        }
    }

    /// A random info hash without trackers: nobody can serve its metadata.
    private static func unknownMagnet() -> AddTorrentSource {
        let infoHash = (0..<20).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        return AddTorrentSource(kind: .magnet, rawValue: "magnet:?xt=urn:btih:\(infoHash)&dn=unknown")
    }

    private func waitForTemporaryTorrentCount(
        _ expectedCount: Int,
        in engine: LibtorrentEngine,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await engine.temporaryTorrentCount() == expectedCount {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}
