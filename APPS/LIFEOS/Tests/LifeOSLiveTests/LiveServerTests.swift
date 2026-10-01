import XCTest

import LifeOSAPI
import LifeOSCore

/// Pruebas contra un servidor de LifeOS **de verdad** (el local o el público).
///
/// No corren por defecto: sin `LIFEOS_LIVE_SERVER` se saltan, para que
/// `swift test` siga siendo offline y determinista. Así el mismo comando sirve
/// para validar el ciclo completo contra el contenedor local:
///
/// ```sh
/// LIFEOS_LIVE_SERVER=http://127.0.0.1:8000 \
/// LIFEOS_LIVE_ENV_FILE=../../0_server_dorticos/LifeOS/.env \
/// swift test --filter LifeOSLiveTests
/// ```
///
/// Las credenciales se leen del `.env` del servidor y nunca se pasan por línea
/// de comandos: quedarían en el historial del shell.
final class LiveServerTests: XCTestCase {
    private var baseURL: URL!
    private var username: String!
    private var password: String!
    /// Llavero propio de la prueba.
    ///
    /// No se usa el llavero real a propósito: escribirlo dejaría una sesión de
    /// verdad en el Mac de quien ejecuta los tests (y la app la encontraría al
    /// abrirse, como pasó el 30-sep-2026 con el servidor local).
    private var credentials: CredentialsStore!

    override func setUpWithError() throws {
        credentials = CredentialsStore(
            service: "com.dmx83.lifeos.livetests.\(UUID().uuidString)",
            account: "session-token"
        )
        let environment = ProcessInfo.processInfo.environment
        guard let raw = environment["LIFEOS_LIVE_SERVER"], !raw.isEmpty else {
            throw XCTSkip("Sin LIFEOS_LIVE_SERVER: las pruebas contra servidor real no se ejecutan.")
        }
        baseURL = try XCTUnwrap(SettingsStore.normalize(raw))

        // El desarrollo local arranca con estas credenciales; si hay fichero de
        // entorno, manda el fichero.
        var values = [
            "LIFEOS_BOOTSTRAP_USERNAME": "owner",
            "LIFEOS_BOOTSTRAP_PASSWORD": "change-me-in-dev"
        ]
        if let path = environment["LIFEOS_LIVE_ENV_FILE"] {
            for (key, value) in LiveServerTests.parseEnvFile(at: path) {
                values[key] = value
            }
        }
        username = values["LIFEOS_BOOTSTRAP_USERNAME"]
        password = values["LIFEOS_BOOTSTRAP_PASSWORD"]
    }

    override func tearDown() {
        try? credentials?.delete()
        super.tearDown()
    }

    private func signedInClient() async throws -> (APIClient, LifeOSUser) {
        let client = APIClient(baseURL: baseURL)
        let auth = await AuthService(client: client, credentials: credentials)
        let user = try await auth.signIn(username: username, password: password)
        return (client, user)
    }

    // MARK: - Sesión

    func testPerfilYSalud() async throws {
        let (client, user) = try await signedInClient()

        XCTAssertFalse(user.username.isEmpty)
        let me = try await client.me()
        XCTAssertEqual(me.id, user.id)
        let token = await client.currentToken()
        XCTAssertNotNil(token)
    }

    func testElAccesoNativoExisteEnElServidor() async throws {
        // Si esto falla con 404, el servidor no tiene desplegado el flujo nativo
        // y la app estaría usando el respaldo por el endpoint clásico.
        let client = APIClient(baseURL: baseURL)
        do {
            _ = try await client.nativeLogin(
                NativeLoginRequest(username: username, password: password)
            )
        } catch let error as APIError {
            XCTAssertFalse(
                error.isMissingNativeSupport,
                "El servidor no expone /auth/native/login: falta desplegar el parche."
            )
        }
    }

    // MARK: - Cierre del día

    func testCierreDelDiaYAvisos() async throws {
        let (client, _) = try await signedInClient()

        let dayClose = try await client.dayClose()
        XCTAssertFalse(dayClose.date.isEmpty)
        XCTAssertGreaterThanOrEqual(dayClose.openTasks, 0)
        XCTAssertGreaterThanOrEqual(dayClose.pendingCaptures, 0)

        let reminders = try await client.upcomingReminders()
        XCTAssertGreaterThan(reminders.windowHours, 0)
    }

    // MARK: - Ciclo de captura

    func testCapturarProducePropuestaYAplicarORechazar() async throws {
        let (client, _) = try await signedInClient()
        let service = LifeOSService(client: client, outbox: OutboxStore(fileURL: temporaryOutbox()))

        let text = "Prueba de humo de LIFEOS: llamar al fontanero mañana"
        let key = "lifeos-live-\(UUID().uuidString)"
        let summary = try await client.createCapture(content: text, idempotencyKey: key)
        XCTAssertEqual(summary.id.count > 0, true)

        let proposal = try await service.awaitProposal(captureId: summary.id, attempts: 30)
        let resolved = try XCTUnwrap(proposal, "La captura no produjo propuesta")
        XCTAssertFalse(resolved.operations.isEmpty, "La propuesta llegó sin operaciones")
        XCTAssertTrue(resolved.isOpen)

        // Se descarta para no dejar basura en la base de datos del servidor.
        let rejected = try await service.reject(proposalId: resolved.id)
        XCTAssertEqual(rejected.status, "rejected")
    }

    func testLaClaveDeIdempotenciaNoDuplicaCapturas() async throws {
        let (client, _) = try await signedInClient()
        let key = "lifeos-live-idem-\(UUID().uuidString)"

        let first = try await client.createCapture(content: "Captura repetida", idempotencyKey: key)
        let second = try await client.createCapture(content: "Captura repetida", idempotencyKey: key)

        XCTAssertEqual(first.id, second.id, "Reintentar con la misma clave duplicó la captura")
    }

    func testLaBandejaResponde() async throws {
        let (client, _) = try await signedInClient()
        let service = LifeOSService(client: client, outbox: OutboxStore(fileURL: temporaryOutbox()))

        let pending = try await service.inbox(pendingOnly: true)
        XCTAssertTrue(pending.allSatisfy(\.isPending))
    }

    // MARK: - Diario

    func testDiarioCicloCompleto() async throws {
        let (client, _) = try await signedInClient()
        let text = "Prueba de humo del diario: hoy he probado el diario de LIFEOS."

        // Alta. El diario es privado por defecto y el día lo pone el servidor.
        let created = try await client.createJournalEntry(
            JournalEntryRequest(contentMarkdown: text, mood: 4, energy: 3)
        )
        // El borrado se hace explícito al final: no hace falta un `defer` que
        // vuelva a borrar (y ensucie el registro del servidor con un 404).
        XCTAssertEqual(created.mood, 4)
        XCTAssertEqual(created.energy, 3)
        XCTAssertTrue(created.isPrivate, "El diario debería nacer privado")
        XCTAssertFalse(created.entryDate.isEmpty)

        // Aparece en la lista, y como la más reciente.
        let entries = try await client.journal(limit: 20)
        XCTAssertTrue(entries.contains { $0.id == created.id })

        // Edición con control optimista: la versión sube.
        let updated = try await client.updateJournalEntry(
            id: created.id,
            JournalUpdateRequest(contentMarkdown: text + " (corregido)", mood: 5, expectedVersion: created.version)
        )
        XCTAssertEqual(updated.mood, 5)
        XCTAssertGreaterThan(updated.version, created.version)

        // Con la versión vieja, el servidor rechaza el cambio en vez de pisarlo.
        do {
            _ = try await client.updateJournalEntry(
                id: created.id,
                JournalUpdateRequest(contentMarkdown: "no debería entrar", expectedVersion: created.version)
            )
            XCTFail("Debería haber dado conflicto")
        } catch let error as APIError {
            guard case .server(let status, _, _) = error else {
                return XCTFail("Error inesperado: \(error)")
            }
            XCTAssertEqual(status, 409)
        }

        // Limpieza real (borrado reversible de la entidad).
        try await client.deleteEntity(id: created.id)
        let after = try await client.journal(limit: 20)
        XCTAssertFalse(after.contains { $0.id == created.id })
    }

    func testLaCabeceraDeLaEntradaSeLeeIgualQueEnElServidor() async throws {
        let (client, _) = try await signedInClient()

        // Un token válido, otro válido y uno que no lo es: el servidor fecha la
        // entrada por los válidos y deja el inválido como texto.
        let created = try await client.createJournalEntry(
            JournalEntryRequest(
                contentMarkdown: "@hora:07:15\n@fecha:2026-01-02\n@hora:xx\nTexto del día."
            )
        )

        XCTAssertEqual(created.entryDate, "2026-01-02")
        XCTAssertNotNil(created.occurredAt, "El servidor deriva la hora del token @hora:")
        XCTAssertEqual(created.leadTokens, ["@hora:07:15", "@fecha:2026-01-02"])
        XCTAssertEqual(created.body, "@hora:xx\nTexto del día.")
        XCTAssertEqual(created.excerpt, "@hora:xx")

        try await client.deleteEntity(id: created.id)
    }

    func testLasReferenciasDeclaradasQuedanVinculadas() async throws {
        let (client, _) = try await signedInClient()

        // Se busca una acción o evento real a la que referirse.
        let candidates = try await client.journalReferenceCandidates(kinds: "task,event", query: "", limit: 1)
        guard let candidate = candidates.first else {
            throw XCTSkip("No hay acciones ni eventos en el espacio para probar referencias.")
        }

        let token = JournalText.token(for: candidate)
        let created = try await client.createJournalEntry(
            JournalEntryRequest(
                contentMarkdown: "Probando el vínculo con \(token) y nada más.",
                references: [JournalReferenceInput(targetId: candidate.id, text: candidate.label)]
            )
        )
        XCTAssertEqual(created.references.count, 1)
        XCTAssertEqual(created.references.first?.id, candidate.id)
        XCTAssertEqual(created.references.first?.status, "ok")
        XCTAssertEqual(created.references.first?.title.isEmpty, false, "El servidor devuelve el nombre actual")
        XCTAssertTrue(created.unresolvedReferences.isEmpty)
        // Y el vínculo se lee en el texto con la etiqueta declarada, no con el
        // resto de la frase pegada detrás.
        XCTAssertEqual(created.readingText, "Probando el vínculo con \(candidate.label) y nada más.")

        // Una referencia inventada no se vincula: el servidor avisa, no la acepta.
        // El id debe caber en lo que acepta el esquema (36 caracteres).
        let bogus = try await client.createJournalEntry(
            JournalEntryRequest(
                contentMarkdown: "Referencia inventada @tarea:no existe.",
                references: [JournalReferenceInput(targetId: UUID().uuidString, text: "no existe")]
            )
        )
        XCTAssertTrue(bogus.references.isEmpty)
        XCTAssertEqual(bogus.unresolvedReferences, ["no existe"])

        // Limpieza: las entradas del diario son entidades y se borran de verdad.
        try await client.deleteEntity(id: created.id)
        try await client.deleteEntity(id: bogus.id)
    }

    func testLosCandidatosDeReferenciaResponden() async throws {
        let (client, _) = try await signedInClient()

        let candidates = try await client.journalReferenceCandidates(query: "", limit: 5)

        // Puede no haber candidatos, pero la llamada tiene que funcionar.
        XCTAssertLessThanOrEqual(candidates.count, 5)
        if let first = candidates.first {
            XCTAssertFalse(first.label.isEmpty)
            XCTAssertTrue(["task", "event"].contains(first.kind))
        }
    }

    // MARK: - Agenda, acciones, búsqueda y cronología

    func testLaAgendaDevuelveLosTresCarriles() async throws {
        let (client, _) = try await signedInClient()
        let bounds = AgendaRange.week(containing: Date())

        let agenda = try await client.agenda(from: bounds.start, to: bounds.end)

        // Puede haber poco o nada, pero la respuesta tiene que ser la esperada.
        // Los nombres de los campos ya los fija el contrato; aquí se comprueba
        // que la llamada funciona de verdad contra el servidor.
        XCTAssertLessThanOrEqual(agenda.events.count, 500)
        XCTAssertEqual(agenda.duplicates.filter(\.isPending).count, agenda.duplicates.count)
    }

    func testCrearEditarYBorrarUnaCita() async throws {
        let (client, _) = try await signedInClient()
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: 3, to: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!)!
        let end = start.addingTimeInterval(1800)

        let created = try await client.createEvent(
            AgendaEventRequest(
                title: "Prueba de humo: cita de LIFEOS",
                startsAt: start,
                endsAt: end,
                location: "Sala de pruebas"
            )
        )
        XCTAssertEqual(created.title, "Prueba de humo: cita de LIFEOS")
        XCTAssertEqual(created.status, "scheduled")
        XCTAssertEqual(created.version, 1)

        // La cita aparece en la agenda de ese día.
        let agenda = try await client.agenda(
            from: AgendaRange.day(created.startsAt).start,
            to: AgendaRange.day(created.startsAt).end
        )
        XCTAssertTrue(agenda.events.contains { $0.id == created.id })

        // Edición con control de versión: la versión sube.
        let updated = try await client.updateEvent(
            id: created.id,
            AgendaEventUpdate(
                title: "Prueba de humo: cita movida",
                startsAt: start,
                endsAt: end.addingTimeInterval(1800),
                allDay: false,
                location: "Sala de pruebas",
                notes: "",
                status: "scheduled",
                expectedVersion: created.version
            )
        )
        XCTAssertEqual(updated.title, "Prueba de humo: cita movida")
        XCTAssertGreaterThan(updated.version, created.version)

        // Y con la versión vieja, el servidor rechaza el cambio.
        do {
            _ = try await client.updateEvent(
                id: created.id,
                AgendaEventUpdate(
                    title: "no debería entrar",
                    startsAt: start,
                    endsAt: end,
                    allDay: false,
                    location: "",
                    notes: "",
                    status: "scheduled",
                    expectedVersion: created.version
                )
            )
            XCTFail("Debería haber dado conflicto")
        } catch let error as APIError {
            guard case .server(let status, _, _) = error else {
                return XCTFail("Error inesperado: \(error)")
            }
            XCTAssertEqual(status, 409)
        }

        // Limpieza real (los eventos son entidades).
        try await client.deleteEntity(id: created.id)
    }

    func testCrearCompletarYBorrarUnaAccion() async throws {
        let (client, _) = try await signedInClient()
        let dueDate = Calendar.current.date(byAdding: .day, value: 2, to: Date())!

        let created = try await client.createTask(
            TaskCreateRequest(title: "Prueba de humo: acción de LIFEOS", priority: 2, dueDate: dueDate, context: "Pruebas")
        )
        XCTAssertEqual(created.status, "todo")
        XCTAssertFalse(created.blocked)
        XCTAssertEqual(created.priority, 2)

        let done = try await client.updateTask(
            id: created.id,
            TaskUpdateRequest.status("done", expectedVersion: created.version)
        )
        XCTAssertTrue(done.isDone)
        XCTAssertNotNil(done.completedAt, "Al terminar, el servidor pone la fecha")
        XCTAssertGreaterThan(done.version, created.version)

        // Reabrir y quitar el vencimiento con un null explícito.
        let reopened = try await client.updateTask(
            id: created.id,
            TaskUpdateRequest(status: "todo", dueDate: .clear, expectedVersion: done.version)
        )
        XCTAssertNil(reopened.dueDate, "El null explícito vacía el vencimiento")
        XCTAssertEqual(reopened.context, "Pruebas", "Lo que no se toca se conserva")

        try await client.deleteEntity(id: created.id)
    }

    func testLaBusquedaYLaCronologiaResponden() async throws {
        let (client, _) = try await signedInClient()

        let results = try await client.search("prueba")
        XCTAssertEqual(results.query, "prueba")
        XCTAssertLessThanOrEqual(results.results.count, 200)

        let timeline = try await client.timeline(days: 30, kinds: ["journal", "task", "event"])
        XCTAssertEqual(timeline.days, 30)
        XCTAssertGreaterThanOrEqual(timeline.end, timeline.start)
        // Sólo los tipos pedidos, y las cuentas cuadran con los elementos.
        XCTAssertTrue(timeline.items.allSatisfy { ["journal", "task", "event"].contains($0.kind) })
        XCTAssertEqual(timeline.counts.values.reduce(0, +), timeline.items.count)
    }

    // MARK: - Apoyo

    private func temporaryOutbox() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lifeos-live-\(UUID().uuidString).json")
    }

    /// Lector mínimo de `.env` (líneas `CLAVE=valor`, sin comillas ni export).
    static func parseEnvFile(at path: String) -> [String: String] {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            values[String(parts[0])] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return values
    }
}
