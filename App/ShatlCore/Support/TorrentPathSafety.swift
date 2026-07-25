// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

nonisolated enum TorrentPathSafety {
    static func normalizedRelativePath(_ path: String) -> String? {
        let normalizedSeparators = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalizedSeparators.hasPrefix("/") else { return nil }

        let components = normalizedSeparators
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard !components.isEmpty else { return nil }
        guard components.allSatisfy({ $0 != "." && $0 != ".." }) else { return nil }

        return components.joined(separator: "/")
    }

    static func normalizedRelativePaths(_ paths: [String]) -> [String] {
        paths.compactMap(normalizedRelativePath)
    }
}
