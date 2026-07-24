import Foundation

/// A dedicated restore entry lets the engine resume after relaunch
/// without depending on UI or transient add-flow state.
nonisolated struct SessionRestoreEntry: Sendable {
    var torrentID: UUID
    var attemptID: UUID
    var archivedTorrentPath: String
    var suggestedSavePath: String
    var selectedFileIndices: [Int]
    var stopAfterDownload: Bool
    var shouldStart: Bool
}
