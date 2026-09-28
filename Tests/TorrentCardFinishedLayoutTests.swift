// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import XCTest
@testable import Shatl

/// A finished download takes one line in the list: its status badge beside
/// the title, without the progress bar or the status under it.
@MainActor
final class TorrentCardFinishedLayoutTests: XCTestCase {
    func testDownloadedAndSeedingCardsTakeOneLine() throws {
        let cases: [(record: TorrentRecord, isOneLine: Bool, name: String)] = [
            (makeTestRecord(status: .completed, progress: 1), true, "downloaded"),
            (makeTestRecord(status: .seeding, progress: 1), true, "seeding"),
            (makeTestRecord(status: .checking, progress: 1), true, "checking a finished download"),
            (makeTestRecord(status: .checking, progress: 0.999), false, "checking at 99 %"),
            (makeTestRecord(status: .downloading, progress: 0.999), false, "downloading"),
            (makeTestRecord(status: .stopped, progress: 0.5), false, "stopped"),
        ]
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: cases.map(\.record))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        for (record, isOneLine, name) in cases {
            let row = try XCTUnwrap(bundle.store.torrentRowPresentationModel(for: record.id)).state
            XCTAssertEqual(row.usesFinishedLayout, isOneLine, name)
        }
    }

    func testAFailedOrPendingCardKeepsTheFullLayout() throws {
        let record = makeTestRecord(status: .completed, progress: 1)
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        let finished = try XCTUnwrap(bundle.store.torrentRowPresentationModel(for: record.id)).state

        var failed = finished
        failed.errorState = TorrentRowErrorState(
            ShatlErrorCatalog.torrentActionError(
                for: TorrentEngineError(kind: .torrentNotFound, debugReason: "Missing archive")
            )
        )
        XCTAssertFalse(failed.usesFinishedLayout)

        var pending = finished
        pending.isPendingAddition = true
        XCTAssertFalse(pending.usesFinishedLayout)
    }

    /// Seeding starts with a check; the card shows the progress it last knew
    /// and stays on one line, only its status changes.
    func testACheckBeforeSeedingKeepsTheCardOnOneLine() throws {
        let record = makeTestRecord(status: .completed, progress: 1)
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        func apply(_ status: TorrentStatus, progress: Double) throws -> TorrentRowState {
            bundle.store.applySnapshotsForTesting([
                EngineTorrentSnapshot(id: record.id, status: status, progress: progress, metrics: record.metrics, errorState: nil),
            ])
            return try XCTUnwrap(bundle.store.torrentRowPresentationModel(for: record.id)).state
        }

        let checking = try apply(.checking, progress: 0.1)
        XCTAssertEqual(checking.status, .checking)
        XCTAssertTrue(checking.usesFinishedLayout)
        XCTAssertTrue(try apply(.seeding, progress: 1).usesFinishedLayout)
        // Missing pieces bring the full card back.
        XCTAssertFalse(try apply(.downloading, progress: 0.9).usesFinishedLayout)
    }

    /// Only the card that finished open closes: another may have opened
    /// meanwhile.
    func testClosingAFinishedCardLeavesAnotherOpenCardAlone() {
        let finished = makeTestRecord(status: .completed, progress: 1)
        let other = makeTestRecord(status: .downloading, progress: 0.4)
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: [finished, other])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        bundle.store.toggleExpanded(for: other.id)
        bundle.store.collapseExpanded(for: finished.id)
        XCTAssertEqual(bundle.store.expandedTorrentID, other.id)

        bundle.store.toggleExpanded(for: finished.id)
        bundle.store.collapseExpanded(for: finished.id)
        XCTAssertNil(bundle.store.expandedTorrentID)
    }

    /// A card built for a finished download, as at launch, is one line from
    /// the start: as tall as the status badge, with no steps to take.
    func testAFinishedCardIsBuiltOnOneLine() throws {
        let finished = makeTestRecord(status: .seeding, progress: 1)
        let downloading = makeTestRecord(status: .downloading, progress: 0.4)
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: [finished, downloading])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        func height(of record: TorrentRecord) throws -> CGFloat {
            let row = try XCTUnwrap(bundle.store.torrentRowPresentationModel(for: record.id)).state
            let card = TorrentCardView(
                row: row,
                resolvePrimaryLocation: { nil },
                onSelect: {},
                onToggleExpanded: {},
                onOpen: {},
                onRevealInFinder: {},
                onToggleRunningState: {},
                onRedownload: {},
                onChooseAnotherFolder: {},
                onRemove: {},
                onRemoveWithFiles: {}
            )
            let host = NSHostingView(rootView: card.frame(width: 600))
            return host.fittingSize.height
        }

        let cardPadding: CGFloat = 20
        XCTAssertEqual(try height(of: finished), ShatlMetricLayout.containerHeight + cardPadding, accuracy: 0.5)
        XCTAssertGreaterThan(try height(of: downloading), ShatlMetricLayout.containerHeight * 2 + cardPadding)
    }
}
