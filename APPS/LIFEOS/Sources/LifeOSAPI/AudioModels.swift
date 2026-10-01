import Foundation

// Voz: el audio se sube y **el servidor lo transcribe**.
//
// Así se esquiva la latencia de transcribir en el Mac (se midió con Whisper local
// y no daba). Y hay una regla que importa: si la captura es **sensible**, el
// servidor guarda el audio pero **no lo transcribe** (no sale a ningún proveedor).

public struct AudioCapture: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let status: String
    /// El texto transcrito, si se transcribió.
    public let transcript: String?
    /// `true` si el audio se ha guardado tal cual (caso sensible).
    public let originalPreserved: Bool

    /// Guardado sin transcribir a propósito (contenido sensible).
    public var isStoredOnly: Bool { status == "stored_sensitive" }

    /// La transcripción no se pudo hacer (proveedor caído o sin configurar).
    public var didFailTranscription: Bool { status == "transcription_failed" }

    /// Está en la bandeja esperando confirmación, como cualquier captura.
    public var isPending: Bool { status == "pending" }

    public var statusLabel: String {
        switch status {
        case "stored_sensitive": return "Guardado sin transcribir (privado)"
        case "transcription_failed": return "No se pudo transcribir"
        case "pending": return "En la bandeja, por clasificar"
        case "transcribing": return "Transcribiendo…"
        default: return status
        }
    }
}
