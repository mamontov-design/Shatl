// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Where a card's progress bar stands. The bar moves in steps, not with every
/// byte: a download that grows a little each second no longer slides every
/// visible bar once a second. Below 95 % a step is 2 %; from there the bar
/// counts each percent to 100, so the end of a download stays visible. The
/// percent beside the bar stays exact.
nonisolated enum TorrentProgressBarSteps {
    static let coarseStepPercent = 2
    static let fineStepsFromPercent = 95

    /// `progress` from 0 to 1; returns the fraction the bar shows.
    static func displayedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }

        let percent = Int((min(max(progress, 0), 1) * 100).rounded(.down))
        let step = percent < fineStepsFromPercent ? coarseStepPercent : 1
        return Double(percent / step * step) / 100
    }
}
