// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct EmptyStateView: View {
    /// A download is being dragged over the window: the link field leaves.
    var isDragInProgress = false
    var onEntryValidationError: (TorrentErrorState) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            centeredContent(minHeight: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func centeredContent(minHeight: CGFloat? = nil) -> some View {
        VStack {
            AddTorrentEntryView(
                placement: .emptyState,
                hidesMagnetFieldForDrag: isDragInProgress,
                onValidationError: onEntryValidationError
            )
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
    }
}
