// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// How much the cards leave out so the list keeps scrolling smoothly with
/// many downloads running at once. The level follows the number of active
/// downloads: the list keeps every card alive, and each active card animates
/// its numbers every second, on screen or not. Measured on an M1 with the
/// demo list: 25 active downloads scrolled with 17 % late frames with
/// everything on, 5 % without the bounce and 2 % without the rolling digits.
nonisolated enum CardSimplificationLevel: Int, CaseIterable, Comparable, Sendable {
    /// Rolling digits, bouncing speed sets and metric shadows.
    case full
    /// No bounce and no metric shadows.
    case lighter
    /// Also digits that change without rolling, in cards and speed chips.
    case lightest

    /// Active downloads from which each level starts.
    var threshold: Int {
        switch self {
        case .full: 0
        case .lighter: 15
        case .lightest: 25
        }
    }

    /// A level ends only once the count falls this far below its threshold,
    /// so a count wavering at the threshold does not switch the cards back
    /// and forth.
    static let fallMargin = 3

    /// The level for `activeDownloads` that follows `previous`.
    static func level(activeDownloads: Int, previous: CardSimplificationLevel) -> CardSimplificationLevel {
        let plain = allCases.last { activeDownloads >= $0.threshold } ?? .full
        var level = max(previous, plain)
        while level > plain,
              activeDownloads < level.threshold - fallMargin,
              let lower = CardSimplificationLevel(rawValue: level.rawValue - 1) {
            level = lower
        }
        return level
    }

    /// Downloads whose numbers move: those downloading and those checking.
    static func activeDownloadCount(in records: [TorrentRecord]) -> Int {
        records.reduce(0) { count, record in
            record.status == .downloading || record.status == .checking ? count + 1 : count
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
