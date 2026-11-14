// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

#if DEBUG
import SwiftUI

/// Debug: the stopped downloads ask their trackers how many seeds and
/// leechers they have, without downloading anything, and the answers show
/// with how long they took. The first step of a queue that would rank
/// downloads by their swarms, tried on the owner's real trackers
/// (2026-11-13). At most ten downloads, so Settings keeps its height.
struct TrackerProbeSettingsSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var rows: [Row] = []
    @State private var isAsking = false
    @State private var probe: Task<Void, Never>?

    private static let shownCount = 10
    private static let patience: Duration = .seconds(15)

    private struct Row: Identifiable, Equatable {
        let id: UUID
        let name: String
        var isHeld = true
        var scrape: EngineTrackerScrape?
    }

    var body: some View {
        ShatlSettingsParameterHeader(localizedTitle: "settings.debug.tracker_probe.section")

        ShatlSettingsParameter {
            HStack(alignment: .center, spacing: 12) {
                Text(verbatim: L10n.string("settings.debug.tracker_probe.caption", localeOverride: localeOverride))
                    .shatlTypography(ShatlTypography.bodyRegular)
                    .foregroundStyle(ShatlColor.typographySecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ShatlButton(localizedTitle: "settings.debug.tracker_probe.button", role: .borderedNeutral) {
                    ask()
                }
                .disabled(isAsking)
            }

            ForEach(rows) { row in
                ShatlSettingsParameterDivider()
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.name)
                        .shatlTypography(ShatlTypography.bodyRegular)
                        .foregroundStyle(ShatlColor.typographyPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: summary(of: row))
                        .shatlTypography(ShatlTypography.bodyRegular)
                        .foregroundStyle(ShatlColor.typographySecondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onDisappear {
            probe?.cancel()
            isAsking = false
        }
    }

    private var localeOverride: AppLocaleOverride {
        store.preferences.localeOverride
    }

    private func ask() {
        probe?.cancel()
        let candidates = store.trackerProbeCandidates
        rows = candidates.prefix(Self.shownCount).map { Row(id: $0.id, name: $0.name) }
        let leftOut = candidates.count - rows.count
        if rows.isEmpty {
            rows = [Row(id: UUID(), name: L10n.string("settings.debug.tracker_probe.empty", localeOverride: localeOverride), isHeld: false)]
            return
        }
        if leftOut > 0 {
            rows.append(Row(
                id: UUID(),
                name: L10n.format("settings.debug.tracker_probe.more", localeOverride: localeOverride, defaultValue: "%@", String(leftOut)),
                isHeld: false
            ))
        }
        isAsking = true
        probe = Task { @MainActor in
            for index in rows.indices where rows[index].isHeld {
                rows[index].isHeld = await store.engineScrapeTrackers(id: rows[index].id)
            }
            let deadline = ContinuousClock.now + Self.patience
            while !Task.isCancelled, ContinuousClock.now < deadline {
                for index in rows.indices where rows[index].isHeld {
                    rows[index].scrape = await store.engineTrackerScrape(id: rows[index].id)
                }
                let pending = rows.contains { row in
                    guard row.isHeld, let scrape = row.scrape else { return row.isHeld }
                    return scrape.answers.count < scrape.trackerCount
                }
                guard pending else { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            isAsking = false
        }
    }

    private func summary(of row: Row) -> String {
        guard row.isHeld else { return "" }
        guard let scrape = row.scrape else {
            return L10n.string("settings.debug.tracker_probe.waiting", localeOverride: localeOverride)
        }
        guard scrape.trackerCount > 0 else {
            return L10n.string("settings.debug.tracker_probe.no_trackers", localeOverride: localeOverride)
        }
        let answered = String(scrape.replies.count)
        let total = String(scrape.trackerCount)
        if let best = scrape.replies.first, let first = scrape.firstReplyMilliseconds {
            return L10n.format(
                "settings.debug.tracker_probe.answer",
                localeOverride: localeOverride,
                defaultValue: "%1$@ %2$@ %3$@ %4$@ %5$@",
                String(best.seeds ?? 0),
                String(best.leechers ?? 0),
                String(first),
                answered,
                total
            )
        }
        if let failure = scrape.answers.first(where: { $0.errorMessage != nil }) {
            return L10n.format(
                "settings.debug.tracker_probe.failed",
                localeOverride: localeOverride,
                defaultValue: "%1$@ %2$@ %3$@",
                String(scrape.answers.count),
                total,
                "\(failure.tracker): \(failure.errorMessage ?? "")"
            )
        }
        return L10n.string("settings.debug.tracker_probe.waiting", localeOverride: localeOverride)
    }
}
#endif
