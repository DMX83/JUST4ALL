import Foundation

/// v1.2 — Renombrado en lote con previsualización.
///
/// `plan` es puro (solo consulta el disco para detectar conflictos): devuelve, por cada
/// fichero, el nombre nuevo o el motivo por el que no se puede renombrar.
/// `apply` ejecuta el plan en dos fases (temporales únicos → nombre final) para soportar
/// intercambios e interdependencias sin colisiones intermedias.
public enum BatchRenamer {

    public struct Options: Sendable, Equatable {
        public var find: String
        public var replace: String
        public var useRegex: Bool
        public var includeExtension: Bool

        public init(find: String, replace: String, useRegex: Bool = false, includeExtension: Bool = false) {
            self.find = find
            self.replace = replace
            self.useRegex = useRegex
            self.includeExtension = includeExtension
        }
    }

    public enum Status: Sendable, Equatable {
        case rename(to: String)
        case unchanged
        case invalid(String)
    }

    public struct ItemPlan: Sendable, Equatable {
        public let url: URL
        public let status: Status

        public var newName: String? {
            if case .rename(let name) = status { return name }
            return nil
        }

        public var errorMessage: String? {
            if case .invalid(let message) = status { return message }
            return nil
        }
    }

    /// Calcula el plan. Detecta: nombres vacíos/reservados, separadores («/», «:»),
    /// conflictos con ficheros existentes y colisiones dentro del propio lote.
    public static func plan(urls: [URL], options: Options) -> [ItemPlan] {
        let regex = options.useRegex ? (try? NSRegularExpression(pattern: options.find)) : nil
        if options.useRegex && regex == nil {
            return urls.map { ItemPlan(url: $0, status: .invalid("Expresión regular no válida")) }
        }

        // 1ª pasada: nombre propuesto por fichero.
        var proposed: [(url: URL, newName: String, invalid: String?)] = []
        for url in urls {
            let ext = url.pathExtension
            let hasExtension = !ext.isEmpty
            let base = hasExtension ? String(url.lastPathComponent.dropLast(ext.count + 1)) : url.lastPathComponent
            let source = options.includeExtension ? url.lastPathComponent : base

            let replaced: String?
            if options.useRegex, let regex {
                let range = NSRange(source.startIndex..., in: source)
                replaced = regex.stringByReplacingMatches(
                    in: source,
                    options: [],
                    range: range,
                    withTemplate: options.replace
                )
            } else if options.find.isEmpty {
                replaced = nil
            } else {
                replaced = source.replacingOccurrences(of: options.find, with: options.replace)
            }

            guard let replaced else {
                proposed.append((url, url.lastPathComponent, nil))
                continue
            }
            let newName = (options.includeExtension || !hasExtension) ? replaced : replaced + "." + ext
            proposed.append((url, newName, validate(newName)))
        }

        // 2ª pasada: conflictos en disco (fuera del lote) y colisiones internas.
        let plannedSources = Set(urls.map { $0.standardizedFileURL.path })
        var used: [String: String] = [:] // clave(dir+nombre) -> nombre original que ya la usa
        var result: [ItemPlan] = []
        for item in proposed {
            if let invalid = item.invalid {
                result.append(ItemPlan(url: item.url, status: .invalid(invalid)))
                continue
            }
            if item.newName == item.url.lastPathComponent {
                result.append(ItemPlan(url: item.url, status: .unchanged))
                used[conflictKey(for: item.url, name: item.newName)] = item.url.lastPathComponent
                continue
            }
            let key = conflictKey(for: item.url, name: item.newName)
            if let previousName = used[key] {
                result.append(ItemPlan(url: item.url, status: .invalid("Colisión con «\(previousName)» del lote")))
                continue
            }
            let target = item.url.deletingLastPathComponent().appendingPathComponent(item.newName)
            if FileManager.default.fileExists(atPath: target.path),
               !plannedSources.contains(target.standardizedFileURL.path) {
                result.append(ItemPlan(url: item.url, status: .invalid("Ya existe «\(item.newName)»")))
                continue
            }
            used[key] = item.url.lastPathComponent
            result.append(ItemPlan(url: item.url, status: .rename(to: item.newName)))
        }
        return result
    }

    /// Ejecuta el plan en dos fases. Devuelve el número de renombrados y los fallos.
    @discardableResult
    public static func apply(_ plan: [ItemPlan]) -> (renamed: Int, failures: [String]) {
        let renames: [(source: URL, destination: URL)] = plan.compactMap { item in
            guard case .rename(let name) = item.status else { return nil }
            return (item.url, item.url.deletingLastPathComponent().appendingPathComponent(name))
        }
        guard !renames.isEmpty else { return (0, []) }

        let fm = FileManager.default
        var staged: [(temp: URL, final: URL, original: URL)] = []
        var failures: [String] = []

        // Fase 1: todo a nombres temporales únicos (permite intercambios).
        for rename in renames {
            let temp = rename.source.deletingLastPathComponent()
                .appendingPathComponent(".j4f-ren-\(UUID().uuidString)")
            do {
                try fm.moveItem(at: rename.source, to: temp)
                staged.append((temp, rename.destination, rename.source))
            } catch {
                failures.append("\(rename.source.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // Fase 2: temporales → nombre final (rollback best-effort si algo falla).
        var renamed = 0
        for entry in staged {
            do {
                try fm.moveItem(at: entry.temp, to: entry.final)
                renamed += 1
            } catch {
                failures.append("\(entry.final.lastPathComponent): \(error.localizedDescription)")
                if !fm.fileExists(atPath: entry.original.path) {
                    try? fm.moveItem(at: entry.temp, to: entry.original)
                }
            }
        }
        return (renamed, failures)
    }

    private static func validate(_ name: String) -> String? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "Nombre vacío" }
        if clean == "." || clean == ".." { return "Nombre reservado" }
        if clean.contains("/") { return "No puede contener «/»" }
        if clean.contains(":") { return "No puede contener «:»" }
        return nil
    }

    private static func conflictKey(for url: URL, name: String) -> String {
        url.deletingLastPathComponent().standardizedFileURL.path + "/" + name.lowercased()
    }
}
