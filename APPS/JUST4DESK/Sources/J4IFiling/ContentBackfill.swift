import Foundation
import J4ICore
import J4IDocs
import J4IIndex

/// G7.3 — Re-extracción de contenido.
///
/// Vuelve a extraer el texto de documentos que quedaron sin `doc_text` (p. ej. los textos que
/// perdieron su vínculo en reindexados anteriores a G7). Los intentos sin texto útil se marcan
/// con una fila vacía en `doc_text` para no repetir OCR/extracción en cada arranque.
///
/// Usa el mismo extractor que el pipeline de archivado (`DocumentAnalyzer`/`TextExtractor`:
/// PDFKit + OCR de respaldo, texto plano, rtf y docx) y el mismo tope de texto indexado.
public enum ContentBackfill {
    /// Extensiones con extractor local disponible.
    public static let supportedExtensions: [String] = ["pdf", "txt", "md", "csv", "rtf", "docx"]

    public struct Outcome: Sendable, Equatable {
        public let extracted: Int
        public let empty: Int
        public let missing: Int

        public var processed: Int { extracted + empty + missing }
    }

    /// Procesa hasta `limit` candidatos en lotes pequeños. `cancelled` se consulta entre ficheros.
    public static func runOnce(
        index: SearchIndex,
        limit: Int = 400,
        batchSize: Int = 24,
        cancelled: @escaping @Sendable () -> Bool = { false }
    ) async -> Outcome {
        var extracted = 0
        var empty = 0
        var missing = 0
        var processedTotal = 0

        while processedTotal < limit, !cancelled() {
            let batchSizeThisRound = min(batchSize, limit - processedTotal)
            let batch = (try? await index.contentCandidates(
                extensions: supportedExtensions,
                limit: batchSizeThisRound
            )) ?? []
            if batch.isEmpty { break }

            for candidate in batch {
                if cancelled() { break }
                let url = URL(fileURLWithPath: candidate.path)
                guard FileManager.default.fileExists(atPath: candidate.path) else {
                    missing += 1
                    try? await index.markContentAttempted(entryID: candidate.entryID)
                    continue
                }
                let text = DocumentAnalyzer.extractedText(from: url)
                if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try? await index.setDocumentText(entryID: candidate.entryID, text: text)
                    extracted += 1
                } else {
                    empty += 1
                    try? await index.markContentAttempted(entryID: candidate.entryID)
                }
            }

            processedTotal += batch.count
            J4Log.debug(.index, "Contenido: \(extracted) re-extraído(s) · \(empty) sin texto · \(missing) ausente(s)…")
        }

        return Outcome(extracted: extracted, empty: empty, missing: missing)
    }
}
