// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import XCTest
@testable import Shatl

/// A popover speaks its window's language. On macOS a plain popover keeps
/// every value its window was given but the locale, which it takes from the
/// system: with the language chosen in Debug, the "i" popovers in Settings
/// stayed in the system's language (found 2026-11-12). The test shows a
/// small window with a popover for about a second.
@MainActor
final class PopoverLocaleTests: XCTestCase {
    private static var seenLocale: String?
    private static var seenMonochrome: Bool?

    func testAPopoverSpeaksItsWindowsLanguage() throws {
        Self.seenLocale = nil
        Self.seenMonochrome = nil
        // Not the system's language, whatever the Mac speaks.
        let language = Locale.current.language.languageCode?.identifier == "fr" ? "de" : "fr"

        let window = makeWindow(
            Anchor()
                .environment(\.locale, Locale(identifier: language))
                .environment(\.shatlUsesMonochromeAppearance, true)
        )
        defer { window.orderOut(nil) }
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        XCTAssertEqual(Self.seenMonochrome, true, "The popover must have opened for this to test anything")
        XCTAssertEqual(Self.seenLocale, language)
    }

    private struct Anchor: View {
        @State private var isShown = false

        var body: some View {
            Color.clear
                .frame(width: 60, height: 40)
                .shatlPopover(isPresented: $isShown) {
                    Probe()
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(300))
                    isShown = true
                }
        }
    }

    private struct Probe: View {
        @Environment(\.locale) private var locale
        @Environment(\.shatlUsesMonochromeAppearance) private var usesMonochrome

        var body: some View {
            Text(verbatim: "Shatl")
                .padding(8)
                .onAppear {
                    PopoverLocaleTests.seenLocale = locale.identifier
                    PopoverLocaleTests.seenMonochrome = usesMonochrome
                }
        }
    }

    private func makeWindow<V: View>(_ view: V) -> NSWindow {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(
            contentRect: CGRect(x: visible.minX + 40, y: visible.maxY - 120, width: 80, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        return window
    }
}
