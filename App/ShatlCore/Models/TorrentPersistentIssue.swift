// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Stores persistent card issues separately from transient runtime errors.
/// Persistent issues survive relaunch and participate in session restoration.
nonisolated struct TorrentPersistentIssue: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case missingContent
        case savePathUnavailable
    }

    var kind: Kind
    var detectedAt: Date
    var statusBeforeIssue: TorrentStatus?
    var debugReason: String?
}
