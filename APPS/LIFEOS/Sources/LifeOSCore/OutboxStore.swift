import Foundation

/// Una captura que no llegó al servidor y espera su momento.
///
/// El `id` es la clave de idempotencia que se enviará en la cabecera
/// `Idempotency-Key`, así que reintentar no duplica nada aunque la primera
/// petición sí haya llegado y se perdiera la respuesta.
public struct OutboxItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let content: String
    public let sensitivity: String
    public let createdAt: Date
    public var attempts: Int
    public var lastError: String?

    public init(
        id: String = UUID().uuidString,
        content: String,
        sensitivity: String,
        createdAt: Date = Date(),
        attempts: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.content = content
        self.sensitivity = sensitivity
        self.createdAt = createdAt
        self.attempts = attempts
        self.lastError = lastError
    }
}

/// Cola de capturas pendientes de enviar, en disco.
///
/// Existe porque el caso real es capturar fuera de casa, o con el servidor
/// apagado: la idea no se pierde, se guarda y sale sola al volver la conexión.
public actor OutboxStore {
    private let fileURL: URL
    private var items: [OutboxItem] = []
    private var loaded = false

    /// - Parameter fileURL: ruta del fichero; por defecto
    ///   `~/Library/Application Support/LIFEOS/outbox.json`.
    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("LIFEOS", isDirectory: true)
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("LIFEOS", isDirectory: true)
            self.fileURL = base.appendingPathComponent("outbox.json")
        }
    }

    public func pending() -> [OutboxItem] {
        loadIfNeeded()
        return items
    }

    public func count() -> Int {
        loadIfNeeded()
        return items.count
    }

    @discardableResult
    public func enqueue(content: String, sensitivity: String) -> OutboxItem {
        loadIfNeeded()
        let item = OutboxItem(content: content, sensitivity: sensitivity)
        items.append(item)
        persist()
        return item
    }

    public func markAttempt(id: String, error: String?) {
        loadIfNeeded()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].attempts += 1
        items[index].lastError = error
        persist()
    }

    public func remove(id: String) {
        loadIfNeeded()
        items.removeAll { $0.id == id }
        persist()
    }

    public func removeAll() {
        loadIfNeeded()
        items.removeAll()
        persist()
    }

    // MARK: - Disco

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        // Tiene que ser el mismo formato con el que se escribe: fechas ISO-8601.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([OutboxItem].self, from: data) else {
            // Un fichero ilegible no puede impedir capturar: se empieza de cero.
            items = []
            return
        }
        items = decoded
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Sin disco no hay cola persistente, pero la captura sigue en memoria.
        }
    }
}
