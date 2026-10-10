// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// What the "i" beside "Сохранена" opens: why the download is in the list
/// unstarted, and whether its disk has room for it now. The card owns the
/// disk's answer and hands it over, so the popover is whole when it opens; a
/// later answer replaces the old one in place.
struct SavedDownloadInfoPopover: View {
    let status: SavedDownloadSpaceStatus?
    let metricsMode: MetricsPresentationMode
    let localeOverride: AppLocaleOverride

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let refreshInterval = Duration.seconds(2)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            paragraph(L10n.string("torrent.saved.info.reason", localeOverride: localeOverride))

            // Old and new text overlap while one replaces the other, as in a
            // message block.
            ZStack(alignment: .topLeading) {
                if let statusText {
                    paragraph(statusText)
                        .id(statusText)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
                }
            }
            .animation(ShatlMotion.messageBlockContent, value: statusText)
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
    }

    private var statusText: String? {
        status.map {
            Self.statusText($0, metricsMode: metricsMode, localeOverride: localeOverride)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .shatlTypography(ShatlTypography.bodyRegular)
            .foregroundStyle(ShatlColor.typographySecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func statusText(
        _ status: SavedDownloadSpaceStatus,
        metricsMode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride
    ) -> String {
        switch status {
        case let .known(check) where check.fits:
            L10n.format(
                "torrent.saved.info.fits",
                localeOverride: localeOverride,
                defaultValue: "",
                check.volumeName,
                check.availableText(mode: metricsMode, localeOverride: localeOverride),
                check.neededText(mode: metricsMode, localeOverride: localeOverride)
            )
        case let .known(check):
            L10n.format(
                "torrent.saved.info.short",
                localeOverride: localeOverride,
                defaultValue: "",
                check.volumeName,
                check.availableText(mode: metricsMode, localeOverride: localeOverride),
                check.neededText(mode: metricsMode, localeOverride: localeOverride),
                check.shortfallText(mode: metricsMode, localeOverride: localeOverride)
            )
        case let .unknown(folderName):
            L10n.format(
                "torrent.saved.info.unknown",
                localeOverride: localeOverride,
                defaultValue: "",
                ShatlErrorCatalog.shortenedTorrentName(folderName)
            )
        }
    }
}
