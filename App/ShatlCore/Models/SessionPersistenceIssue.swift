// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// A durable-state write failure is a condition, not a one-off event: the
/// main window keeps a line message until a session write succeeds again.
/// The attempted operation remains unchanged and can be retried safely.
nonisolated struct SessionPersistenceIssue: Identifiable, Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        /// A save that no user action waits for, such as progress or quit.
        case background
        case stop
        case recheck
        case removeFromList
        case removeWithFiles
        case redownload
    }

    var id = UUID()
    var kind: Kind
}
