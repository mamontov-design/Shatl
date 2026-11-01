// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
@testable import Shatl

/// Texts that promise what the app does, checked against what it does. A
/// change of a formatter or a limit fails here and points at the text to
/// rewrite with it (in all seven languages). The places each part of the app
/// shows up in are listed in `AGENTS.md`, "What shows what".
@MainActor
final class CopyPromiseTests: XCTestCase {
    /// Settings → Appearance → "i" by the simplified mode: every example
    /// pair is what the simplified and the detailed mode show.
    func testThePrecisionPopoverQuotesTheFormatter() {
        let text = russian("settings.appearance.metrics.popover.precision")

        let speed: Int64 = 10_500_000
        XCTAssertTrue(
            text.contains("\(plain(Metrics.formatSpeed(speed, mode: .simplified))) вместо \(plain(Metrics.formatSpeed(speed, mode: .detailed)))"),
            "speed example: \(text)"
        )

        let size: Int64 = 7_700_000_000
        XCTAssertTrue(
            text.contains("\(plain(Metrics.formatBytes(size, purpose: .size, mode: .simplified))) вместо \(plain(Metrics.formatBytes(size, purpose: .size, mode: .detailed)))"),
            "size example: \(text)"
        )

        let peers = 143
        XCTAssertTrue(
            text.contains("\(Metrics.formatPeerCount(peers, mode: .simplified)) пиров вместо \(Metrics.formatPeerCount(peers, mode: .detailed))"),
            "peers example: \(text)"
        )
    }

    /// The same popover on the time left: rounded from 10 minutes to an
    /// hour, the same in both modes below 10 minutes and from an hour on.
    func testTheTimePopoverQuotesTheFormatter() {
        let text = russian("settings.appearance.metrics.popover.eta")

        let eta = 38 * 60
        XCTAssertTrue(
            text.contains("\(plain(Metrics.formatETA(eta, mode: .simplified))) вместо \(plain(Metrics.formatETA(eta, mode: .detailed)))"),
            "time example: \(text)"
        )
        for seconds in [9 * 60, 9 * 60 + 30, 60 * 60, 90 * 60, 5 * 60 * 60] {
            XCTAssertEqual(
                Metrics.formatETA(seconds, mode: .simplified),
                Metrics.formatETA(seconds, mode: .detailed),
                "\(seconds) s should look the same in both modes"
            )
        }
        XCTAssertNotEqual(
            Metrics.formatETA(10 * 60 + 2 * 60, mode: .simplified),
            Metrics.formatETA(10 * 60 + 2 * 60, mode: .detailed),
            "from 10 minutes the simplified mode rounds"
        )
    }

    /// The Halo limits are named in two texts and set in the engine's
    /// settings pack; they must be the same numbers.
    func testTheHaloTextsNameTheEngineLimits() throws {
        let bridge = try String(contentsOf: Self.sourceURL("App/LibtorrentShim/LibtorrentSessionBridge.mm"), encoding: .utf8)
        let economical = try XCTUnwrap(
            bridge.range(of: "LTMakePerformanceSettingsPack(LTPerformanceProfile profile) {").flatMap { function in
                bridge[function.upperBound...].range(of: "case LTPerformanceProfileEconomical: {")
            }.map { start in
                let rest = bridge[start.upperBound...]
                return String(rest[..<(rest.range(of: "return pack;")?.lowerBound ?? rest.endIndex)])
            }
        )
        let download = try Self.limit("download_rate_limit", in: economical)
        let upload = try Self.limit("upload_rate_limit", in: economical)
        let named = [Self.megabytesPerSecond(download), Self.megabytesPerSecond(upload)]

        for key in ["settings.downloads.performance.caption.economical", "halo_notice.message"] {
            let text = russian(key)
            for speed in named {
                XCTAssertTrue(text.contains(speed), "\(key) should name \(speed): \(text)")
            }
        }
    }

    // MARK: - Helpers

    private func russian(_ key: String) -> String {
        plain(L10n.string(key, localeOverride: .russian))
    }

    /// Plain spaces in place of the typograph's non-breaking ones.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private static func sourceURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }

    /// `pack.set_int(lt::settings_pack::<name>, 5 * 1024 * 1024);` → bytes.
    private static func limit(_ name: String, in source: String) throws -> Int {
        let pattern = "settings_pack::\(name),\\s*([0-9 *]+)\\);"
        let regex = try NSRegularExpression(pattern: pattern)
        let match = try XCTUnwrap(regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        let expression = String(source[try XCTUnwrap(Range(match.range(at: 1), in: source))])
        return expression.split(separator: "*").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.reduce(1, *)
    }

    /// Bytes per second as the texts name them: megabytes of 1 024 × 1 024,
    /// with a decimal comma.
    private static func megabytesPerSecond(_ bytes: Int) -> String {
        let value = Double(bytes) / 1_048_576
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru")
        formatter.maximumFractionDigits = 1
        return "\(formatter.string(from: NSNumber(value: value)) ?? "\(value)") МБ/с"
    }
}
