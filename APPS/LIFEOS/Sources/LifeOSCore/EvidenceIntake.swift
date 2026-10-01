import Foundation

/// Lo que alguien manda a LifeOS desde fuera de la app: un texto seleccionado, un
/// fichero arrastrado, algo abierto con la app.
public enum Incoming: Sendable, Hashable {
    case text(String)
    /// Fichero con su tamaño ya medido (si no se pudo medir, `nil`).
    case file(URL, size: Int?)
}

/// Qué hacer con lo que llega.
///
/// Se decide **antes de salir a la red** para poder dar un mensaje de persona en
/// vez de un 422 del servidor. Y vive aquí, fuera de las vistas, para poder
/// probarlo sin app ni servidor.
public enum IntakePlan: Equatable, Sendable {
    /// Va como anotación: el servidor la clasificará y pedirá revisión.
    case capture(text: String)
    /// Va como documento (texto extraído e indexado).
    case upload(file: URL, filename: String, mimeType: String)
    /// No se puede guardar tal cual. `note` es una salida digna, si la hay: la
    /// ruta del fichero como anotación, para no perder el rastro.
    case refuse(reason: String, note: String?)
}

public enum EvidenceIntake {
    /// Lo que acepta `POST /documents/upload`. Son los mismos que el extractor
    /// del servidor: si aquí se colara uno más, el usuario vería un 422 seco.
    public static let allowedExtensions: Set<String> = ["pdf", "docx", "txt", "md"]

    /// `MAX_DOCUMENT_BYTES` del servidor.
    public static let maxDocumentBytes = 20 * 1024 * 1024

    /// `CaptureCreate.content` admite 10 000 caracteres como mucho.
    public static let maxCaptureCharacters = 10_000

    public static func plan(for incoming: Incoming) -> IntakePlan {
        switch incoming {
        case .text(let raw):
            return planForText(raw)
        case .file(let url, let size):
            return planForFile(url, size: size)
        }
    }

    // MARK: - Texto

    static func planForText(_ raw: String) -> IntakePlan {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .refuse(reason: "No había nada que enviar.", note: nil)
        }
        guard text.count <= maxCaptureCharacters else {
            return .refuse(
                reason: """
                    Son \(text.count) caracteres y una anotación admite \
                    \(maxCaptureCharacters). Manda un trozo más corto, o guárdalo como documento \
                    (PDF, Word, texto o Markdown).
                    """,
                note: nil
            )
        }
        return .capture(text: text)
    }

    // MARK: - Ficheros

    static func planForFile(_ url: URL, size: Int?) -> IntakePlan {
        let filename = url.lastPathComponent
        guard url.isFileURL else {
            return .refuse(reason: "Eso no es un fichero del Mac, así que no se puede subir.", note: nil)
        }
        let extensionName = url.pathExtension.lowercased()
        guard allowedExtensions.contains(extensionName) else {
            return .refuse(
                reason: """
                    LifeOS guarda PDF, Word (.docx), texto y Markdown. \
                    «\(filename)» no es de esos tipos.
                    """,
                note: url.path
            )
        }
        if let size, size > maxDocumentBytes {
            return .refuse(reason: tooBigMessage(filename: filename, size: size), note: url.path)
        }
        if let size, size == 0 {
            return .refuse(reason: "«\(filename)» está vacío.", note: nil)
        }
        return .upload(file: url, filename: filename, mimeType: mimeType(for: extensionName))
    }

    // MARK: - Mensajes

    /// «Pesa demasiado», dicho de forma que **no se contradiga**.
    ///
    /// Ojo con este detalle, que ya mordió una vez: redondeando, un fichero de un
    /// byte por encima del límite se formatea igual que el límite, y el mensaje
    /// salía «pesa 21 MB y el máximo son 21 MB». Cuando el redondeo empata, se
    /// dice solo que se pasa.
    static func tooBigMessage(filename: String, size: Int) -> String {
        let peso = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .binary)
        let limite = ByteCountFormatter.string(fromByteCount: Int64(maxDocumentBytes), countStyle: .binary)
        let cola = "Puedes reducirlo o partirlo en dos."
        guard peso != limite else {
            return "«\(filename)» supera el máximo de \(limite) por documento. \(cola)"
        }
        return "«\(filename)» pesa \(peso) y el máximo son \(limite) por documento. \(cola)"
    }

    /// El mismo `mime_type` que deduce el servidor al extraer el texto.
    static func mimeType(for extensionName: String) -> String {
        switch extensionName {
        case "pdf": return "application/pdf"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "md", "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }

    /// El nombre que se le da al documento al abrirlo o al arrastrarlo (el
    /// servidor usa el nombre del fichero si no se le da título).
    public static func title(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}
