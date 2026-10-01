import Foundation

/// Resultado de una petición hecha **para diagnosticar**, no para usar.
///
/// Es distinto de un error normal: aquí interesa saber qué pasó exactamente.
/// Un 404 significa «este servidor no tiene ese endpoint» (versión antigua), un
/// 401 significa «falta entrar», un 200 que no decodifica significa «el servidor
/// y la app no se entienden» (que es el bug de verdad), y un 200 que decodifica
/// es «todo bien». Confundirlos dejaría el diagnóstico en un «algo falló».
public struct ProbeResult: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        /// 2xx y el JSON encaja con lo que la app espera.
        case ok
        /// Respondió, pero con un estado que no es 2xx.
        case http(Int)
        /// 2xx pero el cuerpo no se puede leer con los modelos de la app.
        case contract(String)
        /// No se pudo hablar con el servidor.
        case transport(String)
    }

    public let outcome: Outcome
    public let milliseconds: Int

    public var isOK: Bool { outcome == .ok }

    public var summary: String {
        switch outcome {
        case .ok:
            return "bien (\(milliseconds) ms)"
        case .http(let status):
            return "HTTP \(status)"
        case .contract(let detail):
            return "el servidor contesta algo que la app no entiende: \(detail)"
        case .transport(let detail):
            return "sin conexión: \(detail)"
        }
    }
}

/// Lo que se pudo leer del contrato del servidor. `Result` obliga a que el fallo
/// sea un `Error`, y aquí el fallo es un texto para enseñar, sin más.
public enum OpenAPIDocument: Sendable, Equatable {
    case paths(Set<String>)
    case unavailable(String)
}

extension APIClient {
    /// Estado HTTP de un endpoint **sin sesión**, solo para saber si existe.
    ///
    /// Es la clave para mirar un servidor sin credenciales: si responde 401 es que
    /// existe y pide sesión, y si responde 404 esa versión no lo tiene. Devolver
    /// `nil` es «ni se pudo preguntar».
    public func status(path: String) async -> Int? {
        do {
            let (response, _) = try await diagnosticRequest("GET", path: path, authenticated: false)
            return response.statusCode
        } catch {
            return nil
        }
    }

    /// Igual que `probe`, para un modelo que solo se conoce como existencial
    /// (`any Decodable.Type`): el diagnóstico los guarda en una tabla.
    public func probeAny(
        _ type: any (Decodable & Sendable).Type,
        path: String,
        query: [URLQueryItem] = []
    ) async -> ProbeResult {
        let started = Date()
        do {
            let (response, data) = try await diagnosticRequest("GET", path: path, query: query)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            guard (200..<300).contains(response.statusCode) else {
                return ProbeResult(outcome: .http(response.statusCode), milliseconds: elapsed)
            }
            do {
                _ = try LifeOSJSON.decoder().decode(type, from: data)
                return ProbeResult(outcome: .ok, milliseconds: elapsed)
            } catch {
                return ProbeResult(
                    outcome: .contract(String(describing: error).prefix(240).description),
                    milliseconds: elapsed
                )
            }
        } catch let error as APIError {
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            if case .server(let status, _, _) = error {
                return ProbeResult(outcome: .http(status), milliseconds: elapsed)
            }
            return ProbeResult(outcome: .transport(error.errorDescription ?? "error"), milliseconds: elapsed)
        } catch {
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            return ProbeResult(outcome: .transport(error.localizedDescription), milliseconds: elapsed)
        }
    }

    /// Hace la petición y comprueba **las dos cosas**: el estado y que el JSON
    /// encaje con el modelo de la app. Para el diagnóstico, las dos importan.
    public func probe<T: Decodable>(
        _ type: T.Type,
        path: String,
        query: [URLQueryItem] = []
    ) async -> ProbeResult {
        let started = Date()
        do {
            let (response, data) = try await diagnosticRequest("GET", path: path, query: query)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            guard (200..<300).contains(response.statusCode) else {
                return ProbeResult(outcome: .http(response.statusCode), milliseconds: elapsed)
            }
            do {
                _ = try LifeOSJSON.decoder().decode(T.self, from: data)
                return ProbeResult(outcome: .ok, milliseconds: elapsed)
            } catch {
                return ProbeResult(
                    outcome: .contract(String(describing: error).prefix(240).description),
                    milliseconds: elapsed
                )
            }
        } catch let error as APIError {
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            if case .server(let status, _, _) = error {
                return ProbeResult(outcome: .http(status), milliseconds: elapsed)
            }
            return ProbeResult(outcome: .transport(error.errorDescription ?? "error"), milliseconds: elapsed)
        } catch {
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            return ProbeResult(outcome: .transport(error.localizedDescription), milliseconds: elapsed)
        }
    }

    /// Los endpoints que declara el servidor, leídos de su `/openapi.json`.
    ///
    /// Sirve para saber **qué versión** del servidor hay al otro lado sin tener
    /// que probar pantalla por pantalla: si falta `/api/v1/journal`, esa versión
    /// es más antigua que la app.
    public func openAPIPaths() async -> OpenAPIDocument {
        do {
            let (response, data) = try await diagnosticRequest("GET", path: "/openapi.json")
            guard (200..<300).contains(response.statusCode) else {
                return .unavailable("HTTP \(response.statusCode) en /openapi.json")
            }
            struct Document: Decodable {
                let paths: [String: JSONValue]
            }
            do {
                let document = try LifeOSJSON.decoder().decode(Document.self, from: data)
                return .paths(Set(document.paths.keys))
            } catch {
                return .unavailable("el /openapi.json no se puede leer: \(String(describing: error).prefix(160))")
            }
        } catch let error as APIError {
            return .unavailable(error.errorDescription ?? "error")
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }
}
