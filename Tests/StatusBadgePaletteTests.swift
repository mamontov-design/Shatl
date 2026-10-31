// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XCTest
@testable import Shatl

/// A filled badge means the download is doing something: "Скачивается",
/// "Проверяется", "Раздаётся". The rest wear an outline without a fill,
/// "Скачана" and "Ошибка" too; the error's outline stays red in the
/// monochrome appearance.
@MainActor
final class StatusBadgePaletteTests: XCTestCase {
    func testOnlyWorkingStatusesAreFilled() {
        let filled: [ShatlStatusBadgePalette] = [.downloading, .seeding, .monochromaticFilled]
        let outlined: [ShatlStatusBadgePalette] = [
            .downloadingStalled, .saved, .paused, .seedingStalled, .completed, .error,
            .monochromaticStalled, .monochromaticSaved, .monochromaticError,
        ]

        for palette in filled {
            XCTAssertNil(palette.outline)
        }
        for palette in outlined {
            XCTAssertNotNil(palette.outline)
            for scheme in [ColorScheme.light, .dark] {
                XCTAssertEqual(resolved(palette.fill.rest, scheme).opacity, 0)
                XCTAssertEqual(resolved(palette.fill.hover, scheme).opacity, 0)
            }
        }
    }

    func testTheErrorKeepsItsRedOutlineInMonochrome() {
        let outline = ShatlStatusBadgePalette.monochromaticError.outline
        for scheme in [ColorScheme.light, .dark] {
            XCTAssertEqual(resolved(outline?.rest ?? .clear, scheme), resolved(ShatlColor.statusBadgeOutlineErrorDefault, scheme))
            XCTAssertEqual(resolved(outline?.hover ?? .clear, scheme), resolved(ShatlColor.statusBadgeOutlineErrorHover, scheme))
        }
    }

    private func resolved(_ color: Color, _ scheme: ColorScheme) -> Color.Resolved {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return color.resolve(in: environment)
    }
}
