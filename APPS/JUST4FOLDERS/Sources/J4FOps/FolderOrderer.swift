import Foundation
import J4ICore

/// v2.0 — «Ordenar esta carpeta»: clasifica los ficheros de una carpeta con el motor
/// compartido de JUST4DESK (`RulesFilingClassifier` + `FilingPlanner` + `DefaultTaxonomy`)
/// y los **mueve** (nunca copia ni borra) a las categorías, con diario para deshacer.
public enum FolderOrderer {

    public struct Options: Sendable, Equatable {
        /// Los ficheros sin clasificar se mueven a `99_SinClasificar`; si es false, se quedan.
        public var categorizeUnknown: Bool

        public init(categorizeUnknown: Bool = true) {
            self.categorizeUnknown = categorizeUnknown
        }
    }

    public enum Disposition: Sendable, Equatable {
        case move(relativePath: String, fileName: String, reason: String, confidence: Double, isQuarantine: Bool)
        case skip(reason: String)
    }

    public struct Item: Sendable, Equatable {
        public let url: URL
        public let disposition: Disposition

        public var destinationRelativePath: String? {
            if case .move(let path, _, _, _, _) = disposition { return path }
            return nil
        }

        public var finalName: String? {
            if case .move(_, let name, _, _, _) = disposition { return name }
            return nil
        }

        public var isQuarantine: Bool {
            if case .move(_, _, _, _, let quarantine) = disposition { return quarantine }
            return false
        }

        public var reason: String {
            switch disposition {
            case .move(_, _, let reason, _, _): return reason
            case .skip(let reason): return reason
            }
        }
    }

    /// Movimiento ejecutado (base del diario de deshacer).
    public struct Move: Codable, Sendable, Equatable {
        public let source: String
        public let destination: String

        public init(source: String, destination: String) {
            self.source = source
            self.destination = destination
        }
    }

    /// Plan puro: reglas locales (nombre → extensión) normalizadas contra la taxonomía.
    /// Confianza insuficiente o categoría desconocida → `99_SinClasificar`.
    public static func plan(files: [URL], options: Options = Options()) -> [Item] {
        files.map { url in
            let proposal = RulesFilingClassifier.suggestDestination(fileName: url.lastPathComponent)
            let plan = FilingPlanner.resolve(proposal: proposal, originalFileName: url.lastPathComponent)
            if plan.isQuarantine && !options.categorizeUnknown {
                return Item(url: url, disposition: .skip(reason: "sin clasificar: \(plan.reason)"))
            }
            return Item(
                url: url,
                disposition: .move(
                    relativePath: plan.categoryRelativePath,
                    fileName: plan.fileName,
                    reason: plan.reason,
                    confidence: plan.confidence,
                    isQuarantine: plan.isQuarantine
                )
            )
        }
    }

    /// v2.0 — Plan con asesor IA opcional: solo se consultan los «dudosos» (los que las reglas
    /// mandarían a `99_SinClasificar`), hasta `maxAICalls` por lote. La respuesta se valida con
    /// `FilingPlanner` (categoría permitida y confianza ≥ 0,5); si no pasa, se queda en cuarentena.
    public static func planAsync(
        files: [URL],
        options: Options = Options(),
        advisor: (any FilingAdvising)?,
        maxAICalls: Int = 40,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [Item] {
        var items = plan(files: files, options: options)
        guard let advisor else { return items }

        let candidates: [Int] = items.enumerated().compactMap { index, item in
            switch item.disposition {
            case .move(_, _, _, _, let isQuarantine): return isQuarantine ? index : nil
            case .skip: return index
            }
        }
        let limited = Array(candidates.prefix(max(0, maxAICalls)))
        guard !limited.isEmpty else { return items }

        let allowed = DefaultTaxonomy.allRelativePaths
        var done = 0
        onProgress?(0, limited.count)
        for index in limited {
            if Task.isCancelled { break }
            let url = items[index].url
            done += 1
            onProgress?(done, limited.count)
            guard let proposal = try? await advisor.propose(
                fileName: url.lastPathComponent,
                allowedCategories: allowed
            ) else { continue }
            let resolved = FilingPlanner.resolve(proposal: proposal, originalFileName: url.lastPathComponent)
            guard !resolved.isQuarantine else { continue }
            items[index] = Item(
                url: url,
                disposition: .move(
                    relativePath: resolved.categoryRelativePath,
                    fileName: resolved.fileName,
                    reason: "IA: \(resolved.reason)",
                    confidence: resolved.confidence,
                    isQuarantine: false
                )
            )
        }
        return items
    }

    /// Ejecuta el plan: crea las categorías necesarias y mueve cada fichero.
    /// Devuelve cuántos se movieron, los fallos y el diario (para `undo`).
    @discardableResult
    public static func apply(
        _ items: [Item],
        destinationRoot: URL
    ) -> (moved: Int, failures: [String], journal: [Move]) {
        let fm = FileManager.default
        var journal: [Move] = []
        var failures: [String] = []
        for item in items {
            guard case .move(let relativePath, let fileName, _, _, _) = item.disposition else { continue }
            let directory = destinationRoot.appendingPathComponent(relativePath, isDirectory: true)
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = uniqueDestination(in: directory, fileName: fileName)
                try fm.moveItem(at: item.url, to: destination)
                journal.append(Move(
                    source: item.url.standardizedFileURL.path,
                    destination: destination.standardizedFileURL.path
                ))
            } catch {
                failures.append("\(item.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (journal.count, failures, journal)
    }

    /// Deshace un diario de ordenación: mueve de vuelta (recrea la carpeta original si hace falta).
    @discardableResult
    public static func undo(_ journal: [Move]) -> (restored: Int, failures: [String]) {
        let fm = FileManager.default
        var restored = 0
        var failures: [String] = []
        for move in journal.reversed() {
            let current = URL(fileURLWithPath: move.destination)
            let original = URL(fileURLWithPath: move.source)
            guard fm.fileExists(atPath: move.destination) else { continue }
            do {
                try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: current, to: original)
                restored += 1
            } catch {
                failures.append("\(current.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (restored, failures)
    }

    /// Nombre libre en el directorio de destino («nombre 2.ext», «nombre 3.ext»…).
    static func uniqueDestination(in directory: URL, fileName: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}

/// Persistencia del último diario de ordenación (para «Deshacer última ordenación»).
public enum OrderingJournalStore {
    public static func defaultURL(appFolder: String = "JUST4FOLDERS") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent(appFolder, isDirectory: true)
            .appendingPathComponent("ordering-journal.json", isDirectory: false)
    }

    public static func save(_ journal: [FolderOrderer.Move], to url: URL) {
        guard !journal.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(journal)
            try data.write(to: url, options: .atomic)
        } catch {
            // Sin diario no hay deshacer; no debe tumbar la ordenación ya hecha.
        }
    }

    public static func load(from url: URL) -> [FolderOrderer.Move] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([FolderOrderer.Move].self, from: data)) ?? []
    }

    public static func clear(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
