import Foundation

nonisolated enum AddTorrentReviewState: Equatable, Sendable {
    case loadingMetadata
    case ready
    case invalid(message: String)
}

nonisolated struct AddTorrentFileOption: Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var sizeBytes: Int64
    var fileIndex: Int
    var isSelected: Bool
}

nonisolated enum AddTorrentTreeSelectionState: Equatable, Sendable {
    case selected
    case unselected
    case mixed
}

/// A tree node in the add flow.
/// Represents nested folders and lets users select entire branches,
/// such as "Season 3", instead of only individual files.
nonisolated struct AddTorrentFileTreeNode: Identifiable, Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case folder(path: String)
        case file(id: UUID, path: String)
    }

    var id: String { path }
    var path: String
    var name: String
    var kind: Kind
    var sizeBytes: Int64
    var selectionState: AddTorrentTreeSelectionState
    var fileCount: Int
    var selectedFileCount: Int
    var children: [AddTorrentFileTreeNode]?

    var isFolder: Bool {
        switch kind {
        case .folder:
            true
        case .file:
            false
        }
    }

    var fileID: UUID? {
        switch kind {
        case let .file(id, _):
            id
        case .folder:
            nil
        }
    }
}

/// Prevents the add flow from modifying torrent runtime state before confirmation.
nonisolated struct AddTorrentDraft: Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var source: AddTorrentSource
    var originalName: String
    var infoHash: String?
    var suggestedSavePath: String
    var savePathBookmarkData: Data? = nil
    var alias: String
    var stopAfterDownload: Bool
    var files: [AddTorrentFileOption]
    var reviewState: AddTorrentReviewState
    var errorState: TorrentErrorState?

    nonisolated var selectedBytes: Int64 {
        files.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    nonisolated var selectedFileCount: Int {
        files.reduce(0) { $0 + ($1.isSelected ? 1 : 0) }
    }

    nonisolated var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.sizeBytes }
    }

    /// File indices support session restoration and re-registering the torrent with the engine.
    nonisolated var selectedFileIndices: [Int] {
        files.compactMap { $0.isSelected ? $0.fileIndex : nil }
    }

    /// A download can be confirmed only when at least one file is selected.
    nonisolated var hasSelectedFiles: Bool {
        !selectedFileIndices.isEmpty
    }

    nonisolated var canConfirmDownload: Bool {
        reviewState == .ready && hasSelectedFiles
    }

    nonisolated var fileTree: [AddTorrentFileTreeNode] {
        final class MutableTreeNode {
            let name: String
            let path: String
            var sizeBytes: Int64 = 0
            var fileID: UUID?
            var isSelected = false
            var children: [String: MutableTreeNode] = [:]

            init(name: String, path: String) {
                self.name = name
                self.path = path
            }

            var isFolder: Bool {
                fileID == nil
            }
        }

        let root = MutableTreeNode(name: "", path: "")

        for file in files {
            let normalizedPath = file.name.replacingOccurrences(of: "\\", with: "/")
            let rawComponents = normalizedPath
                .split(separator: "/")
                .map(String.init)
                .filter { !$0.isEmpty }

            let pathComponents = rawComponents.isEmpty ? [file.name] : rawComponents

            var currentNode = root
            var currentPath: [String] = []

            for (componentIndex, component) in pathComponents.enumerated() {
                currentPath.append(component)
                let joinedPath = currentPath.joined(separator: "/")

                let childNode: MutableTreeNode
                if let existingNode = currentNode.children[joinedPath] {
                    childNode = existingNode
                } else {
                    let newNode = MutableTreeNode(name: component, path: joinedPath)
                    currentNode.children[joinedPath] = newNode
                    childNode = newNode
                }

                if componentIndex == pathComponents.count - 1 {
                    childNode.fileID = file.id
                    childNode.isSelected = file.isSelected
                    childNode.sizeBytes = file.sizeBytes
                }

                currentNode = childNode
            }
        }

        func sortNodes(lhs: MutableTreeNode, rhs: MutableTreeNode) -> Bool {
            if lhs.isFolder != rhs.isFolder {
                return lhs.isFolder && !rhs.isFolder
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        func buildNode(from mutableNode: MutableTreeNode) -> AddTorrentFileTreeNode {
            let builtChildren = mutableNode.children.values
                .sorted(by: sortNodes)
                .map(buildNode)

            if let fileID = mutableNode.fileID {
                return AddTorrentFileTreeNode(
                    path: mutableNode.path,
                    name: mutableNode.name,
                    kind: .file(id: fileID, path: mutableNode.path),
                    sizeBytes: mutableNode.sizeBytes,
                    selectionState: mutableNode.isSelected ? .selected : .unselected,
                    fileCount: 1,
                    selectedFileCount: mutableNode.isSelected ? 1 : 0,
                    children: nil
                )
            }

            let childStates = builtChildren.map(\.selectionState)
            let selectionState: AddTorrentTreeSelectionState
            if childStates.allSatisfy({ $0 == .selected }) {
                selectionState = .selected
            } else if childStates.allSatisfy({ $0 == .unselected }) {
                selectionState = .unselected
            } else {
                selectionState = .mixed
            }

            return AddTorrentFileTreeNode(
                path: mutableNode.path,
                name: mutableNode.name,
                kind: .folder(path: mutableNode.path),
                sizeBytes: builtChildren.reduce(0) { $0 + $1.sizeBytes },
                selectionState: selectionState,
                fileCount: builtChildren.reduce(0) { $0 + $1.fileCount },
                selectedFileCount: builtChildren.reduce(0) { $0 + $1.selectedFileCount },
                children: builtChildren
            )
        }

        return root.children.values
            .sorted(by: sortNodes)
            .map(buildNode)
    }
}
