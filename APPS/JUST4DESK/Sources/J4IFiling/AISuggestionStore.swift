import Foundation
import J4ICore

/// Almacén persistente de propuestas de la IA (JSON en Application Support).
///
/// Petición del usuario (2026-09-24): «que haya lugar para guardar las sugerencias de la IA, porque
/// si no hay que gastar tokens de nuevo haciendo la misma pregunta». Cada entrada guarda la propuesta
/// (categoría, confianza, motivo, cuarentena) junto a la **huella del archivo** (tamaño + fecha de
/// modificación) y la **versión de la skill**: si el archivo cambia o la skill sube de versión, la
/// propuesta se considera obsoleta y se volverá a consultar. Reutilizar una entrada **no** consume
/// el cap diario de IA (no hay llamada al modelo).
public final class AISuggestionStore: @unchecked Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public var categoryPath: String
        public var confidence: Double
        public var reason: String
        public var isQuarantine: Bool
        /// Estrategia de carpeta persistida («split» = desglosar; `nil` = entera).
        public var folderStrategy: String?
        public var name: String
        public var sizeBytes: Int64
        public var modifiedAt: Date?
        public var skillVersion: Int
        public var recordedAt: Date

        public init(
            categoryPath: String,
            confidence: Double,
            reason: String,
            isQuarantine: Bool,
            folderStrategy: String? = nil,
            name: String,
            sizeBytes: Int64,
            modifiedAt: Date?,
            skillVersion: Int,
            recordedAt: Date = Date()
        ) {
            self.categoryPath = categoryPath
            self.confidence = confidence
            self.reason = reason
            self.isQuarantine = isQuarantine
            self.folderStrategy = folderStrategy
            self.name = name
            self.sizeBytes = sizeBytes
            self.modifiedAt = modifiedAt
            self.skillVersion = skillVersion
            self.recordedAt = recordedAt
        }
    }

    public static let shared = AISuggestionStore()

    private let fileURL: URL
    private let lock = NSLock()
    private var entries: [String: Entry]

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.entries = Self.loadEntries(from: self.fileURL)
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// Entrada válida para la ruta si la huella (tamaño + fecha) y la versión de skill coinciden.
    public func entry(forPath path: String, sizeBytes: Int64, modifiedAt: Date?, skillVersion: Int = FilingSkill.version) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path] else { return nil }
        guard entry.skillVersion == skillVersion else { return nil }
        guard Self.fingerprintMatches(entry, sizeBytes: sizeBytes, modifiedAt: modifiedAt) else { return nil }
        return entry
    }

    /// Reconstruye la propuesta tipada a partir de la caché (fuente `.ai`).
    public func suggestion(forPath path: String, sizeBytes: Int64, modifiedAt: Date?) -> FilingCoordinator.Suggestion? {
        guard let entry = entry(forPath: path, sizeBytes: sizeBytes, modifiedAt: modifiedAt) else { return nil }
        return FilingCoordinator.Suggestion(
            sourcePath: path,
            name: entry.name,
            categoryPath: entry.categoryPath,
            confidence: entry.confidence,
            source: .ai,
            reason: entry.reason,
            isQuarantine: entry.isQuarantine,
            folderStrategy: entry.folderStrategy.flatMap { FolderFilingStrategy(rawValue: $0) }
        )
    }

    /// Guarda una propuesta recién obtenida del modelo para `path`.
    public func store(_ suggestion: FilingCoordinator.Suggestion, forPath path: String, sizeBytes: Int64, modifiedAt: Date?) {
        save(
            entry: Entry(
                categoryPath: suggestion.categoryPath,
                confidence: suggestion.confidence,
                reason: suggestion.reason,
                isQuarantine: suggestion.isQuarantine,
                folderStrategy: suggestion.folderStrategy?.rawValue,
                name: suggestion.name,
                sizeBytes: sizeBytes,
                modifiedAt: modifiedAt,
                skillVersion: FilingSkill.version
            ),
            forPath: path
        )
    }

    public func save(entry: Entry, forPath path: String) {
        lock.lock()
        entries[path] = entry
        let snapshot = entries
        lock.unlock()
        Self.write(snapshot, to: fileURL)
    }

    public func remove(forPath path: String) {
        lock.lock()
        let removed = entries.removeValue(forKey: path) != nil
        let snapshot = entries
        lock.unlock()
        guard removed else { return }
        Self.write(snapshot, to: fileURL)
    }

    public func removeAll() {
        lock.lock()
        entries = [:]
        lock.unlock()
        Self.write([:], to: fileURL)
    }

    // MARK: - Persistencia

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("JUST4DESK/ai-suggestions.json", isDirectory: false)
    }

    private static func loadEntries(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        do {
            return try JSONDecoder().decode([String: Entry].self, from: data)
        } catch {
            J4Log.warn(.ai, "Caché de sugerencias IA ilegible (\(error.localizedDescription)); se ignora.")
            return [:]
        }
    }

    private static func write(_ entries: [String: Entry], to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            J4Log.warn(.ai, "No se pudo guardar la caché de sugerencias IA: \(error.localizedDescription)")
        }
    }

    private static func fingerprintMatches(_ entry: Entry, sizeBytes: Int64, modifiedAt: Date?) -> Bool {
        guard entry.sizeBytes == sizeBytes else { return false }
        switch (entry.modifiedAt, modifiedAt) {
        case (nil, nil):
            return true
        case let (stored?, current?):
            return abs(stored.timeIntervalSince(current)) < 1
        default:
            return false
        }
    }
}
