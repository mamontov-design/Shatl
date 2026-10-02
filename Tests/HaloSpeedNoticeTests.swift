// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import XCTest
@testable import Shatl

/// Halo caps downloads at 5 MB/s and uploads at 2.5 MB/s. A bar under the
/// toolbar says so each time Halo is switched on, until "Больше не
/// показывать"; a Mac already in Halo sees it once at launch.
@MainActor
final class HaloSpeedNoticeTests: XCTestCase {
    private func makeStore(_ configure: (inout AppPreferences) -> Void = { _ in }) -> AppStore {
        var preferences = AppPreferences.defaultValue
        configure(&preferences)
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), preferences: preferences)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundle.rootURL) }
        return bundle.store
    }

    func testSwitchingToHaloShowsTheBarAndLeavingHidesIt() {
        let store = makeStore()
        XCTAssertFalse(store.isHaloSpeedNoticeVisible)

        store.setPerformanceProfile(.economical)
        XCTAssertTrue(store.isHaloSpeedNoticeVisible)
        XCTAssertTrue(store.preferences.hasSeenHaloSpeedNotice)

        // "Включить Orbit" and any other way out of Halo.
        store.setPerformanceProfile(.balanced)
        XCTAssertFalse(store.isHaloSpeedNoticeVisible)
    }

    func testGotItHidesTheBarUntilTheNextSwitchToHalo() {
        let store = makeStore()
        store.setPerformanceProfile(.economical)

        store.dismissHaloSpeedNotice()
        XCTAssertFalse(store.isHaloSpeedNoticeVisible)

        store.setPerformanceProfile(.maximum)
        store.setPerformanceProfile(.economical)
        XCTAssertTrue(store.isHaloSpeedNoticeVisible)
    }

    func testDontShowAgainIsKept() {
        let store = makeStore()
        store.setPerformanceProfile(.economical)

        store.stopShowingHaloSpeedNotice()
        XCTAssertFalse(store.isHaloSpeedNoticeVisible)
        XCTAssertFalse(store.preferences.showsHaloSpeedNotice)

        store.setPerformanceProfile(.balanced)
        store.setPerformanceProfile(.economical)
        XCTAssertFalse(store.isHaloSpeedNoticeVisible)
    }

    /// Halo chosen before the bar existed: shown once at launch, then only on
    /// a switch.
    func testHaloAtLaunchShowsTheBarOnce() async {
        let unseen = makeStore {
            $0.performanceProfile = .economical
            $0.hasSeenHaloSpeedNotice = false
        }
        unseen.bootstrapRuntimeState()
        let didShow = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            unseen.isHaloSpeedNoticeVisible
        }
        XCTAssertTrue(didShow)
        XCTAssertTrue(unseen.preferences.hasSeenHaloSpeedNotice)

        let seen = makeStore {
            $0.performanceProfile = .economical
            $0.hasSeenHaloSpeedNotice = true
        }
        seen.bootstrapRuntimeState()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(seen.isHaloSpeedNoticeVisible)
    }

    /// Preferences saved before the bar existed read as before, with the bar
    /// on and never seen.
    func testPreferencesWithoutTheBarFieldsRead() throws {
        let data = try JSONEncoder().encode(AppPreferences.defaultValue)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "showsHaloSpeedNotice")
        object.removeValue(forKey: "hasSeenHaloSpeedNotice")
        let older = try JSONSerialization.data(withJSONObject: object)

        let preferences = try JSONDecoder().decode(AppPreferences.self, from: older)
        XCTAssertTrue(preferences.showsHaloSpeedNotice)
        XCTAssertFalse(preferences.hasSeenHaloSpeedNotice)

        var changed = preferences
        changed.showsHaloSpeedNotice = false
        changed.hasSeenHaloSpeedNotice = true
        let reread = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(changed))
        XCTAssertFalse(reread.showsHaloSpeedNotice)
        XCTAssertTrue(reread.hasSeenHaloSpeedNotice)
    }

    /// The three buttons stay on one line in the narrowest window, 440 pt
    /// less the bar's 12 pt sides, in every language.
    func testButtonsFitOneLineInEveryLanguage() {
        let availableWidth: CGFloat = 440 - 12 * 2
        for locale in AppLocaleOverride.allCases where locale != .system {
            let buttons = MainWindowView.haloSpeedNoticeButtons(localeOverride: locale)
            let row = HStack(spacing: 8) {
                ForEach(buttons) { button in
                    ShatlButton(title: button.title, role: .lineMessage, action: {})
                }
            }
            .fixedSize()
            .shatlTypographyProfile(localeOverride: locale)

            let width = NSHostingView(rootView: row).fittingSize.width
            XCTAssertLessThanOrEqual(width, availableWidth, "\(locale.rawValue): \(buttons.map(\.title))")
        }
    }
}
