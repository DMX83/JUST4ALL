import Foundation

/// Valida y normaliza una propuesta de archivado contra la taxonomía.
///
/// Reglas:
/// - La categoría debe existir en la taxonomía (matching normalizado: sin acentos, sin prefijos
///   numéricos como `01_`, insensible a caso). Si solo coincide el último segmento, se resuelve.
/// - Confianza < 0.5 o categoría desconocida → cuarentena (`99_SinClasificar`).
/// - El nombre final se construye con `FileNameFactory` y nunca puede contener rutas.
public enum FilingPlanner {
    public static let minimumConfidence = 0.5

    public static func resolve(
        proposal: FilingProposal?,
        originalFileName: String,
        categories: [TaxonomyNode] = DefaultTaxonomy.categories()
    ) -> FilingPlan {
        let allowed = categories.flatMap { $0.allRelativePaths }

        guard let proposal else {
            return quarantinePlan(originalFileName: originalFileName, reason: "sin propuesta de clasificación", confidence: 0)
        }
        guard proposal.confidence >= minimumConfidence else {
            let formatted = String(format: "%.2f", proposal.confidence)
            return quarantinePlan(
                originalFileName: originalFileName,
                reason: "confianza insuficiente (\(formatted)): \(proposal.reason)",
                confidence: proposal.confidence
            )
        }
        guard let category = normalizeCategory(proposal.categoryPath, allowed: allowed) else {
            return quarantinePlan(
                originalFileName: originalFileName,
                reason: "categoría desconocida «\(proposal.categoryPath)»",
                confidence: proposal.confidence
            )
        }

        let date = parseISODate(proposal.documentDate)
        let fileName = FileNameFactory.make(
            date: date,
            issuer: proposal.issuer,
            title: proposal.suggestedTitle,
            originalFileName: originalFileName
        )
        let safeName = (fileName as NSString).lastPathComponent
        return FilingPlan(
            categoryRelativePath: category,
            fileName: safeName,
            confidence: min(max(proposal.confidence, 0), 1),
            reason: proposal.reason,
            source: proposal.source
        )
    }

    /// Normaliza una categoría emitida por IA/reglas a una ruta válida de la taxonomía.
    public static func normalizeCategory(_ raw: String, allowed: [String]) -> String? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard !cleaned.isEmpty else { return nil }

        let folded = fold(cleaned)
        if let match = allowed.first(where: { fold($0) == folded }) {
            return match
        }
        let lastSegment = folded.split(separator: "/").last.map(String.init) ?? folded
        return allowed.first { path in
            fold(path).split(separator: "/").last.map(String.init) == lastSegment
        }
    }

    public static func parseISODate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return isoDateFormatter.date(from: trimmed)
    }

    private static func quarantinePlan(originalFileName: String, reason: String, confidence: Double) -> FilingPlan {
        let fileName = FileNameFactory.make(date: nil, issuer: nil, title: nil, originalFileName: originalFileName)
        return FilingPlan(
            categoryRelativePath: DefaultTaxonomy.quarantineRelativePath,
            fileName: (fileName as NSString).lastPathComponent,
            confidence: min(max(confidence, 0), 1),
            reason: reason,
            source: .fallback
        )
    }

    /// Plegado para comparar categorías: minúsculas, sin acentos, sin espacios/underscores
    /// y sin prefijos numéricos por segmento (`01_Fiscal` → `fiscal`).
    static func fold(_ raw: String) -> String {
        let folded = raw.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "es_ES"))
        let segments = folded.split(separator: "/").map { segment -> String in
            var s = String(segment).trimmingCharacters(in: .whitespaces)
            s = s.replacingOccurrences(of: "_", with: "")
            s = s.replacingOccurrences(of: " ", with: "")
            while let first = s.first, first.isNumber {
                s.removeFirst()
            }
            return s
        }
        return segments.joined(separator: "/")
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
