// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

enum ShatlMotion {
    /// Primary interface animation for revealing blocks and gently shifting adjacent elements.
    /// `response` controls speed; a lower `dampingFraction` creates a more noticeable bounce.
    static let interface = Animation.spring(response: 0.7, blendDuration: 0.08)

    /// Local animation for containers whose width changes as numbers update.
    static let metricResize = Animation.smooth(duration: metricResizeDuration)
    static let metricResizeDuration: TimeInterval = 0.5

    /// Durations for the one-shot metric-set keyframe animation.
    static let metricSetBounceUpDuration: TimeInterval = 0.14
    static let metricSetBounceHoldDuration: TimeInterval = 0.14
    static let metricSetBounceDownDuration: TimeInterval = 0.24
    static let metricSetBounceTotalDuration =
        metricSetBounceUpDuration + metricSetBounceHoldDuration + metricSetBounceDownDuration

    /// Color changes stay in sync with the complete bounce, including in previews.
    static let speedMetricColor = Animation.easeInOut(duration: metricSetBounceTotalDuration)

    /// Peak scale of the metric-set bounce animation.
    static let metricSetBounceScale: CGFloat = 1.1

    /// Local animation for card height changes as large blocks appear or disappear.
    static let cardLayout = Animation.smooth(duration: cardLayoutDuration)
    static let cardLayoutDuration: TimeInterval = 0.28

    /// Smooth content transformation for the pinned row when its folder changes.
    static let stickyContentReplace = Animation.smooth(duration: 0.38)

    /// Reveals the pinned row with a subtle lift from the list and no zoom.
    static let stickyPinInsertion = AnyTransition
        .offset(y: 8)
        .combined(with: .opacity)

    /// Fast, bouncy toast appearance over current content.
    static let messageToast = Animation.spring(response: 0.34, dampingFraction: 0.66, blendDuration: 0.02)
    static let messageToastTransition = AnyTransition
        .offset(y: 20)
        .combined(with: .opacity)

    /// Local animation for inserting and removing cards in the list.
    /// Bind only to stable torrent IDs, never to card runtime metrics.
    static let cardListMutation = Animation.smooth(duration: cardListMutationDuration)
    /// The main window waits this long after the last card leaves before it
    /// shows the empty state.
    static let cardListMutationDuration: TimeInterval = 0.42

    /// List-item transition with a subtle appearance and no movement of internal metrics.
    static let cardListItem = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.995, anchor: .top).combined(with: .opacity),
        removal: .scale(scale: 0.985, anchor: .center).combined(with: .opacity)
    )

    /// Transition between main window stages: the session placeholder, its
    /// failure, the empty state and the list. Every stage uses this one.
    static let mainContent = AnyTransition
        .scale(scale: 0.985, anchor: .center)
        .combined(with: .opacity)

    /// Animation of a main window stage change; also the bottom chips.
    static let mainContentMode = Animation.smooth(duration: 0.24)

    /// The session-reading message shows only if reading takes this long.
    static let sessionLoadMessageDelay = Duration.milliseconds(300)

    /// Reveals the session-restore status below the toolbar and replaces its completion content.
    static let sessionRestoreStatusBar = Animation.smooth(duration: 0.32)
    static let sessionRestoreStatusContent = Animation.smooth(duration: 0.36)

    /// Smooth presentation and caption change between onboarding steps.
    static let onboardingStepChange = Animation.smooth(duration: 0.48)

    /// Local progress-bar fill animation.
    static let progressBarFill = Animation.smooth(duration: 0.45)

    /// Local animation for a status or progress badge whose width changes with its value.
    static let progressGroupResize = Animation.smooth(duration: 0.32)

    /// Native blur-replace animation for the torrent card's external status label.
    static let progressStatusReplace = Animation.smooth(duration: 0.48)

    /// Local animation for trailing control icons in a card.
    static let cardControlSlide = Animation.smooth(duration: 0.24)

    /// Local animation for the selected-card indicator.
    static let selectedIndicatorAppear = Animation.spring(response: 0.48, dampingFraction: 0.62, blendDuration: 0.04)
    static let selectedIndicatorDisappear = Animation.smooth(duration: 0.16)

    /// Local toolbar-button animation for availability and symbol changes.
    static let toolbarState = Animation.smooth(duration: 0.18)
    static let toolbarSymbolReplace = Animation.smooth(duration: 0.22)

    /// Local animation for changing a card's visual state.
    static let cardState = Animation.smooth(duration: 0.2)

    /// Short color pulse after pressing a selection card.
    static let inputCardActivationPulseIn = Animation.smooth(duration: 0.12)
    static let inputCardActivationPulseHoldDuration = Duration.milliseconds(100)
    static let inputCardActivationPulseOut = Animation.smooth(duration: 0.3)

    /// A busy button keeps its progress title at least this long, so a fast
    /// result does not flicker.
    static let busyButtonMinimumDuration = Duration.seconds(1)

    /// A download that finishes shows its new status for a second, once the
    /// status has changed, before its card starts folding into one line.
    static let finishedCardPause: TimeInterval = metricResizeDuration + 1

    /// A finished card's last step: the title slides aside, and the status
    /// badge comes in once the title is out of its way. On the way back it
    /// goes at once, before the title moves over it.
    static let finishedStatusDelay = cardLayoutDuration * 0.6
    static let finishedStatusSettleDuration = finishedStatusDelay + metricResizeDuration
    static let finishedStatusBesideTitle = AnyTransition.asymmetric(
        insertion: appearFromTop.animation(metricResize.delay(finishedStatusDelay)),
        removal: .identity
    )
    /// Parts of the full card come back once the title above them has
    /// settled, so none passes under it.
    static let finishedCardPartReturn = AnyTransition.opacity
        .animation(cardLayout.delay(cardLayoutDuration / 2))

    /// Shared transition for elements inserted into an existing layout:
    /// the element shrinks and fades when hidden, then returns to full size and opacity.
    static let appearFromTop = AnyTransition
        .scale(scale: 0.85, anchor: .center)
        .combined(with: .opacity)

    /// Reverse transition for blocks that should fade gently upward.
    static let disappearFromTop = AnyTransition.asymmetric(
        insertion: appearFromTop,
        removal: .scale(scale: 0.85, anchor: .center).combined(with: .opacity)
    )

    /// The selection indicator appears from its center with a slight overshoot and shrinks away.
    static let selectedIndicator = AnyTransition.asymmetric(
        insertion: .scale(scale: 1.5, anchor: .center)
            .combined(with: .opacity)
            .animation(selectedIndicatorAppear),
        removal: .scale(scale: 1.5, anchor: .center)
            .combined(with: .opacity)
            .animation(selectedIndicatorDisappear)
    )
}

// MARK: - Animation Environment

private struct ShatlMetricSetOutlinePulseEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ShatlMetricSetOutlineFlashTriggerKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct ShatlDownloadSpeedOutlineFlashTriggerKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct ShatlRollsMetricDigitsKey: EnvironmentKey {
    static let defaultValue = true
}

private struct ShatlMetricSetBounceEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct ShatlMetricSetOutlinePulseColorKey: EnvironmentKey {
    static let defaultValue = ShatlColor.metricPulseHighlight
}

private struct ShatlMetricSetOutlineFlashColorKey: EnvironmentKey {
    static let defaultValue = ShatlColor.metricPulseHighlight
}

extension EnvironmentValues {
    var shatlMetricSetOutlinePulseEnabled: Bool {
        get { self[ShatlMetricSetOutlinePulseEnabledKey.self] }
        set { self[ShatlMetricSetOutlinePulseEnabledKey.self] = newValue }
    }

    var shatlMetricSetOutlineFlashTrigger: Int {
        get { self[ShatlMetricSetOutlineFlashTriggerKey.self] }
        set { self[ShatlMetricSetOutlineFlashTriggerKey.self] = newValue }
    }

    var shatlDownloadSpeedOutlineFlashTrigger: Int {
        get { self[ShatlDownloadSpeedOutlineFlashTriggerKey.self] }
        set { self[ShatlDownloadSpeedOutlineFlashTriggerKey.self] = newValue }
    }

    /// Whether metric numbers roll their digits; off at the deepest card
    /// simplification.
    var shatlRollsMetricDigits: Bool {
        get { self[ShatlRollsMetricDigitsKey.self] }
        set { self[ShatlRollsMetricDigitsKey.self] = newValue }
    }

    var shatlMetricSetBounceEnabled: Bool {
        get { self[ShatlMetricSetBounceEnabledKey.self] }
        set { self[ShatlMetricSetBounceEnabledKey.self] = newValue }
    }

    var shatlMetricSetOutlinePulseColor: Color {
        get { self[ShatlMetricSetOutlinePulseColorKey.self] }
        set { self[ShatlMetricSetOutlinePulseColorKey.self] = newValue }
    }

    var shatlMetricSetOutlineFlashColor: Color {
        get { self[ShatlMetricSetOutlineFlashColorKey.self] }
        set { self[ShatlMetricSetOutlineFlashColorKey.self] = newValue }
    }
}
