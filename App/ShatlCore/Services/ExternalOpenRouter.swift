import Foundation

/// External open events can arrive before the store is ready.
/// Buffers them until the application can process URLs.
@MainActor
final class ExternalOpenRouter {
    static let shared = ExternalOpenRouter()

    private var pendingURLs: [URL] = []
    private var handler: ((URL) -> Void)?

    init() {}

    func attach(handler: @escaping (URL) -> Void) {
        self.handler = handler
        flushPendingURLs()
    }

    func receive(urls: [URL]) {
        guard !urls.isEmpty else { return }

        if let handler {
            urls.forEach(handler)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    private func flushPendingURLs() {
        guard let handler, !pendingURLs.isEmpty else { return }

        let urls = pendingURLs
        pendingURLs.removeAll()
        urls.forEach(handler)
    }
}
