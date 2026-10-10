// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// One download a drag or a paste can add: a `.torrent` file or a magnet link.
nonisolated enum DraggedDownload: Equatable, Sendable {
    case torrentFile(URL)
    case magnetLink(URL)

    /// What the add flow opens, the same as for a file from Finder or a link
    /// from a browser.
    var url: URL {
        switch self {
        case let .torrentFile(url), let .magnetLink(url):
            url
        }
    }
}

/// What the main window answers to a drag over it.
nonisolated enum DraggedDownloadOffer: Equatable, Sendable {
    /// One download: the window invites to release it.
    case accept(DraggedDownload)
    /// Several: downloads are added one at a time, and the window says so.
    case tooMany
    /// Nothing the window adds: it stays as it is.
    case unsupported
}

/// What a drag or the clipboard carries, as the system lists it.
nonisolated struct DraggedContent: Equatable, Sendable {
    var fileURLs: [URL] = []
    /// Links and plain text. A browser puts a dragged link here twice, as a
    /// link and as its text.
    var texts: [String] = []

    /// Files decide alone: a drag of files also carries their names as text.
    /// Only `.torrent` files and magnet links count; a web link to a
    /// `.torrent` does not, as the app downloads nothing from the web itself.
    var offer: DraggedDownloadOffer {
        guard fileURLs.isEmpty else {
            let torrents = fileURLs.filter { $0.pathExtension.lowercased() == "torrent" }
            guard let torrent = torrents.first else { return .unsupported }
            return fileURLs.count == 1 ? .accept(.torrentFile(torrent)) : .tooMany
        }

        var magnets: [URL] = []
        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed),
                  url.scheme?.lowercased() == "magnet",
                  !magnets.contains(url) else {
                continue
            }
            magnets.append(url)
        }

        guard let magnet = magnets.first else { return .unsupported }
        return magnets.count == 1 ? .accept(.magnetLink(magnet)) : .tooMany
    }
}
