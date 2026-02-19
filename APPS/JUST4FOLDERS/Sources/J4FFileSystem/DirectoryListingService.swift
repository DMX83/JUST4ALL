import Foundation

public struct DirectoryEntry: Hashable {
    public let url: URL
    public let isDirectory: Bool
    public let fileSize: Int64?
    public let modifiedDate: Date?
    public let isHidden: Bool
    public let localizedTypeDescription: String?

    public init(
        url: URL,
        isDirectory: Bool,
        fileSize: Int64?,
        modifiedDate: Date?,
        isHidden: Bool,
        localizedTypeDescription: String?
    ) {
        self.url = url
        self.isDirectory = isDirectory
        self.fileSize = fileSize
        self.modifiedDate = modifiedDate
        self.isHidden = isHidden
        self.localizedTypeDescription = localizedTypeDescription
    }
}

public struct URLMetadataSnapshot: Hashable {
    public let isDirectory: Bool
    public let fileSize: Int64?
    public let modifiedDate: Date?
    public let isHidden: Bool
    public let localizedTypeDescription: String?

    public init(
        isDirectory: Bool,
        fileSize: Int64?,
        modifiedDate: Date?,
        isHidden: Bool,
        localizedTypeDescription: String?
    ) {
        self.isDirectory = isDirectory
        self.fileSize = fileSize
        self.modifiedDate = modifiedDate
        self.isHidden = isHidden
        self.localizedTypeDescription = localizedTypeDescription
    }
}

public final class URLMetadataLRUCache {
    private let capacity: Int
    private var clock: UInt64 = 0
    private var storage: [String: (snapshot: URLMetadataSnapshot, accessedAt: UInt64)] = [:]
    private let lock = NSLock()

    public init(capacity: Int) {
        self.capacity = max(256, capacity)
    }

    public func value(forPath path: String) -> URLMetadataSnapshot? {
        lock.lock()
        defer { lock.unlock() }

        guard var entry = storage[path] else {
            return nil
        }
        clock &+= 1
        entry.accessedAt = clock
        storage[path] = entry
        return entry.snapshot
    }

    public func set(_ snapshot: URLMetadataSnapshot, forPath path: String) {
        lock.lock()
        defer { lock.unlock() }

        clock &+= 1
        storage[path] = (snapshot, clock)
        pruneIfNeeded()
    }

    private func pruneIfNeeded() {
        guard storage.count > capacity else { return }
        let overflow = storage.count - capacity
        for _ in 0..<overflow {
            guard let oldest = storage.min(by: { $0.value.accessedAt < $1.value.accessedAt })?.key else {
                return
            }
            storage.removeValue(forKey: oldest)
        }
    }
}

public enum DirectoryListingService {
    private static let typeDescriptionCache = UTTypeDescriptionCache(capacity: 2048)
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .isHiddenKey,
        .localizedTypeDescriptionKey
    ]

    @discardableResult
    public static func listIncremental(
        folder: URL,
        includeHidden: Bool = false,
        batchSize: Int = 256,
        metadataCache: URLMetadataLRUCache?,
        onBatch: @escaping ([DirectoryEntry]) -> Void
    ) throws -> Int {
        let effectiveBatch = max(32, batchSize)
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants, .skipsSubdirectoryDescendants]
        ) else {
            return 0
        }

        var total = 0
        var batch: [DirectoryEntry] = []
        batch.reserveCapacity(effectiveBatch)

        for case let url as URL in enumerator {
            try Task.checkCancellation()

            if let entry = makeEntry(url: url, includeHidden: includeHidden, metadataCache: metadataCache) {
                batch.append(entry)
                total += 1
            }

            if batch.count >= effectiveBatch {
                onBatch(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }

        if !batch.isEmpty {
            onBatch(batch)
        }

        return total
    }

    private static func makeEntry(
        url: URL,
        includeHidden: Bool,
        metadataCache: URLMetadataLRUCache?
    ) -> DirectoryEntry? {
        let path = url.standardizedFileURL.path
        let metadata = resolveMetadata(url: url, path: path, cache: metadataCache)

        if !includeHidden, metadata.isHidden {
            return nil
        }

        return DirectoryEntry(
            url: url,
            isDirectory: metadata.isDirectory,
            fileSize: metadata.fileSize,
            modifiedDate: metadata.modifiedDate,
            isHidden: metadata.isHidden,
            localizedTypeDescription: metadata.localizedTypeDescription
        )
    }

    private static func resolveMetadata(
        url: URL,
        path: String,
        cache: URLMetadataLRUCache?
    ) -> URLMetadataSnapshot {
        if let cached = cache?.value(forPath: path) {
            return cached
        }

        let values = try? url.resourceValues(forKeys: resourceKeys)
        let snapshot = URLMetadataSnapshot(
            isDirectory: values?.isDirectory == true,
            fileSize: values?.fileSize.map(Int64.init),
            modifiedDate: values?.contentModificationDate,
            isHidden: values?.isHidden == true,
            localizedTypeDescription: resolvedTypeDescription(
                explicit: values?.localizedTypeDescription,
                url: url,
                isDirectory: values?.isDirectory == true
            )
        )
        cache?.set(snapshot, forPath: path)
        return snapshot
    }

    private static func resolvedTypeDescription(explicit: String?, url: URL, isDirectory: Bool) -> String? {
        if let explicit, !explicit.isEmpty { return explicit }
        if isDirectory { return "Folder" }
        let ext = url.pathExtension
        return typeDescriptionCache.description(forFileExtension: ext)
    }
}
