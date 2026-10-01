import Foundation

import LifeOSAPI

/// Diagnóstico del servidor al que apunta la app.
///
/// Sirve para dos cosas que se parecen: **comprobar una instalación nueva** (¿está
/// bien la dirección?, ¿tengo sesión?) y **ver por qué una pantalla no funciona**
/// contra un servidor que no es el de desarrollo. Lo importante es que distingue
/// los tres casos: «este servidor no tiene el endpoint» (versión antigua), «me
/// falta entrar» y «contesta algo que la app no entiende» (el bug de verdad).
public struct DoctorCheck: Identifiable, Sendable, Equatable {
    public enum Level: Sendable, Equatable {
        case ok
        case warning
        case failure

        public var symbol: String {
            switch self {
            case .ok: return "✓"
            case .warning: return "•"
            case .failure: return "✗"
            }
        }
    }

    public let id: String
    public let title: String
    public let level: Level
    public let detail: String

    public init(id: String, title: String, level: Level, detail: String) {
        self.id = id
        self.title = title
        self.level = level
        self.detail = detail
    }
}

public struct ServerDoctor: Sendable {
    /// Una pantalla de la app: su endpoint y cómo sondearlo.
    private struct Surface: Sendable {
        let title: String
        let path: String
        let probe: @Sendable (APIClient) async -> ProbeResult

        init(title: String, path: String, query: [URLQueryItem] = [], model: any (Decodable & Sendable).Type) {
            self.title = title
            self.path = path
            if let query = query.isEmpty ? nil : query {
                self.probe = { client in await client.probeAny(model, path: path, query: query) }
            } else {
                self.probe = { client in await client.probeAny(model, path: path) }
            }
        }

        /// Para lo que exige parámetros **calculados al vuelo** (la agenda quiere
        /// `start` y `end`, y no valen los del día en que se escribió esto).
        init(
            title: String,
            path: String,
            queryProvider: @escaping @Sendable () -> [URLQueryItem],
            model: any (Decodable & Sendable).Type
        ) {
            self.title = title
            self.path = path
            self.probe = { client in
                let query = queryProvider()
                guard !query.isEmpty else { return await client.probeAny(model, path: path) }
                return await client.probeAny(model, path: path, query: query)
            }
        }
    }

    private static let surfaces: [Surface] = [
        Surface(title: "Perfil", path: "/api/v1/auth/me", model: LifeOSUser.self),
        Surface(title: "Cierre del día", path: "/api/v1/day-close", model: DayClose.self),
        Surface(title: "Avisos", path: "/api/v1/reminders/upcoming", model: UpcomingReminders.self),
        Surface(
            title: "Agenda",
            path: "/api/v1/agenda",
            queryProvider: {
                let week = AgendaRange.week(containing: Date())
                return APIClient.agendaQuery(from: week.start, to: week.end)
            },
            model: AgendaDay.self
        ),
        Surface(title: "Bandeja", path: "/api/v1/captures", model: [CaptureDetail].self),
        Surface(title: "Diario", path: "/api/v1/journal", model: [JournalEntry].self),
        Surface(
            title: "Candidatos de mención",
            path: "/api/v1/journal/reference-candidates",
            model: [JournalReferenceCandidate].self
        ),
        Surface(title: "Acciones", path: "/api/v1/tasks", model: [LifeOSTask].self),
        Surface(title: "Cronología", path: "/api/v1/timeline", model: Timeline.self),
        Surface(
            title: "Buscar",
            path: "/api/v1/search",
            query: [URLQueryItem(name: "q", value: "prueba")],
            model: SearchResults.self
        )
    ]

    /// Endpoints que la app necesita y que pueden no estar en un servidor antiguo.
    static let requiredPaths = [
        "/api/v1/day-close",
        "/api/v1/reminders/upcoming",
        "/api/v1/captures",
        "/api/v1/journal",
        "/api/v1/journal/reference-candidates",
        "/api/v1/tasks",
        "/api/v1/agenda",
        "/api/v1/timeline",
        "/api/v1/search",
        "/api/v1/captures/audio",
        "/api/v1/entities/{entity_id}"
    ]

    /// Corre las comprobaciones en orden y devuelve la lista para enseñarla.
    public static func run(
        baseURL: URL,
        token: String?,
        session: URLSession = .shared,
        userAgent: String = APIClient.defaultUserAgent
    ) async -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        let client = APIClient(baseURL: baseURL, token: token, session: session, userAgent: userAgent)

        // 1) Dirección y salud.
        let health = await client.probe(HealthStatus.self, path: "/health/ready")
        switch health.outcome {
        case .ok:
            checks.append(DoctorCheck(
                id: "salud",
                title: "El servidor responde",
                level: .ok,
                detail: "\(baseURL.absoluteString) · \(health.summary)"
            ))
        case .transport(let detail):
            checks.append(DoctorCheck(
                id: "salud",
                title: "No se puede hablar con el servidor",
                level: .failure,
                detail: "\(detail). Revisa la dirección y, si es HTTPS, el certificado."
            ))
            return checks
        case .http(let status):
            if status == 404 {
                checks.append(DoctorCheck(
                    id: "salud",
                    title: "El servidor responde, pero sin /health/ready",
                    level: .warning,
                    detail: "HTTP 404. Puede ser una versión antigua; se sigue comprobando."
                ))
            } else {
                checks.append(DoctorCheck(
                    id: "salud",
                    title: "Salud del servidor con problemas",
                    level: .warning,
                    detail: health.summary
                ))
            }
        case .contract(let detail):
            checks.append(DoctorCheck(
                id: "salud",
                title: "El servidor responde, pero /health/ready no se entiende",
                level: .warning,
                detail: detail
            ))
        }

        // 2) Qué versión del servidor hay al otro lado (sus endpoints declarados).
        switch await client.openAPIPaths() {
        case .paths(let paths):
            let missing = requiredPaths.filter { required in
                !paths.contains(required) && !paths.contains(required.replacingOccurrences(of: "/{entity_id}", with: "/") + "{entity_id}")
            }
            if missing.isEmpty {
                checks.append(DoctorCheck(
                    id: "endpoints",
                    title: "Ese servidor tiene todo lo que la app usa",
                    level: .ok,
                    detail: "\(paths.count) endpoints declarados en /openapi.json"
                ))
            } else {
                checks.append(DoctorCheck(
                    id: "endpoints",
                    title: "A ese servidor le faltan endpoints que la app usa",
                    level: .failure,
                    detail: "Faltan: \(missing.joined(separator: ", ")). Suele ser una versión más antigua: hay que desplegar el servidor."
                ))
            }
            // El flujo nativo de acceso es lo que decide cómo se entra.
            if paths.contains("/api/v1/auth/native/login") {
                checks.append(DoctorCheck(
                    id: "acceso",
                    title: "Acceso nativo disponible",
                    level: .ok,
                    detail: "El botón de Google y el usuario/contraseña usan el flujo nativo."
                ))
            } else {
                checks.append(DoctorCheck(
                    id: "acceso",
                    title: "Sin acceso nativo (le falta el parche al servidor)",
                    level: .warning,
                    detail: "La app entrará con usuario y contraseña como la web. Google necesita desplegar el parche."
                ))
            }
        case .unavailable(let detail):
            // Sin documento del contrato (en producción no está publicado), se
            // pregunta endpoint por endpoint **sin sesión**: un 401 quiere decir
            // «existe, pero hay que entrar» y un 404 «esa versión no lo tiene».
            checks.append(contentsOf: await existenceChecks(client: client, reason: detail))
            checks.append(await accessCheck(client: client))
        }

        // 3) Sesión.
        guard let token, !token.isEmpty else {
            checks.append(DoctorCheck(
                id: "sesion",
                title: "Sin sesión guardada",
                level: .warning,
                detail: "Entra con usuario y contraseña (o con Google, si el servidor lo tiene) para probar los datos."
            ))
            return checks
        }

        // 4) ¿La sesión vale en ese servidor? El token es de un servidor concreto.
        let me = await client.probe(LifeOSUser.self, path: "/api/v1/auth/me")
        switch me.outcome {
        case .ok:
            checks.append(DoctorCheck(
                id: "sesion",
                title: "La sesión vale en ese servidor",
                level: .ok,
                detail: "El token guardado se acepta aquí."
            ))
        case .http(let status) where status == 401 || status == 403:
            checks.append(DoctorCheck(
                id: "sesion",
                title: "La sesión guardada no vale en ese servidor",
                level: .warning,
                detail: "HTTP \(status). Normal si el token es de otro servidor (el local): entra otra vez."
            ))
            return checks
        default:
            checks.append(DoctorCheck(
                id: "sesion",
                title: "No se pudo comprobar la sesión",
                level: .warning,
                detail: me.summary
            ))
            return checks
        }

        // 5) Cada pantalla, contra el servidor de verdad.
        for surface in surfaces where surface.title != "Perfil" {
            let result = await surface.probe(client)
            checks.append(describe(result, surface: surface))
        }

        return checks
    }

    private static func describe(_ result: ProbeResult, surface: Surface) -> DoctorCheck {
        switch result.outcome {
        case .ok:
            return DoctorCheck(id: surface.path, title: surface.title, level: .ok, detail: result.summary)
        case .http(let status) where status == 401 || status == 403:
            return DoctorCheck(
                id: surface.path,
                title: surface.title,
                level: .failure,
                detail: "HTTP \(status): el servidor no acepta la sesión."
            )
        case .http(let status) where status == 404:
            return DoctorCheck(
                id: surface.path,
                title: surface.title,
                level: .failure,
                detail: "HTTP 404: ese servidor no tiene \(surface.path)."
            )
        case .http(let status):
            return DoctorCheck(
                id: surface.path,
                title: surface.title,
                level: .failure,
                detail: "HTTP \(status). Mira el registro del servidor para ver el detalle."
            )
        case .contract(let detail):
            return DoctorCheck(
                id: surface.path,
                title: surface.title,
                level: .failure,
                detail: "El servidor contesta, pero la app no lo entiende: \(detail)"
            )
        case .transport(let detail):
            return DoctorCheck(
                id: surface.path,
                title: surface.title,
                level: .failure,
                detail: "Sin conexión: \(detail)"
            )
        }
    }

    /// ¿Tiene el servidor el flujo nativo de acceso? Se pregunta directamente,
    /// porque en producción no hay `/openapi.json` que leer.
    private static func accessCheck(client: APIClient) async -> DoctorCheck {
        // El endpoint solo acepta POST: si existe, un GET devuelve 405.
        switch await client.status(path: "/api/v1/auth/native/login") {
        case .some(405), .some(401), .some(422):
            return DoctorCheck(
                id: "acceso",
                title: "Acceso nativo disponible",
                level: .ok,
                detail: "El servidor tiene /auth/native/login: sirven el botón de Google y el usuario/contraseña."
            )
        case .some(404):
            return DoctorCheck(
                id: "acceso",
                title: "Sin acceso nativo (le falta el parche al servidor)",
                level: .warning,
                detail: "La app entrará con usuario y contraseña como la web. Google necesita desplegar el parche."
            )
        case .some(let status):
            return DoctorCheck(
                id: "acceso",
                title: "No se pudo saber si el acceso nativo está",
                level: .warning,
                detail: "HTTP \(status) en /auth/native/login."
            )
        case .none:
            return DoctorCheck(
                id: "acceso",
                title: "No se pudo comprobar el acceso nativo",
                level: .warning,
                detail: "Sin respuesta de /auth/native/login."
            )
        }
    }

    /// Sondea, **sin sesión**, qué endpoints tiene el servidor de verdad.
    private static func existenceChecks(client: APIClient, reason: String) async -> [DoctorCheck] {
        var missing: [String] = []
        var present = 0
        var unreachable = 0

        for path in requiredPaths {
            let probePath = path.replacingOccurrences(of: "/{entity_id}", with: "/00000000-0000-0000-0000-000000000000")
            switch await client.status(path: probePath) {
            case .none:
                unreachable += 1
            case .some(404):
                missing.append(path)
            case .some(405):
                // Existe pero no acepta GET (raro en esta API): cuenta como que está.
                present += 1
            case .some(200), .some(401), .some(403), .some(422):
                present += 1
            case .some:
                present += 1
            }
        }

        var checks: [DoctorCheck] = []
        if !missing.isEmpty {
            checks.append(DoctorCheck(
                id: "endpoints",
                title: "A ese servidor le faltan endpoints que la app usa",
                level: .failure,
                detail: "No están: \(missing.joined(separator: ", ")). Es una versión más antigua que la app: hay que desplegar el servidor."
            ))
        } else if unreachable > 0 {
            checks.append(DoctorCheck(
                id: "endpoints",
                title: "No se pudieron comprobar todos los endpoints",
                level: .warning,
                detail: "\(present) están y de \(unreachable) no hubo respuesta. (\(reason))"
            ))
        } else {
            checks.append(DoctorCheck(
                id: "endpoints",
                title: "Ese servidor tiene todo lo que la app usa",
                level: .ok,
                detail: "\(present) endpoints comprobados sin sesión (responden pidiendo entrar)."
            ))
        }
        return checks
    }

    /// Resumen en una línea, para la cabecera del diagnóstico.
    public static func summary(_ checks: [DoctorCheck]) -> String {
        let failures = checks.filter { $0.level == .failure }.count
        let warnings = checks.filter { $0.level == .warning }.count
        if failures > 0 {
            return failures == 1 ? "1 problema" : "\(failures) problemas"
        }
        if warnings > 0 {
            return warnings == 1 ? "1 aviso" : "\(warnings) avisos"
        }
        return "todo bien"
    }
}

/// Respuesta de `/health/ready`. Solo hace falta que sea legible.
public struct HealthStatus: Decodable, Sendable {
    public let status: String?
}
