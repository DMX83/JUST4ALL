import Foundation
import os

/// v2.3.11 — caché EN DISCO de tamaños de carpeta (tamaño **asignado en disco**).
///
/// Por qué existe: medido antes de escribir esto, recorrer un árbol grande cuesta lo mismo que
/// `du` — `~/Library` (419.476 ficheros) tarda **19 s** con `FileManager.enumerator` y **14,4 s**
/// con `du -sh`, que es el óptimo del sistema. Es decir, el recorrido no tiene margen de mejora:
/// lo único que ahorra recursos de verdad es **no repetirlo**. Con esta caché, los tamaños ya
/// calculados se muestran al instante en el siguiente arranque (y en cuanto se vuelve a la
/// carpeta) en lugar de provocar otro pico de CPU/disco.
///
/// Semántica: el valor caduca a las `ttl` horas (por defecto 6) y, además, el watcher de
/// JUST4FOLDERS refresca en segundo plano las carpetas que cambian (ver
/// `FolderSizeCalculator.refreshSize`), así que la caché no se queda obsoleta en lo que importa.
public final class FolderSizeCacheStore {

    public struct Entry: Codable {
        public let bytes: Int64
        public let timestamp: TimeInterval
    }

    public static let shared = FolderSizeCacheStore()

    private let ttl: TimeInterval
    private let capacity: Int
    private let fileURL: URL
    private let logger = Logger(subsystem: "com.dmx83.just4folders", category: "folder-size-cache")

    private var entries: [String: Entry] = [:]
    private let lock = NSLock()
    private var saveWorkItem: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "com.dmx83.just4folders.folder-size-cache.save")

    public init(
        ttl: TimeInterval = 6 * 3600,
        capacity: Int = 4000,
        fileURL: URL? = nil
    ) {
        self.ttl = max(60, ttl)
        self.capacity = max(16, capacity)
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("JUST4FOLDERS", isDirectory: true)
            .appendingPathComponent("folder-sizes.json")
    }

    /// Valor cacheado y todavía fresco (nil si no está o caducó).
    public func value(for path: String) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path] else { return nil }
        guard Date().timeIntervalSince1970 - entry.timestamp <= ttl else {
            entries.removeValue(forKey: path)
            return nil
        }
        return entry.bytes
    }

    public func store(_ bytes: Int64, for path: String) {
        lock.lock()
        entries[path] = Entry(bytes: bytes, timestamp: Date().timeIntervalSince1970)
        if entries.count > capacity {
            // Poda simple: fuera las entradas más antiguas.
            let sorted = entries.sorted { $0.value.timestamp < $1.value.timestamp }
            for (key, _) in sorted.prefix(entries.count - capacity) {
                entries.removeValue(forKey: key)
            }
        }
        lock.unlock()
        scheduleSave()
    }

    public func remove(_ path: String) {
        lock.lock()
        let removed = entries.removeValue(forKey: path) != nil
        lock.unlock()
        if removed { scheduleSave() }
    }

    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        scheduleSave()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    // MARK: - Persistencia

    private func scheduleSave() {
        lock.lock()
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = work
        lock.unlock()
        saveQueue.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    /// Guarda ya (tests / cierre ordenado).
    public func flush() {
        saveQueue.sync { [weak self] in
            self?.save()
        }
    }

    private func save() {
        lock.lock()
        let snapshot = entries
        lock.unlock()
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.debug("No se pudo guardar la caché de tamaños: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        lock.lock()
        entries = decoded
        lock.unlock()
    }
}
