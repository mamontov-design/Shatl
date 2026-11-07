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
        /// A saved download was asked to start and still does not fit.
        case notEnoughSpace
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
    /// For `notEnoughSpace`: the disk and what it lacks.
    var spaceCheck: DiskSpaceCheck?
    /// For the add window: the message while other downloads wait in it.
    /// The single one says "Закройте окно…" for its button "Закрыть окно";
    /// among several that button gives way to "Следующая загрузка", and
    /// closing the window would take the others. `nil` when one text
    /// serves both.
    var messageAmongSeveral: String?
    /// For the add window: the title while other downloads wait in it,
    /// naming the download, as no file tree shows which one this is. `nil`
    /// when there is no name to give or the title is not about the download
    /// ("Нет подключения к интернету.").
    var titleAmongSeveral: String?
}
