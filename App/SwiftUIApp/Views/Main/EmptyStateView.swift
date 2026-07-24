import SwiftUI

struct EmptyStateView: View {
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
                onValidationError: onEntryValidationError
            )
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
    }
}
