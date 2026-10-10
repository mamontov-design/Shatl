// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// The main window takes one `.torrent` file or one magnet link from a drag
/// or the clipboard, explains itself to several, and ignores the rest.
final class DraggedDownloadTests: XCTestCase {
    private let torrent = URL(fileURLWithPath: "/Users/example/Downloads/Northstar.torrent")
    private let otherTorrent = URL(fileURLWithPath: "/Users/example/Downloads/Aurora.TORRENT")
    private let picture = URL(fileURLWithPath: "/Users/example/Pictures/photo.jpg")
    private let magnet = "magnet:?xt=urn:btih:abcdef1234567890"

    func testOneTorrentFileIsAccepted() {
        XCTAssertEqual(
            DraggedContent(fileURLs: [torrent]).offer,
            .accept(.torrentFile(torrent))
        )
        XCTAssertEqual(
            DraggedContent(fileURLs: [otherTorrent]).offer,
            .accept(.torrentFile(otherTorrent))
        )
    }

    /// A drag of a file also carries its name as text.
    func testTextBesideAFileDoesNotCount() {
        XCTAssertEqual(
            DraggedContent(fileURLs: [torrent], texts: ["Northstar.torrent", magnet]).offer,
            .accept(.torrentFile(torrent))
        )
    }

    func testSeveralFilesWithATorrentAmongThemAreTooMany() {
        XCTAssertEqual(DraggedContent(fileURLs: [torrent, otherTorrent]).offer, .tooMany)
        XCTAssertEqual(DraggedContent(fileURLs: [torrent, picture]).offer, .tooMany)
    }

    func testOtherFilesAreNotTaken() {
        XCTAssertEqual(DraggedContent(fileURLs: [picture]).offer, .unsupported)
        XCTAssertEqual(
            DraggedContent(fileURLs: [picture, URL(fileURLWithPath: "/Users/example/Movies")]).offer,
            .unsupported
        )
    }

    /// A browser lists a dragged link as a link and as its text.
    func testOneMagnetLinkIsAcceptedHoweverManyTimesItIsListed() throws {
        let url = try XCTUnwrap(URL(string: magnet))
        XCTAssertEqual(DraggedContent(texts: [magnet]).offer, .accept(.magnetLink(url)))
        XCTAssertEqual(DraggedContent(texts: [magnet, magnet]).offer, .accept(.magnetLink(url)))
        XCTAssertEqual(DraggedContent(texts: ["  \(magnet)\n"]).offer, .accept(.magnetLink(url)))
        XCTAssertEqual(
            DraggedContent(texts: ["MAGNET:?xt=urn:btih:abcdef1234567890"]).offer,
            .accept(.magnetLink(try XCTUnwrap(URL(string: "MAGNET:?xt=urn:btih:abcdef1234567890"))))
        )
    }

    func testSeveralMagnetLinksAreTooMany() {
        XCTAssertEqual(
            DraggedContent(texts: [magnet, "magnet:?xt=urn:btih:0987654321fedcba"]).offer,
            .tooMany
        )
    }

    /// The app downloads nothing from the web itself, a `.torrent` included.
    func testWebLinksAndPlainTextAreNotTaken() {
        XCTAssertEqual(
            DraggedContent(texts: ["https://example.com/file.torrent"]).offer,
            .unsupported
        )
        XCTAssertEqual(DraggedContent(texts: ["Northstar season one"]).offer, .unsupported)
        XCTAssertEqual(DraggedContent().offer, .unsupported)
    }

    func testAcceptedDownloadOpensByItsOwnAddress() throws {
        let url = try XCTUnwrap(URL(string: magnet))
        XCTAssertEqual(DraggedDownload.torrentFile(torrent).url, torrent)
        XCTAssertEqual(DraggedDownload.magnetLink(url).url, url)
    }
}

/// A drop or a paste starts the add flow only when the add button would.
@MainActor
final class DraggedDownloadStoreTests: XCTestCase {
    private func makeReadyStore() async -> TestStoreBundle {
        let bundle = makeTestStoreBundle(
            engine: FakeTorrentEngine(),
            torrents: [makeTestRecord(status: .stopped, progress: 0.4)]
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        bundle.store.bootstrapRuntimeState()
        let isReady = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            !bundle.store.isRestoringSession && bundle.store.canAddTorrent
        }
        XCTAssertTrue(isReady)
        return bundle
    }

    func testNothingIsTakenBeforeTheListIsOpen() {
        let bundle = makeTestStoreBundle(
            engine: FakeTorrentEngine(),
            router: ExternalOpenRouter(),
            sessionStoreStartupMode: .requiresInitialLoad
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }

        XCTAssertFalse(bundle.store.acceptsDraggedDownloads)
        bundle.store.addDraggedDownload(.torrentFile(URL(fileURLWithPath: "/tmp/early.torrent")))
        XCTAssertNil(bundle.store.currentAddTorrentDraft)
    }

    func testDroppedLinkOpensTheAddWindowAndBlocksTheNextDrop() async throws {
        let bundle = await makeReadyStore()
        XCTAssertTrue(bundle.store.acceptsDraggedDownloads)

        let link = try XCTUnwrap(URL(string: "magnet:?xt=urn:btih:abcdef1234567890"))
        bundle.store.addDraggedDownload(.magnetLink(link))

        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.source.kind, .magnet)
        XCTAssertTrue(bundle.store.isAddTorrentReviewWindowActive)
        // One download at a time: the add window is busy with this one.
        XCTAssertFalse(bundle.store.acceptsDraggedDownloads)
    }

    func testDroppedFileOpensTheAddWindow() async {
        let bundle = await makeReadyStore()

        bundle.store.addDraggedDownload(.torrentFile(URL(fileURLWithPath: "/tmp/Northstar.torrent")))

        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.source.rawValue, "/tmp/Northstar.torrent")
        XCTAssertTrue(bundle.store.isAddTorrentReviewWindowActive)
    }

    func testNothingIsTakenWhileTheAddSheetIsOpen() async {
        let bundle = await makeReadyStore()

        bundle.store.presentAddTorrentEntry()

        XCTAssertFalse(bundle.store.acceptsDraggedDownloads)
    }
}
