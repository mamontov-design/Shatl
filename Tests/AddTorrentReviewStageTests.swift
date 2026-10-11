// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// The add window shows one thing at a time: nothing for a moment, a message
/// with its actions, or the files and the settings.
final class AddTorrentReviewStageTests: XCTestCase {
    private func stage(
        _ state: AddTorrentReviewState?,
        hasFiles: Bool = false,
        showsWaiting: Bool = false
    ) -> AddTorrentReviewStage {
        .current(reviewState: state, hasFiles: hasFiles, showsWaiting: showsWaiting)
    }

    /// A `.torrent` file is read at once: no message flashes before it.
    func testWaitingShowsNothingUntilItHasLasted() {
        XCTAssertEqual(stage(.loadingMetadata), .blank)
        XCTAssertEqual(stage(nil), .blank)
        XCTAssertEqual(stage(.loadingMetadata, showsWaiting: true), .message)
        XCTAssertEqual(stage(nil, showsWaiting: true), .message)
    }

    func testReadyDownloadShowsItsFilesAndSettings() {
        XCTAssertEqual(stage(.ready, hasFiles: true), .review)
        // Whether waiting was long enough no longer matters.
        XCTAssertEqual(stage(.ready, hasFiles: true, showsWaiting: true), .review)
    }

    /// A failure is shown at once, however short the wait was, and so is a
    /// torrent that turned out to hold no files.
    func testFailureAndEmptyTorrentAreMessages() {
        XCTAssertEqual(stage(.invalid(message: "")), .message)
        XCTAssertEqual(stage(.ready, hasFiles: false), .message)
    }

    func testMessageCarriesItsOwnActions() {
        XCTAssertEqual(
            AddTorrentReviewMessageActions.current(reviewState: .loadingMetadata, isKnownDuplicate: false),
            .cancel
        )
        XCTAssertEqual(
            AddTorrentReviewMessageActions.current(reviewState: nil, isKnownDuplicate: false),
            .cancel
        )
        XCTAssertEqual(
            AddTorrentReviewMessageActions.current(reviewState: .invalid(message: ""), isKnownDuplicate: false),
            .close
        )
        XCTAssertEqual(
            AddTorrentReviewMessageActions.current(reviewState: .invalid(message: ""), isKnownDuplicate: true),
            .showInListAndClose
        )
        XCTAssertEqual(
            AddTorrentReviewMessageActions.current(reviewState: .ready, isKnownDuplicate: false),
            .close
        )
    }
}
