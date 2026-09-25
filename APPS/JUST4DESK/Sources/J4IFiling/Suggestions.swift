import Foundation
import J4IIndex

// MARK: - Modelo de sugerencias proactivas (G2)

/// Tipo de sugerencia proactiva (v1): los tres detectores baratos y explicables de G2.
public enum ProactiveSuggestionKind: String, CaseIterable, Sendable {
    case duplicates
    case screenshots
    case largeForgotten

    /// Título corto para la tarjeta de «Inicio».
    public var title: String {
        switch self {
        case .duplicates: return "Posibles duplicados de lo ya archivado"
        case .screenshots: return "Capturas sueltas"
        case .largeForgotten: return "Grandes y sin cambios en 6+ meses"
        }
    }

    /// Explicación del porqué (siempre visible: las sugerencias no son cajas negras).
    public var explanation: String {
        switch self {
        case .duplicates:
            return "Coinciden en tamaño con documentos del archivo. Al aplicar se verifica el hash: solo los duplicados reales van a la Papelera (reversible desde el Finder)."
        case .screenshots:
            return "Imágenes de captura sin archivar (suelen ser ruido). Al aplicar se archivan con deshacer y quedan buscables."
        case .largeForgotten:
            return "De 1 GB o más y sin cambios desde hace medio año. Candidatos a mover a un archivo en frío (próxima fase)."
        }
    }

    /// Icono de la tarjeta.
    public var symbolName: String {
        switch self {
        case .duplicates: return "doc.on.doc"
        case .screenshots: return "camera.viewfinder"
        case .largeForgotten: return "shippingbox"
        }
    }
}

/// Elemento concreto afectado por una sugerencia.
public struct ProactiveSuggestionItem: Sendable, Equatable, Identifiable {
    public let path: String
    public let name: String
    public let sizeBytes: Int64
    public let modifiedAt: Date?

    public init(path: String, name: String, sizeBytes: Int64, modifiedAt: Date?) {
        self.path = path
        self.name = name
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
    }

    public var id: String { path }
}

/// Sugerencia lista para mostrar: tipo + contexto («En «~/Descargas» y «~/Escritorio»») + elementos.
public struct ProactiveSuggestion: Sendable, Identifiable {
    public let kind: ProactiveSuggestionKind
    public let context: String
    public let items: [ProactiveSuggestionItem]

    public init(kind: ProactiveSuggestionKind, context: String, items: [ProactiveSuggestionItem]) {
        self.kind = kind
        self.context = context
        self.items = items
    }

    public var id: String { kind.rawValue }
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    public var title: String { kind.title }
    public var detail: String { context.isEmpty ? kind.explanation : "\(context). \(kind.explanation)" }
}

// MARK: - Detectores

/// Detectores de G2: baratos y sin efectos secundarios (listados de primer nivel + consultas al
/// índice). Aquí **nada se mueve**: la ejecución es explícita desde «Inicio», con confirmación y
/// siempre con salida reversible (journal/undo o Papelera).
public enum ProactiveSuggestionScanner {
    /// Umbral para candidatos a duplicado (evita el ruido de ficheros diminutos).
    public static let duplicateMinBytes: Int64 = 1_048_576
    /// «Grandes y olvidados»: umbral de tamaño y antigüedad.
    public static let largeMinBytes: Int64 = 1_073_741_824
    public static let largeForgottenDays = 180

    static let screenshotKeywords = ["captura de pantalla", "capturas de pantalla", "screenshot", "screen shot"]
    static let screenshotExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff"]
    static let ignoredExtensions: Set<String> = ["part", "crdownload", "download", "tmp", "partial"]

    /// Capturas sueltas: primer nivel de cada carpeta, nombre con pinta de captura y extensión de imagen.
    public static func screenshots(in folders: [URL], limit: Int = 200, fileManager: FileManager = .default) -> [ProactiveSuggestionItem] {
        var found: [ProactiveSuggestionItem] = []
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        for folder in folders {
            let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
            for url in urls {
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                guard screenshotExtensions.contains(url.pathExtension.lowercased()) else { continue }
                let folded = fold(url.lastPathComponent)
                guard screenshotKeywords.contains(where: { folded.contains($0) }) else { continue }
                found.append(
                    ProactiveSuggestionItem(
                        path: url.path,
                        name: url.lastPathComponent,
                        sizeBytes: Int64(values.fileSize ?? 0),
                        modifiedAt: values.contentModificationDate
                    )
                )
            }
        }
        return Array(found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.prefix(limit))
    }

    /// Candidatos a duplicado: ficheros de primer nivel cuyo tamaño coincide con alguno del índice
    /// (la verificación por hash ocurre al aplicar, no aquí).
    public static func sizeMatchedCandidates(
        in folders: [URL],
        knownSizes: Set<Int64>,
        minSizeBytes: Int64 = duplicateMinBytes,
        limit: Int = 200,
        fileManager: FileManager = .default
    ) -> [ProactiveSuggestionItem] {
        var found: [ProactiveSuggestionItem] = []
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        for folder in folders {
            let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
            for url in urls {
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                guard !ignoredExtensions.contains(url.pathExtension.lowercased()) else { continue }
                let size = Int64(values.fileSize ?? 0)
                guard size >= minSizeBytes, knownSizes.contains(size) else { continue }
                found.append(
                    ProactiveSuggestionItem(
                        path: url.path,
                        name: url.lastPathComponent,
                        sizeBytes: size,
                        modifiedAt: values.contentModificationDate
                    )
                )
            }
        }
        return Array(found.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit))
    }

    /// Grandes y olvidados: parte de entradas ya filtradas por `SearchIndex.largeFiles`.
    public static func largeForgotten(from entries: [IndexEntry], limit: Int = 25) -> [ProactiveSuggestionItem] {
        entries.prefix(limit).map {
            ProactiveSuggestionItem(path: $0.path, name: $0.name, sizeBytes: $0.sizeBytes, modifiedAt: $0.modifiedAt)
        }
    }

    // MARK: Composiciones (texto listo para la tarjeta de «Inicio»)

    public static func duplicateSuggestion(folders: [URL], labels: [String], knownSizes: Set<Int64>) -> ProactiveSuggestion? {
        let items = sizeMatchedCandidates(in: folders, knownSizes: knownSizes)
        guard !items.isEmpty else { return nil }
        return ProactiveSuggestion(kind: .duplicates, context: contextLabel(labels), items: items)
    }

    public static func screenshotSuggestion(folders: [URL], labels: [String]) -> ProactiveSuggestion? {
        let items = screenshots(in: folders)
        guard !items.isEmpty else { return nil }
        return ProactiveSuggestion(kind: .screenshots, context: contextLabel(labels), items: items)
    }

    public static func largeForgottenSuggestion(entries: [IndexEntry]) -> ProactiveSuggestion? {
        let items = largeForgotten(from: entries)
        guard !items.isEmpty else { return nil }
        return ProactiveSuggestion(kind: .largeForgotten, context: "En el archivo", items: items)
    }

    /// «En «A»», «En «A» y «B»», «En «A», «B» y «C»».
    static func contextLabel(_ labels: [String]) -> String {
        switch labels.count {
        case 0: return ""
        case 1: return "En «\(labels[0])»"
        default:
            let allButLast = labels.dropLast().map { "«\($0)»" }.joined(separator: ", ")
            return "En \(allButLast) y «\(labels.last ?? "")»"
        }
    }

    static func fold(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
    }
}
