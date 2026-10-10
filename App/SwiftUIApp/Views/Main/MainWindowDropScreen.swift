// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum MainWindowDropLayout {
    /// The dashed frame keeps this distance from the edges of the window's
    /// content, as the cards of the list do.
    static let frameInset: CGFloat = 8

    /// By the rule of nested corners: 8 pt, and 18 pt on macOS 26.
    static var frameCornerRadius: CGFloat {
        ShatlCornerRadius.nested(in: ShatlCornerRadius.window, inset: frameInset)
    }

    /// What a drag has to carry for the window to look at it at all.
    static let draggedTypes: [UTType] = [.fileURL, .url, .plainText]
}

/// What the main window shows in place of its content while a download is
/// dragged over it: a dashed frame the size of the content and the common
/// message block in the middle. A release anywhere in the window counts; the
/// frame is a sign, not a target.
struct MainWindowDropScreen: View {
    let offer: DraggedDownloadOffer
    let localeOverride: AppLocaleOverride

    var body: some View {
        ShatlMessageBlockPrimary(
            systemImage: systemImage,
            title: title,
            message: message
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(
                cornerRadius: MainWindowDropLayout.frameCornerRadius,
                style: .continuous
            )
            .strokeBorder(
                ShatlColor.accent,
                style: StrokeStyle(lineWidth: 1, dash: [4, 2])
            )
        }
        .padding(MainWindowDropLayout.frameInset)
        .accessibilityElement(children: .combine)
    }

    /// The icon names what is carried: the window has recognised it.
    private var systemImage: String {
        switch offer {
        case .accept(.torrentFile):
            "document.badge.plus"
        case .accept(.magnetLink):
            "link.badge.plus"
        case .tooMany, .unsupported:
            "exclamationmark.circle"
        }
    }

    private var title: String {
        switch offer {
        case .accept:
            L10n.string("main.drop.accept.title", localeOverride: localeOverride)
        case .tooMany, .unsupported:
            L10n.string("main.drop.too_many.title", localeOverride: localeOverride)
        }
    }

    private var message: String? {
        switch offer {
        case .accept:
            nil
        case .tooMany, .unsupported:
            L10n.string("main.drop.too_many.message", localeOverride: localeOverride)
        }
    }
}

/// Answers a drag over the main window while it is still in the air.
struct MainWindowDropDelegate: DropDelegate {
    /// Whether the window can add a download right now.
    let isAvailable: () -> Bool
    /// The window's answer, or `nil` once the drag has left.
    let onOffer: (DraggedDownloadOffer?) -> Void
    let onDrop: (DraggedDownload) -> Void

    /// A drag of anything else passes over the window as if it took no drops.
    func validateDrop(info: DropInfo) -> Bool {
        isAvailable() && DraggedContent.ofCurrentDrag().offer != .unsupported
    }

    func dropEntered(info: DropInfo) {
        onOffer(DraggedContent.ofCurrentDrag().offer)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if case .accept = DraggedContent.ofCurrentDrag().offer {
            return DropProposal(operation: .copy)
        }
        return DropProposal(operation: .forbidden)
    }

    func dropExited(info: DropInfo) {
        onOffer(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isAvailable(),
              case let .accept(download) = DraggedContent.ofCurrentDrag().offer else {
            onOffer(nil)
            return false
        }
        onDrop(download)
        return true
    }
}

extension DraggedContent {
    /// What the drag in progress carries. The system's drag pasteboard holds
    /// it while the pointer is still over the window, so the window can tell
    /// a `.torrent` file from a picture before anything is released.
    static func ofCurrentDrag() -> DraggedContent {
        let pasteboard = NSPasteboard(name: .drag)
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        let texts = (pasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: .string) }

        return DraggedContent(
            fileURLs: urls.filter(\.isFileURL),
            texts: urls.filter { !$0.isFileURL }.map(\.absoluteString) + texts
        )
    }

    /// What a paste carries, as the system hands it over.
    static func pasted(_ providers: [NSItemProvider]) async -> DraggedContent {
        var content = DraggedContent()

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self), let url = await provider.loadURL() {
                if url.isFileURL {
                    content.fileURLs.append(url)
                } else {
                    content.texts.append(url.absoluteString)
                }
            } else if provider.canLoadObject(ofClass: String.self), let text = await provider.loadText() {
                content.texts.append(text)
            }
        }

        return content
    }
}

private extension NSItemProvider {
    func loadURL() async -> URL? {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    func loadText() async -> String? {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }
}
