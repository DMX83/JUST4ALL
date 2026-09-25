import Foundation

/// Punto de entrada de metadatos del módulo J4IDocs.
/// J4IDocs alberga la extracción y análisis local de documentos:
/// PDFKit (texto), Vision OCR (escaneados), txt/md/rtf, docx/xlsx básico y
/// extracción determinista de metadatos (fechas, NIF/CIF, IBAN, importes).
public enum J4IDocsBootstrap {
    public static let moduleName = "J4IDocs"
    public static let version = "0.1.0"
}
