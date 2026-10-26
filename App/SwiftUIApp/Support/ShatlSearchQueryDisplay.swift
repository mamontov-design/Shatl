// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// A search query as a message about no results quotes it: trimmed, and a
/// long one cut to 32 characters with "…", so the title keeps to its block.
/// The main list and the add window's files quote it the same way.
nonisolated enum ShatlSearchQueryDisplay {
    static let maximumLength = 32

    static func trimmed(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func quoted(_ query: String) -> String {
        let trimmed = trimmed(query)
        guard trimmed.count > maximumLength else { return trimmed }
        return trimmed.prefix(maximumLength - 1).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
