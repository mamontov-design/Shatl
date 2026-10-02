// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

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
        /// The wait for a file list ran out with no network at all.
        case noConnection
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
        /// Look for an unavailable folder again: a disk plugged back in.
        case recheckFolder
        case downloadToDefaultFolder
        case dismiss
    }

    var id: UUID = UUID()
    var kind: Kind
    var title: String
    var message: String
    var recoveryOptions: [RecoveryOption]
}
