import Foundation

/// Construcción de direcciones de la API a partir de la base configurada.
///
/// Vive aparte para que el servidor elegido por la persona pueda ser cualquier
/// cosa (el dominio público, la IP de la red local, un puerto de pruebas) sin
/// que ninguna ruta quede escrita a mano en la interfaz.
public enum LifeOSEndpoint {
    public static func url(base: URL, path: String, query: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        return components.url
    }

    /// Dirección de autorización de Google para un cliente nativo.
    public static func googleAuthorizeURL(base: URL) -> URL? {
        url(base: base, path: "/api/v1/auth/google/authorize", query: [
            URLQueryItem(name: "native", value: "true")
        ])
    }
}
