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

/// Files a drag carries beside its `.torrent` files. They stay out, and the
/// window says so: a count lower than the files dragged would otherwise
/// look like a loss.
nonisolated enum LeftOutFiles: Equatable, Sendable {
    /// One file, named, so the window can say which one stays out.
    case one(name: String)
    case several
}

/// What a window answers to a drag over it, or to a paste.
nonisolated enum DraggedDownloadOffer: Equatable, Sendable {
    /// The downloads a release adds, in the order the drag lists them; one
    /// or several go to one add window, as files opened from Finder do.
    /// `leftOut`: the files that are not `.torrent`, if the drag has any.
    case accept([DraggedDownload], leftOut: LeftOutFiles? = nil)
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
    /// A text may hold several links, one to a line.
    var offer: DraggedDownloadOffer {
        guard fileURLs.isEmpty else {
            var torrents: [URL] = []
            var others: [URL] = []
            for url in fileURLs {
                if url.pathExtension.lowercased() == "torrent" {
                    if !torrents.contains(url) { torrents.append(url) }
                } else if !others.contains(url) {
                    others.append(url)
                }
            }
            guard !torrents.isEmpty else { return .unsupported }
            let leftOut: LeftOutFiles? = switch others.count {
            case 0: nil
            case 1: .one(name: others[0].lastPathComponent)
            default: .several
            }
            return .accept(torrents.map(DraggedDownload.torrentFile), leftOut: leftOut)
        }

        var magnets: [URL] = []
        for text in texts {
            for word in text.split(whereSeparator: \.isWhitespace) {
                guard let url = URL(string: String(word)),
                      url.scheme?.lowercased() == "magnet",
                      !magnets.contains(url) else {
                    continue
                }
                magnets.append(url)
            }
        }

        guard !magnets.isEmpty else { return .unsupported }
        return .accept(magnets.map(DraggedDownload.magnetLink))
    }
}
