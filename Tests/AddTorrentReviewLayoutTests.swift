// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

final class AddTorrentReviewLayoutTests: XCTestCase {
    func testTextSegmentSpacingMovesUnicodeWhitespaceToFollowingNumber() {
        let separators = [" ", "\u{00A0}", "\u{202F}"]

        for separator in separators {
            let segments = [
                AddTorrentTextSegment(
                    id: "number-0",
                    kind: .number,
                    value: "8\u{00A0}955",
                    animatesNumericChange: true
                ),
                AddTorrentTextSegment(
                    id: "text-0",
                    kind: .text,
                    value: "\u{202F}из\(separator)",
                    animatesNumericChange: false
                ),
                AddTorrentTextSegment(
                    id: "number-1",
                    kind: .number,
                    value: "8\u{00A0}955",
                    animatesNumericChange: true
                ),
            ]

            let normalized = AddTorrentTextSegmentSpacing
                .movingTrailingWhitespaceToFollowingNumber(in: segments)

            XCTAssertEqual(normalized.map(\.value).joined(), segments.map(\.value).joined())
            XCTAssertEqual(normalized[1].value, "\u{202F}из")
            XCTAssertEqual(normalized[2].value, "\(separator)8\u{00A0}955")
            XCTAssertEqual(normalized.map(\.id), segments.map(\.id))
            XCTAssertEqual(normalized.map(\.kind), segments.map(\.kind))
            XCTAssertEqual(
                normalized.map(\.animatesNumericChange),
                segments.map(\.animatesNumericChange)
            )
        }
    }

    func testTextSegmentSpacingLeavesWhitespaceOnlyGroupingSegmentUnchanged() {
        let segments = [
            AddTorrentTextSegment(
                id: "number-0",
                kind: .number,
                value: "8",
                animatesNumericChange: true
            ),
            AddTorrentTextSegment(
                id: "text-0",
                kind: .text,
                value: "\u{00A0}",
                animatesNumericChange: false
            ),
            AddTorrentTextSegment(
                id: "number-1",
                kind: .number,
                value: "955",
                animatesNumericChange: true
            ),
        ]

        XCTAssertEqual(
            AddTorrentTextSegmentSpacing.movingTrailingWhitespaceToFollowingNumber(
                in: segments
            ),
            segments
        )
    }

    func testSelectedCountSegmentationPreservesSpacingForEverySupportedLocale() {
        let locales: [AppLocaleOverride] = [
            .english,
            .russian,
            .german,
            .spanish,
            .french,
            .japanese,
            .simplifiedChinese,
        ]

        for locale in locales {
            let value = L10n.format(
                "add_torrent.review.summary.selected_count",
                localeOverride: locale,
                defaultValue: "%lld of %lld",
                Int64(8_955),
                Int64(8_955)
            )
            let segments = AddTorrentNumericTextSegmentation.segments(in: value)

            XCTAssertEqual(
                segments.map(\.value).joined(),
                value,
                "Segmentation changed the localized value for \(locale.rawValue)"
            )

            for (segment, followingSegment) in zip(segments, segments.dropFirst()) {
                let containsNonWhitespace = segment.value.contains { !$0.isWhitespace }
                if segment.kind == .text,
                   followingSegment.kind == .number,
                   containsNonWhitespace {
                    XCTAssertFalse(
                        segment.value.last?.isWhitespace == true,
                        "A visible text segment keeps trailing whitespace for \(locale.rawValue)"
                    )
                }
            }
        }
    }

    func testSelectionIndicatorUsesConstantSizeSourcesForEveryTreeState() {
        XCTAssertEqual(
            AddTorrentReviewSelectionIndicator.sourceValues(for: .selected),
            [true]
        )
        XCTAssertEqual(
            AddTorrentReviewSelectionIndicator.sourceValues(for: .unselected),
            [false]
        )
        XCTAssertEqual(
            AddTorrentReviewSelectionIndicator.sourceValues(for: .mixed),
            [true, false]
        )
    }

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
            AddTorrentReviewLayout.summaryOverlayHeight(for: .standard),
            59
        )
        XCTAssertEqual(
            AddTorrentReviewLayout.summaryOverlayHeight(for: .cjk),
            63
        )
    }

    func testWindowAndSplitLayoutMetricsMatchReviewDesign() {
        XCTAssertEqual(AddTorrentReviewLayout.minimumWindowWidth, 780)
        XCTAssertEqual(AddTorrentReviewLayout.minimumWindowHeight, 570)
        XCTAssertEqual(AddTorrentReviewLayout.settingsColumnWidth, 380)
        XCTAssertEqual(AddTorrentReviewLayout.settingsColumnPadding, 12)
        XCTAssertEqual(AddTorrentReviewLayout.leftColumnOutlineWidth, 1)
        XCTAssertEqual(AddTorrentReviewLayout.summaryContainerHorizontalPadding, 6)
        XCTAssertEqual(AddTorrentReviewLayout.summaryContainerBottomPadding, 6)
        XCTAssertEqual(AddTorrentReviewLayout.summaryCornerRadius, 12)
        XCTAssertEqual(AddTorrentReviewLayout.summarySpacing, 24)
        XCTAssertEqual(AddTorrentReviewLayout.summaryVerticalPadding, 12)
    }

    func testSummaryShowsSelectionMetricsOnlyFromFourSelectedFiles() {
        for count in 0...3 {
            XCTAssertFalse(
                AddTorrentSummaryPresentation.showsSelectionMetrics(
                    selectedFileCount: count
                )
            )
        }

        XCTAssertTrue(
            AddTorrentSummaryPresentation.showsSelectionMetrics(
                selectedFileCount: 4
            )
        )
        XCTAssertTrue(
            AddTorrentSummaryPresentation.showsSelectionMetrics(
                selectedFileCount: 8_955
            )
        )
    }

    func testSearchProjectionIncludesMatchesAndTheirAncestorChain() throws {
        let draft = AddTorrentDraft(
            source: AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/search.torrent"),
            originalName: "Search",
            suggestedSavePath: "/tmp",
            alias: "",
            stopAfterDownload: false,
            files: [
                AddTorrentFileOption(
                    name: "Root/Season 1/Episode One.mkv",
                    sizeBytes: 100,
                    fileIndex: 0,
                    isSelected: true
                ),
                AddTorrentFileOption(
                    name: "Root/Season 2/Trailer.mkv",
                    sizeBytes: 200,
                    fileIndex: 1,
                    isSelected: true
                ),
                AddTorrentFileOption(
                    name: "Notes.txt",
                    sizeBytes: 300,
                    fileIndex: 2,
                    isSelected: true
                ),
            ],
            reviewState: .ready,
            errorState: nil
        )

        let root = try XCTUnwrap(draft.fileTree.first { $0.name == "Root" })
        let seasonOne = try XCTUnwrap(root.children?.first { $0.name == "Season 1" })
        let episode = try XCTUnwrap(seasonOne.children?.first)
        let seasonTwo = try XCTUnwrap(root.children?.first { $0.name == "Season 2" })
        let notes = try XCTUnwrap(draft.fileTree.first { $0.name == "Notes.txt" })
        let projection = try XCTUnwrap(
            AddTorrentFileSearchProjection.make(
                from: draft.fileTree,
                query: "episode one"
            )
        )

        XCTAssertEqual(
            projection.visibleNodeIDs,
            Set([root.id, seasonOne.id, episode.id])
        )
        XCTAssertEqual(
            projection.foldersWithVisibleDescendants,
            Set([root.id, seasonOne.id])
        )
        XCTAssertEqual(projection.matchingNodeIDs, Set([episode.id]))
        XCTAssertFalse(projection.visibleNodeIDs.contains(seasonTwo.id))
        XCTAssertFalse(projection.visibleNodeIDs.contains(notes.id))
    }

    func testMatchingFolderCanBeExplicitlyExpandedWithoutMatchingDescendants() throws {
        let draft = AddTorrentDraft(
            source: AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/search-folder.torrent"),
            originalName: "Search folder",
            suggestedSavePath: "/tmp",
            alias: "",
            stopAfterDownload: false,
            files: [
                AddTorrentFileOption(
                    name: "Root/Cute Rin/File.bin",
                    sizeBytes: 100,
                    fileIndex: 0,
                    isSelected: true
                ),
            ],
            reviewState: .ready,
            errorState: nil
        )

        let root = try XCTUnwrap(draft.fileTree.first)
        let matchingFolder = try XCTUnwrap(root.children?.first)
        let projection = try XCTUnwrap(
            AddTorrentFileSearchProjection.make(from: draft.fileTree, query: "cute rin")
        )

        XCTAssertTrue(projection.matchingNodeIDs.contains(matchingFolder.id))
        XCTAssertFalse(projection.foldersWithVisibleDescendants.contains(matchingFolder.id))
        XCTAssertFalse(
            AddTorrentSearchFolderExpansion.isExpanded(
                folderID: matchingFolder.id,
                projection: projection,
                collapsedFolderIDs: [],
                expandedFolderIDs: []
            )
        )
        XCTAssertTrue(
            AddTorrentSearchFolderExpansion.isExpanded(
                folderID: matchingFolder.id,
                projection: projection,
                collapsedFolderIDs: [],
                expandedFolderIDs: [matchingFolder.id]
            )
        )
    }

    func testRowLookupUsesBoundariesOfCachedOffsets() {
        let offsets: [CGFloat] = [36, 82, 114]

        XCTAssertNil(
            AddTorrentReviewRowLookup.index(
                at: 3,
                contentTop: 4,
                rowBottomOffsets: offsets
            )
        )
        XCTAssertEqual(
            AddTorrentReviewRowLookup.index(
                at: 4,
                contentTop: 4,
                rowBottomOffsets: offsets
            ),
            0
        )
        XCTAssertEqual(
            AddTorrentReviewRowLookup.index(
                at: 36,
                contentTop: 4,
                rowBottomOffsets: offsets
            ),
            1
        )
        XCTAssertEqual(
            AddTorrentReviewRowLookup.index(
                at: 113.5,
                contentTop: 4,
                rowBottomOffsets: offsets
            ),
            2
        )
        XCTAssertNil(
            AddTorrentReviewRowLookup.index(
                at: 114,
                contentTop: 4,
                rowBottomOffsets: offsets
            )
        )
    }

    func testEmptySearchDoesNotCreateProjection() {
        XCTAssertNil(
            AddTorrentFileSearchProjection.make(
                from: [],
                query: " \n\t "
            )
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
