// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XCTest
@testable import Shatl

/// The add window's summary says what is chosen as a download card says its
/// expanded metrics: "1 из 2", "2 (все)", a lone "1", or a sparkle for
/// nothing, beside the size and the free space.
@MainActor
final class AddTorrentSummaryTests: XCTestCase {
    private let gigabyte: Int64 = 1_000_000_000

    private func groups(
        selected: Int,
        total: Int,
        bytes: Int64? = nil,
        freeSpace: AddTorrentFreeSpace = .available(120_900_000_000),
        locale: AppLocaleOverride = .russian
    ) -> AddTorrentSummaryGroups {
        AddTorrentSummaryPresentation.groups(
            selectedFileCount: selected,
            totalFileCount: total,
            selectedBytes: bytes ?? Int64(selected) * gigabyte,
            freeSpace: freeSpace,
            mode: .simplified,
            localeOverride: locale
        )
    }

    /// Titles as read, with the typograph's non-breaking spaces as spaces.
    private func titles(_ groups: AddTorrentSummaryGroups) -> [String] {
        groups.leading.map { $0.title.replacingOccurrences(of: "\u{00A0}", with: " ") }
    }

    private func selectedItem(_ groups: AddTorrentSummaryGroups) throws -> MetricItemPresentation {
        try XCTUnwrap(groups.leading.first?.items.first)
    }

    func testSomeOfSeveralFilesAreCountedOutOfTheTotal() throws {
        let summary = groups(selected: 1, total: 2)
        let item = try selectedItem(summary)

        XCTAssertEqual(titles(summary), ["Выбрано файлов", "Размер"])
        XCTAssertEqual(item.number, "1")
        XCTAssertEqual(item.of, "из")
        XCTAssertEqual(item.total, "2")
        XCTAssertNil(item.unit)
        XCTAssertNil(item.iconName)
    }

    /// Everything chosen: the total goes, "из" becomes "(все)".
    func testAllFilesAreCountedOnceAsAll() throws {
        let item = try selectedItem(groups(selected: 2, total: 2))

        XCTAssertEqual(item.number, "2")
        XCTAssertEqual(item.of, "(все)")
        XCTAssertNil(item.total)
    }

    /// The count is one item in every state, so its parts change in place.
    func testTheCountKeepsOneIdentity() throws {
        let ids = try [
            groups(selected: 0, total: 2),
            groups(selected: 1, total: 2),
            groups(selected: 2, total: 2),
            groups(selected: 1, total: 1),
            groups(selected: 0, total: 1),
        ].map { try selectedItem($0).id }

        XCTAssertEqual(Set(ids), ["selected-files"])
    }

    /// Nothing chosen: a sparkle holds the plate, the title says why
    /// "Скачать" is off, and the size, a zero, is not shown.
    func testNothingChosenShowsASparkleAndNoSize() throws {
        let summary = groups(selected: 0, total: 3, bytes: 0)
        let item = try selectedItem(summary)

        XCTAssertEqual(titles(summary), ["Файлы не выбраны"])
        XCTAssertEqual(item.iconName, AddTorrentSummaryPresentation.nothingSelectedIconName)
        XCTAssertEqual(item.iconName, "sparkle")
        XCTAssertNil(item.number)
        XCTAssertNil(item.of)
        XCTAssertNil(item.total)
    }

    func testATorrentOfOneFileCountsItAlone() throws {
        let chosen = groups(selected: 1, total: 1)
        let item = try selectedItem(chosen)
        XCTAssertEqual(titles(chosen), ["Выбран файл", "Размер"])
        XCTAssertEqual(item.number, "1")
        XCTAssertNil(item.of)
        XCTAssertNil(item.total)

        let none = groups(selected: 0, total: 1, bytes: 0)
        XCTAssertEqual(titles(none), ["Файл не выбран"])
        XCTAssertEqual(try selectedItem(none).iconName, "sparkle")
    }

    /// Chosen files of no size have no size to show either.
    func testEmptyFilesShowNoZeroSize() {
        XCTAssertEqual(groups(selected: 2, total: 3, bytes: 0).leading.map(\.id), ["selected-files"])
    }

    /// "1 657 из 1 658": the digits are grouped by a space that does not
    /// break, the parts stand apart.
    func testLargeCountsAreGroupedAsTheLanguageGroupsThem() throws {
        let item = try selectedItem(groups(selected: 1_657, total: 1_658))
        let number = try XCTUnwrap(item.number)
        let total = try XCTUnwrap(item.total)

        XCTAssertEqual(number.filter(\.isNumber), "1657")
        XCTAssertEqual(total.filter(\.isNumber), "1658")
        XCTAssertFalse(number.contains(" "), "A plain space would let the number break")
        XCTAssertGreaterThan(number.count, 4, "The digits are grouped")

        let english = try selectedItem(groups(selected: 1_657, total: 1_658, locale: .english))
        XCTAssertEqual(english.number, "1,657")
        XCTAssertEqual(english.of, "of")
        XCTAssertEqual(english.total, "1,658")
    }

    /// The size is rounded to the nearest whole number and the free space
    /// down, each split into its number and unit.
    func testSizeAndFreeSpaceAreSplitAndRoundedEachTheirWay() throws {
        let summary = groups(selected: 2, total: 3, bytes: 1_600_000_000)
        let size = try XCTUnwrap(summary.leading.last?.items.first)
        XCTAssertEqual(size.number, "2")
        XCTAssertEqual(size.unit, "ГБ")
        XCTAssertEqual(try XCTUnwrap(groups(selected: 2, total: 3, bytes: 1_200_000_000).leading.last?.items.first).number, "1")

        let free = try XCTUnwrap(summary.trailing.items.first)
        XCTAssertEqual(summary.trailing.title, "Свободно")
        XCTAssertEqual(free.number, "120")
        XCTAssertEqual(free.unit, "ГБ")
        XCTAssertFalse(free.isPending)
    }

    /// A file of a little over 2 GB showed "2 ГБ" in its row and "3 ГБ" in
    /// the summary (the owner's screenshot): the row and the summary now
    /// round one way, by the same switch of precision.
    func testOneFileAndItsSummaryNameOneSize() throws {
        for bytes: Int64 in [2_040_000_000, 2_400_000_000, 2_600_000_000, 748_300_000, 999_600_000] {
            for mode in MetricsPresentationMode.allCases {
                let row = AddTorrentSummaryByteFormatter.format(bytes, mode: mode, rounding: .nearest, localeOverride: .russian)
                let summary = AddTorrentSummaryPresentation.groups(
                    selectedFileCount: 1,
                    totalFileCount: 1,
                    selectedBytes: bytes,
                    freeSpace: .available(120_900_000_000),
                    mode: mode,
                    localeOverride: .russian
                )
                let size = try XCTUnwrap(summary.leading.last?.items.first)
                XCTAssertEqual(
                    [size.number, size.unit].compactMap { $0 }.joined(separator: " "),
                    row,
                    "\(bytes) bytes, \(mode)"
                )
            }
        }
    }

    /// While the disk is read a spinner stands in the plate; a folder out of
    /// reach says so in the unit's grey, never with a dash that would read as
    /// no room at all.
    func testFreeSpaceWaitsWithASpinnerAndNamesAFolderOutOfReach() throws {
        let reading = try XCTUnwrap(groups(selected: 1, total: 2, freeSpace: .reading).trailing.items.first)
        XCTAssertTrue(reading.isPending)
        XCTAssertNil(reading.number)
        XCTAssertNil(reading.unit)

        let unavailable = try XCTUnwrap(groups(selected: 1, total: 2, freeSpace: .unavailable).trailing.items.first)
        XCTAssertFalse(unavailable.isPending)
        XCTAssertNil(unavailable.number)
        XCTAssertEqual(unavailable.unit, "Недоступно")
    }

    /// The width animates when a part comes, goes or changes length, as on
    /// a download card.
    func testTheWidthAnimatesOnEveryChangeOfTheCount() {
        let partly = groups(selected: 1, total: 2).widthAnimationSignature
        let all = groups(selected: 2, total: 2).widthAnimationSignature
        let none = groups(selected: 0, total: 2, bytes: 0).widthAnimationSignature

        XCTAssertNotEqual(partly, all)
        XCTAssertNotEqual(all, none)
        XCTAssertEqual(partly, groups(selected: 3, total: 4).widthAnimationSignature)
    }

    func testEveryLanguageHasItsWordsForTheCount() {
        let languages: [AppLocaleOverride] = [.russian, .english, .german, .spanish, .french, .japanese, .simplifiedChinese]
        for language in languages {
            for key in [
                "add_torrent.review.summary.of",
                "add_torrent.review.summary.all",
                "add_torrent.review.summary.selected_file",
                "add_torrent.review.summary.no_file_selected",
                "add_torrent.review.summary.no_files_selected",
            ] {
                let value = L10n.string(key, localeOverride: language, defaultValue: "")
                XCTAssertFalse(value.isEmpty, "\(key) in \(language.rawValue)")
                XCTAssertNotEqual(value, key, "\(key) in \(language.rawValue)")
            }
        }
    }

    /// The files scroll under the summary: its card is solid in both themes,
    /// and in dark as light as a download card looks on the files' ground.
    func testTheCardIsSolidSoTheFilesDoNotShowThrough() {
        for scheme in [ColorScheme.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            XCTAssertEqual(ShatlColor.cardBackgroundSolid.resolve(in: environment).opacity, 1, "\(scheme)")
        }

        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        let solid = ShatlColor.cardBackgroundSolid.resolve(in: dark)
        let ground = ShatlColor.backgroundAddWindow.resolve(in: dark)
        let clear = ShatlColor.cardBackgroundDefault.resolve(in: dark)
        // The clear card over the ground, channel by channel.
        let seen = ground.red + (clear.red - ground.red) * clear.opacity
        XCTAssertEqual(Double(solid.red), Double(seen), accuracy: 0.02)
    }

    /// No room: saved for want of room. The folder out of reach: saved as by
    /// choice, so its "i" does not claim it lacked room. Room lacking wins,
    /// though only a folder that answers can say so.
    func testTheButtonSavesToTheListWhenTheDownloadCannotStart() {
        XCTAssertEqual(AddTorrentConfirmation.decide(lacksSpace: false, folderIsUnavailable: false), .download)
        XCTAssertEqual(AddTorrentConfirmation.decide(lacksSpace: true, folderIsUnavailable: false), .saveToList(byChoice: false))
        XCTAssertEqual(AddTorrentConfirmation.decide(lacksSpace: false, folderIsUnavailable: true), .saveToList(byChoice: true))
        XCTAssertEqual(AddTorrentConfirmation.decide(lacksSpace: true, folderIsUnavailable: true), .saveToList(byChoice: false))
    }

    // MARK: - Plates

    /// A lone "1" or the sparkle stands in a square plate: the set is never
    /// narrower than it is tall.
    func testALoneValueStandsInASquarePlate() throws {
        let one = try size(of: MetricItemPresentation(
            id: "selected-files", iconName: nil, number: "1", unit: nil, usesAccentIcon: false
        ))
        XCTAssertEqual(one.width, ShatlMetricLayout.containerHeight, accuracy: 0.5)
        XCTAssertEqual(one.height, ShatlMetricLayout.containerHeight, accuracy: 0.5)

        let spinner = try size(of: MetricItemPresentation(
            id: "free-space", iconName: nil, number: nil, unit: nil, usesAccentIcon: false, isPending: true
        ))
        XCTAssertGreaterThanOrEqual(spinner.width, ShatlMetricLayout.containerHeight - 0.5)
        XCTAssertEqual(spinner.height, ShatlMetricLayout.containerHeight, accuracy: 0.5)
    }

    /// The parts of a count stand 6 pt apart, a number and its unit 2 pt.
    func testTheCountsPartsStandWiderApartThanANumberAndItsUnit() throws {
        let value = try size(of: MetricItemPresentation(
            id: "a", iconName: nil, number: "1", unit: "из", usesAccentIcon: false
        ))
        let count = try size(of: MetricItemPresentation(
            id: "a", iconName: nil, number: "1", unit: nil, usesAccentIcon: false, of: "из"
        ))
        XCTAssertEqual(count.width - value.width, ShatlMetricItem.countSpacing - 2, accuracy: 0.5)
    }

    private func size(of item: MetricItemPresentation) throws -> CGSize {
        let renderer = ImageRenderer(content: ShatlMetricSet(items: [item], isMuted: true).fixedSize())
        let image = try XCTUnwrap(renderer.cgImage)
        return CGSize(width: CGFloat(image.width) / renderer.scale, height: CGFloat(image.height) / renderer.scale)
    }
}
