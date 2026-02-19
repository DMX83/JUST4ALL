import Foundation

public struct FavoriteLocationStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "j4f.favoriteLocations") {
        self.defaults = defaults
        self.key = key
    }

    public func list() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    public func add(path: String) {
        var paths = list()
        if paths.contains(path) { return }
        paths.insert(path, at: 0)
        defaults.set(paths, forKey: key)
    }

    public func remove(path: String) {
        let updated = list().filter { $0 != path }
        defaults.set(updated, forKey: key)
    }
}
