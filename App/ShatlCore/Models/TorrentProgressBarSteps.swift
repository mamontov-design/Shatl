// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Where a card's progress bar stands. The bar moves in steps, not with every
/// byte: a download that grows a little each second no longer slides every
/// visible bar once a second. In the middle of a download a step is 2 %, and
/// longer with many downloads running: 5 % from the first card
/// simplification, 10 % from the second. The start keeps 2 % steps up to the
/// first long one, so a new download shows it has begun, and from 95 % the bar
/// counts each percent to 100, so the end of a download stays visible. The
/// percent beside the bar stays exact.
nonisolated enum TorrentProgressBarSteps {
    static let startStepPercent = 2
    static let fineStepsFromPercent = 95

    /// The step between the start and the end.
    static func middleStepPercent(for simplification: CardSimplificationLevel) -> Int {
        switch simplification {
        case .full: 2
        case .lighter: 5
        case .lightest: 10
        }
    }

    /// `progress` from 0 to 1; returns the fraction the bar shows.
    static func displayedProgress(
        _ progress: Double,
        simplification: CardSimplificationLevel = .full
    ) -> Double {
        guard progress.isFinite else { return 0 }

        let percent = Int((min(max(progress, 0), 1) * 100).rounded(.down))
        let middleStep = middleStepPercent(for: simplification)
        let step: Int
        if percent >= fineStepsFromPercent {
            step = 1
        } else if percent < middleStep {
            step = startStepPercent
        } else {
            step = middleStep
        }
        return Double(percent / step * step) / 100
    }
}
