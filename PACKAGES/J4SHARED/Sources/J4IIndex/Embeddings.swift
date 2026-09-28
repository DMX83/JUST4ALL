import Foundation
import J4ICore
import NaturalLanguage

/// G7 — Embedder local de texto: vectores semánticos sin salir del Mac.
///
/// Motor primario: `NLContextualEmbedding` (script latino, 512 dimensiones; modelos transformer
/// multilingües de Apple) con pooling medio sobre los tokens y normalización L2. Alternativa:
/// `NLEmbedding.sentenceEmbedding(for: .spanish)` (640d) si el contextual no está disponible.
/// `make()` decide una sola vez y el modelo queda identificado en cada vector almacenado, para
/// poder re-vectorizar cuando cambie.
public actor DocEmbedder {
    public enum Model: String, Sendable {
        case contextualLatin512 = "ctx-latin-512"
        case sentenceSpanish640 = "sent-es-640"
    }

    public nonisolated let model: Model
    public nonisolated let dimension: Int

    /// Tope de caracteres por documento: el inicio concentra la señal (título/emisor/fechas) y
    /// acota el coste por documento en el rellenado en segundo plano.
    public static let maxTextCharacters = 1200

    private var contextual: NLContextualEmbedding?
    private var sentence: NLEmbedding?
    private var contextualLoadFailed = false

    private init(model: Model, dimension: Int) {
        self.model = model
        self.dimension = dimension
    }

    /// Modelo disponible en este Mac (contextual si hay assets; si no, sentence en español).
    /// Devuelve `nil` cuando no hay ningún motor (la búsqueda semántica queda desactivada).
    public static func make() -> DocEmbedder? {
        if #available(macOS 14.0, *) {
            if let ctx = NLContextualEmbedding(script: .latin), ctx.hasAvailableAssets {
                return DocEmbedder(model: .contextualLatin512, dimension: ctx.dimension)
            }
        }
        if let sentence = NLEmbedding.sentenceEmbedding(for: .spanish) {
            return DocEmbedder(model: .sentenceSpanish640, dimension: sentence.dimension)
        }
        return nil
    }

    /// Identificador del modelo tal y como se persiste (`ctx-latin-512`, `sent-es-640`).
    public nonisolated var modelTag: String { model.rawValue }

    /// Vector **normalizado (L2)** del texto; `nil` si no se pudo calcular.
    public func embedNormalized(_ text: String) -> [Float]? {
        guard let vector = embed(text: text), vector.count == dimension else { return nil }
        var sumSquares: Float = 0
        for value in vector { sumSquares += value * value }
        let norm = sqrt(sumSquares)
        guard norm > 0, norm.isFinite else { return nil }
        return vector.map { $0 / norm }
    }

    /// Similitud coseno entre dos vectores (sin asumir normalización).
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for index in a.indices {
            dot += a[index] * b[index]
            na += a[index] * a[index]
            nb += b[index] * b[index]
        }
        let denominator = sqrt(na) * sqrt(nb)
        guard denominator > 0, denominator.isFinite else { return 0 }
        return Double(dot / denominator)
    }

    // MARK: - Internals

    private func embed(text: String) -> [Float]? {
        let trimmed = String(text.prefix(Self.maxTextCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch model {
        case .contextualLatin512:
            return embedContextual(trimmed)
        case .sentenceSpanish640:
            guard let sentence else { return nil }
            return sentence.vector(for: trimmed)?.map { Float($0) }
        }
    }

    private func embedContextual(_ text: String) -> [Float]? {
        guard #available(macOS 14.0, *) else { return nil }
        if contextual == nil, !contextualLoadFailed {
            if let ctx = NLContextualEmbedding(script: .latin) {
                do {
                    try ctx.load()
                    contextual = ctx
                } catch {
                    contextualLoadFailed = true
                    J4Log.warn(.index, "No se pudieron cargar los embeddings contextuales: \(error.localizedDescription)")
                    return nil
                }
            } else {
                contextualLoadFailed = true
                return nil
            }
        }
        guard let ctx = contextual,
              let result = try? ctx.embeddingResult(for: text, language: .spanish) else {
            return nil
        }

        // Pooling medio por palabra (una llamada por token, no por carácter).
        var sum = [Float](repeating: 0, count: dimension)
        var tokenCount = 0
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if let token = result.tokenVector(at: range.lowerBound), token.0.count == sum.count {
                for (index, value) in token.0.enumerated() {
                    sum[index] += Float(value)
                }
                tokenCount += 1
            }
            return true
        }
        guard tokenCount > 0 else { return nil }
        let divisor = Float(tokenCount)
        for index in sum.indices { sum[index] /= divisor }
        return sum
    }
}
