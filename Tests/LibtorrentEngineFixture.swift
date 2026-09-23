// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import CryptoKit
import Foundation
@testable import Shatl

/// A generated torrent with its payload in a temporary folder, for tests that
/// run the real libtorrent bridge.
struct EngineFixture {
    let rootURL: URL
    let directories: ShatlDirectories
    let torrentID: UUID
    let infoHashHex: String
    let entry: SessionRestoreEntry

    var resumeDataURL: URL {
        directories.resumeDataDirectoryURL
            .appendingPathComponent("\(torrentID.uuidString).fastresume", isDirectory: false)
    }

    /// The same torrent as a magnet link without trackers.
    var magnetSource: AddTorrentSource {
        AddTorrentSource(kind: .magnet, rawValue: "magnet:?xt=urn:btih:\(infoHashHex)&dn=payload.bin")
    }

    static func make(named name: String) throws -> EngineFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentEngine-\(name)-\(UUID().uuidString)", isDirectory: true)
        let directories = ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
        try directories.ensureSessionDirectories()

        let saveURL = rootURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveURL, withIntermediateDirectories: true)
        let payload = Data((0..<(32 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try payload.write(to: saveURL.appendingPathComponent("payload.bin", isDirectory: false))

        let torrentURL = rootURL.appendingPathComponent("fixture.torrent", isDirectory: false)
        let info = makeInfoDictionary(fileName: "payload.bin", payload: payload, pieceLength: 16 * 1024)
        try (Data("d4:info".utf8) + info + Data("e".utf8)).write(to: torrentURL)

        let torrentID = UUID()
        return EngineFixture(
            rootURL: rootURL,
            directories: directories,
            torrentID: torrentID,
            infoHashHex: Insecure.SHA1.hash(data: info).map { String(format: "%02x", $0) }.joined(),
            entry: SessionRestoreEntry(
                torrentID: torrentID,
                attemptID: UUID(),
                archivedTorrentPath: torrentURL.path,
                suggestedSavePath: saveURL.path,
                selectedFileIndices: [0],
                stopAfterDownload: false,
                shouldStart: false
            )
        )
    }

    func setResumeDataFolderWritable(_ isWritable: Bool) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: isWritable ? 0o755 : 0o555],
            ofItemAtPath: directories.resumeDataDirectoryURL.path
        )
    }

    func remove() {
        try? setResumeDataFolderWritable(true)
        try? FileManager.default.removeItem(at: rootURL)
    }

    /// The bencoded info dictionary of a minimal single-file v1 torrent without
    /// trackers, so no peers are contacted for it. Its SHA-1 is the info hash.
    private static func makeInfoDictionary(fileName: String, payload: Data, pieceLength: Int) -> Data {
        var pieces = Data()
        var offset = 0
        while offset < payload.count {
            let piece = payload[offset..<min(offset + pieceLength, payload.count)]
            pieces.append(contentsOf: Insecure.SHA1.hash(data: piece))
            offset += pieceLength
        }

        func string(_ value: String) -> Data { Data("\(value.utf8.count):\(value)".utf8) }
        func bytes(_ value: Data) -> Data { Data("\(value.count):".utf8) + value }
        func integer(_ value: Int) -> Data { Data("i\(value)e".utf8) }

        // Bencoded dictionary keys must be sorted.
        return Data("d".utf8)
            + string("length") + integer(payload.count)
            + string("name") + string(fileName)
            + string("piece length") + integer(pieceLength)
            + string("pieces") + bytes(pieces)
            + Data("e".utf8)
    }
}
