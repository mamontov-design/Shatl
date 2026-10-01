// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

enum OnboardingWindowLayout {
    /// The onboarding uses a fixed *window* frame. Its content height is
    /// derived from the active titlebar style so the caption never sits under
    /// the bottom edge of the window.
    static let windowSize = CGSize(width: 440, height: 500)

    static func contentSize(for window: NSWindow) -> NSSize {
        window.contentRect(
            forFrameRect: NSRect(origin: .zero, size: windowSize)
        ).size
    }
}

/// Owns the main-window presentation and resize policy while onboarding is in
/// the view tree. The ordinary window stays at the onboarding size afterwards,
/// but regains its normal chrome and resize limits when the flow completes.
struct OnboardingWindowSizeLock: NSViewRepresentable {
    let onWindowClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowClose: onWindowClose)
    }

    func makeNSView(context: Context) -> LockingView {
        let view = LockingView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: LockingView, context: Context) {
        context.coordinator.onWindowClose = onWindowClose
        if let window = nsView.window {
            context.coordinator.lock(window: window)
        }
    }

    static func dismantleNSView(_ nsView: LockingView, coordinator: Coordinator) {
        coordinator.restoreWindow()
    }

    final class LockingView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            coordinator?.lock(window: window)
        }

        override func layout() {
            super.layout()
            // A step transition can make SwiftUI reconfigure standard window
            // buttons without moving this view to a different window.
            coordinator?.enforceWindowLock()
        }
    }

    @MainActor
    final class Coordinator {
        var onWindowClose: () -> Void

        private weak var window: NSWindow?
        private var originalContentMinSize: NSSize?
        private var originalContentMaxSize: NSSize?
        private var originalZoomButtonEnabled: Bool?
        private var originalStyleMask: NSWindow.StyleMask?
        private var originalTitleVisibility: NSWindow.TitleVisibility?
        private var originalTitlebarAppearsTransparent: Bool?
        private var closeObservation: NSObjectProtocol?
        private var resizeObservation: NSObjectProtocol?
        private var activationObservation: NSObjectProtocol?
        private var didHandleWindowClose = false

        init(onWindowClose: @escaping () -> Void) {
            self.onWindowClose = onWindowClose
        }

        deinit {
            if let closeObservation {
                NotificationCenter.default.removeObserver(closeObservation)
            }
        }

        func lock(window: NSWindow) {
            if self.window !== window {
                restoreWindow()

                self.window = window
                originalContentMinSize = window.contentMinSize
                originalContentMaxSize = window.contentMaxSize
                originalZoomButtonEnabled = window.standardWindowButton(.zoomButton)?.isEnabled
                originalStyleMask = window.styleMask
                originalTitleVisibility = window.titleVisibility
                originalTitlebarAppearsTransparent = window.titlebarAppearsTransparent
                didHandleWindowClose = false

                closeObservation = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.handleWindowClose()
                    }
                }

                resizeObservation = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.enforceWindowLock()
                    }
                }

                activationObservation = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.enforceWindowLock()
                    }
                }
            }

            enforceWindowLock()
            scheduleWindowLockEnforcement()
        }

        /// SwiftUI configures its scene window and standard buttons after
        /// attaching view-backed modifiers. Re-apply the native policy on
        /// subsequent layout passes so every onboarding step stays locked.
        func enforceWindowLock() {
            guard let window else { return }

            if window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.remove(.fullSizeContentView)
            }
            if window.styleMask.contains(.resizable) {
                window.styleMask.remove(.resizable)
            }
            if window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = false
            }
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
            let lockedContentSize = OnboardingWindowLayout.contentSize(for: window)
            if window.contentMinSize != lockedContentSize {
                window.contentMinSize = lockedContentSize
            }
            if window.contentMaxSize != lockedContentSize {
                window.contentMaxSize = lockedContentSize
            }
            if window.contentView?.frame.size != lockedContentSize {
                window.setContentSize(lockedContentSize)
            }
            if window.standardWindowButton(.zoomButton)?.isEnabled == true {
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }
        }

        private func scheduleWindowLockEnforcement() {
            DispatchQueue.main.async { [weak self] in
                self?.enforceWindowLock()

                DispatchQueue.main.async { [weak self] in
                    self?.enforceWindowLock()
                }
            }
        }

        func restoreWindow() {
            if let closeObservation {
                NotificationCenter.default.removeObserver(closeObservation)
                self.closeObservation = nil
            }
            if let resizeObservation {
                NotificationCenter.default.removeObserver(resizeObservation)
                self.resizeObservation = nil
            }
            if let activationObservation {
                NotificationCenter.default.removeObserver(activationObservation)
                self.activationObservation = nil
            }

            guard let window else { return }
            if let originalContentMinSize {
                window.contentMinSize = originalContentMinSize
            }
            if let originalContentMaxSize {
                window.contentMaxSize = originalContentMaxSize
            }
            if let originalZoomButtonEnabled {
                window.standardWindowButton(.zoomButton)?.isEnabled = originalZoomButtonEnabled
            }
            if let originalStyleMask {
                window.styleMask = originalStyleMask
            }
            if let originalTitleVisibility {
                window.titleVisibility = originalTitleVisibility
            }
            if let originalTitlebarAppearsTransparent {
                window.titlebarAppearsTransparent = originalTitlebarAppearsTransparent
            }

            self.window = nil
            originalContentMinSize = nil
            originalContentMaxSize = nil
            originalZoomButtonEnabled = nil
            originalStyleMask = nil
            originalTitleVisibility = nil
            originalTitlebarAppearsTransparent = nil
        }

        private func handleWindowClose() {
            guard !didHandleWindowClose else { return }
            didHandleWindowClose = true
            onWindowClose()
        }
    }
}
