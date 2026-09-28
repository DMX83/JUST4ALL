import Foundation

/// v1.2 — Cálculo de tamaños de carpeta en background para el commander.
///
/// Single-flight por ruta + caché LRU + invalidación selectiva: la UI pide el tamaño al
/// pintar la fila y recibe el valor cuando está listo (sin bloquear el listado).
public actor FolderSizeCalculator {
    public static let shared = FolderSizeCalculator()

    private var cache: [String: Int64] = [:]
    private var order: [String] = []
    private var inFlight: [String: Task<Int64, Never>] = [:]
    private let capacity = 4096

    public init() {}

    /// Tamaño ya calculado (nil si no está en caché).
    public func cachedSize(of path: String) -> Int64? {
        cache[path]
    }

    /// Suma de `fileSize` del subárbol completo. Cachea el resultado.
    public func size(of url: URL, includeHidden: Bool) async -> Int64 {
        let path = url.standardizedFileURL.path
        if let hit = cache[path] { return hit }
        if let task = inFlight[path] { return await task.value }
        let task = Task.detached(priority: .utility) {
            Self.compute(path: path, includeHidden: includeHidden)
        }
        inFlight[path] = task
        let value = await task.value
        inFlight[path] = nil
        store(value, for: path)
        return value
    }

    /// Invalida una ruta y sus ancestros cacheados (un cambio dentro altera los totales).
    public func invalidate(path: String) {
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        let keys = cache.keys.filter { key in
            key == std || std.hasPrefix(key + "/")
        }
        guard !keys.isEmpty else { return }
        let removed = Set(keys)
        for key in removed {
            cache.removeValue(forKey: key)
        }
        order.removeAll { removed.contains($0) }
    }

    private func store(_ value: Int64, for path: String) {
        cache[path] = value
        order.append(path)
        while order.count > capacity, let first = order.first {
            order.removeFirst()
            cache.removeValue(forKey: first)
        }
    }

    /// Recorrido cooperativo (cancelable) que suma el tamaño de los ficheros regulares.
    nonisolated static func compute(path: String, includeHidden: Bool) -> Int64 {
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: options
        ) else { return 0 }

        var total: Int64 = 0
        var processed = 0
        for case let item as URL in enumerator {
            processed += 1
            if processed % 512 == 0, Task.isCancelled { break }
            guard let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
