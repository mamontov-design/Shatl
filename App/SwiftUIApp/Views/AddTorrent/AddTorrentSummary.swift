// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// The free space the summary shows, as far as it is known.
enum AddTorrentFreeSpace: Equatable {
    /// Being read: the first reading for a folder takes a moment.
    case reading
    case available(Int64)
    /// The folder cannot be reached, so its disk says nothing.
    case unavailable
}

/// What stands in the way of "Скачать", said in the summary above its
/// numbers: a title and paragraphs, each a part that changes on its own.
struct AddTorrentSummaryMessage: Equatable {
    var title: String
    var paragraphs: [String]
}

/// What the add window's summary shows, laid out as a download card lays out
/// its expanded metrics: the files chosen and their size on the left, the
/// free space on the right.
struct AddTorrentSummaryGroups: Equatable {
    var leading: [MetricGroupPresentation]
    var trailing: MetricGroupPresentation

    /// What the summary's width animates on, as the card's metrics do.
    var widthAnimationSignature: [MetricGroupWidthAnimationSignature] {
        leading.groupWidthAnimationSignature + [trailing.widthAnimationSignature]
    }
}

enum AddTorrentSummaryPresentation {
    /// With no file chosen the group keeps its place and its title says why
    /// "Скачать" is off; the icon holds the plate.
    static let nothingSelectedIconName = "sparkle"

    static func groups(
        selectedFileCount: Int,
        totalFileCount: Int,
        selectedBytes: Int64,
        freeSpace: AddTorrentFreeSpace,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride
    ) -> AddTorrentSummaryGroups {
        var leading = [
            selectedFilesGroup(
                selectedFileCount: selectedFileCount,
                totalFileCount: totalFileCount,
                localeOverride: localeOverride
            ),
        ]

        // Nothing chosen weighs nothing, and a card never shows a zero.
        if selectedFileCount > 0, selectedBytes > 0 {
            leading.append(
                sizeGroup(selectedBytes: selectedBytes, mode: mode, localeOverride: localeOverride)
            )
        }

        return AddTorrentSummaryGroups(
            leading: leading,
            trailing: freeSpaceGroup(freeSpace, mode: mode, localeOverride: localeOverride)
        )
    }

    /// "1 из 2", "2 (все)", or "1" alone in a torrent of one file. One item
    /// throughout, so its parts change in place.
    private static func selectedFilesGroup(
        selectedFileCount: Int,
        totalFileCount: Int,
        localeOverride: AppLocaleOverride
    ) -> MetricGroupPresentation {
        let id = "selected-files"
        let hasOneFile = totalFileCount <= 1

        guard selectedFileCount > 0 else {
            return MetricGroupPresentation(
                id: id,
                title: hasOneFile
                    ? L10n.string("add_torrent.review.summary.no_file_selected", localeOverride: localeOverride)
                    : L10n.string("add_torrent.review.summary.no_files_selected", localeOverride: localeOverride),
                items: [
                    MetricItemPresentation(
                        id: id,
                        iconName: nothingSelectedIconName,
                        number: nil,
                        unit: nil,
                        usesAccentIcon: false
                    ),
                ]
            )
        }

        guard !hasOneFile else {
            return MetricGroupPresentation(
                id: id,
                title: L10n.string("add_torrent.review.summary.selected_file", localeOverride: localeOverride),
                items: [
                    MetricItemPresentation(
                        id: id,
                        iconName: nil,
                        number: count(selectedFileCount, localeOverride: localeOverride),
                        unit: nil,
                        usesAccentIcon: false
                    ),
                ]
            )
        }

        let isEverything = selectedFileCount >= totalFileCount
        return MetricGroupPresentation(
            id: id,
            title: L10n.string("add_torrent.review.summary.selected_files", localeOverride: localeOverride),
            items: [
                MetricItemPresentation(
                    id: id,
                    iconName: nil,
                    number: count(min(selectedFileCount, totalFileCount), localeOverride: localeOverride),
                    unit: nil,
                    usesAccentIcon: false,
                    of: isEverything
                        ? L10n.string("add_torrent.review.summary.all", localeOverride: localeOverride)
                        : L10n.string("add_torrent.review.summary.of", localeOverride: localeOverride),
                    total: isEverything ? nil : count(totalFileCount, localeOverride: localeOverride)
                ),
            ]
        )
    }

    /// Rounded as the files above it are, so one file and the summary of it
    /// name one size.
    private static func sizeGroup(
        selectedBytes: Int64,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride
    ) -> MetricGroupPresentation {
        let value = TorrentPresentation.splitMetricValue(
            AddTorrentSummaryByteFormatter.format(
                selectedBytes,
                mode: mode,
                rounding: .nearest,
                localeOverride: localeOverride
            )
        )
        return MetricGroupPresentation(
            id: "size",
            title: L10n.string("add_torrent.review.summary.size", localeOverride: localeOverride),
            items: [
                MetricItemPresentation(
                    id: "size",
                    iconName: nil,
                    number: value.number,
                    unit: value.unit,
                    usesAccentIcon: false
                ),
            ]
        )
    }

    /// Rounded down, so the summary never promises room that is not there.
    private static func freeSpaceGroup(
        _ freeSpace: AddTorrentFreeSpace,
        mode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride
    ) -> MetricGroupPresentation {
        let id = "free-space"
        let item: MetricItemPresentation

        switch freeSpace {
        case .reading:
            item = MetricItemPresentation(
                id: id,
                iconName: nil,
                number: nil,
                unit: nil,
                usesAccentIcon: false,
                isPending: true
            )
        case let .available(bytes):
            let value = TorrentPresentation.splitMetricValue(
                AddTorrentSummaryByteFormatter.format(
                    bytes,
                    mode: mode,
                    rounding: .down,
                    localeOverride: localeOverride
                )
            )
            item = MetricItemPresentation(
                id: id,
                iconName: nil,
                number: value.number,
                unit: value.unit,
                usesAccentIcon: false
            )
        case .unavailable:
            // A word in the unit's grey: a dash would read as no room at all.
            item = MetricItemPresentation(
                id: id,
                iconName: nil,
                number: nil,
                unit: L10n.string("add_torrent.review.summary.unavailable", localeOverride: localeOverride),
                usesAccentIcon: false
            )
        }

        return MetricGroupPresentation(
            id: id,
            title: L10n.string("add_torrent.review.summary.free_space", localeOverride: localeOverride),
            items: [item]
        )
    }

    /// A count with its digits grouped as the language groups them: "1 657".
    static func count(_ value: Int, localeOverride: AppLocaleOverride) -> String {
        let formatter = NumberFormatter()
        formatter.locale = L10n.locale(for: localeOverride)
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// The summary's numbers: the groups of a download card's expanded metrics,
/// on the same quiet plates and with the same motion.
struct AddTorrentSummaryMetrics: View {
    let groups: AddTorrentSummaryGroups

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ShatlMetricGroupSet(groups: groups.leading, isMuted: true)
                .layoutPriority(2)

            Spacer(minLength: ShatlMetricLayout.groupSpacing)
                .layoutPriority(0)

            ShatlMetricGroup(group: groups.trailing, isMuted: true)
                .layoutPriority(1)
        }
        .geometryGroup()
        .animation(ShatlMotion.metricResize, value: groups.widthAnimationSignature)
    }
}
