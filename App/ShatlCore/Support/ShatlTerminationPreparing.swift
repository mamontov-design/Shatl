// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

@MainActor
protocol ShatlTerminationPreparing: AnyObject {
    /// Returns `true` only when the durable session state is safe to close.
    /// A `false` result leaves the last committed session untouched on disk.
    func prepareForTermination() async -> Bool
}

@MainActor
protocol ShatlUserAttentionHandling: AnyObject {
    func setApplicationUserAttentionActive(_ isActive: Bool)
    func clearUserEventBadge()
}
