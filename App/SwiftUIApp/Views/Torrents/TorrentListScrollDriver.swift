// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// What of the list is in sight, and where the list has to stand to show a
/// card. Plain arithmetic, apart from AppKit, in the coordinates of the
/// list's content: `origin` is the top of what the scroll view shows.
nonisolated struct TorrentListSight: Equatable, Sendable {
    var origin: CGFloat
    var viewportHeight: CGFloat
    var contentHeight: CGFloat
    /// How much of the scroll view's top the toolbar covers.
    var coveredTop: CGFloat = 0
    var coveredBottom: CGFloat = 0
    /// Room kept clear between a card and the edges of what is in sight.
    var topMargin: CGFloat = 0
    var bottomMargin: CGFloat = 0

    /// The list at its very top shows its content from under the toolbar.
    var lowestOrigin: CGFloat { -coveredTop }

    var highestOrigin: CGFloat {
        max(lowestOrigin, contentHeight - viewportHeight + coveredBottom)
    }

    func clamped(_ origin: CGFloat) -> CGFloat {
        min(max(origin, lowestOrigin), highestOrigin)
    }

    private func origin(forTopOf frame: CGRect) -> CGFloat {
        frame.minY - coveredTop - topMargin
    }

    private func origin(forBottomAt lowerEdge: CGFloat) -> CGFloat {
        lowerEdge + coveredBottom - viewportHeight
    }

    /// Where the list has to stand to show the card at `frame`, moved as
    /// little as possible; `nil` when the card is in sight already. A card
    /// taller than what is in sight shows its top.
    func origin(showing frame: CGRect) -> CGFloat? {
        let top = origin + coveredTop + topMargin
        let bottom = origin + viewportHeight - coveredBottom - bottomMargin

        let target: CGFloat
        if frame.minY < top || frame.height > bottom - top {
            target = origin(forTopOf: frame)
        } else if frame.maxY > bottom {
            target = origin(forBottomAt: frame.maxY + bottomMargin)
        } else {
            return nil
        }
        let clampedTarget = clamped(target)
        return abs(clampedTarget - origin) > 0.5 ? clampedTarget : nil
    }

    /// The next step after a card that is growing at `frame`: down, as far
    /// as the content already reaches, and never past the card's own top.
    /// `nil` when the card's lower edge is in sight.
    func origin(following frame: CGRect) -> CGFloat? {
        let lowerEdge = min(frame.maxY + bottomMargin, contentHeight)
        let target = clamped(min(origin(forBottomAt: lowerEdge), origin(forTopOf: frame)))
        return target > origin + 0.5 ? target : nil
    }

    /// Where the list belongs once `room`, added under the content while
    /// cards left, is taken away again; `nil` when it can stay where it is.
    func origin(afterTakingAway room: CGFloat) -> CGFloat? {
        var withoutRoom = self
        withoutRoom.contentHeight = contentHeight - room
        let target = withoutRoom.highestOrigin
        return origin > target + 0.5 ? target : nil
    }
}

/// Moves the main list's scroll position through AppKit.
///
/// SwiftUI's own animated scrolling is lost when something interrupts it:
/// the next request, or the list being drawn anew under it, which a running
/// download does every second. Arrows pressed faster than one scroll takes
/// left the selected card out of sight, and so did arrows pressed slowly over
/// running downloads (measured in October 2026; `ScrollPosition` loses them
/// the same way). A scroll set on the clip view itself is not lost: the last
/// request wins, wherever the list was on its way to.
///
/// One invisible view in the list's content, `TorrentListScrollAnchor`, is
/// all it needs to find the scroll view. It does nothing between requests.
@MainActor
final class TorrentListScrollDriver {
    fileprivate weak var anchorView: NSView?

    /// Room kept clear between a card brought into sight and the edges of
    /// the list: its own padding above, and under it the speed chips.
    var topMargin: CGFloat = 8
    var bottomMargin: CGFloat = 8

    private var scrollView: NSScrollView? {
        anchorView?.enclosingScrollView
    }

    /// Where the list stands, in the coordinates of its content.
    struct Position: Equatable {
        /// The scroll position, counted from the content's top.
        var offset: CGFloat
        var contentHeight: CGFloat
        var viewportHeight: CGFloat
    }

    private struct Reach {
        let scroll: NSScrollView
        let clip: NSClipView
        let document: NSView
    }

    private var reach: Reach? {
        guard let scroll = scrollView, let document = scroll.documentView else { return nil }
        return Reach(scroll: scroll, clip: scroll.contentView, document: document)
    }

    private func sight(of reach: Reach) -> TorrentListSight {
        // The toolbar covers the top of the scroll view; the scroll view
        // carries it as its top inset.
        let insets = reach.scroll.contentInsets
        return TorrentListSight(
            origin: reach.clip.bounds.origin.y,
            viewportHeight: reach.clip.bounds.height,
            contentHeight: reach.document.frame.height,
            coveredTop: insets.top,
            coveredBottom: insets.bottom,
            topMargin: topMargin,
            bottomMargin: bottomMargin
        )
    }

    var position: Position? {
        guard let reach else { return nil }
        let sight = sight(of: reach)
        return Position(
            offset: sight.origin - sight.lowestOrigin,
            contentHeight: sight.contentHeight,
            viewportHeight: sight.viewportHeight
        )
    }

    // MARK: A card brought into sight

    /// Glides the list just far enough to show `frame`, a card's frame in
    /// the content's coordinates. A card taller than the list shows its top.
    func reveal(_ frame: CGRect, duration: TimeInterval) {
        guard let reach, let origin = sight(of: reach).origin(showing: frame) else { return }
        move(to: origin, in: reach, duration: duration)
    }

    /// Sets the clip view's own origin. With a duration the move is
    /// AppKit's, and a newer one takes over from wherever it has got to.
    private func move(to origin: CGFloat, in reach: Reach, duration: TimeInterval) {
        let clip = reach.clip
        let point = NSPoint(x: clip.bounds.origin.x, y: origin)
        if duration > 0 {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = duration
            NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            clip.animator().setBoundsOrigin(point)
            NSAnimationContext.endGrouping()
        } else {
            clip.setBoundsOrigin(point)
        }
        reach.scroll.reflectScrolledClipView(clip)
    }

    // MARK: A card that grows

    private var followedFrame: CGRect?
    private var followObservation: NSObjectProtocol?
    private var followEnd: DispatchWorkItem?

    /// Keeps a card that is expanding in sight. The content grows a little
    /// with every frame of the expansion, and the list moves a step with it:
    /// the card's lower edge never leaves the window, and no animation of
    /// the list's own is needed. `duration` is how long the growth may take.
    func beginFollowing(for duration: TimeInterval) {
        endFollowing()
        guard let reach else { return }
        reach.document.postsFrameChangedNotifications = true
        followObservation = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: reach.document,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stepAfterFollowedFrame()
            }
        }
        let end = DispatchWorkItem { [weak self] in
            self?.endFollowing()
        }
        followEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: end)
    }

    /// The expanding card's frame, as SwiftUI lays it out; ignored outside a
    /// follow.
    func follow(_ frame: CGRect) {
        guard followObservation != nil else { return }
        followedFrame = frame
        stepAfterFollowedFrame()
    }

    private func stepAfterFollowedFrame() {
        guard let frame = followedFrame, let reach,
              let origin = sight(of: reach).origin(following: frame) else {
            return
        }
        move(to: origin, in: reach, duration: 0)
    }

    private func endFollowing() {
        if let followObservation {
            NotificationCenter.default.removeObserver(followObservation)
        }
        followObservation = nil
        followEnd?.cancel()
        followEnd = nil
        followedFrame = nil
    }

    // MARK: Cards that leave

    private var settleObservation: NSObjectProtocol?
    private var settleGiveUp: DispatchWorkItem?

    /// Glides the list down to where it belongs after cards have left.
    ///
    /// The content loses a leaving card's height at once, in one frame, and
    /// a list scrolled past its new end was pushed there in that frame: the
    /// cards fade out smoothly, the list jumped. The list view adds `room`
    /// under its content for the time of the removal, so nothing is pushed;
    /// once the content is laid out with it, the list glides to the end it
    /// will have without the room, and the room is then taken away unseen.
    ///
    /// Called before that layout, with the content still as tall as
    /// `heightBefore`. The glide waits for the content to change its height:
    /// worked out any sooner, from the old height less the new room, the
    /// end came out far too high and the list went to its top.
    func glideAfterRemoval(room: CGFloat, heightBefore: CGFloat, duration: TimeInterval) {
        cancelSettle()
        guard let reach else { return }

        reach.document.postsFrameChangedNotifications = true
        settleObservation = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: reach.document,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.settle(room: room, heightBefore: heightBefore, duration: duration)
            }
        }
        // Not kept past the removal: if the content never changed its
        // height, there was nothing to glide after.
        let giveUp = DispatchWorkItem { [weak self] in
            self?.cancelSettle()
        }
        settleGiveUp = giveUp
        DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 0.1), execute: giveUp)
    }

    private func settle(room: CGFloat, heightBefore: CGFloat, duration: TimeInterval) {
        guard settleObservation != nil, let reach else { return }
        let sight = sight(of: reach)
        // Still the old layout: the room is not under the content yet.
        guard abs(sight.contentHeight - heightBefore) > 0.5 else { return }
        cancelSettle()

        guard let origin = sight.origin(afterTakingAway: room) else { return }
        move(to: origin, in: reach, duration: duration)
    }

    private func cancelSettle() {
        if let settleObservation {
            NotificationCenter.default.removeObserver(settleObservation)
        }
        settleObservation = nil
        settleGiveUp?.cancel()
        settleGiveUp = nil
    }
}

/// The view through which `TorrentListScrollDriver` finds the list's scroll
/// view. It sits in the scrolled content, takes no room and draws nothing.
struct TorrentListScrollAnchor: NSViewRepresentable {
    let driver: TorrentListScrollDriver

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        driver.anchorView = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        driver.anchorView = view
    }
}
