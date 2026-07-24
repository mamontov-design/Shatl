import Foundation

/// Gives torrent cards and the add flow one error model
/// with consistent problem descriptions and recovery actions.
nonisolated struct TorrentErrorState: Identifiable, Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case missingContent
        case missingFolder
        case savePathUnavailable
        case invalidTorrentFile
        case invalidMagnet
        case metadataTimeout
        case draftPreparationLost
        case insufficientDiskSpace
        case duplicateTorrent
        case torrentNotFound
        case engineFailure
    }

    enum RecoveryOption: String, Codable, Sendable {
        case retry
        case redownload
        case removeFromList
        case chooseAnotherFolder
        case downloadToDefaultFolder
        case dismiss
    }

    var id: UUID = UUID()
    var kind: Kind
    var title: String
    var message: String
    var recoveryOptions: [RecoveryOption]
}
