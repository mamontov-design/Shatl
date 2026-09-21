// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Reports a durable-state failure separately from torrent and payload errors.
/// The attempted operation remains unchanged and can be retried safely.
nonisolated struct SessionPersistenceAlert: Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var message: String
}
