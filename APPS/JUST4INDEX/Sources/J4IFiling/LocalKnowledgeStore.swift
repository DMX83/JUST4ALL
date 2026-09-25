import Foundation
import J4ICore

/// Base de conocimiento LOCAL de la app (F12.0).
///
/// Petición del usuario (25-sep): «¿no podemos generar una inteligencia que sea de la app, con las
/// respuestas que nos va dando la IA… para en un futuro hacer menos preguntas?». Cada decisión de
/// la IA — y cada corrección manual del usuario — se resume en **observaciones** por característica
/// del elemento: la **extensión** de un fichero o las **palabras significativas** del nombre de una
/// carpeta. Cuando una característica se repite (≥ 3 observaciones, ≥ 75 % de acuerdo y confianza
/// media ≥ 0,7) se **promueve** a regla local: las próximas unidades así se clasifican **sin
/// llamar a la IA** (ahorro de tokens) y la decisión queda trazada como «conocimiento local».
/// Una corrección del usuario manda: reescribe la regla al momento.
public final class LocalKnowledgeStore: @unchecked Sendable {
    public enum FeatureKind: String, Codable, Sendable {
        case fileExtension
        case folderToken
    }

    public struct Entry: Codable, Sendable, Equatable {
        public var kind: FeatureKind
        public var value: String
        public var categoryPath: String
        public var positives: Int
        public var total: Int
        public var confidenceSum: Double
        public var lastSeen: Date
        public var lastSkillVersion: Int

        public var averageConfidence: Double { total > 0 ? confidenceSum / Double(total) : 0 }
        public var share: Double { total > 0 ? Double(positives) / Double(total) : 0 }
    }

    public struct PromotedRule: Sendable, Equatable {
        public let categoryPath: String
        public let confidence: Double
        public let observations: Int
    }

    public struct Stats: Sendable, Equatable {
        public let promotedCount: Int
        public let learnedEntries: Int
        public let appliedToday: Int
        public let appliedTotal: Int
    }

    // Criterios de promoción (conservadores, en línea con la filosofía de la skill).
    public static let minObservations = 3
    public static let minShare = 0.75
    public static let minAverageConfidence = 0.7

    public static let shared = LocalKnowledgeStore()

    private struct Payload: Codable {
        var entries: [String: Entry]
        var appliedDate: String?
        var appliedToday: Int
        var appliedTotal: Int
    }

    private let fileURL: URL
    private let lock = NSLock()
    private var entries: [String: Entry]
    private var appliedDate: String?
    private var appliedToday: Int
    private var appliedTotal: Int

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        let payload = Self.load(from: self.fileURL)
        self.entries = payload.entries
        self.appliedDate = payload.appliedDate
        self.appliedToday = payload.appliedToday
        self.appliedTotal = payload.appliedTotal
    }

    // MARK: - Observaciones (aprendizaje)

    /// Registra una observación (decisión de la IA o corrección del usuario).
    /// Devuelve `true` si la regla acaba de promocionarse con esta observación.
    @discardableResult
    public func record(kind: FeatureKind, value: String, categoryPath: String, confidence: Double, fromUser: Bool = false) -> Bool {
        let normalized = Self.normalize(value)
        guard !normalized.isEmpty, !categoryPath.isEmpty else { return false }
        let key = Self.key(kind: kind, value: normalized)
        lock.lock()
        var entry = entries[key] ?? Entry(
            kind: kind,
            value: normalized,
            categoryPath: categoryPath,
            positives: 0,
            total: 0,
            confidenceSum: 0,
            lastSeen: Date(),
            lastSkillVersion: FilingSkill.version
        )
        let wasPromoted = Self.isPromoted(entry)
        if fromUser {
            // La corrección del usuario manda: reescribe la regla lista para usarse.
            entry.categoryPath = categoryPath
            entry.positives = Self.minObservations
            entry.total = Self.minObservations
            entry.confidenceSum = Double(Self.minObservations)
        } else if entry.categoryPath == categoryPath {
            entry.positives += 1
            entry.total += 1
            entry.confidenceSum += min(max(confidence, 0), 1)
        } else {
            // Desacuerdo de la IA: baja el acuerdo (puede des-promocionar la regla).
            entry.total += 1
            entry.confidenceSum += min(max(confidence, 0), 1)
        }
        entry.lastSeen = Date()
        entry.lastSkillVersion = FilingSkill.version
        entries[key] = entry
        let isNowPromoted = Self.isPromoted(entry)
        let snapshot = payload()
        lock.unlock()
        Self.save(snapshot, to: fileURL)
        return !wasPromoted && isNowPromoted
    }

    // MARK: - Consulta (sin IA)

    /// Regla promovida para una característica (nil = la IA decidirá como siempre).
    public func promotedRule(kind: FeatureKind, value: String) -> PromotedRule? {
        let normalized = Self.normalize(value)
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[Self.key(kind: kind, value: normalized)], Self.isPromoted(entry) else { return nil }
        return PromotedRule(
            categoryPath: entry.categoryPath,
            confidence: min(0.9, max(Self.minAverageConfidence, entry.averageConfidence)),
            observations: entry.positives
        )
    }

    /// Cuenta una clasificación resuelta con conocimiento local (sin llamar a la IA).
    public func registerHit() {
        lock.lock()
        rolloverHitsLocked()
        appliedToday += 1
        appliedTotal += 1
        let snapshot = payload()
        lock.unlock()
        Self.save(snapshot, to: fileURL)
    }

    public func stats() -> Stats {
        lock.lock()
        defer { lock.unlock() }
        rolloverHitsLocked()
        return Stats(
            promotedCount: entries.values.filter(Self.isPromoted).count,
            learnedEntries: entries.count,
            appliedToday: appliedToday,
            appliedTotal: appliedTotal
        )
    }

    // MARK: - Privados

    private func payload() -> Payload {
        Payload(entries: entries, appliedDate: appliedDate, appliedToday: appliedToday, appliedTotal: appliedTotal)
    }

    private func rolloverHitsLocked() {
        let today = Self.dayKey(for: Date())
        if appliedDate != today {
            appliedDate = today
            appliedToday = 0
        }
    }

    static func isPromoted(_ entry: Entry) -> Bool {
        entry.positives >= minObservations && entry.share >= minShare && entry.averageConfidence >= minAverageConfidence
    }

    static func key(kind: FeatureKind, value: String) -> String {
        "\(kind.rawValue)|\(value)"
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("JUST4INDEX/knowledge.json", isDirectory: false)
    }

    private static func load(from url: URL) -> Payload {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return Payload(entries: [:], appliedDate: nil, appliedToday: 0, appliedTotal: 0)
        }
        do {
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            J4Log.warn(.ai, "Conocimiento local ilegible (\(error.localizedDescription)); se ignora.")
            return Payload(entries: [:], appliedDate: nil, appliedToday: 0, appliedTotal: 0)
        }
    }

    private static func save(_ payload: Payload, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            J4Log.warn(.ai, "No se pudo guardar el conocimiento local: \(error.localizedDescription)")
        }
    }
}

/// Extracción determinista de características para el conocimiento local.
public enum KnowledgeFeatures {
    /// Ruido habitual en nombres de descargas (se coteja en minúsculas y sin diacríticos).
    static let stopwords: Set<String> = [
        "para", "con", "los", "las", "del", "una", "uno", "por", "the", "and", "for", "with",
        "pro", "premium", "gratis", "free", "download", "downloaded", "descarga", "final",
        "version", "windows", "macos", "portable", "completo", "completa", "espanol", "spanish",
        "subtitulado", "crack", "cracked", "full", "update", "updater"
    ]

    /// Extensión normalizada de un nombre de fichero (`nil` si no tiene).
    public static func fileExtension(ofName name: String) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }

    /// Palabras significativas del nombre de una carpeta: sin diacríticos, ≥ 4 caracteres, sin
    /// números puros ni palabras vacías; ordenadas de mayor a menor longitud (más específicas antes).
    public static func folderTokens(fromName name: String) -> [String] {
        let folded = fold(name)
        var seen = Set<String>()
        return folded
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 4 }
            .filter { !$0.allSatisfy(\.isNumber) }
            .filter { !stopwords.contains($0) }
            .filter { seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
    }

    static func fold(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
    }
}
