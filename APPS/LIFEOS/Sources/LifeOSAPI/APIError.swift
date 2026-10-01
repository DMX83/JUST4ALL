import Foundation

/// Errores que la interfaz puede contar tal cual.
///
/// La API de LifeOS responde los fallos como `application/problem+json`
/// (`title`, `detail`, `status`), así que el mensaje del servidor se conserva en
/// lugar de sustituirlo por uno genérico: «Google necesita que vuelvas a
/// conectar la cuenta» es información útil, no ruido técnico.
public enum APIError: Error, LocalizedError, Sendable {
    case invalidBaseURL(String)
    case transport(String)
    case server(status: Int, title: String, detail: String)
    case decoding(String)
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let raw):
            return "La dirección del servidor no es válida: \(raw)"
        case .transport(let message):
            return "No se pudo conectar con LifeOS: \(message)"
        case .server(let status, let title, let detail):
            let message = detail.isEmpty ? title : detail
            if status == 429 {
                return "Demasiados intentos. Espera unos minutos y vuelve a probar. (\(message))"
            }
            return message.isEmpty ? "El servidor respondió \(status)" : message
        case .decoding(let message):
            return "La respuesta de LifeOS no tiene el formato esperado: \(message)"
        case .notAuthenticated:
            return "La sesión ha caducado. Vuelve a iniciar sesión."
        }
    }

    public var isNotAuthenticated: Bool {
        switch self {
        case .notAuthenticated:
            return true
        case .server(let status, _, _):
            return status == 401
        default:
            return false
        }
    }

    /// El servidor todavía no tiene el flujo de cliente nativo desplegado
    /// (versiones anteriores no exponen `/api/v1/auth/native/*`).
    public var isMissingNativeSupport: Bool {
        switch self {
        case .server(let status, _, _):
            return status == 404 || status == 405
        default:
            return false
        }
    }

    /// Ya existe un documento con ese mismo contenido en el espacio.
    ///
    /// No es un fallo: es el servidor evitando duplicados, y merece un mensaje
    /// que lo diga así («ya estaba») en vez de un error rojo.
    public var isDuplicateDocument: Bool {
        switch self {
        case .server(let status, _, _):
            return status == 409
        default:
            return false
        }
    }

    /// Mensaje de problema devuelto por FastAPI, si lo hay.
    static func from(status: Int, data: Data) -> APIError {
        struct Problem: Decodable {
            let title: String?
            let detail: String?
        }
        if let problem = try? JSONDecoder().decode(Problem.self, from: data) {
            return .server(
                status: status,
                title: problem.title ?? "",
                detail: problem.detail ?? ""
            )
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return .server(status: status, title: "", detail: text.prefix(300).description)
    }
}
