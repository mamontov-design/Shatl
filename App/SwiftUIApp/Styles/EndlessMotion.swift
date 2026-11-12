// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

// Endless motion runs only while it can be seen. A closed Settings window
// is hidden, not taken apart, and its views live on with their animations:
// the speedometers' arrows went on swinging in it sixty times a second
// until Shatl quit, about a tenth of a core with the list standing still
// (measured on 2026-11-12). A view that moves without end therefore reads
// whether its window is on screen (`ShatlWindowVisibilityReader`) and,
// in Settings, whether its tab is the one open (`shatlTabIsShown`), and
// moves only while both hold: a swing through `ShatlEndlessSwing`, the
// wordmark's timeline paused, the logomark's loop keyed by them.

/// Swings its content between two states with `animation`, an endless one,
/// for as long as it is in the hierarchy. Taking it out is what ends the
/// animation: a change of the state without an animation leaves an endless
/// one running (`SettingsMotionVisibilityTests`).
struct ShatlEndlessSwing<Content: View>: View {
    let animation: Animation
    let content: (Bool) -> Content

    @State private var isSwung = false

    init(animation: Animation, @ViewBuilder content: @escaping (Bool) -> Content) {
        self.animation = animation
        self.content = content
    }

    var body: some View {
        content(isSwung)
            .onAppear {
                withAnimation(animation) {
                    isSwung = true
                }
            }
    }
}

private struct ShatlTabIsShownKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the Settings tab that holds a view is the one open. Outside
    /// Settings there is no tab to leave, and it stays true.
    var shatlTabIsShown: Bool {
        get { self[ShatlTabIsShownKey.self] }
        set { self[ShatlTabIsShownKey.self] = newValue }
    }
}

/// Whether the view's window is on screen and not wholly covered: false
/// once the window is closed, hidden, put in the Dock or out of the view's
/// reach, true again when it comes back.
struct ShatlWindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> ShatlWindowVisibilityView {
        let view = ShatlWindowVisibilityView()
        view.onChange = { isVisible = $0 }
        return view
    }

    func updateNSView(_ nsView: ShatlWindowVisibilityView, context: Context) {
        nsView.onChange = { isVisible = $0 }
    }
}

final class ShatlWindowVisibilityView: NSView {
    var onChange: ((Bool) -> Void)?

    private var observation: NSObjectProtocol?
    private var delivered: Bool?
    private var isDeliveryScheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindow()
        report()
    }

    isolated deinit {
        stopObserving()
    }

    static func isVisible(_ window: NSWindow?) -> Bool {
        window?.occlusionState.contains(.visible) ?? false
    }

    /// Hands the window's state over once the view update under way is
    /// done, and only when it changed: SwiftUI forbids changing its state
    /// while it draws, and a view moves into its window in such an update.
    private func report() {
        guard !isDeliveryScheduled else { return }

        isDeliveryScheduled = true
        Task { @MainActor [weak self] in
            self?.deliver()
        }
    }

    private func deliver() {
        isDeliveryScheduled = false
        let isVisible = Self.isVisible(window)
        guard isVisible != delivered else { return }

        delivered = isVisible
        onChange?(isVisible)
    }

    private func observeWindow() {
        stopObserving()

        guard let window else { return }

        observation = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
    }

    private func stopObserving() {
        if let observation {
            NotificationCenter.default.removeObserver(observation)
        }
        observation = nil
    }
}
