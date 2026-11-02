// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import Shatl

/// A card names seeds, who have the whole torrent and only give, and peers,
/// who are still downloading. libtorrent's `num_peers` counts every
/// connection, seeds too: shown as is, it named the connected seeds twice,
/// and with only seeds connected the two cells showed the same number.
@MainActor
final class PeerCountTests: XCTestCase {
    func testOnlySeedsConnectedLeaveNoPeers() {
        XCTAssertEqual(LibtorrentSessionBridge.downloadingPeerCount(forConnectedPeers: 6, seeds: 6), 0)
    }

    func testPeersAreTheConnectionsLeftAfterTheSeeds() {
        XCTAssertEqual(LibtorrentSessionBridge.downloadingPeerCount(forConnectedPeers: 9, seeds: 6), 3)
    }

    /// A seeding download is disconnected from other seeds, so every
    /// connection is a peer.
    func testWithoutSeedsEveryConnectionIsAPeer() {
        XCTAssertEqual(LibtorrentSessionBridge.downloadingPeerCount(forConnectedPeers: 4, seeds: 0), 4)
    }

    /// libtorrent counts the two a little differently: a connection on its
    /// way out leaves `num_peers` but may still count as a seed. The
    /// difference never goes below zero.
    func testTheCountNeverGoesBelowZero() {
        XCTAssertEqual(LibtorrentSessionBridge.downloadingPeerCount(forConnectedPeers: 2, seeds: 3), 0)
        XCTAssertEqual(LibtorrentSessionBridge.downloadingPeerCount(forConnectedPeers: 0, seeds: 0), 0)
    }
}
