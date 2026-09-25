import Foundation

/// G5 — Colección guardada («espacio»): una búsqueda con nombre que organiza **sin mover nada**.
///
/// Las colecciones no tocan los ficheros: son consultas persistentes sobre el índice
/// («Trading», «Fiscal 2026»…) que se abren con un clic desde «Inicio» o el omnibox.
public struct SavedCollection: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var query: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        query: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Persistencia local de las colecciones (`~/Library/Application Support/JUST4DESK/collections.json`).
///
/// Formato versionado y tolerante: un archivo ilegible se ignora (con traza) en vez de romper la app.
public final class CollectionStore: @unchecked Sendable {
    public static let shared = CollectionStore()
    public static let maxNameLength = 60
    public static let maxQueryLength = 200

    private struct Payload: Codable {
        var version: Int
        var collections: [SavedCollection]
    }

    private let fileURL: URL
    private let lock = NSLock()
    private var collections: [SavedCollection]

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.collections = Self.load(from: self.fileURL)
    }

    // MARK: - API

    /// Todas las colecciones en orden de creación.
    public func all() -> [SavedCollection] {
        lock.lock()
        defer { lock.unlock() }
        return collections
    }

    /// Añade una colección (nombre y consulta saneados: sin espacios sobrantes, con tope de largo).
    /// Devuelve `nil` si el nombre o la consulta quedan vacíos.
    @discardableResult
    public func add(name: String, query: String) -> SavedCollection? {
        guard let cleanName = Self.clean(name, max: Self.maxNameLength),
              let cleanQuery = Self.clean(query, max: Self.maxQueryLength) else {
            return nil
        }
        let collection = SavedCollection(name: cleanName, query: cleanQuery)
        lock.lock()
        collections.append(collection)
        let snapshot = collections
        lock.unlock()
        Self.save(snapshot, to: fileURL)
        return collection
    }

    /// Edita nombre y consulta de una colección existente.
    @discardableResult
    public func update(id: String, name: String, query: String) -> Bool {
        guard let cleanName = Self.clean(name, max: Self.maxNameLength),
              let cleanQuery = Self.clean(query, max: Self.maxQueryLength) else {
            return false
        }
        lock.lock()
        guard let index = collections.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return false
        }
        collections[index].name = cleanName
        collections[index].query = cleanQuery
        collections[index].updatedAt = Date()
        let snapshot = collections
        lock.unlock()
        Self.save(snapshot, to: fileURL)
        return true
    }

    /// Borra una colección (no toca ningún fichero: solo la definición guardada).
    @discardableResult
    public func remove(id: String) -> Bool {
        lock.lock()
        let before = collections.count
        collections.removeAll { $0.id == id }
        let removed = collections.count != before
        let snapshot = collections
        lock.unlock()
        if removed {
            Self.save(snapshot, to: fileURL)
        }
        return removed
    }

    // MARK: - Privados

    private static func clean(_ value: String, max: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(max))
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("JUST4DESK/collections.json", isDirectory: false)
    }

    private static func load(from url: URL) -> [SavedCollection] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(Payload.self, from: data)
            return payload.collections
        } catch {
            J4Log.warn(.app, "Colecciones ilegibles (\(error.localizedDescription)); se ignoran.")
            return []
        }
    }

    private static func save(_ collections: [SavedCollection], to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Payload(version: 1, collections: collections))
            try data.write(to: url, options: .atomic)
        } catch {
            J4Log.warn(.app, "No se pudieron guardar las colecciones: \(error.localizedDescription)")
        }
    }
}
