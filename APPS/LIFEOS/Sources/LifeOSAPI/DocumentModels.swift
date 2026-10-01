import Foundation

/// Un documento guardado en LifeOS.
///
/// Nace de subir un fichero (`POST /documents/upload`, `multipart/form-data`).
/// El servidor **extrae el texto** y lo indexa en segundo plano, así que el
/// documento se puede buscar desde la app en cuanto el índice termina.
///
/// Límites del servidor que conviene tener a mano: **20 MB**, y solo `.pdf`,
/// `.docx`, `.txt` y `.md`. Cualquier otra extensión responde 422, y un fichero
/// con el mismo contenido que otro ya subido responde **409** (no se duplica).
public struct LifeOSDocument: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let filename: String
    public let mimeType: String
    public let contentText: String
    public let sensitivity: String
    public let contentHash: String
    public let indexStatus: String

    /// Un documento sensible se guarda pero **no** se manda a ningún proveedor:
    /// se queda solo en el servidor.
    public var isLocalOnly: Bool { indexStatus == "local_only" || sensitivity == "sensitive" }

    /// Todavía no se puede buscar: el índice va por detrás.
    public var isIndexing: Bool { indexStatus == "pending" || indexStatus == "queued" }

    public var indexLabel: String {
        switch indexStatus {
        case "indexed": return "Listo para buscar"
        case "queued": return "En cola para indexar"
        case "pending": return "Pendiente de indexar"
        case "local_only": return "Solo en tu servidor"
        case "failed": return "No se pudo indexar"
        default: return indexStatus
        }
    }

    /// Lo que se enseña cuando el documento acaba de llegar.
    public var confirmation: String {
        if isLocalOnly {
            return "«\(filename)» guardado en LifeOS (sensible: no se envía a ningún proveedor)."
        }
        if isIndexing {
            return "«\(filename)» guardado en LifeOS. Se podrá buscar en cuanto termine de indexarse."
        }
        return "«\(filename)» guardado en LifeOS y listo para buscar."
    }
}
