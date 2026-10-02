// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// A download the engine stopped with an error (a full disk, no write access)
/// offered only "Удалить из списка": Start and Stop are off on an error card,
/// and only a relaunch, which forgets runtime errors, let it start again.
/// "Повторить" does that Stop and Start itself, progress kept.
@MainActor
final class RuntimeRetryTests: XCTestCase {
    private struct Fixture {
        let bundle: TestStoreBundle
        let engine: FakeTorrentEngine
        let record: TorrentRecord
        let folderURL: URL
    }

    /// A download at 40 % the engine stopped with an error; its folder and
    /// file are on disk.
    private func makeFixture(errorState: TorrentErrorState? = nil) async throws -> Fixture {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShatlRuntimeRetry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data(count: 1_024).write(to: folderURL.appendingPathComponent("test-file.bin"))
        let engine = FakeTorrentEngine()
        let record = makeTestRecord(
            savePath: folderURL.path,
            status: .error,
            progress: 0.4,
            runtimeErrorState: errorState ?? ShatlErrorCatalog.runtimeSnapshotError(debugReason: "No space left on device")
        )
        await engine.setHandleActive(true, for: record.id)
        let bundle = makeTestStoreBundle(engine: engine, torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folderURL)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        await bundle.sessionStore.replaceAllRecordsForTesting(from: [record])
        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        return Fixture(bundle: bundle, engine: engine, record: record, folderURL: folderURL)
    }

    private func waitForRetry(_ fixture: Fixture) async {
        _ = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            !fixture.bundle.store.transitioningTorrentIDs.contains(fixture.record.id)
        }
    }

    /// Start stays off on an error card: "Повторить" is its way out.
    func testStartStaysOffOnAnErrorCard() async throws {
        let fixture = try await makeFixture()
        let row = try XCTUnwrap(fixture.bundle.store.rowState(for: fixture.record.id))

        XCTAssertFalse(row.canToggleRunningState)
        XCTAssertEqual(row.errorState?.recoveryOptions, [.retry, .removeFromList])
        fixture.bundle.store.startTorrent(id: fixture.record.id)
        try await Task.sleep(for: .milliseconds(200))
        let restoreCount = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCount, 0)
    }

    func testRetryStopsAndResumesTheDownloadWithItsProgress() async throws {
        let fixture = try await makeFixture()

        fixture.bundle.store.retryAfterRuntimeError(id: fixture.record.id)
        await waitForRetry(fixture)

        let record = try XCTUnwrap(fixture.bundle.store.torrents.first)
        XCTAssertNil(record.errorState)
        // Checking first: the engine confirms the 40 % already on disk.
        XCTAssertTrue([.checking, .downloading].contains(record.status), "\(record.status)")
        let removeCalls = await fixture.engine.recordedRemoveCalls()
        XCTAssertEqual(removeCalls.map(\.id), [fixture.record.id])
        let entries = await fixture.engine.recordedRestoreSessionEntries()
        XCTAssertEqual(entries.count, 1)
        // A resume, not a fresh download: the same attempt, started.
        XCTAssertEqual(entries.first?.attemptID, fixture.record.attemptID)
        XCTAssertEqual(entries.first?.shouldStart, true)
        XCTAssertGreaterThanOrEqual(record.progress, 0.4)
    }

    /// A Stop the engine refuses does not block the Start after it.
    func testRetryStartsEvenWhenTheStopFails() async throws {
        let fixture = try await makeFixture()
        await fixture.engine.setRemoveError(TorrentEngineError(kind: .torrentNotFound))

        fixture.bundle.store.retryAfterRuntimeError(id: fixture.record.id)
        await waitForRetry(fixture)

        XCTAssertNil(fixture.bundle.store.torrents.first?.errorState)
        let restoreCount = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCount, 1)
    }

    /// The error comes back: the card shows it again with "Повторить".
    func testRetryThatFailsShowsTheErrorAgain() async throws {
        let fixture = try await makeFixture()
        await fixture.engine.setRestoreSessionErrors([TorrentEngineError(kind: .engineFailure)])

        fixture.bundle.store.retryAfterRuntimeError(id: fixture.record.id)
        await waitForRetry(fixture)

        let record = try XCTUnwrap(fixture.bundle.store.torrents.first)
        XCTAssertEqual(record.status, .error)
        XCTAssertEqual(record.errorState?.kind, .engineFailure)
        XCTAssertEqual(record.errorState?.recoveryOptions, [.retry, .removeFromList])
    }

    /// The files went missing: Start's own check turns the card into
    /// "Файлы не найдены" with "Скачать заново", nothing restored.
    func testRetryWithTheFilesGoneShowsMissingFiles() async throws {
        let fixture = try await makeFixture()
        try FileManager.default.removeItem(at: fixture.folderURL.appendingPathComponent("test-file.bin"))

        fixture.bundle.store.retryAfterRuntimeError(id: fixture.record.id)
        await waitForRetry(fixture)

        let record = try XCTUnwrap(fixture.bundle.store.torrents.first)
        XCTAssertEqual(record.persistentIssue?.kind, .missingContent)
        XCTAssertNil(record.runtimeErrorState)
        let restoreCount = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCount, 0)
    }

    /// The button shows "Запуск…" for at least a second while the error is
    /// on the card, and a second press meanwhile does nothing.
    func testRetryShowsStartingAndIgnoresASecondPress() async throws {
        let fixture = try await makeFixture()
        await fixture.engine.setRestoreSessionErrors([TorrentEngineError(kind: .engineFailure)])
        let store = fixture.bundle.store

        store.retryAfterRuntimeError(id: fixture.record.id)
        store.retryAfterRuntimeError(id: fixture.record.id)
        XCTAssertEqual(store.rowState(for: fixture.record.id)?.isRecovering, true)

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(store.transitioningTorrentIDs.contains(fixture.record.id))
        XCTAssertEqual(store.rowState(for: fixture.record.id)?.isRecovering, true)

        await waitForRetry(fixture)
        XCTAssertEqual(store.rowState(for: fixture.record.id)?.isRecovering, false)
        let restoreCount = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCount, 1)
    }

    /// The saved torrent is gone: nothing can resume the download, so the
    /// card offers no "Повторить".
    func testMissingSavedTorrentOffersNoRetry() async throws {
        let fixture = try await makeFixture()
        let archiveURL = try await fixture.bundle.archiveStore.destinationURL(for: fixture.record.id)
        try FileManager.default.removeItem(at: archiveURL)

        fixture.bundle.store.retryAfterRuntimeError(id: fixture.record.id)
        await waitForRetry(fixture)

        let record = try XCTUnwrap(fixture.bundle.store.torrents.first)
        XCTAssertEqual(record.errorState?.kind, .torrentNotFound)
        XCTAssertEqual(record.errorState?.recoveryOptions, [.removeFromList])

        fixture.bundle.store.retryAfterRuntimeError(id: fixture.record.id)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(fixture.bundle.store.transitioningTorrentIDs.contains(fixture.record.id))
        let restoreCount = await fixture.engine.restoreSessionCallCount()
        XCTAssertEqual(restoreCount, 0)
    }

    #if DEBUG
    /// The Debug menu stops a running download as the engine would, and
    /// "Повторить" brings it back.
    func testDebugMenuStopsADownloadWithAnErrorThatRetryClears() async throws {
        let engine = FakeTorrentEngine()
        let notifier = SpyTorrentUserEventNotifier()
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShatlRuntimeRetry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data(count: 1_024).write(to: folderURL.appendingPathComponent("test-file.bin"))
        let record = makeTestRecord(savePath: folderURL.path, status: .downloading, progress: 0.4)
        await engine.setHandleActive(true, for: record.id)
        let bundle = makeTestStoreBundle(engine: engine, torrents: [record], userEventNotifier: notifier)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folderURL)
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        await bundle.sessionStore.replaceAllRecordsForTesting(from: [record])
        let archiveURL = try await bundle.archiveStore.destinationURL(for: record.id)
        try Data("archive".utf8).write(to: archiveURL, options: .atomic)
        let store = bundle.store

        XCTAssertTrue(store.canSimulateRuntimeErrorForDebug(id: record.id))
        store.simulateRuntimeErrorForDebug(id: record.id, cause: .diskFull)

        let stopped = try XCTUnwrap(store.torrents.first)
        XCTAssertEqual(stopped.status, .error)
        XCTAssertEqual(stopped.runtimeErrorState?.cause, .diskFull)
        XCTAssertEqual(notifier.notifications.count, 1)
        XCTAssertFalse(store.canSimulateRuntimeErrorForDebug(id: record.id))
        let didRemove = await waitForAsyncCondition {
            await engine.recordedRemoveCalls().count == 1
        }
        XCTAssertTrue(didRemove)

        store.retryAfterRuntimeError(id: record.id)
        _ = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            !store.transitioningTorrentIDs.contains(record.id)
        }
        XCTAssertNil(store.torrents.first?.errorState)
    }
    #endif

    func testFileErrorsMapToTheirCause() {
        XCTAssertEqual(TorrentErrorState.Cause(posixCode: Int(ENOSPC)), .diskFull)
        XCTAssertEqual(TorrentErrorState.Cause(posixCode: Int(EDQUOT)), .diskFull)
        XCTAssertEqual(TorrentErrorState.Cause(posixCode: Int(EACCES)), .noWriteAccess)
        XCTAssertEqual(TorrentErrorState.Cause(posixCode: Int(EPERM)), .noWriteAccess)
        XCTAssertEqual(TorrentErrorState.Cause(posixCode: Int(EROFS)), .noWriteAccess)
        XCTAssertEqual(TorrentErrorState.Cause(posixCode: Int(EIO)), .diskError)
        XCTAssertEqual(TorrentErrorState.Cause(posixCode: Int(ENOENT)), .filesMissing)
        XCTAssertNil(TorrentErrorState.Cause(posixCode: 0))
        XCTAssertNil(TorrentErrorState.Cause(posixCode: Int(EINVAL)))
    }

    /// The card names the cause and the folder; an unknown cause says what
    /// to do if the error comes back.
    func testCardMessageNamesTheCauseAndTheFolder() throws {
        let diskFull = ShatlErrorCatalog.runtimeSnapshotError(debugReason: nil, posixCode: Int(ENOSPC))
        let row = try XCTUnwrap(
            TorrentRowErrorState(diskFull, saveFolderPath: "/Volumes/Metis/Фильмы", localeOverride: .russian)
        )
        XCTAssertEqual(row.title, L10n.string("torrent.error.runtime.title", localeOverride: .russian))
        XCTAssertEqual(
            row.message,
            L10n.format(
                "torrent.error.runtime.disk_full.named_message",
                localeOverride: .russian,
                defaultValue: "",
                "Фильмы"
            )
        )

        let other = ShatlErrorCatalog.runtimeSnapshotError(debugReason: "unknown", posixCode: 0)
        let otherRow = try XCTUnwrap(
            TorrentRowErrorState(other, saveFolderPath: "/Volumes/Metis/Фильмы", localeOverride: .russian)
        )
        XCTAssertEqual(
            otherRow.message,
            L10n.string("torrent.error.runtime.other.message", localeOverride: .russian)
        )
    }

    /// Every cause has its card and notification text in every language.
    func testEveryCauseHasItsTextsInEveryLanguage() {
        let causes: [TorrentErrorState.Cause] = [.diskFull, .noWriteAccess, .diskError, .filesMissing]
        for locale in AppLocaleOverride.allCases where locale != .system {
            for cause in causes {
                let base = "torrent.error.runtime.\(ShatlErrorCatalog.causeKey(cause))"
                for suffix in ["message", "named_message", "notification"] {
                    let key = "\(base).\(suffix)"
                    XCTAssertNotEqual(L10n.string(key, localeOverride: locale), key, "\(locale) \(key)")
                }
            }
            for key in ["torrent.error.runtime.other.message", "torrent.error.runtime.other.notification"] {
                XCTAssertNotEqual(L10n.string(key, localeOverride: locale), key, "\(locale) \(key)")
            }
        }
    }

    /// The engine stopping a running download is told once, with its cause,
    /// and told again only after the download ran without an error.
    func testEngineStopIsNotifiedOncePerStop() async throws {
        let engine = FakeTorrentEngine()
        let notifier = SpyTorrentUserEventNotifier()
        let record = makeTestRecord(status: .downloading, progress: 0.4)
        await engine.setHandleActive(true, for: record.id)
        let bundle = makeTestStoreBundle(engine: engine, torrents: [record], userEventNotifier: notifier)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }

        let diskFull = ShatlErrorCatalog.runtimeSnapshotError(debugReason: nil, posixCode: Int(ENOSPC))
        func snapshot(_ error: TorrentErrorState?) -> EngineTorrentSnapshot {
            EngineTorrentSnapshot(
                id: record.id,
                status: error == nil ? .downloading : .error,
                progress: 0.4,
                metrics: TorrentMetrics(),
                errorState: error
            )
        }

        bundle.store.applySnapshotsForTesting([snapshot(diskFull)])
        bundle.store.applySnapshotsForTesting([snapshot(diskFull)])
        let expected = ShatlErrorCatalog.runtimeErrorNotification(for: .diskFull)
        XCTAssertEqual(
            notifier.notifications,
            [
                .downloadStopped(
                    torrentID: record.id,
                    torrentTitle: record.displayName,
                    title: expected.title,
                    body: expected.body
                )
            ]
        )

        bundle.store.applySnapshotsForTesting([snapshot(nil)])
        bundle.store.applySnapshotsForTesting([snapshot(diskFull)])
        XCTAssertEqual(notifier.notifications.count, 2)
    }
}
