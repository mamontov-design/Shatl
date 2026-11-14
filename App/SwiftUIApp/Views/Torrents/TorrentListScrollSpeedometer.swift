// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Observation
import QuartzCore

/// Tells how fast the list of downloads moves, from where its clip view
/// stands, and says when it becomes too fast to read and when it calms
/// down (`TorrentListScrollPace`). It reads AppKit directly and redraws
/// nothing: a scroll must not make SwiftUI do any work of its own.
@MainActor
final class TorrentListScrollSpeedometer {
    /// Called when the list becomes fast, and when it is no longer.
    var onFastChange: (@MainActor (Bool) -> Void)?
    #if DEBUG
    /// The Debug readout over the list, while it is shown.
    var readout: TorrentListScrollReadout?
    #endif

    private var pace = TorrentListScrollPace()
    private weak var clip: NSClipView?
    private var observation: NSObjectProtocol?
    private var stillCheck: Task<Void, Never>?

    /// Watches the scroll view the list is in; `nil` when the list has
    /// left its window.
    func watch(_ scroll: NSScrollView?) {
        let newClip = scroll?.contentView
        guard newClip !== clip else { return }
        stopWatching()
        guard let newClip else { return }
        clip = newClip
        newClip.postsBoundsChangedNotifications = true
        observation = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: newClip,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clipMoved()
            }
        }
    }

    private func stopWatching() {
        if let observation {
            NotificationCenter.default.removeObserver(observation)
        }
        observation = nil
        clip = nil
        stillCheck?.cancel()
        stillCheck = nil
        let wasFast = pace.isFast
        pace = TorrentListScrollPace()
        report(wasFast: wasFast)
    }

    private func clipMoved() {
        guard let clip else { return }
        let wasFast = pace.isFast
        pace.note(origin: Double(clip.bounds.origin.y), at: CACurrentMediaTime())
        report(wasFast: wasFast)
        scheduleStillCheck()
    }

    /// One check pending at a time, not one per frame: it asks the pace
    /// when to look next (the list stands, then it is calm) and looks again
    /// later if the list has moved since.
    private func scheduleStillCheck() {
        guard stillCheck == nil else { return }
        stillCheck = Task { @MainActor [weak self] in
            while true {
                guard let self, let next = self.pace.nextStillCheck(after: CACurrentMediaTime()) else { break }
                let wait = next - CACurrentMediaTime()
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                guard !Task.isCancelled else { return }
                let wasFast = self.pace.isFast
                self.pace.noteStill(at: CACurrentMediaTime())
                self.report(wasFast: wasFast)
            }
            self?.stillCheck = nil
        }
    }

    private func report(wasFast: Bool) {
        if pace.isFast != wasFast {
            onFastChange?(pace.isFast)
        }
        #if DEBUG
        readout?.show(speed: pace.speed, isFast: pace.isFast, at: CACurrentMediaTime())
        #endif
    }
}

#if DEBUG
/// What the Debug readout over the list shows: the list's speed, whether
/// the cards hold their numbers back, and how many wait for their point in
/// the second. It changes ten times a second at most while the list moves.
@MainActor
@Observable
final class TorrentListScrollReadout {
    private(set) var speed = 0
    private(set) var isFast = false
    var waitingCount = 0
    @ObservationIgnored private var shownAt = 0.0

    func show(speed: Double, isFast: Bool, at time: Double) {
        let rounded = Int(speed.rounded())
        guard isFast != self.isFast || (rounded == 0) != (self.speed == 0) || time - shownAt >= 0.1 else {
            return
        }
        shownAt = time
        if self.speed != rounded {
            self.speed = rounded
        }
        if self.isFast != isFast {
            self.isFast = isFast
        }
    }
}
#endif
