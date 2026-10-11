// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import XCTest
@testable import Shatl

/// A message block replaces its icon in place, so the icon must not decide
/// the block's height: symbols of one font size are 25 to 34 pt tall, and a
/// new one moved the whole block in a single frame.
@MainActor
final class MessageBlockLayoutTests: XCTestCase {
    func testBlockHeightDoesNotDependOnItsIcon() {
        let icons = [
            "exclamationmark.circle",
            "wifi.slash",
            "doc.text.magnifyingglass",
            "tray",
            "hourglass",
            "exclamationmark.magnifyingglass",
            "document.badge.plus",
            "link.badge.plus",
            "clock.arrow.trianglehead.2.counterclockwise.rotate.90",
        ]

        let heights = icons.map { icon in
            NSHostingView(
                rootView: ShatlMessageBlockPrimary(
                    systemImage: icon,
                    title: "Не удалось получить список файлов.",
                    message: "Участники раздачи не ответили вовремя."
                )
                .fixedSize()
            )
            .fittingSize.height
        }

        XCTAssertEqual(Set(heights).count, 1, "\(Array(zip(icons, heights)))")
    }
}
