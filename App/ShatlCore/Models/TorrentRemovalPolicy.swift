// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Defines removal policy independently so future dialogs do not change
/// the backend contract or session restoration.
nonisolated enum TorrentRemovalPolicy: Sendable {
    case removeFromListOnly
    case removeFromListAndDeleteFiles

    var shouldDeleteFiles: Bool {
        switch self {
        case .removeFromListOnly:
            false
        case .removeFromListAndDeleteFiles:
            true
        }
    }
}

nonisolated struct PayloadDeletionAlert: Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var message: String
    /// The files that stayed on disk, shown by the alert's "Show in Finder".
    var revealURL: URL?
}

/// One request to scroll the list to a download; a new one each time, so
/// asking twice for the same download scrolls twice.
nonisolated struct TorrentListRevealRequest: Identifiable, Equatable, Sendable {
    var id = UUID()
    var torrentID: UUID
}
