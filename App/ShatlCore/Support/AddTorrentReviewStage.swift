// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// What the add window shows as a whole. Each stage takes the whole window
/// and shares nothing with the next: one dissolves as the other comes, the
/// way the main window's stages do.
nonisolated enum AddTorrentReviewStage: Equatable, Sendable {
    /// Nothing yet: the download is being read and may be ready in a moment.
    /// A `.torrent` file is read at once, and a message shown for that
    /// moment would only flash.
    case blank
    /// A message in the middle of the window, with its own actions: waiting,
    /// a failure, or a torrent with no files.
    case message
    /// The files, the summary and the settings.
    case review

    /// `showsWaiting` turns true once waiting has lasted long enough to be
    /// worth a message.
    static func current(
        reviewState: AddTorrentReviewState?,
        hasFiles: Bool,
        showsWaiting: Bool
    ) -> AddTorrentReviewStage {
        switch reviewState {
        case .ready?:
            hasFiles ? .review : .message
        case .invalid?:
            .message
        case .loadingMetadata?, nil:
            showsWaiting ? .message : .blank
        }
    }
}

/// The actions a message in the add window carries. They sit in the message
/// itself, as everywhere else, and not in a corner of the window.
nonisolated enum AddTorrentReviewMessageActions: Equatable, Sendable {
    /// Still waiting: stop and close.
    case cancel
    /// Nothing can be downloaded: close the window.
    case close
    /// A duplicate of a download in the list: show it, or close the window.
    case showInListAndClose

    static func current(
        reviewState: AddTorrentReviewState?,
        isKnownDuplicate: Bool
    ) -> AddTorrentReviewMessageActions {
        switch reviewState {
        case .loadingMetadata?, nil:
            .cancel
        case .invalid?:
            isKnownDuplicate ? .showInListAndClose : .close
        case .ready?:
            .close
        }
    }
}
