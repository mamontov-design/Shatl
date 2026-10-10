// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// What the "i" beside "Сохранена" opens: why the download is in the list
/// unstarted, and whether its disk has room for it now. It opens with the
/// disk's answer already in hand; while it stays open the disk is asked
/// again, never from the list's own tick, and a new answer replaces the old
/// one in place.
struct SavedDownloadInfoPopover: View {
    let metricsMode: MetricsPresentationMode
    let localeOverride: AppLocaleOverride
    let resolveStatus: @Sendable () async -> SavedDownloadSpaceStatus?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var status: SavedDownloadSpaceStatus?

    private static let refreshInterval = Duration.seconds(2)

    init(
        initialStatus: SavedDownloadSpaceStatus?,
        metricsMode: MetricsPresentationMode,
        localeOverride: AppLocaleOverride,
        resolveStatus: @escaping @Sendable () async -> SavedDownloadSpaceStatus?
    ) {
        self.metricsMode = metricsMode
        self.localeOverride = localeOverride
        self.resolveStatus = resolveStatus
        _status = State(initialValue: initialStatus)
    }

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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { return }
                status = await resolveStatus()
            }
        }
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
