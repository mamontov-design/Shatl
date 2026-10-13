// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import SwiftUI
import XCTest
@testable import Shatl

/// Several selected downloads: what the cards, the toolbar and the bar under
/// it know about them, and how they are started, stopped and removed.
@MainActor
final class TorrentMultiSelectionStoreTests: XCTestCase {
    private func makeBundle(_ records: [TorrentRecord]) -> TestStoreBundle {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: records)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        return bundle
    }

    private func failedRecord() -> TorrentRecord {
        makeTestRecord(
            status: .error,
            runtimeErrorState: ShatlErrorCatalog.torrentActionError(
                for: TorrentEngineError(kind: .torrentNotFound, debugReason: "Missing archive")
            )
        )
    }

    private func rowState(_ id: UUID, in store: AppStore) throws -> TorrentRowState {
        try XCTUnwrap(store.torrentRowPresentationModel(for: id)).state
    }

    func testCommandClickSelectsSeveralAndTheirCardsKnowIt() throws {
        let records = [makeTestRecord(), makeTestRecord(), makeTestRecord()]
        let store = makeBundle(records).store
        let ids = records.map(\.id)

        XCTAssertTrue(store.clickTorrent(id: ids[0], .plain, visibleTorrentIDs: ids))
        XCTAssertEqual(store.selectedTorrentID, ids[0])
        XCTAssertFalse(try rowState(ids[0], in: store).isSelectedWithOthers)

        XCTAssertTrue(store.clickTorrent(id: ids[2], .toggle, visibleTorrentIDs: ids))
        XCTAssertEqual(store.selectedTorrentCount, 2)
        // "Open" and the other single-download actions have nothing to act on.
        XCTAssertNil(store.selectedTorrentID)
        XCTAssertNil(store.selectedTorrent)
        XCTAssertEqual(store.selectedTorrents.map(\.id), [ids[0], ids[2]])

        XCTAssertTrue(try rowState(ids[0], in: store).isSelected)
        XCTAssertTrue(try rowState(ids[0], in: store).isSelectedWithOthers)
        XCTAssertFalse(try rowState(ids[1], in: store).isSelected)
        XCTAssertTrue(try rowState(ids[2], in: store).isSelectedWithOthers)

        store.clearTorrentSelection()
        XCTAssertEqual(store.selectedTorrentCount, 0)
        XCTAssertFalse(try rowState(ids[0], in: store).isSelected)
    }

    func testShiftClickSelectsARun() {
        let records = (0..<4).map { _ in makeTestRecord() }
        let store = makeBundle(records).store
        let ids = records.map(\.id)

        store.clickTorrent(id: ids[0], .plain, visibleTorrentIDs: ids)
        store.clickTorrent(id: ids[2], .range, visibleTorrentIDs: ids)
        XCTAssertEqual(store.selectedTorrents.map(\.id), Array(ids[0...2]))

        store.clickTorrent(id: ids[3], .range, visibleTorrentIDs: ids)
        XCTAssertEqual(store.selectedTorrentCount, 4)

        store.clickTorrent(id: ids[2], .plain, visibleTorrentIDs: ids)
        XCTAssertEqual(store.selectedTorrentID, ids[2])
    }

    /// A card with an error acts through its own buttons: it is never
    /// selected, by a click, by ⌘A or by "Show in List".
    func testCardWithAnErrorIsNeverSelected() throws {
        let failed = failedRecord()
        let records = [makeTestRecord(), failed, makeTestRecord()]
        let store = makeBundle(records).store
        let ids = records.map(\.id)

        // A plain click changes nothing and is no refusal; the second of a
        // quick pair is answered.
        XCTAssertTrue(store.clickTorrent(id: failed.id, .plain, visibleTorrentIDs: ids))
        XCTAssertFalse(store.clickTorrent(id: failed.id, .plain, isRepeated: true, visibleTorrentIDs: ids))
        XCTAssertEqual(store.selectedTorrentCount, 0)

        store.clickTorrent(id: ids[0], .plain, visibleTorrentIDs: ids)
        XCTAssertTrue(store.clickTorrent(id: failed.id, .plain, visibleTorrentIDs: ids))
        XCTAssertEqual(store.selectedTorrentID, ids[0])

        // With ⌘ or Shift it refuses aloud.
        XCTAssertFalse(store.clickTorrent(id: failed.id, .toggle, visibleTorrentIDs: ids))
        XCTAssertFalse(store.clickTorrent(id: failed.id, .range, visibleTorrentIDs: ids))
        XCTAssertEqual(store.selectedTorrentID, ids[0])
        XCTAssertFalse(try rowState(failed.id, in: store).isSelected)

        // ⌘A leaves it out.
        store.selectAllTorrents(visibleTorrentIDs: ids)
        XCTAssertEqual(store.selectedTorrents.map(\.id), [ids[0], ids[2]])

        // Asked for by name, it clears the selection instead of joining it.
        store.selectTorrent(id: failed.id)
        XCTAssertEqual(store.selectedTorrentCount, 0)
    }

    #if DEBUG
    func testDownloadThatFailsWhileSelectedLeavesTheSelection() {
        let records = [makeTestRecord(), makeTestRecord(), makeTestRecord()]
        let store = makeBundle(records).store
        let ids = records.map(\.id)
        store.selectAllTorrents(visibleTorrentIDs: ids)

        store.simulateRuntimeErrorForDebug(id: ids[1], cause: .diskFull)

        XCTAssertEqual(store.selectedTorrents.map(\.id), [ids[0], ids[2]])
        XCTAssertTrue(store.isToolbarRemoveEnabled)

        // Selected alone, it leaves too.
        store.clickTorrent(id: ids[0], .plain, visibleTorrentIDs: ids)
        store.simulateRuntimeErrorForDebug(id: ids[0], cause: .diskFull)
        XCTAssertEqual(store.selectedTorrentCount, 0)
    }

    #endif

    /// From two to nine selected cards wear their numbers and there is no
    /// bar; from ten the bar names the count and the cards wear check marks.
    func testSelectedCardsWearNumbersUpToNineAndTheBarComesFromTen() throws {
        let records = (0..<10).map { _ in makeTestRecord() }
        let store = makeBundle(records).store
        let ids = records.map(\.id)

        // One selected card wears the check mark.
        store.clickTorrent(id: ids[4], .plain, visibleTorrentIDs: ids)
        XCTAssertNil(store.selectionCountShownInBar)
        XCTAssertNil(try rowState(ids[4], in: store).selectionNumber)

        // Numbered in the order of the clicks, not of the list: the card
        // clicked last wears the count.
        store.clickTorrent(id: ids[1], .toggle, visibleTorrentIDs: ids)
        XCTAssertNil(store.selectionCountShownInBar)
        XCTAssertEqual(try rowState(ids[4], in: store).selectionNumber, 1)
        XCTAssertEqual(try rowState(ids[1], in: store).selectionNumber, 2)
        XCTAssertNil(try rowState(ids[0], in: store).selectionNumber)

        store.clickTorrent(id: ids[2], .toggle, visibleTorrentIDs: ids)
        XCTAssertEqual(try rowState(ids[2], in: store).selectionNumber, 3)
        // A card taken out hands its number down.
        store.clickTorrent(id: ids[4], .toggle, visibleTorrentIDs: ids)
        XCTAssertEqual(try rowState(ids[1], in: store).selectionNumber, 1)
        XCTAssertEqual(try rowState(ids[2], in: store).selectionNumber, 2)
        XCTAssertNil(try rowState(ids[4], in: store).selectionNumber)

        // Nine is the last number a card can wear.
        store.selectAllTorrents(visibleTorrentIDs: Array(ids[0..<9]))
        XCTAssertNil(store.selectionCountShownInBar)
        XCTAssertEqual(try rowState(ids[8], in: store).selectionNumber, 9)

        store.selectAllTorrents(visibleTorrentIDs: ids)
        XCTAssertEqual(store.selectionCountShownInBar, 10)
        XCTAssertNil(try rowState(ids[1], in: store).selectionNumber)
    }

    func testToolbarStartsWhileAnySelectedDownloadIsStopped() {
        let running = makeTestRecord(status: .downloading)
        let stopped = makeTestRecord(status: .stopped)
        let seeding = makeTestRecord(status: .seeding, progress: 1)
        let store = makeBundle([running, stopped, seeding]).store
        let ids = [running.id, stopped.id, seeding.id]

        store.selectAllTorrents(visibleTorrentIDs: ids)
        XCTAssertTrue(store.isToolbarStartStopEnabled)
        XCTAssertEqual(store.toolbarRunAction, .start)
        XCTAssertTrue(store.canStartSelectedTorrents)
        XCTAssertTrue(store.canStopSelectedTorrents)

        store.clickTorrent(id: stopped.id, .toggle, visibleTorrentIDs: ids)
        XCTAssertEqual(store.toolbarRunAction, .stop)
        XCTAssertFalse(store.canStartSelectedTorrents)
        XCTAssertTrue(store.canStopSelectedTorrents)
    }

    func testCardsHiddenByASearchLeaveTheSelection() {
        let records = [makeTestRecord(), makeTestRecord(), makeTestRecord()]
        let store = makeBundle(records).store
        let ids = records.map(\.id)
        store.selectAllTorrents(visibleTorrentIDs: ids)

        store.clearHiddenSelection(visibleTorrentIDs: [ids[0], ids[2]])

        XCTAssertEqual(store.selectedTorrents.map(\.id), [ids[0], ids[2]])
    }

    func testRemovingSeveralFromTheListRemovesExactlyThem() async throws {
        let records = (0..<4).map { index in
            makeTestRecord(originalName: "Download \(index)", status: .stopped)
        }
        let bundle = makeBundle(records)
        let store = bundle.store
        let ids = records.map(\.id)
        await bundle.sessionStore.replaceAllRecordsForTesting(from: records)

        store.clickTorrent(id: ids[0], .plain, visibleTorrentIDs: ids)
        store.clickTorrent(id: ids[1], .toggle, visibleTorrentIDs: ids)
        store.clickTorrent(id: ids[3], .toggle, visibleTorrentIDs: ids)

        await store.removeTorrents(ids: store.selectedTorrents.map(\.id), policy: .removeFromListOnly)

        XCTAssertEqual(store.torrents.map(\.id), [ids[2]])
        XCTAssertEqual(store.selectedTorrentCount, 0)
        XCTAssertNil(store.payloadDeletionAlert)
        let snapshot = await bundle.sessionStore.load().snapshot
        XCTAssertEqual(snapshot?.torrents.map(\.torrentID), [ids[2]])
    }

    /// Unsafe or partial deletion stays visible: one message for all the
    /// downloads, and Finder can show what each of them left.
    func testFilesLeftBySeveralDownloadsAreReportedOnce() async throws {
        var saveRoots: [URL] = []
        var records: [TorrentRecord] = []
        for index in 0..<2 {
            let saveRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("RemoveSeveral-\(index)-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: saveRoot, withIntermediateDirectories: true)
            try Data("payload".utf8).write(
                to: saveRoot.appendingPathComponent("Movie.mkv", isDirectory: false),
                options: .atomic
            )
            saveRoots.append(saveRoot)
            // No file paths: which files belong to the download cannot be told.
            records.append(
                makeTestRecord(
                    originalName: "Download \(index)",
                    savePath: saveRoot.path,
                    selectedFileIndices: [0],
                    selectedFileRelativePaths: [],
                    selectedFileCount: 1,
                    totalFileCount: 1,
                    status: .completed,
                    progress: 1
                )
            )
        }

        let bundle = makeBundle(records)
        let store = bundle.store
        addTeardownBlock {
            saveRoots.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        await bundle.sessionStore.replaceAllRecordsForTesting(from: records)
        for (record, saveRoot) in zip(records, saveRoots) {
            await bundle.bookmarkStore.saveBookmark(for: record.id, url: saveRoot)
        }

        await store.removeTorrents(ids: records.map(\.id), policy: .removeFromListAndDeleteFiles)

        XCTAssertTrue(store.torrents.isEmpty)
        let alert = try XCTUnwrap(store.payloadDeletionAlert)
        XCTAssertEqual(
            alert.title,
            L10n.string("payload_deletion.several.title", localeOverride: store.preferences.localeOverride)
        )
        XCTAssertNotNil(alert.revealURL)
        XCTAssertEqual(alert.additionalRevealURLs.count, 1)
        for saveRoot in saveRoots {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: saveRoot.appendingPathComponent("Movie.mkv").path)
            )
        }
    }

    /// The count and the hint stay on one line in the narrowest window,
    /// 440 pt, in every language and for a count of any length in use.
    func testSelectionBarFitsOneLineInEveryLanguage() {
        for locale in AppLocaleOverride.allCases where locale != .system {
            for count in [2, 5, 21, 100, 1000] {
                let bar = ShatlSelectionCountBar(count: count, localeOverride: locale)
                    .fixedSize()
                    .shatlTypographyProfile(localeOverride: locale)

                let size = NSHostingView(rootView: bar).fittingSize
                XCTAssertLessThanOrEqual(size.width, 440, "\(locale.rawValue), \(count)")
            }
        }
    }
}
