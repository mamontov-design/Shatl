// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// What of the list is in sight, and where the list has to stand to keep
/// a growing card in sight or to rest at its end. Plain arithmetic, apart
/// from AppKit, in the coordinates of the list's content: `origin` is the
/// top of what the scroll view shows.
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
    /// Where the list stands at its very top: under the toolbar its content
    /// starts lower than the scroll view does, so the origin goes below 0.
    var lowestOrigin: CGFloat = 0

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

    /// The next step after a card that is growing at `frame`: down, as far
    /// as the content already reaches, and never past the card's own top.
    /// `nil` when the card's lower edge is in sight.
    ///
    /// `debt` holds the list back by that much. A card that was partly out
    /// of sight when it began to grow has a way to go before its growth
    /// counts at all: taken at once, it was a jump before the expansion.
    /// The caller pays the debt off over the time the card grows.
    func origin(following frame: CGRect, heldBackBy debt: CGFloat = 0) -> CGFloat? {
        let lowerEdge = min(frame.maxY + bottomMargin, contentHeight)
        let whole = clamped(min(origin(forBottomAt: lowerEdge), origin(forTopOf: frame)))
        let target = whole - max(0, debt)
        // Half a pixel: the last step of the way is that short.
        return target > origin + 0.25 ? target : nil
    }

    /// Where the list belongs once `room`, added under the content while
    /// cards left, is taken away again: the end it will have then, or where
    /// it stands now when that is not past the end.
    func stand(afterTakingAway room: CGFloat) -> CGFloat {
        var withoutRoom = self
        withoutRoom.contentHeight = contentHeight - room
        return min(origin, withoutRoom.highestOrigin)
    }

    /// The same, as a move to make; `nil` when the list can stay.
    func origin(afterTakingAway room: CGFloat) -> CGFloat? {
        let stand = stand(afterTakingAway: room)
        return origin > stand + 0.5 ? stand : nil
    }
}

/// Moves the main list's scroll position through AppKit.
///
/// SwiftUI's own animated scrolling is lost when something interrupts it:
/// the next request, or the list being drawn anew under it, which a running
/// download does every second (measured in October 2026 on the arrows that
/// selected cards then; `ScrollPosition` loses a scroll the same way). A
/// scroll set on the clip view itself is not lost.
///
/// The driver moves the list in two cases: with a card that expands, and to
/// its new end after cards have left. For the second it is given a goal,
/// the end to stand at, and not a place: where the goal lies is worked out
/// anew with every frame of the display, from the list as it is then. The
/// list around the cards changes while it moves. The bar under the toolbar
/// comes and goes with the selection and takes the list from under the
/// toolbar and back; cards leave one after another; the content changes its
/// height over several frames. A place worked out once was wrong by the
/// time the list got there, and a list the system had moved meanwhile
/// looked like one moved by hand (the owner's recording of three downloads
/// removed at once).
///
/// The list moves by the system's spring, the one the cards move by, and
/// keeps its speed when the goal changes. It gives way only to scrolling by
/// hand. The driver runs while something moves and not otherwise. One
/// invisible view in the list's content, `TorrentListScrollAnchor`, is all
/// it needs to find the scroll view.
@MainActor
final class TorrentListScrollDriver {
    fileprivate weak var anchorView: NSView?

    /// Room kept clear between a card kept in sight and the edges of the
    /// list: its own padding above, and under it the speed chips.
    var topMargin: CGFloat = 8
    var bottomMargin: CGFloat = 8

    /// Where the list stands, in the coordinates of its scroll view.
    struct Position: Equatable {
        /// The top of what the scroll view shows.
        var origin: CGFloat
        var lowestOrigin: CGFloat
        var highestOrigin: CGFloat
        var contentHeight: CGFloat
        var viewportHeight: CGFloat

        /// Away from its top: content that shrinks can push it.
        var isScrolled: Bool { origin > lowestOrigin + 0.5 }
        /// Scrolled down as far as it goes. A list at its top is not, even
        /// when its top is also its end: content that grows under it leaves
        /// it at its top.
        var isAtItsEnd: Bool { isScrolled && origin >= highestOrigin - 0.5 }
    }

    fileprivate struct Reach {
        let scroll: NSScrollView
        let clip: NSClipView
        let document: NSView
    }

    private var reach: Reach? {
        guard let scroll = anchorView?.enclosingScrollView, let document = scroll.documentView else {
            return nil
        }
        return Reach(scroll: scroll, clip: scroll.contentView, document: document)
    }

    fileprivate func sight(of reach: Reach) -> TorrentListSight {
        // Where the list stands at its top is asked of the clip view itself:
        // it is where AppKit will hold the list, whatever insets it counts.
        var farAbove = reach.clip.bounds
        farAbove.origin.y = -1_000_000
        let lowestOrigin = min(0, reach.clip.constrainBoundsRect(farAbove).origin.y)

        // The toolbar covers the top of the scroll view. At its top the list
        // shows its content from under the toolbar, so where the content
        // starts then tells how much is covered.
        let coveredTop = max(0, reach.document.frame.minY - lowestOrigin)
        return TorrentListSight(
            origin: reach.clip.bounds.origin.y,
            viewportHeight: reach.clip.bounds.height,
            contentHeight: reach.document.frame.maxY,
            coveredTop: coveredTop,
            coveredBottom: reach.scroll.contentInsets.bottom,
            topMargin: topMargin,
            bottomMargin: bottomMargin,
            lowestOrigin: lowestOrigin
        )
    }

    /// A frame the list view measured in its content's coordinates, in the
    /// coordinates the scroll position is counted in. The anchor sits at the
    /// content's top left corner, so this holds wherever SwiftUI puts the
    /// content.
    private func scrolled(_ frame: CGRect, in reach: Reach) -> CGRect {
        guard let anchorView else { return frame }
        let contentOrigin = anchorView.convert(NSPoint.zero, to: reach.clip)
        return frame.offsetBy(dx: contentOrigin.x, dy: contentOrigin.y)
    }

    var position: Position? {
        guard let reach else { return nil }
        let sight = sight(of: reach)
        return Position(
            origin: sight.origin,
            lowestOrigin: sight.lowestOrigin,
            highestOrigin: sight.highestOrigin,
            contentHeight: sight.contentHeight,
            viewportHeight: sight.viewportHeight
        )
    }

    // MARK: Moving to a goal

    /// What decides where the list may stand. When it has changed between
    /// two frames, a move of the list is the system's own, made to keep the
    /// content where it was on screen; when it has not, the list was moved
    /// by hand.
    private struct Surroundings: Equatable {
        var viewportHeight: CGFloat
        var contentHeight: CGFloat
        var lowestOrigin: CGFloat
        var coveredBottom: CGFloat

        init(_ sight: TorrentListSight) {
            viewportHeight = sight.viewportHeight
            contentHeight = sight.contentHeight
            lowestOrigin = sight.lowestOrigin
            coveredBottom = sight.coveredBottom
        }
    }

    private struct Steering {
        /// The goal: the end the list will have once this much room under
        /// its content is gone.
        var room: CGFloat
        /// The goal is the end itself, wherever it now lies: content grew
        /// under a list that stood at its end, and the list goes down with
        /// it. Otherwise the list only gives back what it stands past its
        /// end.
        var keepsToTheEnd = false
        /// How long the move takes when nothing changes on the way; 0 for a
        /// move made at once.
        var duration: TimeInterval
        /// Where the list stands, finer than the pixels it is put on.
        var position: CGFloat
        var velocity: CGFloat = 0
        var lastFrame: CFTimeInterval
        /// Where the driver last put the list, on whole pixels.
        var lastSetOrigin: CGFloat
        var surroundings: Surroundings
        /// When the list last moved or anything around it last changed.
        var lastChange: CFTimeInterval
        /// The content's height as cards began to leave. Until it changes,
        /// the room is not laid out, and the end worked out from the old
        /// height less the new room comes out at the list's very top.
        var contentHeightBeforeRoom: CGFloat?
        /// Called once the list has arrived, or has given way.
        var onEnd: [() -> Void] = []
    }

    /// The list stays on its goal this long after everything has come to
    /// rest: the bar under the toolbar begins to move a frame or two after
    /// the change that brings it.
    private static let restBeforeLeavingGoal: TimeInterval = 0.2
    /// However things go, a move is over this long after its time.
    private static let patience: TimeInterval = 1.2

    private var steering: Steering?
    private var steeringDeadline: DispatchWorkItem?
    private var liveScrollObservation: NSObjectProtocol?
    private let ticker = TorrentListScrollTicker()

    private func set(_ origin: CGFloat, in reach: Reach) {
        let clip = reach.clip
        // On whole pixels: text between them is drawn blurred.
        let scale = reach.scroll.window?.backingScaleFactor ?? 2
        let aligned = (origin * scale).rounded() / scale
        guard abs(aligned - clip.bounds.origin.y) > 0.001 else { return }
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: aligned))
        reach.scroll.reflectScrolledClipView(clip)
    }

    /// Sets the list on its way to the end it will have without `room`. A
    /// move in progress goes on to the new goal from where it is and at the
    /// speed it has, and what waited for it to end waits for the new one.
    private func steer(
        toTheEndWithout room: CGFloat,
        keepingToTheEnd: Bool = false,
        duration: TimeInterval,
        in reach: Reach,
        onEnd: (() -> Void)? = nil
    ) {
        let now = CACurrentMediaTime()
        let sight = sight(of: reach)
        var next = Steering(
            room: room,
            keepsToTheEnd: keepingToTheEnd,
            duration: duration,
            position: sight.origin,
            lastFrame: now,
            lastSetOrigin: sight.origin,
            surroundings: Surroundings(sight),
            lastChange: now
        )
        if let steering {
            next.position = steering.position + (sight.origin - steering.lastSetOrigin)
            next.velocity = steering.velocity
            next.lastFrame = steering.lastFrame
            next.onEnd = steering.onEnd
            next.contentHeightBeforeRoom = steering.contentHeightBeforeRoom
        } else {
            next.contentHeightBeforeRoom = sight.contentHeight
        }
        if let onEnd {
            next.onEnd.append(onEnd)
        }
        steering = next

        if liveScrollObservation == nil {
            liveScrollObservation = NotificationCenter.default.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: reach.scroll,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.endSteering(takingTheListToItsGoal: false)
                }
            }
        }
        // The display may not be drawing this window at all; the list
        // arrives all the same.
        steeringDeadline?.cancel()
        let deadline = DispatchWorkItem { [weak self] in
            self?.endSteering(takingTheListToItsGoal: true)
        }
        steeringDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + Self.patience, execute: deadline)

        startTicker(in: reach)
    }

    /// Where the goal lies for a list standing at `position`, as things are
    /// now; `nil` while it cannot be told yet.
    private func stand(for steering: Steering, in sight: TorrentListSight) -> CGFloat? {
        var sight = sight
        sight.origin = steering.position
        if let before = steering.contentHeightBeforeRoom, abs(sight.contentHeight - before) < 0.5 {
            return nil
        }
        // Laid out without the room for a pass: wait for it.
        guard sight.contentHeight >= steering.room - 0.5 else { return nil }
        if steering.keepsToTheEnd {
            return sight.highestOrigin
        }
        return sight.stand(afterTakingAway: steering.room)
    }

    /// One frame of a move.
    private func steerOneFrame() {
        guard var steering, let reach else {
            endSteering(takingTheListToItsGoal: false)
            return
        }
        let sight = sight(of: reach)
        let now = CACurrentMediaTime()
        let surroundings = Surroundings(sight)
        let moved = sight.origin - steering.lastSetOrigin

        if surroundings != steering.surroundings {
            // The system keeps the content where it was as the list's
            // frame and insets change: the list goes on from there.
            steering.surroundings = surroundings
            steering.position += moved
            steering.lastChange = now
        } else if abs(moved) > 1 {
            endSteering(takingTheListToItsGoal: false)
            return
        }
        let deltaTime = min(max(now - steering.lastFrame, 0), 0.05)
        steering.lastFrame = now

        guard let stand = stand(for: steering, in: sight) else {
            steering.lastSetOrigin = sight.origin
            self.steering = steering
            return
        }
        steering.contentHeightBeforeRoom = nil

        let before = steering.position
        if steering.duration > 0 {
            Spring.smooth(duration: steering.duration).update(
                value: &steering.position,
                velocity: &steering.velocity,
                target: stand,
                deltaTime: deltaTime
            )
        } else {
            steering.position = stand
            steering.velocity = 0
        }
        let isOnGoal = abs(stand - steering.position) < 0.5 && abs(steering.velocity) < 8
        if isOnGoal {
            steering.position = stand
            steering.velocity = 0
        }
        if abs(steering.position - before) > 0.01 {
            steering.lastChange = now
        }
        set(steering.position, in: reach)
        steering.lastSetOrigin = reach.clip.bounds.origin.y
        self.steering = steering

        if isOnGoal, now - steering.lastChange >= Self.restBeforeLeavingGoal {
            endSteering(takingTheListToItsGoal: false)
        }
    }

    private func endSteering(takingTheListToItsGoal: Bool) {
        guard let steering else { return }
        self.steering = nil
        steeringDeadline?.cancel()
        steeringDeadline = nil
        if let liveScrollObservation {
            NotificationCenter.default.removeObserver(liveScrollObservation)
        }
        liveScrollObservation = nil

        if takingTheListToItsGoal, let reach, let stand = stand(for: steering, in: sight(of: reach)) {
            set(stand, in: reach)
        }
        for action in steering.onEnd {
            action()
        }
        if following != nil {
            startFollowingFromHere()
        }
        stopTickerIfIdle()
    }

    private func startTicker(in reach: Reach) {
        ticker.onFrame = { [weak self] in
            self?.frame() ?? false
        }
        ticker.start(on: reach.scroll)
    }

    private func stopTickerIfIdle() {
        if steering == nil, following == nil {
            ticker.stop()
        }
    }

    /// One frame of the display. Tells whether anything is still moving.
    private func frame() -> Bool {
        guard reach != nil else {
            endSteering(takingTheListToItsGoal: false)
            stopFollowing()
            return false
        }
        if steering != nil {
            steerOneFrame()
        } else if following != nil {
            frameWhileFollowing()
        }
        return steering != nil || following != nil
    }

    // MARK: A card that grows

    private struct Follow {
        /// How long the list takes to cover what was out of sight at first.
        var catchUp: TimeInterval
        /// The content's height as the following began.
        var contentHeight: CGFloat
        /// When the card began to grow on screen; `nil` until it has.
        var start: CFTimeInterval?
        var framesWaited = 0
        /// How far the list was from showing the card when it began to grow.
        var debt: CGFloat = 0
        var frame: CGRect?

        /// How far into the card's growth the clock is.
        var elapsed: TimeInterval {
            start.map { CACurrentMediaTime() - $0 } ?? 0
        }
    }

    private var following: Follow?
    private var followObservation: NSObjectProtocol?
    private var followEnd: DispatchWorkItem?

    /// Keeps a card that is expanding in sight.
    ///
    /// The content grows a little with every frame of the expansion, and
    /// the list goes down with it, so the card's lower edge does not leave
    /// the window. A card that was partly out of sight to begin with has
    /// that part to cover as well, and a card in the middle of the list is
    /// laid out at its full height at once. Taken in one step, either was a
    /// jump before the expansion: the list covers them over `catchUp`, the
    /// time the card takes to grow, along the curve the card grows by, and
    /// from the frame the card begins to grow in, so the two move as one.
    /// `duration` is how long the following lasts.
    func beginFollowing(for duration: TimeInterval, catchingUpOver catchUp: TimeInterval) {
        stopFollowing()
        guard let reach else { return }
        following = Follow(catchUp: catchUp, contentHeight: reach.document.frame.height)

        reach.document.postsFrameChangedNotifications = true
        followObservation = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: reach.document,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.contentChangedWhileFollowing()
            }
        }
        // What was out of sight is covered by the clock, whether or not the
        // content changes its height on a given frame.
        startTicker(in: reach)

        let end = DispatchWorkItem { [weak self] in
            self?.finishFollowing()
        }
        followEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: end)
    }

    /// The expanding card's frame, as SwiftUI reports it; ignored outside a
    /// follow.
    ///
    /// The frame has the card's full height from the first, and the card's
    /// place as it is on screen: under a card that collapses meanwhile it
    /// comes again with every frame, moving up. What is left to cover is
    /// counted once, from the first of them. Counted anew with each, the
    /// way never got shorter, and the list took it in one step at the end.
    func follow(_ frame: CGRect) {
        guard let follow = following, let reach else { return }
        let frame = scrolled(frame, in: reach)
        following?.frame = frame
        if follow.frame == nil {
            startFollowingFromHere()
        } else if follow.frame != frame, follow.start == nil {
            // The card moves: the cards have begun to change on screen.
            following?.start = CACurrentMediaTime()
        }
        stepAfterFollowedCard()
    }

    /// How much of the way is covered `elapsed` into `catchUp`: the cards'
    /// own curve, `Animation.smooth`.
    private func covered(_ elapsed: TimeInterval, of catchUp: TimeInterval) -> CGFloat {
        guard catchUp > 0 else { return 1 }
        let value = Spring.smooth(duration: catchUp).value(target: 1.0, initialVelocity: 0.0, time: max(0, elapsed))
        return CGFloat(min(max(value, 0), 1))
    }

    /// The content has changed its height: the first time it does, the card
    /// has begun to grow on screen, and the clock starts with it. Started
    /// with the request, it ran a frame or two ahead of the card, more after
    /// a card that took long to build, and the list set off before the card.
    private func contentChangedWhileFollowing() {
        guard let follow = following, let reach else { return }
        if follow.start == nil, abs(reach.document.frame.height - follow.contentHeight) > 0.01 {
            following?.start = CACurrentMediaTime()
        }
        stepAfterFollowedCard()
    }

    /// One frame of the display while following. A card that takes the room
    /// of a card collapsing under it leaves the content's height as it was,
    /// and stays where it is: the clock waits for neither longer than the
    /// frame the cards take to begin.
    private func frameWhileFollowing() {
        if var follow = following, follow.start == nil, follow.frame != nil {
            follow.framesWaited += 1
            if follow.framesWaited >= 2 {
                follow.start = CACurrentMediaTime()
            }
            following = follow
        }
        stepAfterFollowedCard()
    }

    /// Counts what is left to cover from where the list stands now, so the
    /// next step starts here and not with a jump: called when the card's
    /// frame is first known, and when a move of the list has ended.
    private func startFollowingFromHere() {
        guard let follow = following, let frame = follow.frame, let reach else { return }
        let sight = sight(of: reach)
        let gap = sight.origin(following: frame).map { $0 - sight.origin } ?? 0
        let left = 1 - covered(follow.elapsed, of: follow.catchUp)
        // Almost no time left to cover it in: the last step takes it.
        following?.debt = left > 0.01 ? gap / left : 0
    }

    private func stepAfterFollowedCard() {
        // A move in progress has the list; the following goes on after it.
        guard steering == nil, let follow = following, let frame = follow.frame, let reach else {
            return
        }
        // Not growing on screen yet: nothing is covered.
        let left = follow.start == nil ? 1 : 1 - covered(follow.elapsed, of: follow.catchUp)
        guard let origin = sight(of: reach).origin(following: frame, heldBackBy: follow.debt * left) else {
            return
        }
        set(origin, in: reach)
    }

    private func finishFollowing() {
        // Whatever is left of the way, in one last step.
        following?.debt = 0
        stepAfterFollowedCard()
        stopFollowing()
    }

    private func stopFollowing() {
        if let followObservation {
            NotificationCenter.default.removeObserver(followObservation)
        }
        followObservation = nil
        followEnd?.cancel()
        followEnd = nil
        following = nil
        stopTickerIfIdle()
    }

    // MARK: Cards that leave

    /// Takes the list down to where it belongs after cards have left.
    ///
    /// The content loses a leaving card's height at once, in one frame, and
    /// a list scrolled past its new end was pushed there in that frame: the
    /// cards fade out smoothly, the list jumped. The list view adds `room`
    /// under its content for the time of the removal, so nothing is pushed.
    /// The list goes to the end it will have without the room, wherever
    /// that end moves meanwhile, and `onSettled` is called once it stands
    /// there: the room can then be taken away unseen.
    ///
    /// Called before the room is laid out, and again for every card that
    /// leaves while the list is on its way.
    func settleAfterRemoval(room: CGFloat, duration: TimeInterval, onSettled: @escaping () -> Void) {
        guard let reach else {
            onSettled()
            return
        }
        stopFollowing()
        // One call when the list has settled is enough, however many cards
        // have left on the way.
        let isSettlingAlready = steering != nil
        steer(toTheEndWithout: room, duration: duration, in: reach, onEnd: isSettlingAlready ? nil : onSettled)
    }

    /// Content grows under a list that stands at its end: the speed chips
    /// come, and the room under the last card grows with them. The list
    /// goes down to its new end over `duration`, so the last card stays
    /// clear of the chips.
    ///
    /// Called before the content has grown; the list sets off once it has.
    func keepToTheEnd(duration: TimeInterval) {
        guard let reach else { return }
        stopFollowing()
        steer(toTheEndWithout: 0, keepingToTheEnd: true, duration: duration, in: reach)
    }
}

/// Calls back once per frame of the display while the list is being moved,
/// and not at all otherwise.
@MainActor
private final class TorrentListScrollTicker: NSObject {
    /// Tells whether to go on.
    var onFrame: (() -> Bool)?
    private var link: CADisplayLink?

    func start(on view: NSView) {
        guard link == nil else { return }
        let link = view.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if onFrame?() != true {
            stop()
        }
    }
}

/// The view through which `TorrentListScrollDriver` finds the list's scroll
/// view. It sits in the scrolled content, at its top left corner, takes no
/// room and draws nothing.
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
