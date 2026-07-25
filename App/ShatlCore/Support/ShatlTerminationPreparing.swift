// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

@MainActor
protocol ShatlTerminationPreparing: AnyObject {
    func prepareForTermination() async
}

@MainActor
protocol ShatlUserAttentionHandling: AnyObject {
    func setApplicationUserAttentionActive(_ isActive: Bool)
    func clearUserEventBadge()
}
