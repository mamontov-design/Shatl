// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// What the "i" beside "Сохранена" opens: why the download is in the list
/// unstarted, and whether its disk has room for it now. The disk is asked
/// while the popover is open and never from the list's own tick.
struct SavedDownloadInfoPopover: View {
    let metricsMode: MetricsPresentationMode
    let localeOverride: AppLocaleOverride
    let resolveStatus: @Sendable () async -> SavedDownloadSpaceStatus?

    @State private var status: SavedDownloadSpaceStatus?

    private static let refreshInterval = Duration.seconds(2)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            paragraph(L10n.string("torrent.saved.info.reason", localeOverride: localeOverride))

            if let status {
                paragraph(Self.statusText(status, metricsMode: metricsMode, localeOverride: localeOverride))
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .animation(ShatlMotion.cardState, value: status)
        .task {
            while !Task.isCancelled {
                status = await resolveStatus()
                try? await Task.sleep(for: Self.refreshInterval)
            }
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
