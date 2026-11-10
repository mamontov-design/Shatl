// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// A download that does not fit on its disk is named with what it lacks, and
/// the numbers in one sentence agree with each other.
final class DiskSpaceCheckTests: XCTestCase {
    private let gigabyte: Int64 = 1_000_000_000

    private func check(needed: Int64, available: Int64) -> DiskSpaceCheck {
        DiskSpaceCheck(neededBytes: needed, availableBytes: available, volumeName: "Macintosh HD")
    }

    func testDownloadFitsUpToTheLastByte() {
        XCTAssertTrue(check(needed: 10, available: 10).fits)
        XCTAssertTrue(check(needed: 10, available: 11).fits)
        XCTAssertFalse(check(needed: 11, available: 10).fits)
    }

    func testShortfallIsReportedOnlyWhenTheDownloadDoesNotFit() {
        let disk = DiskSpaceInfo(availableBytes: 16 * gigabyte, volumeName: "Macintosh HD")

        XCTAssertNil(DiskSpaceCheck.shortfall(neededBytes: 16 * gigabyte, on: disk))
        XCTAssertNil(DiskSpaceCheck.shortfall(neededBytes: 0, on: disk))
        XCTAssertEqual(
            DiskSpaceCheck.shortfall(neededBytes: 172 * gigabyte, on: disk),
            DiskSpaceCheck(neededBytes: 172 * gigabyte, availableBytes: 16 * gigabyte, volumeName: "Macintosh HD")
        )
    }

    /// 171.6 GB needed and 16.8 GB free show as 172 and 16; the sentence
    /// then lacks 156 GB, not the 155 the exact bytes round to.
    func testRoundedShortfallIsTheDifferenceOfTheNumbersShown() {
        let space = check(needed: 171_600_000_000, available: 16_800_000_000)

        XCTAssertEqual(space.neededText(mode: .simplified, localeOverride: .russian), "172\u{00A0}ГБ")
        XCTAssertEqual(space.availableText(mode: .simplified, localeOverride: .russian), "16\u{00A0}ГБ")
        XCTAssertEqual(space.shortfallText(mode: .simplified, localeOverride: .russian), "156\u{00A0}ГБ")
    }

    /// A size is rounded to the nearest whole number, as the add window's
    /// files are: 2.1 GB is "2 ГБ", and 2 GB less 800 MB lacks about 1 GB.
    func testShortfallAcrossUnitsIsRoundedAsASize() {
        let space = check(needed: 2_100_000_000, available: 800_000_000)

        XCTAssertEqual(space.neededText(mode: .simplified, localeOverride: .russian), "2\u{00A0}ГБ")
        XCTAssertEqual(space.availableText(mode: .simplified, localeOverride: .russian), "800\u{00A0}МБ")
        XCTAssertEqual(space.shortfallText(mode: .simplified, localeOverride: .russian), "1\u{00A0}ГБ")
    }

    /// 2.4 GB needed and 2.3 GB free both show as 2 GB: the numbers shown
    /// leave nothing missing, so the sentence names what the bytes lack.
    func testShortfallBetweenEqualNumbersIsTheExactOne() {
        let space = check(needed: 2_400_000_000, available: 2_300_000_000)

        XCTAssertFalse(space.fits)
        XCTAssertEqual(space.neededText(mode: .simplified, localeOverride: .russian), "2\u{00A0}ГБ")
        XCTAssertEqual(space.availableText(mode: .simplified, localeOverride: .russian), "2\u{00A0}ГБ")
        XCTAssertEqual(space.shortfallText(mode: .simplified, localeOverride: .russian), "100\u{00A0}МБ")
    }

    func testDetailedShortfallUsesTheExactBytes() {
        let space = check(needed: 171_300_000_000, available: 16_800_000_000)

        XCTAssertEqual(
            space.shortfallText(mode: .detailed, localeOverride: .russian),
            Metrics.formatBytes(154_500_000_000, mode: .detailed, localeOverride: .russian)
                .replacingOccurrences(of: " ", with: "\u{00A0}")
        )
    }

    func testRoundedBytesFollowTheUnitShown() {
        XCTAssertEqual(AddTorrentSummaryByteFormatter.roundedBytes(171_300_000_000, rounding: .nearest), 171 * gigabyte)
        XCTAssertEqual(AddTorrentSummaryByteFormatter.roundedBytes(171_600_000_000, rounding: .nearest), 172 * gigabyte)
        XCTAssertEqual(AddTorrentSummaryByteFormatter.roundedBytes(999_600_000, rounding: .nearest), gigabyte)
        XCTAssertEqual(AddTorrentSummaryByteFormatter.roundedBytes(16_800_000_000, rounding: .down), 16 * gigabyte)
        XCTAssertEqual(AddTorrentSummaryByteFormatter.roundedBytes(800_400_000, rounding: .down), 800_000_000)
        XCTAssertEqual(AddTorrentSummaryByteFormatter.roundedBytes(512, rounding: .nearest), 512)
    }

    /// 100 GB free, 60 GB promised to downloads in progress: a download of
    /// 60 GB lacks 20 GB, one of 40 GB fits.
    func testPromisedSpaceCountsBesideTheFreeSpace() throws {
        let disk = DiskSpaceInfo(availableBytes: 100 * gigabyte, volumeName: "Macintosh HD")

        XCTAssertNil(DiskSpaceCheck.shortfall(neededBytes: 40 * gigabyte, promisedBytes: 60 * gigabyte, on: disk))
        XCTAssertNil(DiskSpaceCheck.shortfall(neededBytes: 60 * gigabyte, promisedBytes: 0, on: disk))
        let space = try XCTUnwrap(
            DiskSpaceCheck.shortfall(neededBytes: 60 * gigabyte, promisedBytes: 60 * gigabyte, on: disk)
        )
        XCTAssertEqual(space.shortfallText(mode: .simplified, localeOverride: .russian), "20\u{00A0}ГБ")
        XCTAssertEqual(space.promisedText(mode: .simplified, localeOverride: .russian), "60\u{00A0}ГБ")
        XCTAssertEqual(
            DiskSpaceCheck.shortfall(neededBytes: 160 * gigabyte, promisedBytes: 0, on: disk)?.promisedBytes,
            nil
        )
    }

    /// 59.6 GB needed and 59.7 GB promised show as 60 and 60, 100.7 GB free
    /// as 100: the sentence lacks the 20 GB they add up to, not the 19 the
    /// exact bytes round to.
    func testRoundedShortfallAddsUpThePromisedNumberShown() {
        let space = DiskSpaceCheck(
            neededBytes: 59_600_000_000,
            availableBytes: 100_700_000_000,
            volumeName: "Macintosh HD",
            promisedBytes: 59_700_000_000
        )

        XCTAssertFalse(space.fits)
        XCTAssertEqual(space.neededText(mode: .simplified, localeOverride: .russian), "60\u{00A0}ГБ")
        XCTAssertEqual(space.promisedText(mode: .simplified, localeOverride: .russian), "60\u{00A0}ГБ")
        XCTAssertEqual(space.availableText(mode: .simplified, localeOverride: .russian), "100\u{00A0}ГБ")
        XCTAssertEqual(space.shortfallText(mode: .simplified, localeOverride: .russian), "20\u{00A0}ГБ")
    }

    /// A runtime error saved in the session before promised space was
    /// counted still reads, and a check without it writes nothing new.
    func testChecksSavedBeforePromisedSpaceStillRead() throws {
        let old = Data(#"{"neededBytes":10,"availableBytes":5,"volumeName":"Macintosh HD"}"#.utf8)
        let decoded = try JSONDecoder().decode(DiskSpaceCheck.self, from: old)

        XCTAssertEqual(decoded, check(needed: 10, available: 5))
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(decoded), encoding: .utf8))
        XCTAssertFalse(encoded.contains("promisedBytes"), encoded)
    }
}

/// What downloads in the list will still write: only those that write by
/// themselves, on the same disk, each once.
@MainActor
final class PromisedDiskSpaceTests: XCTestCase {
    private let gigabyte: Int64 = 1_000_000_000

    private func record(
        _ status: TorrentStatus,
        in folder: String,
        selectedGigabytes: Int64 = 10,
        progress: Double = 0.4,
        savedForLater: Bool = false
    ) -> TorrentRecord {
        var record = makeTestRecord(savePath: folder, status: status, progress: progress)
        record.metrics.selectedBytes = selectedGigabytes * gigabyte
        record.isSavedForLater = savedForLater
        return record
    }

    private func makeStore(torrents: [TorrentRecord], disk: FakeDiskSpaceReader = FakeDiskSpaceReader()) -> AppStore {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine(), torrents: torrents, diskSpaceReader: disk)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        return bundle.store
    }

    /// Downloading and checking count; a stopped, saved, failed or finished
    /// download does not, nor one on another disk.
    func testOnlyDownloadsThatWriteByThemselvesPromiseSpace() {
        let store = makeStore(torrents: [
            record(.downloading, in: "/Disk/Movies", progress: 0.4),
            record(.checking, in: "/Disk/Movies/", progress: 0.9),
            record(.stopped, in: "/Disk/Movies"),
            record(.stopped, in: "/Disk/Movies", savedForLater: true),
            record(.error, in: "/Disk/Movies"),
            record(.seeding, in: "/Disk/Movies", progress: 1),
            record(.downloading, in: "/Other/Series"),
        ])

        XCTAssertEqual(store.writingDownloadFolders, ["/Disk/Movies", "/Other/Series"])
        XCTAssertEqual(store.promisedBytes(inFolders: ["/Disk/Movies"]), 6 * gigabyte + 1 * gigabyte)
        XCTAssertEqual(store.promisedBytes(inFolders: ["/Elsewhere"]), 0)
    }

    /// The text promises that a download stopped in the main window gives
    /// its room back and "Скачать" returns in the same window.
    func testAStoppedDownloadGivesItsRoomBackAtOnce() {
        let store = makeStore(torrents: [record(.downloading, in: "/Disk/Movies", selectedGigabytes: 60, progress: 0)])
        let disk = DiskSpaceInfo(availableBytes: 100 * gigabyte, volumeName: "Macintosh HD")
        let folders: Set<String> = ["/Disk/Movies"]

        XCTAssertNotNil(
            DiskSpaceCheck.shortfall(neededBytes: 60 * gigabyte, promisedBytes: store.promisedBytes(inFolders: folders), on: disk)
        )

        store.torrents[0].status = .stopped

        XCTAssertEqual(store.promisedBytes(inFolders: folders), 0)
        XCTAssertNil(
            DiskSpaceCheck.shortfall(neededBytes: 60 * gigabyte, promisedBytes: store.promisedBytes(inFolders: folders), on: disk)
        )
    }

    /// Another folder counts when the system puts it on the same disk; the
    /// add window's own folder always counts.
    func testFoldersOnTheSameDiskAreFoundByTheirMountPoint() async {
        let disk = FakeDiskSpaceReader()
        disk.setAvailableBytes(100 * gigabyte, volumeName: "Macintosh HD", atPath: "/Disk/Movies")
        disk.setAvailableBytes(100 * gigabyte, volumeName: "Macintosh HD", atPath: "/Disk/Downloads")
        disk.setAvailableBytes(500 * gigabyte, volumeName: "Archive", atPath: "/Other/Series")
        let store = makeStore(
            torrents: [record(.downloading, in: "/Disk/Movies"), record(.downloading, in: "/Other/Series")],
            disk: disk
        )
        let target = await store.diskSpace(atPath: "/Disk/Downloads")

        let folders = await store.writingFolders(onDiskOf: "/Disk/Downloads", volumeURL: target?.volumeURL)

        XCTAssertEqual(folders, ["/Disk/Downloads", "/Disk/Movies"])
    }

    /// A download sent with "Скачать" counts while it is being added, and
    /// once in the list counts once.
    func testADownloadBeingAddedPromisesItsSizeOnce() async throws {
        let engine = FakeTorrentEngine()
        let bundle = makeTestStoreBundle(engine: engine)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        await engine.setAddSuspended(true)
        bundle.store.presentedModal = .addTorrentReview
        bundle.store.currentAddTorrentDraft = AddTorrentDraft(
            source: AddTorrentSource(kind: .torrentFile, rawValue: "/tmp/test.torrent"),
            originalName: "New Torrent",
            infoHash: "new-info-hash",
            suggestedSavePath: "/Disk/Downloads",
            alias: "",
            stopAfterDownload: false,
            files: [
                AddTorrentFileOption(name: "A.bin", sizeBytes: 7 * gigabyte, fileIndex: 0, isSelected: true),
                AddTorrentFileOption(name: "B.bin", sizeBytes: 3 * gigabyte, fileIndex: 1, isSelected: false),
            ],
            reviewState: .ready,
            errorState: nil
        )

        bundle.store.confirmDraft()

        XCTAssertEqual(bundle.store.writingDownloadFolders, ["/Disk/Downloads"])
        XCTAssertEqual(bundle.store.promisedBytes(inFolders: ["/Disk/Downloads"]), 7 * gigabyte)

        await engine.setAddSuspended(false)
        let didAdd = await waitForCondition { bundle.store.torrents.count == 1 }
        XCTAssertTrue(didAdd)
        let added = try XCTUnwrap(bundle.store.torrents.first)
        XCTAssertEqual(
            bundle.store.promisedBytes(inFolders: ["/Disk/Downloads"]),
            PromisedDiskSpace.remainingBytes(of: added)
        )
    }
}
