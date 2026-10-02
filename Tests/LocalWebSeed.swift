// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Network

/// Serves one payload over HTTP byte ranges on the loopback, as a web seed:
/// the only way a test gets libtorrent to download, and so to write, without
/// peers.
final class LocalWebSeed: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "LocalWebSeed")
    private let lock = NSLock()
    private var payloadValue = Data()
    private(set) var port: UInt16 = 0

    var payload: Data {
        get { lock.withLock { payloadValue } }
        set { lock.withLock { payloadValue = newValue } }
    }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled:
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        port = listener.port?.rawValue ?? 0
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffered: Data())
    }

    /// Answers every complete request in the buffer, then reads on: the
    /// connection is kept alive and requests may arrive together.
    private func receive(on connection: NWConnection, buffered: Data) {
        var buffered = buffered
        let separator = Data("\r\n\r\n".utf8)
        while let end = buffered.range(of: separator) {
            respond(to: String(decoding: buffered[..<end.lowerBound], as: UTF8.self), on: connection)
            buffered = Data(buffered[end.upperBound...])
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, error == nil, !isComplete || data != nil else {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffered: buffered + (data ?? Data()))
        }
    }

    private func respond(to header: String, on connection: NWConnection) {
        let payload = self.payload
        var range = 0..<payload.count
        let prefix = "range: bytes="
        for line in header.components(separatedBy: "\r\n") where line.lowercased().hasPrefix(prefix) {
            let bounds = line.dropFirst(prefix.count).split(separator: "-")
            if bounds.count == 2, let lower = Int(bounds[0]), let upper = Int(bounds[1]) {
                range = min(lower, payload.count)..<min(upper + 1, payload.count)
            }
        }
        let body = payload.subdata(in: range)
        let head = "HTTP/1.1 206 Partial Content\r\n"
            + "Content-Type: application/octet-stream\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Content-Range: bytes \(range.lowerBound)-\(range.upperBound - 1)/\(payload.count)\r\n"
            + "\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in })
    }
}
