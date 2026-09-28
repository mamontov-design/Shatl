// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Combine
import SwiftUI

/// Parts a Debug build can take off a card to find what makes scrolling
/// heavy. Release builds always keep every part, with the same view tree as
/// before the experiment.
enum TorrentCardDebugPart: String, CaseIterable, Identifiable {
    /// Every animation and transition below at once.
    case animations
    case progressBarAnimation
    case hoverAnimations
    case metricAnimations
    case statusAnimations
    case stateAnimations
    case titleTransition
    case digitRoll
    case metricBounce
    case metricHighlight
    case chipDigitRoll
    case metricShadows
    case fileCheck

    var id: Self { self }

    var logName: String {
        switch self {
        case .animations: "animations"
        case .progressBarAnimation: "progressbar"
        case .hoverAnimations: "hoveranim"
        case .metricAnimations: "metricanim"
        case .statusAnimations: "statusanim"
        case .stateAnimations: "stateanim"
        case .titleTransition: "title"
        case .digitRoll: "digits"
        case .metricBounce: "bounce"
        case .metricHighlight: "highlight"
        case .chipDigitRoll: "chipdigits"
        case .metricShadows: "shadows"
        case .fileCheck: "filecheck"
        }
    }

    var titleKey: String {
        "settings.debug.list.card_parts.\(rawValue)"
    }

    #if DEBUG
    /// What the frame meter counts when an animation of this part starts, and
    /// for how long: the longest animation in the part.
    var tracedAnimation: (kind: ShatlFrameTrace.AnimationKind, duration: Double)? {
        switch self {
        case .progressBarAnimation: (.progressBar, 0.45)
        case .hoverAnimations: (.hover, 0.2)
        case .metricAnimations: (.metricWidth, 0.5)
        case .statusAnimations: (.status, 0.48)
        case .stateAnimations: (.state, 0.28)
        case .metricHighlight: (.speedColor, ShatlMotion.metricSetBounceTotalDuration)
        default: nil
        }
    }
    #endif

    /// Parts that the switch for every animation also takes off.
    var isAnimation: Bool {
        switch self {
        case .progressBarAnimation, .hoverAnimations, .metricAnimations,
             .statusAnimations, .stateAnimations, .titleTransition,
             .digitRoll, .metricBounce, .metricHighlight, .chipDigitRoll:
            true
        default:
            false
        }
    }
}

/// Card modifiers a Debug build can take off. In Release each one is the
/// plain SwiftUI modifier, so the card keeps its exact view tree; in Debug a
/// small view modifier decides whether to apply it.
extension View {
    func cardAnimation<Value: Equatable>(
        _ animation: Animation?,
        value: Value,
        part: TorrentCardDebugPart
    ) -> some View {
        #if DEBUG
        modifier(RemovableCardAnimation(
            animation: animation,
            value: value,
            isRemoved: isCardPartRemoved(part),
            trace: part.tracedAnimation
        ))
        #else
        self.animation(animation, value: value)
        #endif
    }

    func cardContentTransition(_ transition: ContentTransition, part: TorrentCardDebugPart) -> some View {
        #if DEBUG
        modifier(RemovableCardContentTransition(transition: transition, isRemoved: isCardPartRemoved(part)))
        #else
        contentTransition(transition)
        #endif
    }

    /// An identity that makes a value change replace the view with a transition.
    func cardTransitionIdentity<ID: Hashable>(_ id: ID, part: TorrentCardDebugPart) -> some View {
        #if DEBUG
        modifier(RemovableCardIdentity(identity: id, isRemoved: isCardPartRemoved(part)))
        #else
        self.id(id)
        #endif
    }

    func cardTask<ID: Equatable>(id: ID, _ action: @escaping @isolated(any) () async -> Void) -> some View {
        #if DEBUG
        modifier(RemovableCardTask(id: id, action: action, isRemoved: isCardPartRemoved(.fileCheck)))
        #else
        task(id: id, action)
        #endif
    }

    /// The card whose animations the frame meter counts below this view.
    func cardAnimationTraceID(_ id: UUID) -> some View {
        #if DEBUG
        environment(\.shatlTracedCardID, id)
        #else
        self
        #endif
    }
}

#if DEBUG
extension View {
    /// Tells the frame meter when this animation starts.
    func cardAnimationTrace<Value: Equatable>(
        _ kind: ShatlFrameTrace.AnimationKind,
        value: Value,
        duration: Double
    ) -> some View {
        modifier(TracedCardAnimation(kind: kind, value: value, duration: duration))
    }
}

private nonisolated struct ShatlTracedCardIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    nonisolated var shatlTracedCardID: UUID? {
        get { self[ShatlTracedCardIDKey.self] }
        set { self[ShatlTracedCardIDKey.self] = newValue }
    }
}
#endif

func isCardPartRemoved(_ part: TorrentCardDebugPart) -> Bool {
    #if DEBUG
    let removedParts = TorrentCardDebugOptions.shared.removedParts
    return removedParts.contains(part) || (part.isAnimation && removedParts.contains(.animations))
    #else
    false
    #endif
}

#if DEBUG
private struct RemovableCardAnimation<Value: Equatable>: ViewModifier {
    let animation: Animation?
    let value: Value
    /// Read when the card draws, so a change of the switch redraws the card.
    let isRemoved: Bool
    let trace: (kind: ShatlFrameTrace.AnimationKind, duration: Double)?

    func body(content: Content) -> some View {
        if isRemoved {
            content
        } else if let trace {
            content
                .animation(animation, value: value)
                .modifier(TracedCardAnimation(kind: trace.kind, value: value, duration: trace.duration))
        } else {
            content.animation(animation, value: value)
        }
    }
}

private struct TracedCardAnimation<Value: Equatable>: ViewModifier {
    let kind: ShatlFrameTrace.AnimationKind
    let value: Value
    let duration: Double
    @Environment(\.shatlTracedCardID) private var cardID

    func body(content: Content) -> some View {
        content.onChange(of: value) {
            ShatlFrameTrace.animationStarted(kind, cardID: cardID, duration: duration)
        }
    }
}

private struct RemovableCardContentTransition: ViewModifier {
    let transition: ContentTransition
    /// Read when the card draws, so a change of the switch redraws the card.
    let isRemoved: Bool

    func body(content: Content) -> some View {
        if isRemoved {
            content
        } else {
            content.contentTransition(transition)
        }
    }
}

private struct RemovableCardIdentity<ID: Hashable>: ViewModifier {
    let identity: ID
    /// Read when the card draws, so a change of the switch redraws the card.
    let isRemoved: Bool

    func body(content: Content) -> some View {
        if isRemoved {
            content
        } else {
            content.id(identity)
        }
    }
}

private struct RemovableCardTask<ID: Equatable>: ViewModifier {
    let id: ID
    let action: @isolated(any) () async -> Void
    /// Read when the card draws, so a change of the switch redraws the card.
    let isRemoved: Bool

    func body(content: Content) -> some View {
        if isRemoved {
            content
        } else {
            content.task(id: id, action)
        }
    }
}

/// Debug builds only: the card simplification level to show, the one the
/// number of active downloads gives or one picked to compare. Not kept.
enum CardSimplificationChoice: String, CaseIterable, Identifiable {
    case automatic
    case full
    case lighter
    case lightest

    var id: Self { self }

    init(level: CardSimplificationLevel?) {
        switch level {
        case nil: self = .automatic
        case .full: self = .full
        case .lighter: self = .lighter
        case .lightest: self = .lightest
        }
    }

    var level: CardSimplificationLevel? {
        switch self {
        case .automatic: nil
        case .full: .full
        case .lighter: .lighter
        case .lightest: .lightest
        }
    }

    var titleKey: String {
        "settings.debug.list.simplification.\(rawValue)"
    }
}

/// Not kept between launches, so a part cannot stay off by accident.
final class TorrentCardDebugOptions: ObservableObject {
    static let shared = TorrentCardDebugOptions()

    @Published var removedParts: Set<TorrentCardDebugPart> = []

    var logName: String {
        let names = TorrentCardDebugPart.allCases
            .filter { removedParts.contains($0) }
            .map(\.logName)
        return names.isEmpty ? "-" : names.joined(separator: "+")
    }

    func isRemoved(_ part: TorrentCardDebugPart) -> Binding<Bool> {
        Binding(
            get: { self.removedParts.contains(part) },
            set: { isRemoved in
                if isRemoved {
                    self.removedParts.insert(part)
                } else {
                    self.removedParts.remove(part)
                }
            }
        )
    }
}
#endif
