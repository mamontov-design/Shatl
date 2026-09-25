// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Darwin
import Foundation
import XCTest
@testable import Shatl

/// Runs the real libtorrent bridge under 256 open files, the soft limit launchd
/// gives a process before AppKit raises it to 2560. Every TCP peer and every
/// open payload file takes one descriptor.
final class LibtorrentEngineOpenFileLimitTests: XCTestCase {
    /// Descriptors Shatl itself and libtorrent's own sockets need beside peer
    /// connections and the file pool: libtorrent alone opens three sockets per
    /// local address, 75 on a Mac with VPN interfaces.
    private let minimumHeadroom = 160

    /// When the process runs out of descriptors, libtorrent cannot open a
    /// payload file, pauses the torrent and reports the error; Shatl shows it
    /// as the engine error card (after relaunch it is «Остановлен», see
    /// `SessionStoreTests`).
    func testRunningOutOfDescriptorsPutsDownloadIntoError() async throws {
        let fixture = try EngineFixture.make(named: "OutOfDescriptors")
        addTeardownBlock { fixture.remove() }
        let bridge = LibtorrentSessionBridge(resumeDataDirectoryURL: fixture.directories.resumeDataDirectoryURL)
        let recordID = fixture.torrentID.uuidString

        // Without fast-resume data the paused torrent waits for a full check,
        // which opens the payload file only after Start.
        _ = try bridge.restoreTorrent(
            withTorrentFilePath: fixture.entry.archivedTorrentPath,
            suggestedSavePath: fixture.entry.suggestedSavePath,
            stopAfterDownload: false,
            selectedFileIndices: [0],
            recordIdentifier: recordID,
            shouldStart: false
        )
        try await Task.sleep(for: .milliseconds(300))

        let exhaustion = try DescriptorExhaustion()
        addTeardownBlock { exhaustion.release() }
        try bridge.startTorrent(withIdentifier: recordID)
        let errorSnapshot = try await firstSnapshot(of: recordID, in: bridge) { $0.status == .error }
        exhaustion.release()

        let snapshot = try XCTUnwrap(errorSnapshot, "The download did not fall into an error")
        XCTAssertEqual(snapshot.errorMessage, "Too many open files")
    }

    func testBootRaisesTheLimitAppsStartWith() throws {
        try setSoftOpenFileLimit(256)
        let bridge = makeBridge()

        try bridge.boot()

        let budget = try XCTUnwrap(bridge.currentResourceBudget())
        XCTAssertEqual(budget.initialOpenFileLimit, 256)
        XCTAssertEqual(budget.openFileLimit, expectedRaisedLimit())
        XCTAssertEqual(currentSoftOpenFileLimit(), expectedRaisedLimit())
    }

    func testBootKeepsAHigherLimit() throws {
        let higherLimit = 20_000
        guard higherLimit <= perProcessOpenFileLimit(), higherLimit <= hardOpenFileLimit() else {
            throw XCTSkip("This Mac does not allow \(higherLimit) open files per process")
        }
        try setSoftOpenFileLimit(higherLimit)
        let bridge = makeBridge()

        try bridge.boot()

        XCTAssertEqual(currentSoftOpenFileLimit(), higherLimit)
    }

    /// libtorrent caps connections to the limit only when the session is
    /// created; a profile switch used to lift the cap to 1000 or 5000.
    func testSessionStaysWithinTheLimitAcrossProfileSwitches() throws {
        try setSoftOpenFileLimit(256)
        let bridge = makeBridge()

        try bridge.boot()
        try assertWithinLimit(bridge)

        for profile: LTPerformanceProfile in [.maximum, .economical, .balanced, .maximum] {
            try bridge.apply(profile)
            try assertWithinLimit(bridge)
        }
    }

    /// A limit that could not be raised still bounds every profile switch.
    func testProfileSwitchFitsALimitThatCouldNotBeRaised() throws {
        try setSoftOpenFileLimit(256)
        let bridge = makeBridge()
        try bridge.boot()
        try setSoftOpenFileLimit(256)

        for profile: LTPerformanceProfile in [.maximum, .balanced, .economical] {
            try bridge.apply(profile)
            let budget = try XCTUnwrap(bridge.currentResourceBudget())
            XCTAssertEqual(budget.openFileLimit, 256)
            try assertWithinLimit(bridge)
        }
    }

    func testRaisedLimitKeepsEveryProfileAsDesigned() throws {
        try setSoftOpenFileLimit(256)
        guard expectedRaisedLimit() >= 10_240 else {
            throw XCTSkip("This Mac does not allow 10 240 open files per process")
        }
        let bridge = makeBridge()
        try bridge.boot()

        let expected: [(LTPerformanceProfile, connections: Int, filePool: Int)] = [
            (.balanced, 1_000, 200),
            (.maximum, 5_000, 400),
            (.economical, 24, 4),
            (.balanced, 1_000, 200),
        ]
        for (index, (profile, connections, filePool)) in expected.enumerated() {
            if index > 0 {
                try bridge.apply(profile)
            }
            let budget = try XCTUnwrap(bridge.currentResourceBudget())
            XCTAssertEqual(budget.connectionsLimit, connections, "profile \(profile.rawValue)")
            XCTAssertEqual(budget.filePoolSize, filePool, "profile \(profile.rawValue)")
            XCTAssertEqual(budget.requestedConnectionsLimit, connections, "profile \(profile.rawValue)")
            XCTAssertEqual(budget.requestedFilePoolSize, filePool, "profile \(profile.rawValue)")
        }
    }

    /// Guards the profile map: a future profile that asks for more than the
    /// limit holds still fits, and the raised limit leaves profiles untouched.
    func testEveryProfileFitsEveryLimit() {
        let profiles: [LTPerformanceProfile] = [.economical, .balanced, .maximum]
        for limit in [256, 512, 1_024, 4_096, 10_240, 1_048_576] {
            for profile in profiles {
                let budget = LibtorrentSessionBridge.resourceBudget(for: profile, openFileLimit: limit)
                let context = "profile \(profile.rawValue), limit \(limit)"
                XCTAssertLessThanOrEqual(
                    budget.connectionsLimit + budget.filePoolSize + minimumHeadroom,
                    limit,
                    context
                )
                XCTAssertLessThanOrEqual(budget.connectionsLimit, budget.requestedConnectionsLimit, context)
                XCTAssertLessThanOrEqual(budget.filePoolSize, budget.requestedFilePoolSize, context)
                XCTAssertGreaterThan(budget.connectionsLimit, 0, context)
                XCTAssertGreaterThan(budget.filePoolSize, 0, context)
                if limit >= 10_240 {
                    XCTAssertEqual(budget.connectionsLimit, budget.requestedConnectionsLimit, context)
                    XCTAssertEqual(budget.filePoolSize, budget.requestedFilePoolSize, context)
                }
            }
        }
    }

    func testEngineReportsItsBudgetOnceBooted() async throws {
        let fixture = try EngineFixture.make(named: "Budget")
        addTeardownBlock { fixture.remove() }
        let engine = LibtorrentEngine(directories: fixture.directories)

        let budgetBeforeBoot = await engine.resourceBudget()
        XCTAssertNil(budgetBeforeBoot)

        try await engine.boot()

        let bootedBudget = await engine.resourceBudget()
        let budget = try XCTUnwrap(bootedBudget)
        XCTAssertGreaterThan(budget.openFileCount, 0)
        XCTAssertLessThan(budget.openFileCount, budget.openFileLimit)
        XCTAssertLessThanOrEqual(
            budget.connectionsLimit + budget.filePoolSize + minimumHeadroom,
            budget.openFileLimit
        )
    }

    // MARK: - Helpers

    private func makeBridge() -> LibtorrentSessionBridge {
        LibtorrentSessionBridge(
            resumeDataDirectoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("OpenFileLimit-\(UUID().uuidString)", isDirectory: true)
        )
    }

    private func assertWithinLimit(
        _ bridge: LibtorrentSessionBridge,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let budget = try XCTUnwrap(bridge.currentResourceBudget(), file: file, line: line)
        XCTAssertLessThanOrEqual(
            budget.connectionsLimit + budget.filePoolSize + minimumHeadroom,
            budget.openFileLimit,
            "connections \(budget.connectionsLimit) + file pool \(budget.filePoolSize) do not fit \(budget.openFileLimit)",
            file: file,
            line: line
        )
    }

    private func firstSnapshot(
        of recordID: String,
        in bridge: LibtorrentSessionBridge,
        within timeout: Duration = .seconds(5),
        where predicate: (LTTorrentSnapshot) -> Bool
    ) async throws -> LTTorrentSnapshot? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let snapshot = try bridge.fetchActiveSnapshots().first { $0.recordIdentifier == recordID }
            if let snapshot, predicate(snapshot) {
                return snapshot
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    /// Sets the soft open-file limit for this test and restores it afterwards.
    private func setSoftOpenFileLimit(_ value: Int) throws {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else {
            throw XCTSkip("getrlimit failed")
        }
        let original = limit
        addTeardownBlock {
            var restored = original
            setrlimit(RLIMIT_NOFILE, &restored)
        }
        limit.rlim_cur = rlim_t(value)
        guard setrlimit(RLIMIT_NOFILE, &limit) == 0 else {
            throw XCTSkip("setrlimit(\(value)) failed")
        }
    }

    private func currentSoftOpenFileLimit() -> Int {
        var limit = rlimit()
        getrlimit(RLIMIT_NOFILE, &limit)
        return Int(clamping: limit.rlim_cur)
    }

    private func hardOpenFileLimit() -> Int {
        var limit = rlimit()
        getrlimit(RLIMIT_NOFILE, &limit)
        return Int(clamping: limit.rlim_max)
    }

    private func perProcessOpenFileLimit() -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.maxfilesperproc", &value, &size, nil, 0) == 0 else { return Int.max }
        return Int(value)
    }

    /// Apple's setrlimit(2) asks apps for at most `OPEN_MAX` (10 240).
    private func expectedRaisedLimit() -> Int {
        min(10_240, hardOpenFileLimit(), perProcessOpenFileLimit())
    }
}

/// Takes every free descriptor under a lowered soft limit, like a process that
/// has run out of them. `release()` returns them and restores the limit.
private final class DescriptorExhaustion: @unchecked Sendable {
    private var descriptors: [Int32] = []
    private var originalLimit = rlimit()
    private var isReleased = false

    init() throws {
        guard getrlimit(RLIMIT_NOFILE, &originalLimit) == 0 else {
            throw XCTSkip("getrlimit failed")
        }
        // A ceiling just above what is open keeps this quick at any limit.
        var lowered = originalLimit
        lowered.rlim_cur = rlim_t(LibtorrentSessionBridge.openFileDescriptorCount() + 32)
        guard setrlimit(RLIMIT_NOFILE, &lowered) == 0 else {
            throw XCTSkip("setrlimit failed")
        }

        while true {
            let descriptor = dup(STDERR_FILENO)
            guard descriptor >= 0 else {
                let failure = errno
                guard failure == EMFILE else {
                    release()
                    throw XCTSkip("dup failed with errno \(failure)")
                }
                break
            }
            descriptors.append(descriptor)
        }
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        descriptors.forEach { close($0) }
        descriptors.removeAll()
        var restored = originalLimit
        setrlimit(RLIMIT_NOFILE, &restored)
    }
}
