// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import XCTest
@testable import Shatl

/// The add window's files come out from under a cover, and never through an
/// effect of their own. While the files faded and scaled in, SwiftUI kept the
/// settings plate's labels in one AppKit view with the plate's text field and
/// switch, and there they were at times drawn upside down for the whole fade
/// (the owner's recording, October 2026). The upside-down picture is the
/// system's and cannot be seen from a test; where the labels sit can.
@MainActor
final class AddTorrentReviewAppearanceTests: XCTestCase {
    private func makeDraft(reviewState: AddTorrentReviewState = .ready, id: UUID = UUID()) -> AddTorrentDraft {
        AddTorrentDraft(
            id: id,
            source: AddTorrentSource(kind: .externalOpen, rawValue: "/tmp/Northstar.torrent"),
            originalName: "Northstar",
            infoHash: "northstar",
            suggestedSavePath: NSTemporaryDirectory(),
            alias: "",
            stopAfterDownload: false,
            files: [AddTorrentFileOption(name: "Northstar/E01.mkv", sizeBytes: 300_000_000, fileIndex: 0, isSelected: true)],
            reviewState: reviewState,
            errorState: nil
        )
    }

    private struct HostedWindow {
        let window: NSWindow
        let hosting: NSView
    }

    private func makeWindow(store: AppStore) -> HostedWindow {
        let size = NSSize(width: 780, height: 570)
        let hosting = NSHostingView(
            rootView: AddTorrentReviewView()
                .environmentObject(store)
                .frame(width: size.width, height: size.height)
        )
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        return HostedWindow(window: window, hosting: hosting)
    }

    private func allViews(in root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap { allViews(in: $0) }
    }

    /// Something SwiftUI has drawn itself, a label first of all: a layer with
    /// a picture in it that is no AppKit view's own layer.
    private struct Drawn {
        var frame: CGRect
        /// Whether it sits in the window's own view, and not in an AppKit
        /// view put into it.
        var isInTheWindowsOwnView: Bool
    }

    private func drawn(in hosting: NSView) -> [Drawn] {
        guard let root = hosting.layer else { return [] }
        var found: [Drawn] = []
        func visit(_ layer: CALayer, owner: NSView?) {
            let view = layer.delegate as? NSView
            if view == nil, layer.contents != nil {
                found.append(Drawn(frame: layer.convert(layer.bounds, to: root), isInTheWindowsOwnView: owner === hosting))
            }
            for sublayer in layer.sublayers ?? [] {
                visit(sublayer, owner: view ?? owner)
            }
        }
        visit(root, owner: nil)
        return found
    }

    /// The labels of the settings plate, as they lie once the window is at
    /// rest: what is drawn in the right column above the alias field.
    private func settingsLabels(in hosted: HostedWindow) throws -> [CGRect] {
        let aliasField = try XCTUnwrap(
            allViews(in: hosted.hosting).compactMap { $0 as? NSTextField }.first(where: \.isEditable)
        )
        let field = aliasField.convert(aliasField.bounds, to: hosted.hosting)
        return drawn(in: hosted.hosting)
            .filter { $0.isInTheWindowsOwnView }
            .map(\.frame)
            .filter { $0.minX >= field.minX - 4 && $0.maxY <= field.minY + 1 && $0.width > 30 }
    }

    private func lies(_ frame: CGRect, at label: CGRect) -> Bool {
        abs(frame.midX - label.midX) <= 8 && abs(frame.midY - label.midY) <= 8
            && abs(frame.width - label.width) <= 4 && abs(frame.height - label.height) <= 3
    }

    /// What is drawn in the window, read as often as the main thread lets
    /// go, for `duration`.
    private func watch(_ hosted: HostedWindow, for duration: TimeInterval) async throws -> [(time: TimeInterval, drawn: [Drawn])] {
        var samples: [(time: TimeInterval, drawn: [Drawn])] = []
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < duration {
            samples.append((CACurrentMediaTime() - start, drawn(in: hosted.hosting)))
            try await Task.sleep(for: .milliseconds(4))
        }
        return samples
    }

    private func labelsInAppKitViews(
        _ samples: [(time: TimeInterval, drawn: [Drawn])],
        labels: [CGRect]
    ) -> [TimeInterval] {
        samples
            .filter { sample in
                sample.drawn.contains { drawn in
                    !drawn.isInTheWindowsOwnView && labels.contains { lies(drawn.frame, at: $0) }
                }
            }
            .map(\.time)
    }

    func testSettingsLabelsStayInTheWindowsOwnViewAsTheFilesAppear() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        bundle.store.currentAddTorrentDraft = makeDraft()

        let hosted = makeWindow(store: bundle.store)
        defer { hosted.window.orderOut(nil) }
        hosted.window.orderFrontRegardless()
        let samples = try await watch(hosted, for: 0.8)

        let labels = try settingsLabels(in: hosted)
        XCTAssertGreaterThanOrEqual(labels.count, 6, "The plate's labels must be found for this to test anything")
        let times = labelsInAppKitViews(samples, labels: labels)
        XCTAssertTrue(
            times.isEmpty,
            "The plate's labels sat in an AppKit view from \(Int((times.first ?? 0) * 1000)) to \(Int((times.last ?? 0) * 1000)) ms"
        )
    }

    /// The files leave for a message the same way: under the cover, as they
    /// were, and out of the window once it has come over them.
    func testFilesStayAsTheyWereUnderTheCoverAsAMessageComes() async throws {
        let bundle = makeTestStoreBundle(engine: FakeTorrentEngine())
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundle.rootURL)
        }
        let id = UUID()
        bundle.store.currentAddTorrentDraft = makeDraft(id: id)

        let hosted = makeWindow(store: bundle.store)
        defer { hosted.window.orderOut(nil) }
        hosted.window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(800))
        let labels = try settingsLabels(in: hosted)
        XCTAssertGreaterThanOrEqual(labels.count, 6, "The plate's labels must be found for this to test anything")

        bundle.store.currentAddTorrentDraft = makeDraft(reviewState: .invalid(message: "No peers"), id: id)
        let samples = try await watch(hosted, for: 0.8)

        func labelsShown(in sample: (time: TimeInterval, drawn: [Drawn])) -> Int {
            labels.filter { label in
                sample.drawn.contains { $0.isInTheWindowsOwnView && lies($0.frame, at: label) }
            }.count
        }
        let early = samples.filter { $0.time > 0.03 && $0.time < 0.12 }
        if let sample = early.first {
            XCTAssertEqual(labelsShown(in: sample), labels.count, "The files are still there while the cover comes over them")
        }
        let last = try XCTUnwrap(samples.last)
        XCTAssertEqual(labelsShown(in: last), 0, "The files are out of the window once the message has come")
        XCTAssertTrue(labelsInAppKitViews(samples, labels: labels).isEmpty)
    }
}
