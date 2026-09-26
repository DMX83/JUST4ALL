import Foundation

/// G7 — Fusión de resultados léxicos y semánticos para la ventana «Buscar».
///
/// Criterio: lo que el usuario escribió («palabra clave») manda y conserva su orden natural; los
/// aciertos *por significado* que no aparezcan ya se añaden después (marcados en la fila) hasta el
/// tope. `semantic` debe venir ya ordenado por relevancia (la lista se respeta tal cual).
public enum SemanticMerge {
    public static func merge(
        keyword: [IndexSearchHit],
        semantic: [IndexSearchHit],
        semanticLimit: Int = 8,
        totalLimit: Int = 300
    ) -> [IndexSearchHit] {
        guard !semantic.isEmpty else { return Array(keyword.prefix(totalLimit)) }
        var seen = Set(keyword.map(\.entry.id))
        var extras: [IndexSearchHit] = []
        for hit in semantic {
            guard extras.count < semanticLimit else { break }
            guard !seen.contains(hit.entry.id) else { continue }
            seen.insert(hit.entry.id)
            var annotated = hit
            annotated.matchedSemantically = true
            extras.append(annotated)
        }
        return Array((keyword + extras).prefix(totalLimit))
    }
}
