// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import XCTest
@testable import Shatl

/// A selected card wears a circle in its top right corner: a check mark, or
/// its number among the selected ones. The circle is 16 pt as drawn, not as
/// laid out, and follows the card's corner the way the metric plates do.
@MainActor
final class TorrentCardSelectionMarkTests: XCTestCase {
    func testTheMarkFollowsTheCardCorner() {
        XCTAssertEqual(TorrentCardLayout.selectionMarkDiameter, 16)
        XCTAssertEqual(
            TorrentCardLayout.contentInset + TorrentCardLayout.selectionMarkDiameter / 2,
            TorrentCardLayout.cornerRadius
        )
    }

    /// In a card of several lines the circle stands as far from the top as
    /// from the side, so its centre is the centre of the card's corner.
    func testTheMarkStandsInTheCornerOfAFullCard() throws {
        for number in [nil, 2] as [Int?] {
            let name = number.map { "number \($0)" } ?? "check mark"
            let drawn = try drawnMark(of: makeTestRecord(status: .downloading, progress: 0.4), number: number)

            XCTAssertEqual(drawn.mark.width, 16, accuracy: Self.accuracy, name)
            XCTAssertEqual(drawn.mark.height, 16, accuracy: Self.accuracy, name)
            XCTAssertEqual(drawn.cardWidth - drawn.mark.maxX, 10, accuracy: Self.accuracy, name)
            XCTAssertEqual(drawn.mark.minY, 10, accuracy: Self.accuracy, name)
        }
    }

    /// On one line the circle stands in the middle, with the title and the
    /// status badge beside it.
    func testTheMarkStandsInTheMiddleOfAOneLineCard() throws {
        for number in [nil, 2] as [Int?] {
            let name = number.map { "number \($0)" } ?? "check mark"
            let drawn = try drawnMark(of: makeTestRecord(status: .seeding, progress: 1), number: number)

            XCTAssertEqual(drawn.mark.width, 16, accuracy: Self.accuracy, name)
            XCTAssertEqual(drawn.mark.height, 16, accuracy: Self.accuracy, name)
            XCTAssertEqual(drawn.cardWidth - drawn.mark.maxX, 10, accuracy: Self.accuracy, name)
            XCTAssertEqual(drawn.mark.minY, drawn.cardHeight - drawn.mark.maxY, accuracy: Self.accuracy, name)
        }
    }

    // MARK: - Drawing

    /// Four pixels to a point: an edge found at half coverage is within a
    /// pixel of where it is.
    private static let scale: CGFloat = 4
    private static let accuracy: CGFloat = 0.3

    private struct DrawnMark {
        var mark: CGRect
        var cardWidth: CGFloat
        var cardHeight: CGFloat
    }

    /// Draws the selected card and finds the circle in its top right corner,
    /// in points. Nothing else is drawn there: the expand button stands to
    /// the left of the circle, and the outline and the progress bar are left
    /// out of the search.
    private func drawnMark(of record: TorrentRecord, number: Int?) throws -> DrawnMark {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: [record])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        var row = try XCTUnwrap(bundle.store.torrentRowPresentationModel(for: record.id)).state
        row.isSelected = true
        row.selectionNumber = number

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
        let renderer = ImageRenderer(content: card.frame(width: 600))
        renderer.scale = Self.scale
        let bitmap = Bitmap(try XCTUnwrap(renderer.cgImage))

        let width = CGFloat(bitmap.width) / Self.scale
        let height = CGFloat(bitmap.height) / Self.scale
        // The title row ends at 28 pt in a full card, and the progress bar
        // starts at 36 pt; a one-line card has nothing below its row.
        let searchBottom = row.usesFinishedLayout ? height - 8 : 32
        let area = CGRect(x: width - 32, y: 8, width: 24, height: searchBottom - 8)
        let background = bitmap.color(atX: Int(width / 2 * Self.scale), y: Int(5 * Self.scale))

        let pixels = bitmap.pixels(in: area, scale: Self.scale)
        let distances = pixels.map { bitmap.distance(of: $0, from: background) }
        let strongest = try XCTUnwrap(distances.max())
        XCTAssertGreaterThan(strongest, 64, "no mark found")

        var covered = CGRect.null
        for (pixel, distance) in zip(pixels, distances) where distance * 2 >= strongest {
            covered = covered.union(CGRect(x: pixel.x, y: pixel.y, width: 1, height: 1))
        }
        let mark = CGRect(
            x: covered.minX / Self.scale,
            y: covered.minY / Self.scale,
            width: covered.width / Self.scale,
            height: covered.height / Self.scale
        )
        return DrawnMark(mark: mark, cardWidth: width, cardHeight: height)
    }

    private struct Bitmap {
        let width: Int
        let height: Int
        private let bytes: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
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

        /// The first row is the top of the image.
        func color(atX x: Int, y: Int) -> [Int] {
            let offset = (y * width + x) * 4
            return (0..<4).map { Int(bytes[offset + $0]) }
        }

        func pixels(in area: CGRect, scale: CGFloat) -> [(x: Int, y: Int)] {
            let xs = Int(area.minX * scale)..<Int(area.maxX * scale)
            let ys = Int(area.minY * scale)..<Int(area.maxY * scale)
            return ys.flatMap { y in xs.map { x in (x: x, y: y) } }
        }

        func distance(of pixel: (x: Int, y: Int), from background: [Int]) -> Int {
            zip(color(atX: pixel.x, y: pixel.y), background).map { abs($0 - $1) }.max() ?? 0
        }
    }
}
