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
    /// v2.3.11 — caché en disco (entre arranques). Ver `FolderSizeCacheStore`.
    private let cacheStore: FolderSizeCacheStore?

    /// v2.3.10 — tope de cálculos simultáneos. Sin él, un panel en `~` lanza una decena de
    /// escaneos profundos a la vez (incluidos `Library`/`Movies`…): la CPU se dispara y una
    /// carpeta grande puede tardar minutos en aparecer. En cola FIFO, las pequeñas pasan en
    /// milisegundos y las grandes terminan pronto.
    ///
    /// Nota de prioridad: se usa `.userInitiated` a propósito. Con `.utility` el sistema estrangula
    /// el I/O (sobre todo a batería) y `~/Library` (418k ficheros) tardaba más de 2 minutos con la
    /// CPU al 80 %, mientras el mismo recorrido en primer plano tarda ~20 s. El usuario ha pedido
    /// explícitamente los tamaños, así que el coste es aceptable (acotado por el tope de abajo).
    private var activeComputations = 0
    private var slotWaiters: [CheckedContinuation<Void, Never>] = []
    private let maxConcurrentComputations = 3

    public init(cacheStore: FolderSizeCacheStore? = FolderSizeCacheStore.shared) {
        self.cacheStore = cacheStore
    }

    /// Tamaño ya calculado (nil si no está en caché).
    public func cachedSize(of path: String) -> Int64? {
        cache[path]
    }

    /// Suma de `fileSize` del subárbol completo. Cachea el resultado.
    public func size(of url: URL, includeHidden: Bool) async -> Int64 {
        let path = url.standardizedFileURL.path
        if let hit = cache[path] { return hit }
        if let task = inFlight[path] { return await task.value }
        // v2.3.11 — caché en disco: evita repetir un recorrido caro entre arranques (medido:
        // `~/Library` = 419k ficheros ⇒ 19 s de recorrido; `du` tarda 14,4 s, o sea que el walk
        // ya está en el óptimo del sistema y lo único que ahorra recursos es NO repetirlo).
        if let cached = cacheStore?.value(for: path) {
            store(cached, for: path)
            return cached
        }
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.waitForSlot()
            let value = Self.compute(path: path, includeHidden: includeHidden)
            await self?.releaseSlot()
            return value
        }
        inFlight[path] = task
        let value = await task.value
        inFlight[path] = nil
        store(value, for: path)
        cacheStore?.store(value, for: path)
        return value
    }

    /// v2.3.10 — puerta de concurrencia (FIFO) para los cálculos.
    private func waitForSlot() async {
        if activeComputations < maxConcurrentComputations {
            activeComputations += 1
            return
        }
        await withCheckedContinuation { continuation in
            slotWaiters.append(continuation)
        }
        activeComputations += 1
    }

    private func releaseSlot() {
        activeComputations = max(0, activeComputations - 1)
        guard !slotWaiters.isEmpty else { return }
        let next = slotWaiters.removeFirst()
        next.resume()
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
            cacheStore?.remove(key)
        }
        order.removeAll { removed.contains($0) }
    }

    /// v2.3.11 — invalida y recalcula en la misma operación (refresco tras cambios en disco, sin
    /// que el valor desaparezca de la interfaz mientras tanto).
    public func refreshSize(of url: URL, includeHidden: Bool) async -> Int64 {
        invalidate(path: url.standardizedFileURL.path)
        return await size(of: url, includeHidden: includeHidden)
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
    ///
    /// v2.3.10 — se suma el tamaño **ASIGNADO EN DISCO** (`totalFileAllocatedSize`), no el lógico:
    /// un fichero disperso (caso real: `~/Library/Containers/com.docker.docker/…/Docker.raw`,
    /// 995 GB lógicos y 71 GB reales) inflaba el total hasta hacerlo imposible — se llegó a mostrar
    /// **1,06 TB** en `~/Library` de un Mac con disco de 995 GB, cuando `du` dice **127 GB**.
    /// Así el número cuadra con `du` / «Acerca de este Mac» y con el espacio realmente ocupado.
    /// Fallbacks: `fileAllocatedSize` y, si el volumen no lo informa (p. ej. red), `fileSize`.
    nonisolated static func compute(path: String, includeHidden: Bool) -> Int64 {
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: options
        ) else { return 0 }

        var total: Int64 = 0
        var processed = 0
        for case let item as URL in enumerator {
            processed += 1
            if processed % 512 == 0, Task.isCancelled { break }
            guard let values = try? item.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
            total += Int64(allocated)
        }
        return total
    }
}
