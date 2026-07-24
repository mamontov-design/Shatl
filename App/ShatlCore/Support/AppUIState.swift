import Foundation

/// Keeps window UI state in the core so the store does not depend on SwiftUI.
enum PresentedModal: String, Identifiable {
    case addTorrentEntry
    case addTorrentReview

    var id: String { rawValue }
}
