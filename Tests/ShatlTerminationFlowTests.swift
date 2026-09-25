// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import CoreServices
import Foundation
import XCTest
@testable import Shatl

final class ShatlTerminationFlowTests: XCTestCase {
    func testSuccessfulSaveQuitsWithoutDialog() async {
        let handler = ScriptedTerminationHandler(results: [true])
        let presenter = ScriptedFailurePresenter(choices: [])

        let shouldTerminate = await ShatlTerminationFlow.resolve(
            handler: handler,
            source: .user,
            presenter: presenter
        )

        XCTAssertTrue(shouldTerminate)
        XCTAssertEqual(presenter.presentationCount, 0)
        XCTAssertEqual(handler.finishCount, 1)
    }

    func testRetryQuitsOnceSaveSucceeds() async {
        let handler = ScriptedTerminationHandler(results: [false, true])
        let presenter = ScriptedFailurePresenter(choices: [.retry])

        let shouldTerminate = await ShatlTerminationFlow.resolve(
            handler: handler,
            source: .user,
            presenter: presenter
        )

        XCTAssertTrue(shouldTerminate)
        XCTAssertEqual(handler.callCount, 2)
        XCTAssertEqual(presenter.presentationCount, 1)
        XCTAssertEqual(handler.finishCount, 1)
    }

    func testRepeatedFailureKeepsAskingUntilUserReturnsToApp() async {
        let handler = ScriptedTerminationHandler(results: [false, false, false])
        let presenter = ScriptedFailurePresenter(choices: [.retry, .retry, .returnToApp])

        let shouldTerminate = await ShatlTerminationFlow.resolve(
            handler: handler,
            source: .user,
            presenter: presenter
        )

        XCTAssertFalse(shouldTerminate)
        XCTAssertEqual(handler.callCount, 3)
        XCTAssertEqual(presenter.presentationCount, 3)
        XCTAssertEqual(handler.finishCount, 0, "Returning to Shatl must keep the engine running")
    }

    func testQuitWithoutSavingEndsFailedQuit() async {
        let handler = ScriptedTerminationHandler(results: [false])
        let presenter = ScriptedFailurePresenter(choices: [.quitWithoutSaving])

        let shouldTerminate = await ShatlTerminationFlow.resolve(
            handler: handler,
            source: .user,
            presenter: presenter
        )

        XCTAssertTrue(shouldTerminate)
        XCTAssertEqual(handler.callCount, 1)
        XCTAssertEqual(handler.finishCount, 1)
    }

    func testSystemQuitNeverShowsDialogOrCancelsMacOS() async {
        let handler = ScriptedTerminationHandler(results: [false])
        let presenter = ScriptedFailurePresenter(choices: [])

        let shouldTerminate = await ShatlTerminationFlow.resolve(
            handler: handler,
            source: .system,
            presenter: presenter
        )

        XCTAssertTrue(shouldTerminate)
        XCTAssertEqual(handler.callCount, 1)
        XCTAssertEqual(presenter.presentationCount, 0)
        XCTAssertEqual(handler.finishCount, 1)
    }

    /// Shatl leaves the screen as soon as the quit is decided; libtorrent then
    /// closes its connections behind it for up to two seconds.
    func testDecidedQuitLeavesTheScreenBeforeTheEngineStops() async {
        var events: [String] = []
        let handler = ScriptedTerminationHandler(results: [true]) { events.append("engine stopped") }
        let presenter = ScriptedFailurePresenter(choices: [])

        let shouldTerminate = await ShatlTerminationFlow.resolve(
            handler: handler,
            source: .user,
            presenter: presenter,
            willFinish: { events.append("left screen") }
        )

        XCTAssertTrue(shouldTerminate)
        XCTAssertEqual(events, ["left screen", "engine stopped"])
    }

    func testReturningToShatlKeepsItOnScreen() async {
        var leftScreen = false
        let handler = ScriptedTerminationHandler(results: [false])
        let presenter = ScriptedFailurePresenter(choices: [.returnToApp])

        let shouldTerminate = await ShatlTerminationFlow.resolve(
            handler: handler,
            source: .user,
            presenter: presenter,
            willFinish: { leftScreen = true }
        )

        XCTAssertFalse(shouldTerminate)
        XCTAssertFalse(leftScreen)
    }

    /// macOS hands a launch to the quitting copy instead of starting a new
    /// one, so the quitting copy starts the next one only when asked to.
    func testQuitRelaunchesOnlyWhenShatlWasOpenedDuringIt() {
        let torrent = URL(fileURLWithPath: "/tmp/a.torrent")
        let magnet = URL(string: "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567")!

        XCTAssertFalse(ShatlRelaunchRequest().shouldRelaunch(after: .user))

        var reopened = ShatlRelaunchRequest()
        reopened.noteReopen()
        XCTAssertTrue(reopened.shouldRelaunch(after: .user))
        XCTAssertEqual(reopened.urls, [])

        var opened = ShatlRelaunchRequest()
        opened.note([])
        XCTAssertFalse(opened.shouldRelaunch(after: .user))
        opened.note([torrent])
        opened.note([magnet])
        XCTAssertTrue(opened.shouldRelaunch(after: .user))
        XCTAssertEqual(opened.urls, [torrent, magnet])

        // A logout or restart must not be held up by a new copy.
        XCTAssertFalse(opened.shouldRelaunch(after: .system))
    }

    func testQuitReasonSeparatesSystemRequestsFromUserQuit() {
        for reason in [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAERestart, kAEShowShutdownDialog, kAEShutDown] {
            XCTAssertEqual(ShatlTerminationRequestSource(quitReason: OSType(reason)), .system)
        }
        XCTAssertEqual(ShatlTerminationRequestSource(quitReason: nil), .user)
        XCTAssertEqual(ShatlTerminationRequestSource(quitReason: OSType(kAEQuitApplication)), .user)
    }

    func testQuitWithoutSavingLeavesLastCommittedSessionUntouched() async throws {
        let engine = FakeTorrentEngine()
        let writer = ControllableSessionDataWriter()
        let record = makeTestRecord(status: .downloading, progress: 0.42)
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
        let originalSessionData = try Data(contentsOf: bundle.directories.sessionSnapshotURL)
        await engine.setHandleActive(true, for: record.id)
        writer.failNextWrite()
        let presenter = ScriptedFailurePresenter(choices: [.quitWithoutSaving])

        let shouldTerminate = await ShatlTerminationFlow.resolve(
            handler: bundle.store,
            source: .user,
            presenter: presenter
        )

        XCTAssertTrue(shouldTerminate)
        XCTAssertEqual(presenter.presentationCount, 1)
        XCTAssertEqual(
            try Data(contentsOf: bundle.directories.sessionSnapshotURL),
            originalSessionData
        )
        XCTAssertEqual(bundle.store.sessionPersistenceIssue?.kind, .background)
    }
}

private final class ScriptedTerminationHandler: ShatlTerminationPreparing {
    private var results: [Bool]
    private let onFinish: () -> Void
    private(set) var callCount = 0
    private(set) var finishCount = 0

    init(results: [Bool], onFinish: @escaping () -> Void = {}) {
        self.results = results
        self.onFinish = onFinish
    }

    func prepareForTermination() async -> Bool {
        callCount += 1
        return results.isEmpty ? true : results.removeFirst()
    }

    func finishTermination() async {
        finishCount += 1
        onFinish()
    }
}

private final class ScriptedFailurePresenter: ShatlTerminationFailurePresenting {
    private var choices: [ShatlTerminationSaveFailureChoice]
    private(set) var presentationCount = 0

    init(choices: [ShatlTerminationSaveFailureChoice]) {
        self.choices = choices
    }

    func presentSessionSaveFailure() -> ShatlTerminationSaveFailureChoice {
        presentationCount += 1
        return choices.isEmpty ? .returnToApp : choices.removeFirst()
    }
}
