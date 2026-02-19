import Foundation

public struct RecentLocationStore {
    private let defaults: UserDefaults
    private let key: String
    private let limit: Int

    public init(defaults: UserDefaults = .standard, key: String = "j4f.recentLocations", limit: Int = 30) {
        self.defaults = defaults
        self.key = key
        self.limit = max(1, limit)
    }

    public func list() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    public func add(path: String) {
        let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var paths = list().filter { $0 != clean }
        paths.insert(clean, at: 0)
        if paths.count > limit {
            paths = Array(paths.prefix(limit))
        }
        defaults.set(paths, forKey: key)
    }

    public func remove(path: String) {
        let updated = list().filter { $0 != path }
        defaults.set(updated, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
