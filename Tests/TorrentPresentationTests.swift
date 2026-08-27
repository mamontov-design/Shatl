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
        XCTAssertEqual(ShatlBottomChipLayout.standardListBottomPadding, 8)
    }

    func testExpandedMetricsHideConnectivityMetricsForSleepingStatuses() {
        let record = makeTestRecord(status: .stopped, progress: 0.23)
        var mutatedRecord = record
        mutatedRecord.metrics.seeds = 2
        mutatedRecord.metrics.peers = 2
        mutatedRecord.metrics.uploadSpeedBytesPerSecond = 16_384
        mutatedRecord.metrics.uploadedBytes = 4_096
        mutatedRecord.metrics.totalBytes = 2_147_483_648

        let metrics = TorrentPresentation.expandedMetrics(for: mutatedRecord, mode: .detailed)
        let metricIDs = Set(metrics.map { $0.id })

        XCTAssertFalse(metricIDs.contains("peers"))
        XCTAssertFalse(metricIDs.contains("upload-speed"))
        XCTAssertTrue(metricIDs.contains("uploaded"))
        XCTAssertTrue(metricIDs.contains("size"))
    }

    func testExpandedMetricsShowConnectivityMetricsForSeeding() {
        let record = makeTestRecord(status: .seeding, progress: 1.0)
        var mutatedRecord = record
        mutatedRecord.metrics.seeds = 5
        mutatedRecord.metrics.peers = 7
        mutatedRecord.metrics.uploadSpeedBytesPerSecond = 8_192

        let metrics = TorrentPresentation.expandedMetrics(for: mutatedRecord, mode: .detailed)
        let metricIDs = Set(metrics.map { $0.id })

        XCTAssertTrue(metricIDs.contains("peers"))
        XCTAssertTrue(metricIDs.contains("upload-speed"))
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

    func testPeerCountsAreCappedForLegacyExpandedMetrics() {
        var record = makeTestRecord(status: .downloading, progress: 0.5)
        record.metrics.seeds = 1_000
        record.metrics.peers = 15_000

        let metrics = TorrentPresentation.expandedMetrics(for: record, mode: .simplified)
        let peersMetric = metrics.first { $0.id == "peers" }

        XCTAssertEqual(peersMetric?.value, ">999 ↑  >999 ↓")
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

    func testDetailedSpeedKeepsSubKilobyteValuesVisible() {
        XCTAssertEqual(Metrics.formatSpeed(67, mode: .detailed), "67 Б/с")
        XCTAssertEqual(Metrics.formatSpeed(410, mode: .detailed), "0,4 КБ/с")
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
