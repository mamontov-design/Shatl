// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Darwin
import Foundation
import XCTest
@testable import Shatl

/// Two copies of Shatl on one data folder overwrite each other's
/// `session.json` and clean up each other's archives, so only the first copy
/// may own the folder. A second descriptor of the lock file in this process
/// stands for a second copy: `flock` belongs to the open file, not the process.
final class SingleInstanceLockTests: XCTestCase {
    private let firstCopyPath = "/Applications/Shatl.app"
    private let secondCopyPath = "/Volumes/Shatl/Shatl.app"

    func testSecondCopyFindsTheFirstOne() throws {
        let directoryURL = makeDirectory()
        let first = try acquire(in: directoryURL, bundlePath: firstCopyPath)

        guard case .heldByAnotherProcess(let holder) = SingleInstanceLock.acquire(
            in: directoryURL,
            bundlePath: secondCopyPath
        ) else {
            return XCTFail("The second copy took a folder the first one owns")
        }

        XCTAssertEqual(
            holder,
            SingleInstanceHolder(processIdentifier: getpid(), bundlePath: firstCopyPath, isClosing: false)
        )
        withExtendedLifetime(first) {}
    }

    /// The kernel drops the lock with the process, so a crash leaves nothing behind.
    func testLockEndsWithItsOwner() throws {
        let directoryURL = makeDirectory()
        var first: SingleInstanceLock? = try acquire(in: directoryURL, bundlePath: firstCopyPath)
        XCTAssertNotNil(first)

        first = nil

        let second = try acquire(in: directoryURL, bundlePath: secondCopyPath)
        XCTAssertEqual(SingleInstanceLock.readHolder(at: second.fileURL)?.bundlePath, secondCopyPath)
    }

    /// An inherited descriptor would keep the lock after Shatl quits, and the
    /// next launch would find the folder taken by a helper process.
    func testHelperProcessDoesNotInheritTheLock() throws {
        let directoryURL = makeDirectory()
        var first: SingleInstanceLock? = try acquire(in: directoryURL, bundlePath: firstCopyPath)
        XCTAssertNotNil(first)
        let helper = try spawnSleepingHelper()
        defer {
            kill(helper, SIGKILL)
            var status: Int32 = 0
            waitpid(helper, &status, 0)
        }

        first = nil

        XCTAssertNoThrow(try acquire(in: directoryURL, bundlePath: secondCopyPath))
    }

    func testQuittingCopyIsMarkedClosing() throws {
        let directoryURL = makeDirectory()
        let first = try acquire(in: directoryURL, bundlePath: firstCopyPath)

        first.setClosing(true)
        XCTAssertEqual(SingleInstanceLock.readHolder(at: first.fileURL)?.isClosing, true)

        first.setClosing(false)
        XCTAssertEqual(SingleInstanceLock.readHolder(at: first.fileURL)?.isClosing, false)
    }

    func testGateHandsARunningFolderToItsOwner() throws {
        let directoryURL = makeDirectory()
        let first = try acquire(in: directoryURL, bundlePath: firstCopyPath)
        let startedAt = ContinuousClock.now

        let role = SingleInstanceGate.resolve(directoryURL: directoryURL, bundlePath: secondCopyPath)

        guard case .secondary(let holder) = role else {
            return XCTFail("The second copy became the owner, got \(role)")
        }
        XCTAssertEqual(holder?.bundlePath, firstCopyPath)
        XCTAssertLessThan(ContinuousClock.now - startedAt, .seconds(1))
        withExtendedLifetime(first) {}
    }

    /// Cmd+Q in the first copy, then a launch of another copy while the first
    /// one still saves: the second waits and takes over the folder.
    func testGateWaitsForAQuittingOwnerAndTakesOver() throws {
        let directoryURL = makeDirectory()
        let first = LockBox(try acquire(in: directoryURL, bundlePath: firstCopyPath))
        first.lock?.setClosing(true)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            first.release()
        }
        let startedAt = ContinuousClock.now

        let role = SingleInstanceGate.resolve(
            directoryURL: directoryURL,
            bundlePath: secondCopyPath,
            closingHolderTimeout: 5,
            pollInterval: 0.05
        )

        guard case .primary(let lock?) = role else {
            return XCTFail("The second copy did not take over, got \(role)")
        }
        XCTAssertEqual(SingleInstanceLock.readHolder(at: lock.fileURL)?.bundlePath, secondCopyPath)
        XCTAssertLessThan(ContinuousClock.now - startedAt, .seconds(3))
    }

    /// A quit that waits on the failed-save dialog may never finish; the second
    /// copy then hands its launch over, so the user sees the dialog.
    func testGateStopsWaitingForAnOwnerThatStaysClosing() throws {
        let directoryURL = makeDirectory()
        let first = try acquire(in: directoryURL, bundlePath: firstCopyPath)
        first.setClosing(true)

        let role = SingleInstanceGate.resolve(
            directoryURL: directoryURL,
            bundlePath: secondCopyPath,
            closingHolderTimeout: 0.3,
            pollInterval: 0.05
        )

        guard case .secondary(let holder) = role else {
            return XCTFail("The second copy took a folder the first one owns, got \(role)")
        }
        XCTAssertEqual(holder?.isClosing, true)
    }

    /// Refusing to start would be worse than running as before.
    func testGateRunsWithoutLockWhenTheFolderCannotBeLocked() throws {
        let rootURL = makeDirectory()
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let blockerURL = rootURL.appendingPathComponent("blocker", isDirectory: false)
        try Data().write(to: blockerURL)

        let role = SingleInstanceGate.resolve(
            directoryURL: blockerURL.appendingPathComponent("Shatl", isDirectory: true),
            bundlePath: firstCopyPath
        )

        guard case .primary(nil) = role else {
            return XCTFail("Expected a lockless start, got \(role)")
        }
    }

    // MARK: - The lock file and the session

    func testLockFileKeepsTheMissingSessionBlocked() async throws {
        let directories = makeDirectories()
        let lock = try acquire(in: directories.applicationSupportURL, bundlePath: firstCopyPath)

        let result = await makeSessionStore(directories).load(expectsExistingSession: true)

        guard case .failure(.missingWithRecoveryArtifacts) = result else {
            return XCTFail("A lock file must not pass for a session, got \(result)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directories.sessionDirectoryURL.path))
        withExtendedLifetime(lock) {}
    }

    func testLockFileKeepsTheCleanFirstLaunch() async throws {
        let directories = makeDirectories()
        let lock = try acquire(in: directories.applicationSupportURL, bundlePath: firstCopyPath)

        let result = await makeSessionStore(directories).load(expectsExistingSession: false)

        guard case .missing = result else {
            return XCTFail("A clean first launch with a lock file was not accepted, got \(result)")
        }
        withExtendedLifetime(lock) {}
    }

    func testStartingWithAnEmptyListKeepsTheLockFile() async throws {
        let directories = makeDirectories()
        try directories.ensureSessionDirectories()
        let lock = try acquire(in: directories.applicationSupportURL, bundlePath: firstCopyPath)
        try Data("broken session".utf8).write(to: directories.sessionSnapshotURL)
        let sessionStore = makeSessionStore(directories)
        _ = await sessionStore.load(expectsExistingSession: true)

        let outcome = await sessionStore.discardFailedSessionAndCreateEmpty()

        XCTAssertEqual(outcome, .saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lock.fileURL.path))
        guard case .heldByAnotherProcess = SingleInstanceLock.acquire(
            in: directories.applicationSupportURL,
            bundlePath: secondCopyPath
        ) else {
            return XCTFail("The folder lost its lock")
        }
    }

    // MARK: - Handing the launch over

    func testTorrentGoesToTheRunningCopyWithoutNotice() {
        let recorder = HandoffRecorder()
        let torrentURL = URL(fileURLWithPath: "/Users/example/Downloads/Movie.torrent")
        let magnetURL = URL(string: "magnet:?xt=urn:btih:abc")!

        recorder.handoff(holderPath: firstCopyPath).run(urls: [torrentURL, magnetURL]) {
            recorder.completions += 1
        }

        XCTAssertEqual(recorder.openedURLs, [torrentURL, magnetURL])
        XCTAssertEqual(recorder.targetURL?.path, firstCopyPath)
        XCTAssertEqual(recorder.notices, 0)
        XCTAssertEqual(recorder.reopenedURL, nil)
        XCTAssertEqual(recorder.completions, 1)
    }

    func testPlainLaunchTellsThatShatlIsRunningAndBringsItForward() {
        let recorder = HandoffRecorder()

        recorder.handoff(holderPath: firstCopyPath).run(urls: []) {
            recorder.completions += 1
        }

        XCTAssertEqual(recorder.notices, 1)
        XCTAssertEqual(recorder.reopenedURL?.path, firstCopyPath)
        XCTAssertEqual(recorder.openedURLs, [])
        XCTAssertEqual(recorder.completions, 1)
    }

    func testHandoffFindsAnOwnerThatHasNotWrittenItsRecord() {
        let recorder = HandoffRecorder()
        recorder.runningCopies = [URL(fileURLWithPath: firstCopyPath, isDirectory: true)]

        recorder.handoff(holderPath: nil).run(urls: []) {
            recorder.completions += 1
        }

        XCTAssertEqual(recorder.reopenedURL?.path, firstCopyPath)
        XCTAssertEqual(recorder.completions, 1)
    }

    func testOnlyALiveLaunchTakesTheUsersFolder() {
        XCTAssertTrue(ShatlMain.usesSingleInstanceLock(.live))
        XCTAssertFalse(ShatlMain.usesSingleInstanceLock(.unitTestHost))
        XCTAssertFalse(ShatlMain.usesSingleInstanceLock(.xcodePreview))
    }

    // MARK: - Helpers

    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SingleInstanceLockTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeDirectories() -> ShatlDirectories {
        let rootURL = makeDirectory()
        return ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
    }

    private func makeSessionStore(_ directories: ShatlDirectories) -> SessionStore {
        SessionStore(
            directories: directories,
            archiveStore: TorrentArchiveStore(directories: directories),
            bookmarkStore: BookmarkStore(directories: directories),
            resumeDataStore: ResumeDataStore(directories: directories)
        )
    }

    private func acquire(in directoryURL: URL, bundlePath: String) throws -> SingleInstanceLock {
        let result = SingleInstanceLock.acquire(in: directoryURL, bundlePath: bundlePath)
        guard case .acquired(let lock) = result else {
            throw LockError.notAcquired("\(result)")
        }
        return lock
    }

    /// Starts `/bin/sleep`, which inherits every descriptor not marked close-on-exec.
    private func spawnSleepingHelper() throws -> pid_t {
        var processIdentifier: pid_t = 0
        let argumentStrings = ["/bin/sleep", "30"]
        var arguments: [UnsafeMutablePointer<CChar>?] = argumentStrings.map { strdup($0) } + [nil]
        defer { arguments.forEach { free($0) } }
        let status = posix_spawn(&processIdentifier, "/bin/sleep", nil, nil, &arguments, nil)
        guard status == 0 else {
            throw LockError.notAcquired("posix_spawn failed with \(status)")
        }
        return processIdentifier
    }
}

private enum LockError: Error {
    case notAcquired(String)
}

/// Lets another thread end the first copy's lock.
private final class LockBox: @unchecked Sendable {
    private(set) var lock: SingleInstanceLock?

    init(_ lock: SingleInstanceLock) {
        self.lock = lock
    }

    func release() {
        lock = nil
    }
}

private final class HandoffRecorder {
    var openedURLs: [URL] = []
    var targetURL: URL?
    var reopenedURL: URL?
    var notices = 0
    var completions = 0
    var runningCopies: [URL] = []

    func handoff(holderPath: String?) -> ShatlSecondaryInstanceHandoff {
        ShatlSecondaryInstanceHandoff(
            holder: holderPath.map {
                SingleInstanceHolder(processIdentifier: 1, bundlePath: $0, isClosing: false)
            },
            openURLs: { [self] urls, applicationURL, completion in
                openedURLs = urls
                targetURL = applicationURL
                completion()
            },
            reopenApplication: { [self] applicationURL, completion in
                reopenedURL = applicationURL
                completion()
            },
            runningCopyURLs: { [self] in runningCopies },
            presentAlreadyRunningNotice: { [self] in
                notices += 1
            }
        )
    }
}
