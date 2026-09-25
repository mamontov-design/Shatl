// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Darwin
import Foundation

/// The copy of Shatl that owns a data folder, as it wrote itself into the lock file.
nonisolated struct SingleInstanceHolder: Codable, Equatable, Sendable {
    var processIdentifier: Int32
    var bundlePath: String
    /// Set while the holder is quitting, so a copy launched meanwhile waits
    /// for the folder instead of handing torrents to a process that is going away.
    var isClosing: Bool
}

/// Keeps one Shatl per data folder: two copies would overwrite each other's
/// `session.json` and clean up each other's archives as orphans. The lock is
/// `flock` on `Shatl.lock` in the folder root, so the kernel drops it when the
/// process exits or crashes and a crash never leaves a stale lock behind.
/// The lock lasts as long as this object.
nonisolated final class SingleInstanceLock: @unchecked Sendable {
    nonisolated enum AcquireResult {
        case acquired(SingleInstanceLock)
        /// The record is nil while the holder has not written it yet.
        case heldByAnotherProcess(SingleInstanceHolder?)
        /// The file system gives no lock, e.g. a network home folder.
        case unavailable(errno: Int32)
    }

    static let fileName = "Shatl.lock"

    let fileURL: URL
    private let descriptor: Int32
    private let bundlePath: String

    private init(fileURL: URL, descriptor: Int32, bundlePath: String) {
        self.fileURL = fileURL
        self.descriptor = descriptor
        self.bundlePath = bundlePath
    }

    deinit {
        close(descriptor)
    }

    static func acquire(in directoryURL: URL, bundlePath: String = Bundle.main.bundlePath) -> AcquireResult {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
            let code = underlying.flatMap { $0.domain == NSPOSIXErrorDomain ? Int32($0.code) : nil }
            return .unavailable(errno: code ?? EIO)
        }

        let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        // Close-on-exec: a helper process must never inherit the lock and keep
        // it after Shatl quits, or the next launch would find the folder taken.
        let descriptor = open(fileURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            return .unavailable(errno: errno)
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(descriptor)
            return failure == EWOULDBLOCK
                ? .heldByAnotherProcess(readHolder(at: fileURL))
                : .unavailable(errno: failure)
        }

        let lock = SingleInstanceLock(fileURL: fileURL, descriptor: descriptor, bundlePath: bundlePath)
        lock.writeHolder(isClosing: false)
        return .acquired(lock)
    }

    /// Quitting sets the mark; a cancelled quit clears it.
    func setClosing(_ isClosing: Bool) {
        writeHolder(isClosing: isClosing)
    }

    static func readHolder(at fileURL: URL) -> SingleInstanceHolder? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SingleInstanceHolder.self, from: data)
    }

    private func writeHolder(isClosing: Bool) {
        let holder = SingleInstanceHolder(
            processIdentifier: getpid(),
            bundlePath: bundlePath,
            isClosing: isClosing
        )
        guard let data = try? JSONEncoder().encode(holder) else { return }
        _ = ftruncate(descriptor, 0)
        _ = data.withUnsafeBytes { bytes in
            pwrite(descriptor, bytes.baseAddress, bytes.count, 0)
        }
    }
}

/// Who this process is for its data folder.
nonisolated enum SingleInstanceRole {
    /// The lock is nil when the file system gives none: Shatl then runs as
    /// before rather than refuse to start.
    case primary(SingleInstanceLock?)
    case secondary(SingleInstanceHolder?)
}

nonisolated enum SingleInstanceGate {
    /// A copy launched while the holder quits waits for the folder, up to
    /// `closingHolderTimeout`; the holder may be saving the session or asking
    /// the user what to do about a failed save.
    static func resolve(
        directoryURL: URL,
        bundlePath: String = Bundle.main.bundlePath,
        closingHolderTimeout: TimeInterval = 20,
        pollInterval: TimeInterval = 0.1
    ) -> SingleInstanceRole {
        let deadline = ContinuousClock.now + .seconds(closingHolderTimeout)
        while true {
            switch SingleInstanceLock.acquire(in: directoryURL, bundlePath: bundlePath) {
            case .acquired(let lock):
                return .primary(lock)
            case .unavailable:
                return .primary(nil)
            case .heldByAnotherProcess(let holder):
                guard holder?.isClosing == true, ContinuousClock.now < deadline else {
                    return .secondary(holder)
                }
                Thread.sleep(forTimeInterval: pollInterval)
            }
        }
    }
}
