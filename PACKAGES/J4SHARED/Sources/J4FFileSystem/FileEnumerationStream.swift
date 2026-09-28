import Foundation

public struct EnumeratedNode: Hashable {
    public let url: URL
    public let isDirectory: Bool
    public let sizeBytes: Int64

    public init(url: URL, isDirectory: Bool, sizeBytes: Int64) {
        self.url = url
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
    }
}

public enum FileEnumerationStream {
    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .isHiddenKey]

    public static func stream(
        roots: [URL],
        includeHidden: Bool = false,
        onNode: (EnumeratedNode) throws -> Void
    ) throws {
        for root in roots {
            try streamOne(root: root, includeHidden: includeHidden, onNode: onNode)
        }
    }

    private static func streamOne(
        root: URL,
        includeHidden: Bool,
        onNode: (EnumeratedNode) throws -> Void
    ) throws {
        let rootValues = try root.resourceValues(forKeys: keys)
        let rootIsDir = rootValues.isDirectory == true
        if rootIsDir {
            try onNode(EnumeratedNode(url: root, isDirectory: true, sizeBytes: 0))
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants]
            ) else {
                return
            }

            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: keys)
                if !includeHidden, values.isHidden == true {
                    if values.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                if values.isDirectory == true {
                    try onNode(EnumeratedNode(url: url, isDirectory: true, sizeBytes: 0))
                } else if values.isRegularFile == true {
                    try onNode(EnumeratedNode(url: url, isDirectory: false, sizeBytes: Int64(values.fileSize ?? 0)))
                }
            }
            return
        }

        if rootValues.isRegularFile == true {
            try onNode(EnumeratedNode(url: root, isDirectory: false, sizeBytes: Int64(rootValues.fileSize ?? 0)))
        }
    }
}
