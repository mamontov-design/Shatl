// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
#if DEBUG
import os
#endif

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
/// The driver sets every step of a move itself, once per frame of the
/// display, and so depends on no animation context it is called in. It runs
/// only while something moves. One invisible view in the list's content,
/// `TorrentListScrollAnchor`, is all it needs to find the scroll view.
@MainActor
final class TorrentListScrollDriver {
    fileprivate weak var anchorView: NSView?

    /// Room kept clear between a card brought into sight and the edges of
    /// the list: its own padding above, and under it the speed chips.
    var topMargin: CGFloat = 8
    var bottomMargin: CGFloat = 8

    /// Where the list stands, in the coordinates of its scroll view.
    struct Position: Equatable {
        /// The top of what the scroll view shows.
        var origin: CGFloat
        var lowestOrigin: CGFloat
        var contentHeight: CGFloat
        var viewportHeight: CGFloat

        /// Away from its top: content that shrinks can push it.
        var isScrolled: Bool { origin > lowestOrigin + 0.5 }
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
            contentHeight: sight.contentHeight,
            viewportHeight: sight.viewportHeight
        )
    }

    // MARK: Moving

    private struct Glide {
        var from: CGFloat
        var to: CGFloat
        var start: CFTimeInterval
        var duration: TimeInterval
    }

    private var glide: Glide?
    private var glideEnd: DispatchWorkItem?
    private let ticker = TorrentListScrollTicker()
    /// Where the driver last put the list. Found elsewhere, the list was
    /// moved by someone else, the user's own scrolling first of all, and a
    /// glide gives way.
    private var lastSetOrigin: CGFloat?

    private func set(_ origin: CGFloat, in reach: Reach) {
        let clip = reach.clip
        // On whole pixels: text between them is drawn blurred.
        let scale = reach.scroll.window?.backingScaleFactor ?? 2
        let aligned = (origin * scale).rounded() / scale
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: aligned))
        reach.scroll.reflectScrolledClipView(clip)
        lastSetOrigin = clip.bounds.origin.y
    }

    /// Takes the list to `origin` over `duration`, slow at both ends. A
    /// newer glide takes over from wherever this one has got to.
    private func glide(to origin: CGFloat, in reach: Reach, duration: TimeInterval) {
        glideEnd?.cancel()
        glideEnd = nil
        guard duration > 0 else {
            glide = nil
            set(origin, in: reach)
            stopTickerIfIdle()
            return
        }
        glide = Glide(
            from: reach.clip.bounds.origin.y,
            to: origin,
            start: CACurrentMediaTime(),
            duration: duration
        )
        lastSetOrigin = reach.clip.bounds.origin.y
        startTicker(in: reach)

        // The display may not be drawing this window at all; the list
        // arrives all the same.
        let end = DispatchWorkItem { [weak self] in
            self?.finishGlide()
        }
        glideEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05, execute: end)
    }

    private func finishGlide() {
        guard let glide else { return }
        self.glide = nil
        glideEnd?.cancel()
        glideEnd = nil
        if let reach {
            set(glide.to, in: reach)
        }
        if following != nil {
            startFollowingFromHere()
        }
        stopTickerIfIdle()
    }

    private func cancelGlide() {
        glide = nil
        glideEnd?.cancel()
        glideEnd = nil
    }

    private func startTicker(in reach: Reach) {
        ticker.onFrame = { [weak self] in
            self?.frame() ?? false
        }
        ticker.start(on: reach.scroll)
    }

    private func stopTickerIfIdle() {
        if glide == nil, following == nil {
            ticker.stop()
        }
    }

    /// One frame of the display. Tells whether anything is still moving.
    private func frame() -> Bool {
        guard let reach else {
            cancelGlide()
            stopFollowing()
            return false
        }
        if let glide {
            if let lastSetOrigin, abs(reach.clip.bounds.origin.y - lastSetOrigin) > 1 {
                #if DEBUG
                trace("glide given up: the list was moved to \(Int(reach.clip.bounds.origin.y)) from outside")
                #endif
                cancelGlide()
            } else {
                let progress = (CACurrentMediaTime() - glide.start) / glide.duration
                if progress >= 1 {
                    finishGlide()
                } else {
                    let done = UnitCurve.easeInOut.value(at: progress)
                    set(glide.from + (glide.to - glide.from) * done, in: reach)
                }
            }
        } else if following != nil {
            frameWhileFollowing()
        }
        return glide != nil || following != nil
    }

    // MARK: A card brought into sight

    /// Glides the list just far enough to show `frame`, a card's frame in
    /// the content's coordinates. A card taller than the list shows its top.
    func reveal(_ frame: CGRect, duration: TimeInterval) {
        guard let reach else { return }
        // The card asked for now, not the one that was growing.
        stopFollowing()
        guard let origin = sight(of: reach).origin(showing: scrolled(frame, in: reach)) else {
            return
        }
        glide(to: origin, in: reach, duration: duration)
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
            #if DEBUG
            trace("expansion: card at \(Int(frame.minY))…\(Int(frame.maxY)), \(describe(reach))")
            #endif
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
    /// frame is first known, and when a glide has ended.
    private func startFollowingFromHere() {
        guard let follow = following, let frame = follow.frame, let reach else { return }
        let sight = sight(of: reach)
        let gap = sight.origin(following: frame).map { $0 - sight.origin } ?? 0
        let left = 1 - covered(follow.elapsed, of: follow.catchUp)
        // Almost no time left to cover it in: the last step takes it.
        following?.debt = left > 0.01 ? gap / left : 0
    }

    private func stepAfterFollowedCard() {
        // A glide in progress has the list; the following goes on after it.
        guard glide == nil, let follow = following, let frame = follow.frame, let reach else {
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
    /// Called before that layout, with the list standing at `before`. The
    /// glide waits for the content to be laid out with the room: worked out
    /// any sooner, from the old height less the new room, the end came out
    /// far too high and the list went to its top. Should the list have been
    /// pushed all the same before the room was there, it is put back first.
    func glideAfterRemoval(room: CGFloat, before: Position, duration: TimeInterval) {
        cancelSettle()
        stopFollowing()
        guard let reach else { return }
        #if DEBUG
        trace("removal: room \(Int(room)), \(describe(reach))")
        #endif

        reach.document.postsFrameChangedNotifications = true
        settleObservation = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: reach.document,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.settle(room: room, before: before, duration: duration)
            }
        }
        // Not kept past the removal: if the content never changed its
        // height, there was nothing to glide after.
        let giveUp = DispatchWorkItem { [weak self] in
            #if DEBUG
            if self?.settleObservation != nil {
                self?.trace("removal: gave up, the content was never laid out with the room")
            }
            #endif
            self?.cancelSettle()
        }
        settleGiveUp = giveUp
        DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 0.1), execute: giveUp)
    }

    private func settle(room: CGFloat, before: Position, duration: TimeInterval) {
        guard settleObservation != nil, let reach else { return }
        var sight = sight(of: reach)
        // Still without the room under the content: wait for it.
        guard sight.contentHeight >= room - 0.5,
              abs(sight.contentHeight - before.contentHeight) > 0.5,
              sight.highestOrigin >= before.origin - 0.5 else {
            #if DEBUG
            trace("removal: content changed, the room is not there yet, \(describe(reach))")
            #endif
            return
        }
        cancelSettle()

        if sight.origin < before.origin - 0.5 {
            // Pushed before the room was there; there is room for it now.
            #if DEBUG
            trace("removal: the list was pushed from \(Int(before.origin)) to \(Int(sight.origin)), put back")
            #endif
            cancelGlide()
            set(before.origin, in: reach)
            sight.origin = before.origin
        }
        guard let origin = sight.origin(afterTakingAway: room) else {
            #if DEBUG
            trace("removal: the list can stay, \(describe(reach))")
            #endif
            return
        }
        #if DEBUG
        trace("removal: gliding to \(Int(origin)) over \(duration) s, \(describe(reach))")
        #endif
        glide(to: origin, in: reach, duration: duration)
    }

    private func cancelSettle() {
        if let settleObservation {
            NotificationCenter.default.removeObserver(settleObservation)
        }
        settleObservation = nil
        settleGiveUp?.cancel()
        settleGiveUp = nil
    }

    #if DEBUG
    fileprivate var traceObservations: [NSObjectProtocol] = []
    fileprivate var tracedOrigin: CGFloat?
    fileprivate var tracedContentHeight: CGFloat?
    #endif
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

#if DEBUG
/// Debug builds only, and for the time being: a trace of where the list
/// stands, in the system log. In October 2026 a list barely taller than its
/// window still jumped in one frame as a card left it in the owner's window,
/// and nowhere else. To be removed with the cause found.
extension TorrentListScrollDriver {
    private static let logger = Logger(subsystem: "mamontov.design.shatl", category: "ListScroll")

    func trace(_ message: String) {
        Self.logger.notice("\(message, privacy: .public)")
    }

    fileprivate func describe(_ reach: Reach) -> String {
        let sight = sight(of: reach)
        let insets = reach.scroll.contentInsets
        var farBelow = reach.clip.bounds
        farBelow.origin.y = 1_000_000
        let highestByAppKit = reach.clip.constrainBoundsRect(farBelow).origin.y
        let contentOrigin = anchorView?.convert(NSPoint.zero, to: reach.clip) ?? .zero
        return "origin \(Int(sight.origin)) of \(Int(sight.lowestOrigin))…\(Int(sight.highestOrigin))"
            + " (AppKit: …\(Int(highestByAppKit))), content \(Int(reach.document.frame.minY))…\(Int(sight.contentHeight)),"
            + " viewport \(Int(sight.viewportHeight)), insets \(Int(insets.top))/\(Int(insets.bottom)),"
            + " covered \(Int(sight.coveredTop))/\(Int(sight.coveredBottom)), cards from \(Int(contentOrigin.y))"
    }

    /// Notes every change of the content's height and every step of the
    /// list longer than a glide makes, from whoever makes it.
    fileprivate func traceScrollView() {
        for observation in traceObservations {
            NotificationCenter.default.removeObserver(observation)
        }
        traceObservations = []
        guard let reach else { return }
        tracedOrigin = reach.clip.bounds.origin.y
        tracedContentHeight = reach.document.frame.height
        trace("list found: \(describe(reach))")

        reach.clip.postsBoundsChangedNotifications = true
        reach.document.postsFrameChangedNotifications = true
        traceObservations.append(NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: reach.clip,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let reach = self.reach else { return }
                let origin = reach.clip.bounds.origin.y
                if let before = self.tracedOrigin, abs(origin - before) > 12 {
                    self.trace("step: \(Int(before)) → \(Int(origin)), content \(Int(reach.document.frame.height))")
                }
                self.tracedOrigin = origin
            }
        })
        traceObservations.append(NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: reach.document,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let reach = self.reach else { return }
                let height = reach.document.frame.height
                if let before = self.tracedContentHeight, abs(height - before) > 12 {
                    self.trace("content: \(Int(before)) → \(Int(height)), origin \(Int(reach.clip.bounds.origin.y))")
                }
                self.tracedContentHeight = height
            }
        })
    }
}
#endif

/// The view through which `TorrentListScrollDriver` finds the list's scroll
/// view. It sits in the scrolled content, at its top left corner, takes no
/// room and draws nothing.
struct TorrentListScrollAnchor: NSViewRepresentable {
    let driver: TorrentListScrollDriver

    func makeNSView(context: Context) -> NSView {
        let view = AnchorView(frame: .zero)
        attach(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        attach(view)
    }

    private func attach(_ view: NSView) {
        driver.anchorView = view
        #if DEBUG
        (view as? AnchorView)?.onMoveToWindow = { [weak driver] in
            driver?.traceScrollView()
        }
        #endif
    }

    private final class AnchorView: NSView {
        var onMoveToWindow: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onMoveToWindow?()
        }
    }
}
