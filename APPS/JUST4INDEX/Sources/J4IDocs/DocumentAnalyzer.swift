import Foundation
import CryptoKit
import J4ICore

/// Análisis local de un documento: hash SHA-256 + extracción de texto + metadatos deterministas.
public enum DocumentAnalyzer {
    public static let defaultSampleCharacters = 4000
    public static let defaultIndexTextLimit = 50_000

    public static func analyze(url: URL, sampleCharacters: Int = defaultSampleCharacters) -> DocumentProfile? {
        let standardized = url.standardizedFileURL
        guard let values = try? standardized.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true else {
            return nil
        }
        guard let hash = sha256Hex(of: standardized) else { return nil }

        // La extracción puede no ser posible (binarios, instaladores, vídeo…): en ese caso se
        // genera igualmente un perfil «lite» (hash + nombre + metadatos) para poder clasificar
        // por nombre y extensión en vez de dejar el fichero sin procesar.
        let extraction = TextExtractor.extract(from: standardized)
        let extractedText = extraction?.text ?? ""
        let scanWindow = String(extractedText.prefix(50_000))
        let scan = MetadataScanner.scan(text: scanWindow)

        if let extraction {
            J4Log.debug(.extract, "Extracción de «\(standardized.lastPathComponent)»: \(extractedText.count) caracteres, \(extraction.pageCount.map { String($0) } ?? "-") página(s), OCR: \(extraction.usedOCR ? "sí" : "no"), capa de texto: \(extraction.hasTextLayer ? "sí" : "no").")
        } else {
            J4Log.debug(.extract, "Sin texto extraíble de «\(standardized.lastPathComponent)»: se clasificará por nombre y metadatos.")
        }

        return DocumentProfile(
            fileName: standardized.lastPathComponent,
            fileExtension: standardized.pathExtension.lowercased(),
            fileSizeBytes: Int64(values.fileSize ?? 0),
            contentHash: hash,
            hasTextLayer: extraction?.hasTextLayer ?? false,
            usedOCR: extraction?.usedOCR ?? false,
            pageCount: extraction?.pageCount,
            textLength: extractedText.count,
            textSample: String(extractedText.prefix(sampleCharacters)),
            dates: scan.dates,
            amounts: scan.amounts,
            identifiers: scan.identifiers,
            analyzedAt: Date()
        )
    }

    /// Texto extraído (limitado) para almacenar en el índice de búsqueda por contenido.
    public static func extractedText(from url: URL, limit: Int = defaultIndexTextLimit) -> String? {
        guard let extraction = TextExtractor.extract(from: url, maxCharacters: limit) else { return nil }
        let trimmed = extraction.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func sha256Hex(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
