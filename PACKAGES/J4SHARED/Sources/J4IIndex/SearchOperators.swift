import Foundation

/// N8 — Operadores de búsqueda: `ext:pdf`, `tipo:vídeo`, `fecha:2026-09`.
///
/// Se aceptan alias y variantes sin acento (`imagenes`, `video`). Los operadores se extraen del
/// texto de la consulta y el resto se busca como siempre; si la consulta queda vacía, la lista
/// se convierte en «todos los que cumplen los filtros» (lo resuelve la capa de búsqueda).
///
/// Semántica:
/// - `ext:pdf,doc` — extensiones concretas (varias apariciones se acumulan).
/// - `tipo:documentos|imagenes|audio|video|comprimidos` — familias completas (mismos conjuntos
///   que los chips de la UI). Con `ext:` y `tipo:` a la vez se aplica la **intersección**.
/// - `fecha:2026` | `fecha:2026-09` | `fecha:2026-09-15` — por fecha de modificación (año, mes
///   o día, en el calendario recibido).
/// Los tokens con pinta de operador pero desconocidos (`foo:bar`) se dejan en el texto.
public enum SearchQueryParser {
    public struct Parsed: Equatable {
        /// Texto de la consulta sin operadores (puede quedar vacío).
        public let text: String
        /// Extensiones resultado de `ext:`/`tipo:` (sin punto, minúsculas). `nil` = sin filtro.
        public let extensions: Set<String>?
        public let modifiedAfter: Date?
        public let modifiedBefore: Date?
        public var hasFilters: Bool {
            extensions != nil || modifiedAfter != nil || modifiedBefore != nil
        }

        public init(text: String, extensions: Set<String>?, modifiedAfter: Date?, modifiedBefore: Date?) {
            self.text = text
            self.extensions = extensions
            self.modifiedAfter = modifiedAfter
            self.modifiedBefore = modifiedBefore
        }
    }

    // MARK: - Familias (espejo de ResultKindFilter de la UI; mantener sincronizadas)

    /// Extensiones de cada familia de `tipo:` (sin punto, minúsculas). `nil` = familia desconocida.
    public static func kindExtensions(for rawValue: String) -> Set<String>? {
        switch fold(rawValue) {
        case "documentos", "documento", "docs", "doc", "documents":
            return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "rtf", "csv"]
        case "imagenes", "imagen", "fotos", "foto", "images":
            return ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp", "svg"]
        case "audio", "audios", "musica", "music":
            return ["mp3", "m4a", "aac", "wav", "aiff", "flac", "alac", "ogg"]
        case "video", "videos", "peliculas", "series":
            return ["mp4", "mov", "mkv", "avi", "webm", "m4v"]
        case "comprimidos", "comprimido", "archivos", "archives", "zips":
            return ["zip", "rar", "7z", "tar", "gz", "dmg", "pkg", "iso"]
        default:
            return nil
        }
    }

    // MARK: - Parseo

    public static func parse(_ raw: String, calendar: Calendar = .current) -> Parsed {
        var textTokens: [String] = []
        var explicitExtensions: Set<String>?
        var kindSet: Set<String>?
        var modifiedAfter: Date?
        var modifiedBefore: Date?

        for token in raw.split(whereSeparator: { $0.isWhitespace }) {
            let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else {
                textTokens.append(String(token))
                continue
            }
            let key = fold(String(parts[0]))
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            var consumed = false

            switch key {
            case "ext", "extension", "extensiones":
                let list = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
                    .filter { !$0.isEmpty }
                if !list.isEmpty {
                    explicitExtensions = (explicitExtensions ?? []).union(list)
                    consumed = true
                }
            case "tipo", "type", "kind":
                let values = value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                let sets = values.compactMap { kindExtensions(for: $0) }
                if !values.isEmpty, sets.count == values.count {
                    kindSet = (kindSet ?? []).union(sets.flatMap { $0 })
                    consumed = true
                }
            case "fecha", "date", "mod":
                if let range = dateRange(value, calendar: calendar) {
                    modifiedAfter = range.start
                    modifiedBefore = range.end
                    consumed = true
                }
            default:
                break
            }

            if !consumed {
                textTokens.append(String(token))
            }
        }

        // `ext:` y `tipo:` juntos = intersección (p. ej. `tipo:documentos ext:pdf` → solo pdf).
        var extensions: Set<String>? = explicitExtensions
        if let kindSet {
            extensions = extensions.map { $0.intersection(kindSet) } ?? kindSet
        }

        return Parsed(
            text: textTokens.joined(separator: " "),
            extensions: extensions,
            modifiedAfter: modifiedAfter,
            modifiedBefore: modifiedBefore
        )
    }

    // MARK: - Fechas

    /// Rango [inicio, fin inclusivo] de `YYYY` / `YYYY-MM` / `YYYY-MM-DD` en el calendario dado.
    static func dateRange(_ value: String, calendar: Calendar) -> (start: Date, end: Date)? {
        let parts = value.split(separator: "-").map(String.init)
        switch parts.count {
        case 1:
            guard let year = Int(parts[0]), (1900...2200).contains(year) else { return nil }
            return range(year: year, month: nil, day: nil, calendar: calendar)
        case 2:
            guard let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else { return nil }
            return range(year: year, month: month, day: nil, calendar: calendar)
        case 3:
            guard let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]), (1...31).contains(day) else { return nil }
            return range(year: year, month: month, day: day, calendar: calendar)
        default:
            return nil
        }
    }

    private static func range(year: Int, month: Int?, day: Int?, calendar: Calendar) -> (start: Date, end: Date)? {
        var components = DateComponents()
        components.year = year
        components.month = month ?? 1
        components.day = day ?? 1
        guard let start = calendar.date(from: components) else { return nil }
        var advance = DateComponents()
        if day != nil {
            advance.day = 1
        } else if month != nil {
            advance.month = 1
        } else {
            advance.year = 1
        }
        guard let exclusiveEnd = calendar.date(byAdding: advance, to: start) else { return nil }
        return (start, exclusiveEnd.addingTimeInterval(-1))
    }

    private static func fold(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
    }
}
