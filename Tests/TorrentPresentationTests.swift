// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

final class TorrentPresentationTests: XCTestCase {
    func testModernBottomChipLayoutReservesChipHeightAndSixPointGaps() {
        XCTAssertEqual(ShatlMetricLayout.containerHeight, 27)
        XCTAssertEqual(ShatlBottomChipLayout.modernEdgePadding, 6)
        XCTAssertEqual(ShatlBottomChipLayout.modernCornerRadius, 10)
        XCTAssertEqual(ShatlBottomChipLayout.cardGap, 6)
        XCTAssertEqual(ShatlBottomChipLayout.modernListBottomPadding, 39)
        XCTAssertEqual(ShatlBottomChipLayout.legacyEdgePadding, 12)
        XCTAssertEqual(ShatlBottomChipLayout.legacyCornerRadius, 13.5)
        XCTAssertEqual(ShatlBottomChipLayout.standardListBottomPadding, 8)
    }

    func testExpandedMetricGroupsHideConnectivityMetricsForSleepingStatuses() {
        let record = makeTestRecord(status: .stopped, progress: 0.23)
        var mutatedRecord = record
        mutatedRecord.metrics.seeds = 2
        mutatedRecord.metrics.peers = 2
        mutatedRecord.metrics.uploadSpeedBytesPerSecond = 16_384
        mutatedRecord.metrics.uploadedBytes = 4_096
        mutatedRecord.metrics.totalBytes = 2_147_483_648

        let groups = TorrentPresentation.expandedMetricGroups(for: mutatedRecord, mode: .detailed)
        let groupIDs = Set(groups.dynamicGroups.map(\.id))

        XCTAssertFalse(groupIDs.contains("peers"))
        XCTAssertFalse(groupIDs.contains("upload-speed"))
        XCTAssertTrue(groupIDs.contains("uploaded"))
        XCTAssertEqual(groups.sizeGroup.id, "size")
    }

    func testExpandedMetricGroupsShowConnectivityMetricsForSeeding() {
        let record = makeTestRecord(status: .seeding, progress: 1.0)
        var mutatedRecord = record
        mutatedRecord.metrics.seeds = 5
        mutatedRecord.metrics.peers = 7
        mutatedRecord.metrics.uploadSpeedBytesPerSecond = 8_192

        let groups = TorrentPresentation.expandedMetricGroups(for: mutatedRecord, mode: .detailed)
        let groupIDs = Set(groups.dynamicGroups.map(\.id))

        XCTAssertTrue(groupIDs.contains("peers"))
        XCTAssertTrue(groupIDs.contains("upload-speed"))
    }

    func testExpandedMetricGroupsHideUploadSpeedWhenUploadSpeedIsZero() {
        var record = makeTestRecord(status: .downloading, progress: 0.5)
        record.metrics.uploadSpeedBytesPerSecond = 0

        let groups = TorrentPresentation.expandedMetricGroups(for: record, mode: .simplified)

        XCTAssertFalse(groups.dynamicGroups.contains { $0.id == "upload-speed" })
    }

    func testExpandedMetricGroupsUseSelectedSizeForSizeGroup() {
        let record = makeTestRecord(status: .downloading, progress: 0.5)
        var mutatedRecord = record
        mutatedRecord.metrics.totalBytes = 16_000
        mutatedRecord.metrics.selectedBytes = 3_000

        let groups = TorrentPresentation.expandedMetricGroups(for: mutatedRecord, mode: .detailed)
        let sizeItem = groups.sizeGroup.items.first

        XCTAssertEqual(groups.sizeGroup.id, "size")
        XCTAssertEqual(sizeItem?.iconName, "scalemass")
        XCTAssertEqual(
            [sizeItem?.number, sizeItem?.unit].compactMap { $0 }.joined(separator: " "),
            Metrics.formatBytes(3_000, mode: .detailed)
        )
    }

    func testPeerCountsAreCappedForExpandedMetricGroups() {
        var record = makeTestRecord(status: .downloading, progress: 0.5)
        record.metrics.seeds = 999
        record.metrics.peers = 1_000

        let groups = TorrentPresentation.expandedMetricGroups(for: record, mode: .detailed)
        let peerItems = groups.dynamicGroups.first { $0.id == "peers" }?.items

        XCTAssertEqual(peerItems?.first { $0.id == "seeds" }?.number, "999")
        XCTAssertEqual(peerItems?.first { $0.id == "peers" }?.number, ">999")
    }

    func testSimplifiedPeerCountsAreCappedForExpandedMetricGroups() {
        var record = makeTestRecord(status: .downloading, progress: 0.5)
        record.metrics.seeds = 1_000
        record.metrics.peers = 15_000

        let peerItems = TorrentPresentation.expandedMetricGroups(for: record, mode: .simplified)
            .dynamicGroups
            .first { $0.id == "peers" }?
            .items

        XCTAssertEqual(peerItems?.first { $0.id == "seeds" }?.number, ">999")
        XCTAssertEqual(peerItems?.first { $0.id == "peers" }?.number, ">999")
    }

    func testPeerCountFormatterCapsOnlyFourDigitValues() {
        XCTAssertEqual(Metrics.formatPeerCount(-1, mode: .detailed), "0")
        XCTAssertEqual(Metrics.formatPeerCount(999, mode: .detailed), "999")
        XCTAssertEqual(Metrics.formatPeerCount(1_000, mode: .detailed), ">999")
        XCTAssertEqual(Metrics.formatPeerCount(15_000, mode: .detailed), ">999")
    }

    func testSimplifiedPeerCountsRoundDownByProductBuckets() {
        XCTAssertEqual(Metrics.formatPeerCount(9, mode: .simplified), "9")
        XCTAssertEqual(Metrics.formatPeerCount(14, mode: .simplified), "10")
        XCTAssertEqual(Metrics.formatPeerCount(99, mode: .simplified), "95")
        XCTAssertEqual(Metrics.formatPeerCount(109, mode: .simplified), "100")
        XCTAssertEqual(Metrics.formatPeerCount(499, mode: .simplified), "490")
        XCTAssertEqual(Metrics.formatPeerCount(549, mode: .simplified), "500")
        XCTAssertEqual(Metrics.formatPeerCount(999, mode: .simplified), "950")
        XCTAssertEqual(Metrics.formatPeerCount(1_000, mode: .simplified), ">999")
    }

    func testDetailedETAUsesSingleUnitAndCapsLargeValues() {
        XCTAssertEqual(Metrics.formatETA(59, mode: .detailed), "59 сек")
        XCTAssertEqual(Metrics.formatETA(60, mode: .detailed), "1 мин")
        XCTAssertEqual(Metrics.formatETA(119, mode: .detailed), "2 мин")
        XCTAssertEqual(Metrics.formatETA(3_601, mode: .detailed), "2 ч")
        XCTAssertEqual(Metrics.formatETA(86_400 * 6, mode: .detailed), "6 дн")
        XCTAssertEqual(Metrics.formatETA(86_400 * 7, mode: .detailed), "1 нед")
        XCTAssertEqual(Metrics.formatETA(86_400 * 11, mode: .detailed), ">1 нед")
        XCTAssertEqual(Metrics.formatETA(0, mode: .detailed), "—")
    }

    func testSpeedLevelGoesUpAtOnceAndDownOnlyWellBelowTheThreshold() {
        let kilobyte: Int64 = 1_024
        let megabyte: Int64 = 1_024 * 1_024

        XCTAssertEqual(TransferSpeedLevel(bytesPerSecond: 100 * kilobyte), .tortoise)
        XCTAssertEqual(TransferSpeedLevel(bytesPerSecond: 250 * kilobyte), .walk)
        XCTAssertEqual(TransferSpeedLevel(bytesPerSecond: 2 * megabyte), .run)
        XCTAssertEqual(TransferSpeedLevel(bytesPerSecond: 8 * megabyte), .hare)
        XCTAssertEqual(TransferSpeedLevel(bytesPerSecond: 25 * megabyte), .bolt)

        XCTAssertEqual(TransferSpeedLevel(bytesPerSecond: 2 * megabyte, after: .walk), .run)
        XCTAssertEqual(TransferSpeedLevel(bytesPerSecond: 30 * megabyte, after: .tortoise), .bolt)
        XCTAssertEqual(TransferSpeedLevel(bytesPerSecond: 19 * megabyte / 10, after: .run), .run)
        XCTAssertEqual(TransferSpeedLevel(bytesPerSecond: 17 * megabyte / 10, after: .run), .walk)
        // A fall through several levels lands where the speed is.
        XCTAssertEqual(TransferSpeedLevel(bytesPerSecond: 100 * kilobyte, after: .bolt), .tortoise)
        // Holding 10 % below the level it holds, not below the one under it.
        XCTAssertEqual(TransferSpeedLevel(bytesPerSecond: 23 * megabyte, after: .bolt), .bolt)
        XCTAssertEqual(TransferSpeedLevel(bytesPerSecond: 22 * megabyte, after: .bolt), .hare)

        XCTAssertEqual(TransferSpeedLevel(iconName: "figure.run"), .run)
        XCTAssertEqual(TransferSpeedLevel(iconName: "hare"), .hare)
        XCTAssertEqual(TransferSpeedLevel(iconName: "bolt.fill"), .bolt)
        XCTAssertNil(TransferSpeedLevel(iconName: "scalemass"))
    }

    func testSpeedLevelsStartAfreshAfterAStop() {
        var metrics = TorrentMetrics()
        metrics.downloadSpeedBytesPerSecond = 3 * 1_024 * 1_024
        metrics.uploadSpeedBytesPerSecond = 100 * 1_024
        let levels = TransferSpeedLevels().following(metrics)
        XCTAssertEqual(levels, TransferSpeedLevels(download: .run, upload: .tortoise))

        metrics.downloadSpeedBytesPerSecond = 0
        XCTAssertEqual(levels.following(metrics), TransferSpeedLevels(download: nil, upload: .tortoise))
    }

    func testDetailedSpeedKeepsSubKilobyteValuesVisible() {
        XCTAssertEqual(Metrics.formatSpeed(67, mode: .detailed), "67 Б/с")
        XCTAssertEqual(Metrics.formatSpeed(410, mode: .detailed), "410 Б/с")
    }

    /// A fraction of a kilobyte changed every second and rolled the digits of
    /// every card; a tenth of a megabyte still tells 1.4 from 1.
    func testDetailedSpeedShowsWholeKilobytesAndTenthsOfMegabytes() {
        XCTAssertEqual(Metrics.formatSpeed(697_300, mode: .detailed), "697 КБ/с")
        XCTAssertEqual(Metrics.formatSpeed(768_600, mode: .detailed), "769 КБ/с")
        XCTAssertEqual(Metrics.formatSpeed(999_400, mode: .detailed), "999 КБ/с")
        XCTAssertEqual(Metrics.formatSpeed(999_700, mode: .detailed), "1 МБ/с")
        XCTAssertEqual(Metrics.formatSpeed(1_400_000, mode: .detailed), "1,4 МБ/с")
        XCTAssertEqual(Metrics.formatSpeed(12_400_000, mode: .detailed), "12,4 МБ/с")
        XCTAssertEqual(Metrics.formatSpeed(12_000_000, mode: .detailed), "12 МБ/с")
    }

    func testCompactTransferMetricSetIsHiddenWhenDownloadSpeedIsZero() {
        var record = makeTestRecord(status: .downloading, progress: 0.5)
        record.metrics.downloadSpeedBytesPerSecond = 0
        record.metrics.etaSeconds = 300

        XCTAssertNil(TorrentPresentation.compactTransferMetricSet(for: record, mode: .simplified))
    }

    func testCompactTransferMetricSetHidesETAWhenEngineDoesNotProvideIt() {
        var record = makeTestRecord(status: .downloading, progress: 0.98)
        record.metrics.downloadSpeedBytesPerSecond = bytes(forMegabytes: 36)
        record.metrics.etaSeconds = 0

        let metricSet = TorrentPresentation.compactTransferMetricSet(for: record, mode: .simplified)

        XCTAssertEqual(metricSet?.items.map(\.id), ["download-speed"])
        XCTAssertFalse(metricSet?.items.contains { $0.iconName == "infinity" } ?? true)
    }

    func testCompactTransferMetricSetShowsETAWhenAvailable() {
        var record = makeTestRecord(status: .downloading, progress: 0.5)
        record.metrics.downloadSpeedBytesPerSecond = bytes(forMegabytes: 2)
        record.metrics.etaSeconds = 60

        let metricSet = TorrentPresentation.compactTransferMetricSet(for: record, mode: .simplified)

        XCTAssertEqual(metricSet?.items.map(\.id), ["download-speed", "eta"])
        XCTAssertNil(metricSet?.items.last?.iconName)
        XCTAssertEqual(metricSet?.items.last?.number, "1")
        XCTAssertEqual(metricSet?.items.last?.unit, "мин")
    }

    func testMetricWidthSignatureIgnoresSameWidthDigitChanges() {
        let oldItem = MetricItemPresentation(
            id: "download-speed",
            iconName: "figure.run",
            number: "98",
            unit: "МБ/с",
            usesAccentIcon: true
        )
        var newItem = oldItem
        newItem.number = "99"

        var oldDecimalItem = oldItem
        oldDecimalItem.number = "4,2"
        var newDecimalItem = oldDecimalItem
        newDecimalItem.number = "4,3"

        XCTAssertEqual(oldItem.widthAnimationSignature, newItem.widthAnimationSignature)
        XCTAssertEqual(oldDecimalItem.widthAnimationSignature, newDecimalItem.widthAnimationSignature)
    }

    func testMetricWidthSignatureChangesWhenNumberWidthChanges() {
        let oldItem = MetricItemPresentation(
            id: "download-speed",
            iconName: "figure.run",
            number: "99",
            unit: "МБ/с",
            usesAccentIcon: true
        )
        var newItem = oldItem
        newItem.number = "100"

        XCTAssertNotEqual(oldItem.widthAnimationSignature, newItem.widthAnimationSignature)
    }

    func testMetricWidthSignaturePreservesSeparatorsUnitsAndIcons() {
        let baseItem = MetricItemPresentation(
            id: "download-speed",
            iconName: "figure.run",
            number: "9,9",
            unit: "МБ/с",
            usesAccentIcon: true
        )
        var changedSeparatorPattern = baseItem
        changedSeparatorPattern.number = "10"
        var changedUnit = baseItem
        changedUnit.unit = "КБ/с"
        var changedIcon = baseItem
        changedIcon.iconName = "hare.fill"

        XCTAssertNotEqual(baseItem.widthAnimationSignature, changedSeparatorPattern.widthAnimationSignature)
        XCTAssertNotEqual(baseItem.widthAnimationSignature, changedUnit.widthAnimationSignature)
        XCTAssertNotEqual(baseItem.widthAnimationSignature, changedIcon.widthAnimationSignature)
    }

    func testMetricWidthAnimationPatternOnlyChangesWhenTextStructureChanges() {
        XCTAssertEqual(
            MetricWidthAnimationPattern.forText("5%"),
            MetricWidthAnimationPattern.forText("6%")
        )
        XCTAssertNotEqual(
            MetricWidthAnimationPattern.forText("9%"),
            MetricWidthAnimationPattern.forText("10%")
        )
    }

    func testMetricGroupWidthSignatureIgnoresSameWidthNumberChanges() {
        let item = MetricItemPresentation(
            id: "upload-speed",
            iconName: "figure.walk",
            number: "1,1",
            unit: "МБ/с",
            usesAccentIcon: false
        )
        let oldGroup = MetricGroupPresentation(
            id: "upload-speed",
            title: "Раздача",
            items: [item]
        )
        var newGroup = oldGroup
        newGroup.items[0].number = "1,2"

        XCTAssertEqual(oldGroup.widthAnimationSignature, newGroup.widthAnimationSignature)
    }

    func testDownloadAndUploadSpeedMetricsUseDistinctSymbolStylesAtEveryThreshold() {
        let cases: [(speed: Int64, downloadIcon: String, uploadIcon: String)] = [
            (1, "tortoise.fill", "tortoise"),
            (250 * 1_024, "figure.walk", "figure.walk"),
            (2 * 1_024 * 1_024, "figure.run", "figure.run"),
            (8 * 1_024 * 1_024, "hare.fill", "hare"),
            (25 * 1_024 * 1_024, "bolt.fill", "bolt"),
        ]

        for testCase in cases {
            var record = makeTestRecord(status: .downloading, progress: 0.5)
            record.metrics.downloadSpeedBytesPerSecond = testCase.speed
            record.metrics.uploadSpeedBytesPerSecond = testCase.speed

            let downloadMetric = TorrentPresentation
                .compactTransferMetricSet(for: record, mode: .simplified)?
                .items
                .first { $0.id == "download-speed" }
            let uploadMetric = TorrentPresentation
                .expandedMetricGroups(for: record, mode: .simplified)
                .dynamicGroups
                .first { $0.id == "upload-speed" }?
                .items
                .first

            XCTAssertEqual(downloadMetric?.iconName, testCase.downloadIcon)
            XCTAssertEqual(uploadMetric?.iconName, testCase.uploadIcon)
        }
    }

    func testSimplifiedETARoundsSecondsByProductBuckets() {
        XCTAssertEqual(Metrics.formatETA(60, mode: .simplified), "1 мин")
        XCTAssertEqual(Metrics.formatETA(59, mode: .simplified), "55 сек")
        XCTAssertEqual(Metrics.formatETA(54, mode: .simplified), "50 сек")
        XCTAssertEqual(Metrics.formatETA(11, mode: .simplified), "10 сек")
        XCTAssertEqual(Metrics.formatETA(10, mode: .simplified), "10 сек")
        XCTAssertEqual(Metrics.formatETA(9, mode: .simplified), "9 сек")
        XCTAssertEqual(Metrics.formatETA(1, mode: .simplified), "1 сек")
        XCTAssertEqual(Metrics.formatETA(0, mode: .simplified), "—")
    }

    func testSimplifiedETARoundsMinutesByProductBuckets() {
        XCTAssertEqual(Metrics.formatETA(60 * 9, mode: .simplified), "9 мин")
        XCTAssertEqual(Metrics.formatETA(60 * 10, mode: .simplified), "10 мин")
        XCTAssertEqual(Metrics.formatETA((60 * 27) + 30, mode: .simplified), "25 мин")
        XCTAssertEqual(Metrics.formatETA(60 * 38, mode: .simplified), "35 мин")
        XCTAssertEqual(Metrics.formatETA(60 * 59, mode: .simplified), "55 мин")
        XCTAssertEqual(Metrics.formatETA(60 * 60, mode: .simplified), "1 ч")
    }

    func testSimplifiedSpeedRoundsDownByProductBuckets() {
        XCTAssertEqual(Metrics.formatSpeed(bytes(forKilobytes: 0.9), mode: .simplified), "<1 КБ/с")
        XCTAssertEqual(Metrics.formatSpeed(bytes(forKilobytes: 1.2), mode: .simplified), "10 КБ/с")
        XCTAssertEqual(Metrics.formatSpeed(bytes(forKilobytes: 94), mode: .simplified), "90 КБ/с")
        XCTAssertEqual(Metrics.formatSpeed(bytes(forKilobytes: 100), mode: .simplified), "120 КБ/с")
        XCTAssertEqual(Metrics.formatSpeed(bytes(forKilobytes: 499), mode: .simplified), "480 КБ/с")
        XCTAssertEqual(Metrics.formatSpeed(bytes(forKilobytes: 500), mode: .simplified), "550 КБ/с")
        XCTAssertEqual(Metrics.formatSpeed(bytes(forKilobytes: 999), mode: .simplified), "950 КБ/с")
        XCTAssertEqual(Metrics.formatSpeed(bytes(forKilobytes: 1000), mode: .simplified), "1 МБ/с")
        XCTAssertEqual(Metrics.formatSpeed(bytes(forMegabytes: 1.2), mode: .simplified), "1 МБ/с")
        XCTAssertEqual(Metrics.formatSpeed(bytes(forMegabytes: 11.9), mode: .simplified), "10 МБ/с")
        XCTAssertEqual(Metrics.formatSpeed(bytes(forMegabytes: 13.1), mode: .simplified), "12 МБ/с")
    }

    func testSimplifiedBytesUsePurposeSpecificPrecision() {
        XCTAssertEqual(
            Metrics.formatBytes(512, purpose: .uploaded, mode: .simplified),
            "<1 КБ"
        )
        XCTAssertEqual(
            Metrics.formatBytes(1_234_567_890, purpose: .size, mode: .simplified),
            "1 ГБ"
        )
        XCTAssertEqual(
            Metrics.formatBytes(391_900_000, purpose: .size, mode: .simplified),
            "390 МБ"
        )
        XCTAssertEqual(
            Metrics.formatBytes(192_400_000, purpose: .size, mode: .simplified),
            "190 МБ"
        )
        XCTAssertEqual(
            Metrics.formatBytes(192_400_000, purpose: .size, mode: .detailed),
            "192,4 МБ"
        )
        XCTAssertEqual(
            Metrics.formatBytes(1_234_567_890, purpose: .uploaded, mode: .simplified),
            "1 ГБ"
        )
    }

    private func bytes(forKilobytes kilobytes: Double) -> Int64 {
        Int64((kilobytes * 1_024).rounded())
    }

    private func bytes(forMegabytes megabytes: Double) -> Int64 {
        Int64((megabytes * 1_048_576).rounded())
    }
}
