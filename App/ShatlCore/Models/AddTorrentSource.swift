// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated enum AddTorrentSourceKind: String, Codable, Sendable {
    case magnet
    case torrentFile
    case externalOpen
}

/// Keeps add sources independent from UI so the empty state, toolbar,
/// menu bar, and external open events use the same behavior.
nonisolated struct AddTorrentSource: Equatable, Codable, Sendable {
    var kind: AddTorrentSourceKind
    var rawValue: String
}
