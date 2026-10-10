// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// What the disk of a folder can still take, and what macOS calls that disk.
nonisolated struct DiskSpaceInfo: Equatable, Sendable {
    var availableBytes: Int64
    var volumeName: String
}

/// Reads the free space of the disk a folder is on. One call asks the system
/// once; nothing here walks the folder.
nonisolated protocol DiskSpaceReading: Sendable {
    /// `nil` when the folder cannot be reached: a disk unplugged, a folder
    /// removed.
    func diskSpace(atPath path: String) async -> DiskSpaceInfo?
}

nonisolated struct SystemDiskSpaceReader: DiskSpaceReading {
    func diskSpace(atPath path: String) async -> DiskSpaceInfo? {
        await Task.detached(priority: .utility) {
            Self.read(atPath: path)
        }.value
    }

    private static func read(atPath path: String) -> DiskSpaceInfo? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeLocalizedNameKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let plainCapacity = values.volumeAvailableCapacity else {
            return nil
        }

        // Free space as Finder counts it, with what macOS clears by itself
        // when room is needed: the number a person checks the warning
        // against. A disk that does not report it gives its plain free space.
        let importantCapacity = values.volumeAvailableCapacityForImportantUsage ?? 0
        return DiskSpaceInfo(
            availableBytes: importantCapacity > 0 ? importantCapacity : Int64(plainCapacity),
            volumeName: values.volumeLocalizedName ?? ""
        )
    }
}
