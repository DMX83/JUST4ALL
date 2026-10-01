import Foundation

/// Caja para poder pasar cualquier `Encodable` a un método que necesita un tipo
/// concreto (`JSONEncoder` no acepta existenciales directamente).
struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ value: some Encodable) {
        encodeClosure = { encoder in try value.encode(to: encoder) }
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

/// Cliente HTTP de la API de LifeOS.
///
/// Es un `actor` porque la sesión cambia en caliente (iniciar sesión, cambiar de
/// servidor, cerrarla) y varias partes de la interfaz la usan a la vez.
///
/// Todo el tráfico va con `Authorization: Bearer <token>`, que la API acepta
/// además de su cookie de navegador (`current_user` en el servidor). Así la app
/// no depende de la semántica de cookies: funciona igual en HTTPS público que en
/// la red local.
public actor APIClient {
    public static let defaultUserAgent = "LifeOSMac/0.1.0 (macOS)"

    private var baseURL: URL
    private var token: String?
    private let session: URLSession
    private let userAgent: String
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        baseURL: URL,
        token: String? = nil,
        session: URLSession = .shared,
        userAgent: String = APIClient.defaultUserAgent
    ) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.userAgent = userAgent
        self.decoder = APIClient.makeDecoder()
        self.encoder = APIClient.makeEncoder()
    }

    // MARK: - Sesión

    public func setBaseURL(_ url: URL) {
        baseURL = url
    }

    public func currentBaseURL() -> URL { baseURL }

    public func setToken(_ value: String?) {
        token = value
    }

    public func currentToken() -> String? { token }

    // MARK: - Autenticación

    /// Acceso de cliente nativo (devuelve el token en el cuerpo).
    ///
    /// Requiere que el servidor tenga desplegado el flujo nativo
    /// (`/api/v1/auth/native/login`). Si no lo tiene, el llamante puede caer al
    /// acceso clásico con `legacyLogin`.
    public func nativeLogin(_ payload: NativeLoginRequest) async throws -> NativeSession {
        try await send(
            "POST",
            path: "/api/v1/auth/native/login",
            body: AnyEncodable(payload),
            authenticated: false
        )
    }

    /// Acceso clásico: usa el mismo endpoint que la web y recupera el token de la
    /// respuesta (cabecera `X-LifeOS-Session`, cabecera `Set-Cookie` o, en último
    /// término, el almacén de cookies de la sesión).
    ///
    /// Sirve contra servidores que aún no exponen el flujo nativo. Ojo: en
    /// producción la cookie es `Secure`, así que por HTTP en la red local no se
    /// guardaría; ahí el camino bueno es el flujo nativo.
    public func legacyLogin(username: String, password: String, mfaCode: String?) async throws -> String {
        let payload = LegacyLoginRequest(username: username, password: password, mfaCode: mfaCode)
        let (response, _) = try await sendRaw(
            "POST",
            path: "/api/v1/auth/login",
            body: AnyEncodable(payload),
            authenticated: false
        )
        if let header = response.value(forHTTPHeaderField: "X-LifeOS-Session"), !header.isEmpty {
            return header
        }
        if let cookie = response.value(forHTTPHeaderField: "Set-Cookie"),
           let token = APIClient.sessionToken(fromSetCookie: cookie) {
            return token
        }
        let storage = session.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        let cookies = storage.cookies(for: baseURL) ?? []
        if let cookie = cookies.first(where: { $0.name == APIClient.sessionCookieName }) {
            return cookie.value
        }
        throw APIError.server(
            status: 401,
            title: "",
            detail: "El servidor no devolvió la sesión (¿la dirección usa HTTPS?)"
        )
    }

    public static let sessionCookieName = "lifeos_session"

    /// Saca el token de una cabecera `Set-Cookie` sin depender del almacén de
    /// cookies: así funciona igual con HTTPS público y con HTTP en la red local.
    public static func sessionToken(fromSetCookie header: String) -> String? {
        let marker = sessionCookieName + "="
        guard let start = header.range(of: marker) else { return nil }
        let rest = header[start.upperBound...]
        let value = rest.prefix { $0 != ";" }.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Canjea el código de un solo uso que devuelve el retorno de Google.
    public func exchange(code: String) async throws -> NativeSession {
        try await send(
            "POST",
            path: "/api/v1/auth/native/exchange",
            body: AnyEncodable(ExchangeRequest(code: code)),
            authenticated: false
        )
    }

    public func me() async throws -> LifeOSUser {
        try await send("GET", path: "/api/v1/auth/me")
    }

    /// Empieza a **vincular** Google con la cuenta que ya tiene sesión.
    ///
    /// Devuelve la URL de Google (con su `state`): la app la abre en la ventana de
    /// autorización y el servidor vuelve a `lifeos://auth?linked=…`. Así, quien
    /// entró con Google por primera vez y acabó con una cuenta nueva y vacía
    /// puede hacer que *su* cuenta de siempre sea la que responde a ese Google.
    public func googleLinkStart() async throws -> GoogleLinkStart {
        try await send("POST", path: "/api/v1/auth/google/link")
    }

    public func logout() async throws {
        _ = try await sendRaw("POST", path: "/api/v1/auth/logout", authenticated: true)
    }

    /// Comprueba que el servidor responde, sin credenciales.
    public func probeServer() async throws {
        _ = try await sendRaw("GET", path: "/health/live", authenticated: false)
    }

    // MARK: - Hoy

    public func dayClose(date: String? = nil) async throws -> DayClose {
        var query: [URLQueryItem] = []
        if let date { query.append(URLQueryItem(name: "date", value: date)) }
        return try await send("GET", path: "/api/v1/day-close", query: query)
    }

    public func upcomingReminders() async throws -> UpcomingReminders {
        try await send("GET", path: "/api/v1/reminders/upcoming")
    }

    // MARK: - Capturas

    public func captures(status: String? = nil) async throws -> [CaptureDetail] {
        var query: [URLQueryItem] = []
        if let status { query.append(URLQueryItem(name: "status", value: status)) }
        return try await send("GET", path: "/api/v1/captures", query: query)
    }

    /// Estado de una captura concreta.
    ///
    /// Ojo: este endpoint devuelve `CaptureResponse` (sin `content`), a diferencia de
    /// `GET /captures`, que sí trae el detalle completo de cada una. Es una asimetría real
    /// del servidor y conviene no confundirlas.
    public func captureStatus(id: String) async throws -> CaptureSummary {
        try await send("GET", path: "/api/v1/captures/\(id)")
    }

    /// Crea una captura.
    ///
    /// La clave de idempotencia es obligatoria a propósito: es lo que permite
    /// reintentar una captura encolada sin conexión sin duplicarla, y el servidor
    /// ya la soporta.
    public func createCapture(
        content: String,
        sensitivity: String = "standard",
        idempotencyKey: String
    ) async throws -> CaptureSummary {
        try await send(
            "POST",
            path: "/api/v1/captures",
            body: AnyEncodable(CaptureRequest(content: content, sensitivity: sensitivity)),
            headers: ["Idempotency-Key": idempotencyKey]
        )
    }

    public func clarify(captureId: String, answer: String?, manualKind: String?) async throws -> CaptureSummary {
        try await send(
            "PATCH",
            path: "/api/v1/captures/\(captureId)",
            body: AnyEncodable(CaptureClarificationRequest(answer: answer, manualKind: manualKind))
        )
    }

    // MARK: - Documentos

    /// Sube un documento (`multipart/form-data`) y devuelve lo que guardó el
    /// servidor.
    ///
    /// Solo acepta `.pdf`, `.docx`, `.txt` y `.md` de hasta **20 MB** (el resto
    /// responde 422) y **no duplica**: si ya hay un documento con el mismo
    /// contenido en el espacio, responde **409**. Las dos cosas se comprueban
    /// antes en `EvidenceIntake` para poder dar un mensaje de persona.
    public func uploadDocument(
        data: Data,
        filename: String,
        mimeType: String = "application/octet-stream",
        title: String? = nil,
        sensitivity: String = "standard"
    ) async throws -> LifeOSDocument {
        let boundary = MultipartFormData.makeBoundary()
        var fields: [(name: String, value: String)] = [("sensitivity", sensitivity)]
        if let title, !title.isEmpty {
            fields.append((name: "title", value: title))
        }
        let body = MultipartFormData.build(
            boundary: boundary,
            fields: fields,
            file: (name: "file", filename: filename, mimeType: mimeType, data: data)
        )
        return try await send(
            "POST",
            path: "/api/v1/documents/upload",
            bodyData: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }

    // MARK: - Propuestas

    public func proposal(id: String) async throws -> Proposal {
        try await send("GET", path: "/api/v1/proposals/\(id)")
    }

    /// Aplica sólo las operaciones elegidas (la API no aplica todo o nada).
    public func apply(proposalId: String, operationIds: [String]) async throws -> Proposal {
        try await send(
            "POST",
            path: "/api/v1/proposals/\(proposalId)/apply",
            body: AnyEncodable(ApplyProposalRequest(operationIds: operationIds))
        )
    }

    public func reject(proposalId: String) async throws -> Proposal {
        try await send("POST", path: "/api/v1/proposals/\(proposalId)/reject")
    }

    // MARK: - Diario

    public func journal(from: String? = nil, to: String? = nil, limit: Int = 60) async throws -> [JournalEntry] {
        var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let from { query.append(URLQueryItem(name: "from", value: from)) }
        if let to { query.append(URLQueryItem(name: "to", value: to)) }
        return try await send("GET", path: "/api/v1/journal", query: query)
    }

    public func journalEntry(id: String) async throws -> JournalEntry {
        try await send("GET", path: "/api/v1/journal/\(id)")
    }

    public func createJournalEntry(_ payload: JournalEntryRequest) async throws -> JournalEntry {
        try await send("POST", path: "/api/v1/journal", body: AnyEncodable(payload))
    }

    public func updateJournalEntry(id: String, _ payload: JournalUpdateRequest) async throws -> JournalEntry {
        try await send("PATCH", path: "/api/v1/journal/\(id)", body: AnyEncodable(payload))
    }

    /// Candidatos para el selector de referencias (`@tarea:`/`@evento:`).
    public func journalReferenceCandidates(
        kinds: String = "task,event",
        query text: String = "",
        limit: Int = 20
    ) async throws -> [JournalReferenceCandidate] {
        try await send("GET", path: "/api/v1/journal/reference-candidates", query: [
            URLQueryItem(name: "kinds", value: kinds),
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "limit", value: String(limit))
        ])
    }

    /// Borra una entidad (las entradas del diario lo son). Es un borrado
    /// reversible en el servidor, no una destrucción.
    public func deleteEntity(id: String) async throws {
        _ = try await sendRaw("DELETE", path: "/api/v1/entities/\(id)", authenticated: true)
    }

    /// Sube una grabación de voz (`multipart/form-data`).
    ///
    /// El servidor responde 202 y transcribe con el proveedor configurado; si la
    /// captura es **sensible**, guarda el audio y no lo transcribe. El límite es
    /// de 25 MB.
    public func createAudioCapture(
        data: Data,
        filename: String,
        mimeType: String = "audio/m4a",
        sensitivity: String = "standard",
        language: String = "es"
    ) async throws -> AudioCapture {
        let boundary = MultipartFormData.makeBoundary()
        let body = MultipartFormData.build(
            boundary: boundary,
            fields: [
                (name: "sensitivity", value: sensitivity),
                (name: "language", value: language)
            ],
            file: (name: "file", filename: filename, mimeType: mimeType, data: data)
        )
        return try await send(
            "POST",
            path: "/api/v1/captures/audio",
            bodyData: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }

    // MARK: - Agenda

    /// Los tres carriles de un intervalo: eventos, bloques de foco con hora,
    /// vencimientos sin hora, y los pares acción+evento por resolver.
    ///
    /// `start` y `end` son **obligatorios** en el servidor (y `end` debe ser
    /// posterior a `start`, si no responde 422).
    public func agenda(from start: Date, to end: Date) async throws -> AgendaDay {
        try await send("GET", path: "/api/v1/agenda", query: APIClient.agendaQuery(from: start, to: end))
    }

    public func createEvent(_ payload: AgendaEventRequest) async throws -> AgendaEvent {
        try await send("POST", path: "/api/v1/events", body: AnyEncodable(payload))
    }

    public func updateEvent(id: String, _ payload: AgendaEventUpdate) async throws -> AgendaEvent {
        try await send("PATCH", path: "/api/v1/events/\(id)", body: AnyEncodable(payload))
    }

    /// Decide sobre un par acción+evento. La decisión se guarda en el servidor y
    /// no vuelve a preguntarse.
    public func resolveDuplicate(_ payload: DuplicateResolveRequest) async throws -> DuplicatePair {
        try await send(
            "POST",
            path: "/api/v1/agenda/duplicates/resolve",
            body: AnyEncodable(payload)
        )
    }

    // MARK: - Acciones

    public func tasks() async throws -> [LifeOSTask] {
        try await send("GET", path: "/api/v1/tasks")
    }

    public func createTask(_ payload: TaskCreateRequest) async throws -> LifeOSTask {
        try await send("POST", path: "/api/v1/tasks", body: AnyEncodable(payload))
    }

    public func updateTask(id: String, _ payload: TaskUpdateRequest) async throws -> LifeOSTask {
        try await send("PATCH", path: "/api/v1/tasks/\(id)", body: AnyEncodable(payload))
    }

    // MARK: - Buscar y cronología

    public func search(_ query: String) async throws -> SearchResults {
        try await send("GET", path: "/api/v1/search", query: [URLQueryItem(name: "q", value: query)])
    }

    public func timeline(
        days: Int = 7,
        kinds: [String] = [],
        includeSensitive: Bool = true,
        limit: Int = 200
    ) async throws -> Timeline {
        var query = [
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "include_sensitive", value: includeSensitive ? "true" : "false")
        ]
        if !kinds.isEmpty {
            query.append(URLQueryItem(name: "kinds", value: kinds.joined(separator: ",")))
        }
        return try await send("GET", path: "/api/v1/timeline", query: query)
    }

    /// Un instante en el formato que espera el servidor (ISO-8601, en UTC).
    public static func instant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Los parámetros que exige `GET /agenda` (el final es **exclusivo**).
    ///
    /// Vive aquí y no en cada llamante para que el diagnóstico del servidor
    /// sondee la agenda exactamente como lo hace la pantalla: si se escribe mal
    /// en un sitio y bien en el otro, la prueba mentira.
    public static func agendaQuery(from start: Date, to end: Date) -> [URLQueryItem] {
        [
            URLQueryItem(name: "start", value: instant(start)),
            URLQueryItem(name: "end", value: instant(end))
        ]
    }

    // MARK: - Transporte

    private func send<T: Decodable>(
        _ method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: AnyEncodable? = nil,
        bodyData: Data? = nil,
        contentType: String? = nil,
        headers: [String: String] = [:],
        authenticated: Bool = true
    ) async throws -> T {
        let (_, data) = try await sendRaw(
            method,
            path: path,
            query: query,
            body: body,
            bodyData: bodyData,
            contentType: contentType,
            headers: headers,
            authenticated: authenticated
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func sendRaw(
        _ method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: AnyEncodable? = nil,
        bodyData: Data? = nil,
        contentType: String? = nil,
        headers: [String: String] = [:],
        authenticated: Bool = true
    ) async throws -> (HTTPURLResponse, Data) {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = method
        // Subir audio puede tardar más que una llamada normal.
        request.timeoutInterval = bodyData == nil ? 30 : 120
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw APIError.decoding(String(describing: error))
            }
        } else if let bodyData {
            request.setValue(contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue(String(bodyData.count), forHTTPHeaderField: "Content-Length")
            request.httpBody = bodyData
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("respuesta sin estado HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.from(status: http.statusCode, data: data)
        }
        return (http, data)
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        guard let url = LifeOSEndpoint.url(base: baseURL, path: path, query: query) else {
            throw APIError.invalidBaseURL(baseURL.absoluteString)
        }
        return url
    }

    /// Petición para **diagnosticar**: devuelve el estado tal cual y no lanza por
    /// un no-2xx (un 404 aquí es un dato, no un fallo).
    func diagnosticRequest(
        _ method: String,
        path: String,
        query: [URLQueryItem] = [],
        authenticated: Bool = true
    ) async throws -> (HTTPURLResponse, Data) {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("respuesta sin estado HTTP")
            }
            return (http, data)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    // MARK: - Codificación

    private static func makeDecoder() -> JSONDecoder {
        LifeOSJSON.decoder()
    }

    private static func makeEncoder() -> JSONEncoder {
        LifeOSJSON.encoder()
    }
}
