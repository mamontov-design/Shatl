import AppKit
import Foundation

@MainActor
enum TorrentFileNavigationPresenter {
    static func open(_ location: ManagedTorrentLocation) {
        guard let openItemURL = location.openItemURL else { return }
        NSWorkspace.shared.open(openItemURL)
    }

    static func revealInFinder(_ location: ManagedTorrentLocation) {
        NSWorkspace.shared.activateFileViewerSelecting([location.revealItemURL])
    }
}
