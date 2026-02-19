import Foundation

public struct BookmarkedLocation: Codable, Hashable, Identifiable {
    public let id: UUID
    public let path: String
    public let createdAt: Date
    public let bookmarkData: Data

    public init(id: UUID = UUID(), path: String, createdAt: Date = Date(), bookmarkData: Data) {
        self.id = id
        self.path = path
        self.createdAt = createdAt
        self.bookmarkData = bookmarkData
    }
}

public struct BookmarkResolutionReport {
    public let resolvedURLs: [URL]
    public let refreshedCount: Int
    public let failedLocations: [BookmarkedLocation]

    public init(resolvedURLs: [URL], refreshedCount: Int, failedLocations: [BookmarkedLocation]) {
        self.resolvedURLs = resolvedURLs
        self.refreshedCount = refreshedCount
        self.failedLocations = failedLocations
    }
}

public struct SecurityScopedBookmarkStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "j4f.securityScopedBookmarks") {
        self.defaults = defaults
        self.key = key
    }

    public func list() -> [BookmarkedLocation] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([BookmarkedLocation].self, from: data)) ?? []
    }

    public func save(url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        var current = list()
        if current.contains(where: { $0.path == url.path }) {
            return
        }

        current.insert(BookmarkedLocation(path: url.path, bookmarkData: bookmark), at: 0)
        try persist(current)
    }

    public func replace(path oldPath: String, with url: URL) throws {
        let newBookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        var current = list()
        current.removeAll { $0.path == oldPath || $0.path == url.path }
        current.insert(BookmarkedLocation(path: url.path, bookmarkData: newBookmark), at: 0)
        try persist(current)
    }

    public func resolveAll() -> [URL] {
        resolveReport().resolvedURLs
    }

    public func resolveReport() -> BookmarkResolutionReport {
        let bookmarks = list()
        var resolvedURLs: [URL] = []
        var refreshedCount = 0
        var updated: [BookmarkedLocation] = []
        var failed: [BookmarkedLocation] = []

        for location in bookmarks {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: location.bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    let freshData = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                    updated.append(BookmarkedLocation(id: location.id, path: url.path, createdAt: location.createdAt, bookmarkData: freshData))
                    refreshedCount += 1
                } else {
                    updated.append(location)
                }

                resolvedURLs.append(url)
            } catch {
                failed.append(location)
            }
        }

        if refreshedCount > 0 || failed.count > 0 {
            try? persist(updated)
        }

        return BookmarkResolutionReport(
            resolvedURLs: resolvedURLs,
            refreshedCount: refreshedCount,
            failedLocations: failed
        )
    }

    private func persist(_ entries: [BookmarkedLocation]) throws {
        let encoded = try JSONEncoder().encode(entries)
        defaults.set(encoded, forKey: key)
    }
}
