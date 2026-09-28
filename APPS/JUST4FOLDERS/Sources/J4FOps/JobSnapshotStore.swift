import Foundation

public final class JobSnapshotStore {
    private let fileURL: URL
    private let lock = NSLock()
    public var storageURL: URL { fileURL }

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("JUST4FOLDERS", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("job-snapshots.json")
    }

    public func save(_ snapshot: JobSnapshot) {
        lock.lock()
        defer { lock.unlock() }

        var all = loadAllUnsafe()
        all[snapshot.id.uuidString] = snapshot
        all = Self.pruningTerminal(all)
        persistUnsafe(all)
    }

    public func remove(jobId: UUID) {
        lock.lock()
        defer { lock.unlock() }

        var all = loadAllUnsafe()
        all.removeValue(forKey: jobId.uuidString)
        persistUnsafe(all)
    }

    public func loadAll() -> [JobSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return Array(loadAllUnsafe().values)
    }

    // MARK: - Diario de items (v1.1 — reanudación tras caída)

    /// Fichero con la lista de `JobItem` del trabajo (se escribe una vez al encolar).
    private func itemsURL(for jobId: UUID) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("job-\(jobId.uuidString)-items.json", isDirectory: false)
    }

    public func saveItems(_ items: [JobItem], jobId: UUID) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: itemsURL(for: jobId), options: .atomic)
    }

    public func loadItems(jobId: UUID) -> [JobItem]? {
        guard let data = try? Data(contentsOf: itemsURL(for: jobId)), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([JobItem].self, from: data)
    }

    public func hasItems(jobId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: itemsURL(for: jobId).path)
    }

    public func removeItems(jobId: UUID) {
        try? FileManager.default.removeItem(at: itemsURL(for: jobId))
    }

    private func loadAllUnsafe() -> [String: JobSnapshot] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [:] }
        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode([String: JobSnapshot].self, from: data) else { return [:] }
        return decoded
    }

    /// Historial acotado: se guardan todos los snapshots activos y solo los N terminales más
    /// recientes. Sin esto, el fichero crece sin límite y cada `emit` de progreso reescribe el
    /// JSON entero (hallazgo 28-sep: 280 entradas acumuladas).
    static let maxTerminalSnapshots = 50

    private static func pruningTerminal(_ map: [String: JobSnapshot]) -> [String: JobSnapshot] {
        let terminalKeys = map.keys.filter { key in
            guard let snapshot = map[key] else { return false }
            switch snapshot.state {
            case .done, .cancelled, .failed: return true
            default: return false
            }
        }
        guard terminalKeys.count > maxTerminalSnapshots else { return map }
        let sorted = terminalKeys.sorted { lhs, rhs in
            let l = map[lhs].flatMap { $0.finishedAt ?? $0.startedAt } ?? .distantPast
            let r = map[rhs].flatMap { $0.finishedAt ?? $0.startedAt } ?? .distantPast
            return l > r
        }
        var pruned = map
        for key in sorted.dropFirst(maxTerminalSnapshots) {
            pruned.removeValue(forKey: key)
        }
        return pruned
    }

    private func persistUnsafe(_ map: [String: JobSnapshot]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(map) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
