import Foundation
import J4ICore
import NaturalLanguage

/// G7 — Expansión semántica de consultas con embeddings de palabras locales.
///
/// Para cada término propone sinónimos cercanos del modelo del sistema («sueldo» → «nómina»,
/// «alquiler» → «arrendamiento», «recibo» → «factura») y construye una consulta FTS ampliada
/// `(term OR sin1 OR sin2) AND …`. Todo local: ningún término sale del Mac.
public actor QueryExpander {
    private let word: NLEmbedding
    private var cache: [String: [String]] = [:]

    private init(word: NLEmbedding) {
        self.word = word
    }

    /// Disponible en Macs con el modelo de palabras en español (prácticamente todos).
    public static func make() -> QueryExpander? {
        guard let word = NLEmbedding.wordEmbedding(for: .spanish) else { return nil }
        return QueryExpander(word: word)
    }

    /// Consulta ampliada, o `nil` si ningún término tiene sinónimos útiles (consulta sin cambios).
    public func expandedQuery(for query: String, maxPerToken: Int = 3, maxDistance: Double = 0.88) -> String? {
        let tokens = Self.tokens(of: query)
        guard !tokens.isEmpty else { return nil }
        var groups: [(String, [String])] = []
        var changed = false
        for token in tokens {
            // Los términos muy cortos («de», «la») no se expanden: sus vecinos son ruido.
            let expansions = token.count >= 3
                ? expansions(for: token, maxPerToken: maxPerToken, maxDistance: maxDistance)
                : []
            if !expansions.isEmpty { changed = true }
            groups.append((token, expansions))
        }
        guard changed else { return nil }
        return Self.build(groups: groups)
    }

    /// Expresión FTS «OR» para **recuperación de contexto** (chat): todos los términos útiles de la
    /// pregunta (≥3 letras, sin muletillas tipo «que/para/tengo») más sus sinónimos, unidos con OR
    /// — el ranking bm25 ordena por cuántos términos (y tan raros) acierta cada documento.
    public func retrievalExpression(for question: String) -> String? {
        let tokens = Self.tokens(of: question).filter { $0.count >= 3 && !Self.stopwords.contains($0) }
        guard !tokens.isEmpty else { return nil }
        var terms: [String] = []
        var seen = Set<String>()
        for token in tokens {
            if seen.insert(token).inserted { terms.append(token) }
            for expansion in expansions(for: token, maxPerToken: 2, maxDistance: 0.88)
            where !Self.stopwords.contains(expansion) && seen.insert(expansion).inserted {
                terms.append(expansion)
            }
        }
        guard !terms.isEmpty else { return nil }
        return terms.map { "\($0)*" }.joined(separator: " OR ")
    }

    /// Muletillas y verbos de relleno que no aportan a la recuperación.
    static let stopwords: Set<String> = [
        "que", "los", "las", "una", "uno", "unos", "unas", "del", "con", "por", "para",
        "como", "donde", "cuando", "cuanto", "cuanta", "cuantos", "cuantas", "hay", "tengo",
        "tiene", "tienen", "esta", "este", "esto", "esos", "esas", "son", "sus", "mis",
        "tus", "sobre", "entre", "pero", "mas", "muy", "sin", "que"
    ]

    private func expansions(for token: String, maxPerToken: Int, maxDistance: Double) -> [String] {
        if let cached = cache[token] { return cached }
        var results: [String] = []
        for (neighbor, distance) in word.neighbors(for: token, maximumCount: 12) {
            guard results.count < maxPerToken else { break }
            guard distance <= maxDistance else { continue }
            let cleaned = neighbor.lowercased()
            guard cleaned != token, cleaned.count >= 3 else { continue }
            guard cleaned.allSatisfy({ $0.isLetter }) else { continue }
            results.append(cleaned)
        }
        cache[token] = results
        return results
    }

    /// Trocea como el buscador: sub-tokens alfanuméricos en minúsculas, sin repetir, ≥2 caracteres.
    static func tokens(of query: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for scalar in query.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        var seen = Set<String>()
        return tokens.filter { $0.count >= 2 && seen.insert($0).inserted }
    }

    /// «(a OR sin1 OR sin2) AND b*» — forma estable (probada por tests).
    static func build(groups: [(String, [String])]) -> String {
        groups
            .map { term, expansions in
                if expansions.isEmpty { return "\(term)*" }
                return "(" + ([term] + expansions).map { "\($0)*" }.joined(separator: " OR ") + ")"
            }
            .joined(separator: " AND ")
    }
}
