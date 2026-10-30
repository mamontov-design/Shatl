// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import XCTest
@testable import Shatl

/// A selected download card wears a circle in its top right corner: a check
/// mark, or its number among the selected ones; a selected option card in
/// Settings wears a check mark there. The circle is 16 pt as drawn, not as
/// laid out, and follows the corner of its card the way the metric plates
/// follow the download card's.
@MainActor
final class SelectionMarkTests: XCTestCase {
    func testTheMarkFollowsTheCornersOfBothCards() {
        XCTAssertEqual(ShatlSelectionMark.diameter, 16)
        XCTAssertEqual(ShatlSelectionMark.inset(in: TorrentCardLayout.cornerRadius), TorrentCardLayout.contentInset)
        XCTAssertEqual(ShatlSelectionMark.inset(in: ShatlCornerRadius.containerSelectionCorner), 10)
    }

    /// In a card of several lines the circle stands as far from the top as
    /// from the side, so its centre is the centre of the card's corner.
    func testTheMarkStandsInTheCornerOfAFullCard() throws {
        for number in [nil, 2] as [Int?] {
            let name = number.map { "number \($0)" } ?? "check mark"
            let drawn = try drawCard(makeTestRecord(status: .downloading, progress: 0.4), number: number)
            let mark = try XCTUnwrap(drawn.mark, name)

            XCTAssertEqual(mark.width, 16, accuracy: Self.accuracy, name)
            XCTAssertEqual(mark.height, 16, accuracy: Self.accuracy, name)
            XCTAssertEqual(drawn.width - mark.maxX, 10, accuracy: Self.accuracy, name)
            XCTAssertEqual(mark.minY, 10, accuracy: Self.accuracy, name)
        }
    }

    /// The font sets the expand symbol half a point low in its box; lifted,
    /// it is drawn in the middle of the title row, beside the circle at the
    /// row's top. Drawn in a window on a Retina screen, as the owner sees
    /// it: a picture renderer sets symbols drawn by a font half a point
    /// higher than a window does.
    func testTheExpandSymbolIsDrawnInTheMiddleOfItsRow() throws {
        let rowMiddle = TorrentCardLayout.contentInset + TorrentCardLayout.expandButtonSize / 2
        for expanded in [false, true] {
            let name = expanded ? "compress" : "expand"
            let drawn = try drawCard(
                makeTestRecord(status: .downloading, progress: 0.4),
                number: nil,
                isExpanded: expanded,
                inWindow: true
            )
            let expandSymbol = try XCTUnwrap(drawn.expandSymbol, name)

            XCTAssertEqual(expandSymbol.midY, rowMiddle, accuracy: 0.25, name)
        }
    }

    /// On one line the circle stands in the middle, with the title and the
    /// status badge beside it.
    func testTheMarkStandsInTheMiddleOfAOneLineCard() throws {
        for number in [nil, 2] as [Int?] {
            let name = number.map { "number \($0)" } ?? "check mark"
            let drawn = try drawCard(makeTestRecord(status: .seeding, progress: 1), number: number)
            let mark = try XCTUnwrap(drawn.mark, name)

            XCTAssertEqual(mark.width, 16, accuracy: Self.accuracy, name)
            XCTAssertEqual(mark.height, 16, accuracy: Self.accuracy, name)
            XCTAssertEqual(drawn.width - mark.maxX, 10, accuracy: Self.accuracy, name)
            XCTAssertEqual(mark.minY, drawn.height - mark.maxY, accuracy: Self.accuracy, name)
        }
    }

    /// The performance modes and the themes: the image container is rounded
    /// by 18 pt at the top right, so the mark stands 10 pt from its top and
    /// side, as on a download card.
    func testTheMarkStandsInTheCornerOfAnOptionCard() throws {
        let performance = ShatlSettingsInputCard(
            title: "Orbit",
            isSelected: true,
            imageContainerHeight: 100,
            imageContentVerticalPadding: 26,
            overlaysSelectionMark: true,
            action: {}
        ) {
            Color.clear.frame(width: 48, height: 48)
        }
        let theme = ShatlSettingsInputCard(
            title: "Auto",
            isSelected: true,
            imageContainerHeight: 81,
            action: {}
        ) {
            Color.clear.frame(width: 110, height: 76)
        }

        for (name, card) in [("performance", AnyView(performance)), ("theme", AnyView(theme))] {
            let bitmap = try draw(card.frame(width: 130))
            let mark = try XCTUnwrap(bitmap.mark(in: bitmap.cornerArea(bottom: 34)), name)

            XCTAssertEqual(mark.width, 16, accuracy: Self.accuracy, name)
            XCTAssertEqual(mark.height, 16, accuracy: Self.accuracy, name)
            XCTAssertEqual(bitmap.width - mark.maxX, 10, accuracy: Self.accuracy, name)
            XCTAssertEqual(mark.minY, 10, accuracy: Self.accuracy, name)
        }
    }

    /// The option card's image container is rounded by 20 pt, and by 18 pt
    /// only at the top right, where the mark stands: what a corner cuts away
    /// grows as the square of its radius.
    func testAnOptionCardRoundsTheMarksCornerLess() throws {
        let card = ShatlSettingsInputCard(
            title: "Orbit",
            isSelected: false,
            imageContainerHeight: 100,
            imageContentVerticalPadding: 26,
            overlaysSelectionMark: true,
            action: {}
        ) {
            Color.clear.frame(width: 48, height: 48)
        }
        let bitmap = try draw(card.frame(width: 130))
        let topLeft = bitmap.clearPixelCount(in: CGRect(x: 0, y: 0, width: 24, height: 24))
        let topRight = bitmap.clearPixelCount(in: CGRect(x: bitmap.width - 24, y: 0, width: 24, height: 24))
        let bottomRight = bitmap.clearPixelCount(in: CGRect(x: bitmap.width - 24, y: 100 - 24, width: 24, height: 24))

        XCTAssertGreaterThan(topLeft, 0)
        XCTAssertEqual(Double(bottomRight) / Double(topLeft), 1, accuracy: 0.03)
        let container = Double(ShatlCornerRadius.container)
        let markCorner = Double(ShatlCornerRadius.containerSelectionCorner)
        XCTAssertEqual(Double(topRight) / Double(topLeft), pow(markCorner / container, 2), accuracy: 0.03)
    }

    /// A theme card's preview window stands low enough that the mark keeps
    /// farther from the window's corner than from the container's edge.
    func testTheMarkKeepsClearOfTheThemePreview() throws {
        func themeCard(isSelected: Bool) -> some View {
            ShatlSettingsInputCard(
                title: "Light",
                isSelected: isSelected,
                imageContainerHeight: 81,
                action: {}
            ) {
                // The preview's picture, placed as `ThemeAppearanceDemo` does.
                Image("settingsCardImageThemeLight")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .frame(width: 110, height: 76, alignment: .top)
            }
            .frame(width: 130)
        }

        let selected = try draw(themeCard(isSelected: true))
        let mark = try XCTUnwrap(selected.mark(in: selected.cornerArea(bottom: 30)))
        XCTAssertEqual(mark.width, 16, accuracy: Self.accuracy)

        // The window's outline, drawn without the mark.
        let plain = try draw(themeCard(isSelected: false))
        let window = plain.inkedPoints(in: CGRect(x: plain.width - 64, y: 8, width: 56, height: 60), threshold: 24)
        XCTAssertFalse(window.isEmpty)

        let centre = CGPoint(x: mark.midX, y: mark.midY)
        let gap = window.map { hypot($0.x - centre.x, $0.y - centre.y) }.min()! - mark.width / 2
        let edge = ShatlSelectionMark.inset(in: ShatlCornerRadius.containerSelectionCorner)
        XCTAssertGreaterThan(gap, edge, "the mark stands \(gap) pt from the preview")
    }

    // MARK: - Drawing

    /// Four pixels to a point: an edge found at half coverage is within a
    /// pixel of where it is.
    private static let scale: CGFloat = 4
    private static let accuracy: CGFloat = 0.3

    private struct DrawnCard {
        var mark: CGRect?
        var expandSymbol: CGRect?
        var width: CGFloat
        var height: CGFloat
    }

    /// Draws the selected download card and finds the circle in its top
    /// right corner and the expand symbol to the left of it, in points. The
    /// outline and the progress bar are left out of the search.
    private func drawCard(
        _ record: TorrentRecord,
        number: Int?,
        isExpanded: Bool = false,
        inWindow: Bool = false
    ) throws -> DrawnCard {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        var row = try XCTUnwrap(bundle.store.torrentRowPresentationModel(for: record.id)).state
        row.isSelected = true
        row.selectionNumber = number
        row.isExpanded = isExpanded

        let card = TorrentCardView(
            row: row,
            resolvePrimaryLocation: { nil },
            onSelect: { true },
            onToggleExpanded: {},
            onOpen: {},
            onRevealInFinder: {},
            onToggleRunningState: {},
            onRedownload: {},
            onChooseAnotherFolder: {},
            onRemove: {},
            onRemoveWithFiles: {}
        )
        let bitmap = inWindow
            ? try drawInWindow(card, size: CGSize(width: 600, height: 120))
            : try draw(card.frame(width: 600))

        // The title row ends at 28 pt in a full card, and the progress bar
        // starts at 36 pt; a one-line card has nothing below its row.
        let bottom = row.usesFinishedLayout ? bitmap.height - 8 : 32
        // The expand button's box stands 8 pt to the left of the mark.
        let expandRight = bitmap.width - TorrentCardLayout.contentInset - ShatlSelectionMark.diameter - 8
        let expandArea = CGRect(
            x: expandRight - TorrentCardLayout.expandButtonSize,
            y: 8,
            width: TorrentCardLayout.expandButtonSize,
            height: bottom - 8
        )
        return DrawnCard(
            mark: bitmap.mark(in: bitmap.cornerArea(bottom: bottom)),
            expandSymbol: bitmap.mark(in: expandArea),
            width: bitmap.width,
            height: bitmap.height
        )
    }

    private func draw<V: View>(_ view: V) throws -> Bitmap {
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        return Bitmap(try XCTUnwrap(renderer.cgImage), scale: Self.scale)
    }

    /// Draws the view at the top of a window that is never shown, at the
    /// screen's scale; skips unless that is Retina.
    private func drawInWindow<V: View>(_ view: V, size: CGSize) throws -> Bitmap {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top))
        hosting.frame = CGRect(origin: .zero, size: size)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / size.width
        try XCTSkipUnless(scale == 2, "Drawn as on a Retina screen only.")
        return Bitmap(try XCTUnwrap(rep.cgImage), scale: scale)
    }

    private struct Bitmap {
        let pixelsWide: Int
        let pixelsHigh: Int
        let scale: CGFloat
        private let bytes: [UInt8]

        var width: CGFloat { CGFloat(pixelsWide) / scale }
        var height: CGFloat { CGFloat(pixelsHigh) / scale }

        init(_ image: CGImage, scale: CGFloat) {
            pixelsWide = image.width
            pixelsHigh = image.height
            self.scale = scale
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            self.bytes = bytes
        }

        /// The top right corner, 8 pt in from the edges: the outline of a
        /// card rounded by 20 pt or less stays outside it.
        func cornerArea(bottom: CGFloat) -> CGRect {
            CGRect(x: width - 32, y: 8, width: 24, height: bottom - 8)
        }

        /// The box of what is drawn in the area over the card's own ground
        /// (taken 5 pt below the card's top, in the middle), at half its
        /// strongest coverage; nil when nothing is drawn there.
        func mark(in area: CGRect) -> CGRect? {
            let ground = color(atX: pixelsWide / 2, y: Int(5 * scale))
            let xs = Int(area.minX * scale)..<Int(area.maxX * scale)
            let ys = Int(area.minY * scale)..<Int(area.maxY * scale)
            let distances = ys.flatMap { y in
                xs.map { x in (x: x, y: y, distance: zip(color(atX: x, y: y), ground).map { abs($0 - $1) }.max() ?? 0) }
            }
            guard let strongest = distances.map(\.distance).max(), strongest > 64 else { return nil }

            var covered = CGRect.null
            for pixel in distances where pixel.distance * 2 >= strongest {
                covered = covered.union(CGRect(x: pixel.x, y: pixel.y, width: 1, height: 1))
            }
            return CGRect(
                x: covered.minX / scale,
                y: covered.minY / scale,
                width: covered.width / scale,
                height: covered.height / scale
            )
        }

        /// The centres of the pixels in the area that differ from the card's
        /// ground by more than `threshold`, in points.
        func inkedPoints(in area: CGRect, threshold: Int) -> [CGPoint] {
            let ground = color(atX: pixelsWide / 2, y: Int(5 * scale))
            let xs = Int(area.minX * scale)..<Int(area.maxX * scale)
            let ys = Int(area.minY * scale)..<Int(area.maxY * scale)
            return ys.flatMap { y in
                xs.compactMap { x in
                    let distance = zip(color(atX: x, y: y), ground).map { abs($0 - $1) }.max() ?? 0
                    guard distance > threshold else { return nil }
                    return CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                }
            }
        }

        /// The pixels in the area that are mostly see-through: outside the
        /// card's shape.
        func clearPixelCount(in area: CGRect) -> Int {
            let xs = Int(area.minX * scale)..<Int(area.maxX * scale)
            let ys = Int(area.minY * scale)..<Int(area.maxY * scale)
            return ys.reduce(0) { count, y in
                count + xs.filter { x in color(atX: x, y: y)[3] < 128 }.count
            }
        }

        /// The first row is the top of the image.
        private func color(atX x: Int, y: Int) -> [Int] {
            let offset = (y * pixelsWide + x) * 4
            return (0..<4).map { Int(bytes[offset + $0]) }
        }
    }
}
