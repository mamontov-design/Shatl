// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import XCTest
@testable import Shatl

/// A window takes `.torrent` files and magnet links from a drag or the
/// clipboard, one or several, and ignores the rest.
final class DraggedDownloadTests: XCTestCase {
    private let torrent = URL(fileURLWithPath: "/Users/example/Downloads/Northstar.torrent")
    private let otherTorrent = URL(fileURLWithPath: "/Users/example/Downloads/Aurora.TORRENT")
    private let picture = URL(fileURLWithPath: "/Users/example/Pictures/photo.jpg")
    private let magnet = "magnet:?xt=urn:btih:abcdef1234567890"

    func testOneTorrentFileIsAccepted() {
        XCTAssertEqual(
            DraggedContent(fileURLs: [torrent]).offer,
            .accept([.torrentFile(torrent)])
        )
        XCTAssertEqual(
            DraggedContent(fileURLs: [otherTorrent]).offer,
            .accept([.torrentFile(otherTorrent)])
        )
    }

    /// A drag of a file also carries its name as text.
    func testTextBesideAFileDoesNotCount() {
        XCTAssertEqual(
            DraggedContent(fileURLs: [torrent], texts: ["Northstar.torrent", magnet]).offer,
            .accept([.torrentFile(torrent)])
        )
    }

    /// Several `.torrent` files go to one add window, in the order dragged;
    /// other files stay out, and the window says so: one by its name.
    func testSeveralTorrentFilesAreTakenAndOtherFilesStayOut() {
        let both: [DraggedDownload] = [.torrentFile(torrent), .torrentFile(otherTorrent)]
        let notes = URL(fileURLWithPath: "/Users/example/Downloads/Northstar.nfo")

        XCTAssertEqual(DraggedContent(fileURLs: [torrent, otherTorrent]).offer, .accept(both))
        XCTAssertEqual(
            DraggedContent(fileURLs: [torrent, picture, otherTorrent]).offer,
            .accept(both, leftOut: .one(name: "photo.jpg"))
        )
        XCTAssertEqual(
            DraggedContent(fileURLs: [torrent, picture, picture]).offer,
            .accept([.torrentFile(torrent)], leftOut: .one(name: "photo.jpg"))
        )
        XCTAssertEqual(
            DraggedContent(fileURLs: [torrent, picture, otherTorrent, notes]).offer,
            .accept(both, leftOut: .several)
        )
        XCTAssertEqual(DraggedContent(fileURLs: [torrent, torrent]).offer, .accept([.torrentFile(torrent)]))
    }

    /// A long name of the one file left out is shortened in the middle, so
    /// its extension stays; several are not named.
    @MainActor
    func testTheDropScreenNamesTheOneFileLeftOut() throws {
        let one = try XCTUnwrap(MainWindowDropScreen.message(
            for: .accept([.torrentFile(torrent)], leftOut: .one(name: "Отпуск на море 2026 фото.jpg")),
            localeOverride: .russian
        ))
        XCTAssertTrue(one.contains("«Отпуск на мор…то.jpg»"), one)
        XCTAssertTrue(one.hasPrefix("Файл"), one)

        let short = try XCTUnwrap(MainWindowDropScreen.message(
            for: .accept([.torrentFile(torrent)], leftOut: .one(name: "photo.jpg")),
            localeOverride: .english
        ))
        XCTAssertTrue(short.contains("“photo.jpg”"), short)

        XCTAssertEqual(
            MainWindowDropScreen.message(for: .accept([.torrentFile(torrent)], leftOut: .several), localeOverride: .russian),
            L10n.string("main.drop.other_files.message", localeOverride: .russian)
        )
        XCTAssertNil(MainWindowDropScreen.message(for: .accept([.torrentFile(torrent)]), localeOverride: .russian))
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
        XCTAssertEqual(DraggedContent(texts: [magnet]).offer, .accept([.magnetLink(url)]))
        XCTAssertEqual(DraggedContent(texts: [magnet, magnet]).offer, .accept([.magnetLink(url)]))
        XCTAssertEqual(DraggedContent(texts: ["  \(magnet)\n"]).offer, .accept([.magnetLink(url)]))
        XCTAssertEqual(
            DraggedContent(texts: ["MAGNET:?xt=urn:btih:abcdef1234567890"]).offer,
            .accept([.magnetLink(try XCTUnwrap(URL(string: "MAGNET:?xt=urn:btih:abcdef1234567890")))])
        )
    }

    /// Several links go in their order, listed apart or copied as one text,
    /// a link to a line; the words around a link do not count.
    func testSeveralMagnetLinksAreAllTaken() throws {
        let other = "magnet:?xt=urn:btih:0987654321fedcba"
        let links: [DraggedDownload] = [
            .magnetLink(try XCTUnwrap(URL(string: magnet))),
            .magnetLink(try XCTUnwrap(URL(string: other))),
        ]
        XCTAssertEqual(DraggedContent(texts: [magnet, other]).offer, .accept(links))
        XCTAssertEqual(DraggedContent(texts: ["\(magnet)\n\(other)\n"]).offer, .accept(links))
        XCTAssertEqual(DraggedContent(texts: ["Season one: \(magnet)"]).offer, .accept([links[0]]))
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

    /// The window reads a drag from its pasteboard: a file as a file, a link
    /// as text, however the source listed it.
    @MainActor
    func testContentIsReadFromAPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ShatlTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.writeObjects([torrent as NSURL])
        XCTAssertEqual(DraggedContent(pasteboard: pasteboard).offer, .accept([.torrentFile(torrent)]))

        pasteboard.clearContents()
        pasteboard.setString(magnet, forType: .string)
        XCTAssertEqual(
            DraggedContent(pasteboard: pasteboard).offer,
            .accept([.magnetLink(try XCTUnwrap(URL(string: magnet)))])
        )

        // A browser lists a dragged link as a link and as its text.
        pasteboard.clearContents()
        pasteboard.writeObjects([try XCTUnwrap(URL(string: magnet)) as NSURL])
        pasteboard.pasteboardItems?.first?.setString(magnet, forType: .string)
        XCTAssertEqual(
            DraggedContent(pasteboard: pasteboard).offer,
            .accept([.magnetLink(try XCTUnwrap(URL(string: magnet)))])
        )

        pasteboard.clearContents()
        pasteboard.setString("Northstar season one", forType: .string)
        XCTAssertEqual(DraggedContent(pasteboard: pasteboard).offer, .unsupported)
    }

    func testAcceptedDownloadOpensByItsOwnAddress() throws {
        let url = try XCTUnwrap(URL(string: magnet))
        XCTAssertEqual(DraggedDownload.torrentFile(torrent).url, torrent)
        XCTAssertEqual(DraggedDownload.magnetLink(url).url, url)
    }
}

/// A drop or a paste adds downloads only when the add button would, and an
/// open add window takes them at its end.
@MainActor
final class DraggedDownloadStoreTests: XCTestCase {
    private func makeReadyStore() async -> TestStoreBundle {
        // Each source its own torrent: two drops are two downloads.
        let engine = FakeTorrentEngine()
        await engine.setNamesDraftsBySource(true)
        let bundle = makeTestStoreBundle(
            engine: engine,
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
        bundle.store.addDraggedDownloads([.torrentFile(URL(fileURLWithPath: "/tmp/early.torrent"))])
        XCTAssertNil(bundle.store.currentAddTorrentDraft)
    }

    /// With the add window open, the next drop or paste waits at its end,
    /// and the window stays on the download it shows. A link pasted again,
    /// as the message about an unreadable link asks, comes in this way.
    func testDroppedLinkOpensTheAddWindowAndTheNextOneWaitsAtItsEnd() async throws {
        let bundle = await makeReadyStore()
        XCTAssertTrue(bundle.store.acceptsDraggedDownloads)

        let link = try XCTUnwrap(URL(string: "magnet:?xt=urn:btih:abcdef1234567890"))
        bundle.store.addDraggedDownloads([.magnetLink(link)])

        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.source.kind, .magnet)
        XCTAssertTrue(bundle.store.isAddTorrentReviewWindowActive)
        XCTAssertTrue(bundle.store.acceptsDraggedDownloads)

        let next = try XCTUnwrap(URL(string: "magnet:?xt=urn:btih:0987654321fedcba"))
        bundle.store.addDraggedDownloads([.magnetLink(next)])

        let review = bundle.store.addTorrentReview
        XCTAssertEqual(review.items.map(\.draft.source.rawValue), [link.absoluteString, next.absoluteString])
        XCTAssertEqual(review.position, 1, "The window stays on the download it shows")
    }

    /// Several dropped at once open one add window, in the order dragged.
    func testSeveralDroppedFilesWaitInOneAddWindow() async {
        let bundle = await makeReadyStore()

        bundle.store.addDraggedDownloads([
            .torrentFile(URL(fileURLWithPath: "/tmp/Alpha.torrent")),
            .torrentFile(URL(fileURLWithPath: "/tmp/Bravo.torrent")),
        ])

        let review = bundle.store.addTorrentReview
        let areWaiting = await waitForCondition(timeoutNanoseconds: 2_000_000_000) { review.count == 2 }
        XCTAssertTrue(areWaiting)
        XCTAssertEqual(review.items.map(\.draft.source.rawValue), ["/tmp/Alpha.torrent", "/tmp/Bravo.torrent"])
        XCTAssertEqual(review.position, 1)
    }

    func testDroppedFileOpensTheAddWindow() async {
        let bundle = await makeReadyStore()

        bundle.store.addDraggedDownloads([.torrentFile(URL(fileURLWithPath: "/tmp/Northstar.torrent"))])

        XCTAssertEqual(bundle.store.currentAddTorrentDraft?.source.rawValue, "/tmp/Northstar.torrent")
        XCTAssertTrue(bundle.store.isAddTorrentReviewWindowActive)
    }

    func testNothingIsTakenWhileTheAddSheetIsOpen() async {
        let bundle = await makeReadyStore()

        bundle.store.presentAddTorrentEntry()

        XCTAssertFalse(bundle.store.acceptsDraggedDownloads)
    }
}
