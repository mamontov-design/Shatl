// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

final class AddTorrentReviewLayoutTests: XCTestCase {
    func testListItemMetricsFollowTypographyProfile() {
        XCTAssertEqual(
            AddTorrentReviewLayout.listItemHeight(for: .standard),
            32
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.listItemHeight(for: .cjk),
            34
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.listItemHeight(for: .standard, showsFolderSummary: true),
            46
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.listItemHeight(for: .cjk, showsFolderSummary: true),
            52
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.fileTypeIconWidth(for: .standard),
            18
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.fileTypeIconWidth(for: .cjk),
            20
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.summaryContentHeight(for: .standard),
            29
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.summaryContentHeight(for: .cjk),
            33
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.invalidContentHeight(for: .standard),
            491
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.invalidContentHeight(for: .cjk),
            499
        )
    }

    func testTabContentHeightReservesSummarySpace() {
        XCTAssertEqual(
            AddTorrentReviewLayout.tabContentHeight(for: .standard, showsSummary: false),
            360
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.tabContentHeight(for: .standard, showsSummary: true),
            405
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.tabContentHeight(for: .cjk, showsSummary: true),
            409
        )
    }

    func testSummaryByteFormatterRoundsSimplifiedValuesByContext() {
        XCTAssertEqual(
            AddTorrentSummaryByteFormatter.format(
                1_200_000_000,
                mode: .simplified,
                rounding: .up,
                localeOverride: .russian
            ),
            "2 ГБ"
        )
        XCTAssertEqual(
            AddTorrentSummaryByteFormatter.format(
                1_200_000_000,
                mode: .simplified,
                rounding: .down,
                localeOverride: .russian
            ),
            "1 ГБ"
        )
        XCTAssertEqual(
            AddTorrentSummaryByteFormatter.format(
                512,
                mode: .simplified,
                rounding: .up,
                localeOverride: .russian
            ),
            "512 Б"
        )
    }

    func testSummaryByteFormatterKeepsDetailedModePrecision() {
        let bytes: Int64 = 1_234_567_890

        XCTAssertEqual(
            AddTorrentSummaryByteFormatter.format(
                bytes,
                mode: .detailed,
                rounding: .up,
                localeOverride: .russian
            ),
            Metrics.formatBytes(bytes, mode: .detailed, localeOverride: .russian)
        )
    }

    func testRootLeadingPaddingDependsOnNodeKind() {
        XCTAssertEqual(
            AddTorrentReviewLayout.leadingPadding(isFolder: true, level: 0),
            10
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.leadingPadding(isFolder: false, level: 0),
            6
        )
    }

    func testNestedItemsUseSharedLeadingPadding() {
        XCTAssertEqual(
            AddTorrentReviewLayout.leadingPadding(isFolder: true, level: 1),
            20
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.leadingPadding(isFolder: false, level: 3),
            20
        )
    }

    func testNearestHierarchyGuideIsNarrow() {
        XCTAssertEqual(
            AddTorrentReviewLayout.hierarchyGuideWidths(for: 0),
            []
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.hierarchyGuideWidths(for: 1),
            [10]
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.hierarchyGuideWidths(for: 3),
            [20, 20, 10]
        )
    }

    func testFileTreeStoresRecursiveSelectionCounts() throws {
        let draft = AddTorrentDraft(
            source: AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/example.torrent"),
            originalName: "Example",
            suggestedSavePath: "/tmp",
            alias: "",
            stopAfterDownload: false,
            files: [
                AddTorrentFileOption(
                    name: "Root/Season 1/Episode 1.mkv",
                    sizeBytes: 1_000,
                    fileIndex: 0,
                    isSelected: true
                ),
                AddTorrentFileOption(
                    name: "Root/Season 1/Episode 2.mkv",
                    sizeBytes: 2_000,
                    fileIndex: 1,
                    isSelected: false
                ),
                AddTorrentFileOption(
                    name: "Root/Season 2/Episode 3.mkv",
                    sizeBytes: 3_000,
                    fileIndex: 2,
                    isSelected: true
                ),
            ],
            reviewState: .ready,
            errorState: nil
        )

        let root = try XCTUnwrap(draft.fileTree.first)
        XCTAssertEqual(root.fileCount, 3)
        XCTAssertEqual(root.selectedFileCount, 2)
        XCTAssertEqual(draft.selectedFileCount, 2)

        let firstSeason = try XCTUnwrap(root.children?.first { $0.name == "Season 1" })
        XCTAssertEqual(firstSeason.fileCount, 2)
        XCTAssertEqual(firstSeason.selectedFileCount, 1)
    }

    func testPluralCategoriesFollowSupportedLocales() {
        XCTAssertEqual(
            AddTorrentFilePluralCategory.resolve(count: 1, localeOverride: .russian),
            .one
        )
        XCTAssertEqual(
            AddTorrentFilePluralCategory.resolve(count: 2, localeOverride: .russian),
            .few
        )
        XCTAssertEqual(
            AddTorrentFilePluralCategory.resolve(count: 5, localeOverride: .russian),
            .many
        )
        XCTAssertEqual(
            AddTorrentFilePluralCategory.resolve(count: 11, localeOverride: .russian),
            .many
        )
        XCTAssertEqual(
            AddTorrentFilePluralCategory.resolve(count: 21, localeOverride: .russian),
            .one
        )
        XCTAssertEqual(
            AddTorrentFilePluralCategory.resolve(count: 1, localeOverride: .english),
            .one
        )
        XCTAssertEqual(
            AddTorrentFilePluralCategory.resolve(count: 2, localeOverride: .english),
            .other
        )
        XCTAssertEqual(
            AddTorrentFilePluralCategory.resolve(count: 1, localeOverride: .french),
            .one
        )
        XCTAssertEqual(
            AddTorrentFilePluralCategory.resolve(count: 2, localeOverride: .french),
            .other
        )
        XCTAssertEqual(
            AddTorrentFilePluralCategory.resolve(count: 1, localeOverride: .japanese),
            .other
        )
    }
}
