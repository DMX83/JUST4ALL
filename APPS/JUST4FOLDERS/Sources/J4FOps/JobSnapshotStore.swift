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

    private func loadAllUnsafe() -> [String: JobSnapshot] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [:] }
        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode([String: JobSnapshot].self, from: data) else { return [:] }
        return decoded
    }

    private func persistUnsafe(_ map: [String: JobSnapshot]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(map) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
