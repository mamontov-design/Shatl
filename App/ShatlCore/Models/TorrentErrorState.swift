// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Gives torrent cards and the add flow one error model
/// with consistent problem descriptions and recovery actions.
nonisolated struct TorrentErrorState: Identifiable, Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case missingContent
        case savePathUnavailable
        case invalidTorrentFile
        case invalidMagnet
        case metadataTimeout
        /// The wait for a file list ran out with no network at all.
        case noConnection
        case draftPreparationLost
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
        case dismiss
    }

    /// Why the engine stopped a running download, read from its file error.
    enum Cause: String, Codable, Sendable {
        case diskFull
        case noWriteAccess
        case diskError
        case filesMissing

        init?(posixCode: Int) {
            switch Int32(truncatingIfNeeded: posixCode) {
            case ENOSPC, EDQUOT:
                self = .diskFull
            case EACCES, EPERM, EROFS:
                self = .noWriteAccess
            case EIO, ENXIO, ENODEV:
                self = .diskError
            case ENOENT:
                self = .filesMissing
            default:
                return nil
            }
        }
    }

    var id: UUID = UUID()
    var kind: Kind
    var title: String
    var message: String
    var recoveryOptions: [RecoveryOption]
    /// For an error the engine reported while the download ran.
    var cause: Cause?
}
