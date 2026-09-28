import Foundation
import J4ICore
import J4IDocs
import J4IIndex

/// G7.2 — Servicio del archivo para agentes (MCP): búsqueda y lectura sobre el índice local.
///
/// Solo lectura: no mueve, no escribe nada del archivo. La búsqueda es la misma que usa la app
/// (FTS5 + rescate por sinónimos en español); la lectura prefiere el texto ya indexado y, si no
/// lo hay, extrae al momento con el extractor local (PDFKit/OCR, texto, rtf, docx).
public struct ArchiveSearchResult: Sendable {
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let modifiedAt: Date?
    public let matchedContent: Bool
    public let snippet: String?
}

public actor ArchiveService {
    private let index: SearchIndex
    private var expander: QueryExpander?
    private var expanderInitAttempted = false

    public init(index: SearchIndex) {
        self.index = index
    }

    /// Busca por nombre/ruta/contenido. Si el resultado estricto es escaso, reintenta con la
    /// expresión OR + sinónimos (igual que el chat). Nunca devuelve carpetas.
    public func search(
        _ query: String,
        limit: Int = 12,
        includeContent: Bool = true
    ) async -> [ArchiveSearchResult] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let cap = max(1, min(limit, 50))

        var hits = (try? await index.search(
            IndexSearchRequest(query: term, limit: cap, includeContent: includeContent)
        )) ?? []
        if hits.count < 3, let expander = ensureExpander(),
           let retrieval = await expander.retrievalExpression(for: term) {
            let request = IndexSearchRequest(
                query: term,
                limit: cap,
                includeContent: includeContent,
                matchExpression: retrieval
            )
            let expanded = (try? await index.search(request)) ?? []
            if !expanded.isEmpty {
                hits = SemanticMerge.merge(keyword: hits, semantic: expanded, semanticLimit: cap, totalLimit: cap)
            }
        }
        hits = hits.filter { !$0.entry.isDirectory }
        return hits.map {
            ArchiveSearchResult(
                name: $0.entry.name,
                path: $0.entry.path,
                sizeBytes: $0.entry.sizeBytes,
                modifiedAt: $0.entry.modifiedAt,
                matchedContent: $0.matchedContent,
                snippet: $0.contentSnippet
            )
        }
    }

    /// Texto de un documento: primero el índice; si no hay, extracción al momento (mismo extractor
    /// local del pipeline). Admite `~` en la ruta.
    public func read(path: String, maxCharacters: Int = 6000) async -> (name: String, text: String, fromIndex: Bool)? {
        let normalized = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        if let entryID = try? await index.entryID(path: normalized),
           let text = try? await index.documentText(entryID: entryID),
           !text.isEmpty {
            return ((normalized as NSString).lastPathComponent, String(text.prefix(maxCharacters)), true)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        guard let text = DocumentAnalyzer.extractedText(from: URL(fileURLWithPath: normalized)), !text.isEmpty else {
            return nil
        }
        return ((normalized as NSString).lastPathComponent, String(text.prefix(maxCharacters)), false)
    }

    private func ensureExpander() -> QueryExpander? {
        if let expander { return expander }
        guard !expanderInitAttempted else { return nil }
        expanderInitAttempted = true
        let made = QueryExpander.make()
        expander = made
        return made
    }
}
