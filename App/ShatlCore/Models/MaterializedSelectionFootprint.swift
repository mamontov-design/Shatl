// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// A compact snapshot of selected files already materialized on disk.
/// Stored as a bit set:
/// - 1 means the selected file has existed on disk;
/// - 0 means the file has not been materialized yet.
///
/// Bit order matches `selectedFileIndices` in `TorrentRecord`.
nonisolated struct MaterializedSelectionFootprint: Equatable, Codable, Sendable {
    var selectedFileCount: Int
    var bitsetData: Data

    init(selectedFileCount: Int, bitsetData: Data) {
        self.selectedFileCount = selectedFileCount

        let expectedByteCount = Self.byteCount(for: selectedFileCount)
        if bitsetData.count == expectedByteCount {
            self.bitsetData = bitsetData
        } else if bitsetData.count > expectedByteCount {
            self.bitsetData = Data(bitsetData.prefix(expectedByteCount))
        } else {
            var normalized = bitsetData
            normalized.append(Data(repeating: 0, count: expectedByteCount - bitsetData.count))
            self.bitsetData = normalized
        }
    }

    init(selectedFileCount: Int, materializedOrdinals: Set<Int>) {
        self.init(
            selectedFileCount: selectedFileCount,
            bitsetData: Self.makeBitsetData(
                selectedFileCount: selectedFileCount,
                materializedOrdinals: materializedOrdinals
            )
        )
    }

    static func empty(selectedFileCount: Int) -> MaterializedSelectionFootprint {
        MaterializedSelectionFootprint(
            selectedFileCount: selectedFileCount,
            bitsetData: Data(repeating: 0, count: byteCount(for: selectedFileCount))
        )
    }

    var materializedOrdinals: Set<Int> {
        guard selectedFileCount > 0 else { return [] }

        var ordinals: Set<Int> = []
        for ordinal in 0..<selectedFileCount where containsOrdinal(ordinal) {
            ordinals.insert(ordinal)
        }
        return ordinals
    }

    var isEmpty: Bool {
        materializedOrdinals.isEmpty
    }

    func containsOrdinal(_ ordinal: Int) -> Bool {
        guard ordinal >= 0, ordinal < selectedFileCount else { return false }

        let byteIndex = ordinal / 8
        let bitOffset = ordinal % 8
        guard byteIndex < bitsetData.count else { return false }

        let byte = bitsetData[byteIndex]
        return (byte & (1 << bitOffset)) != 0
    }

    func union(_ other: MaterializedSelectionFootprint) -> MaterializedSelectionFootprint {
        let maxSelectedFileCount = max(selectedFileCount, other.selectedFileCount)
        let expectedByteCount = Self.byteCount(for: maxSelectedFileCount)
        var merged = Data(repeating: 0, count: expectedByteCount)

        for byteIndex in 0..<expectedByteCount {
            let lhs = byteIndex < bitsetData.count ? bitsetData[byteIndex] : 0
            let rhs = byteIndex < other.bitsetData.count ? other.bitsetData[byteIndex] : 0
            merged[byteIndex] = lhs | rhs
        }

        return MaterializedSelectionFootprint(
            selectedFileCount: maxSelectedFileCount,
            bitsetData: merged
        )
    }

    func missingOrdinals(comparedTo current: MaterializedSelectionFootprint) -> Set<Int> {
        materializedOrdinals.subtracting(current.materializedOrdinals)
    }

    private static func makeBitsetData(
        selectedFileCount: Int,
        materializedOrdinals: Set<Int>
    ) -> Data {
        var data = Data(repeating: 0, count: byteCount(for: selectedFileCount))

        for ordinal in materializedOrdinals where ordinal >= 0 && ordinal < selectedFileCount {
            let byteIndex = ordinal / 8
            let bitOffset = ordinal % 8
            data[byteIndex] |= (1 << bitOffset)
        }

        return data
    }

    private static func byteCount(for selectedFileCount: Int) -> Int {
        guard selectedFileCount > 0 else { return 0 }
        return (selectedFileCount + 7) / 8
    }
}
