import Foundation

struct ConversionHistoryEntry: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let outputURL: URL
    let format: ConversionFormat
    let date: Date
}

struct ConversionHistoryStore {
    private let defaults: UserDefaults
    private let key = "just4convert.history"
    private let maxEntries = 24

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [ConversionHistoryEntry] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([ConversionHistoryEntry].self, from: data)) ?? []
    }

    func save(_ entries: [ConversionHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    func append(entry: ConversionHistoryEntry) {
        var entries = load()
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save(entries)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
