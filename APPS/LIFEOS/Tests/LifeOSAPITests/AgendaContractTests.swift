import XCTest

import LifeOSAPI
import TestSupport

/// Contrato de la agenda, las acciones, la búsqueda y la cronología.
///
/// Aquí se fijan las cosas que ya han mordido una vez: que las fechas viajen como
/// **texto ISO-8601** (no como número), que el `PATCH` de las acciones distinga
/// «no lo toques» de «bórralo», y que los nombres de los campos sean los del
/// servidor (`snake_case`).
final class AgendaContractTests: XCTestCase {
    private let base = URL(string: "https://lifeos.example")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func makeClient() -> APIClient {
        APIClient(baseURL: base, token: "t", session: StubURLProtocol.session())
    }

    private func eventJSON(
        id: String = "e1",
        title: String = "Reunión con el cliente",
        startsAt: String = "2026-09-30T14:00:00+02:00",
        endsAt: String = "2026-09-30T15:00:00+02:00"
    ) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "starts_at": startsAt,
            "ends_at": endsAt,
            "all_day": false,
            "timezone": "Europe/Madrid",
            "location": "Videollamada",
            "notes": "",
            "status": "scheduled",
            "sensitivity": "standard",
            "recurrence_rule": "",
            "reminders": [10],
            "focus_target_id": NSNull(),
            "version": 3,
            "recurrence_id": NSNull(),
            "series": false,
            "focus_target": NSNull(),
            "source": "google",
            "external_id": "g1",
            "external_state": "synced",
            "origin": ["id": "cal1", "label": "Calendar · Trabajo", "kind": "calendar", "direction": "pull"]
        ]
    }

    private func taskJSON(
        id: String = "t1",
        title: String = "Enviar el informe",
        status: String = "todo",
        dueDate: Any = NSNull()
    ) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "priority": 2,
            "due_date": dueDate,
            "estimate_minutes": 90,
            "context": "Trabajo",
            "scheduled_start": NSNull(),
            "scheduled_end": NSNull(),
            "recurrence_rule": "",
            "reminders": [5],
            "energy": "high",
            "status": status,
            "objective_ids": [],
            "blocked": false,
            "completed_at": NSNull(),
            "version": 4,
            "source": "manual",
            "external_id": NSNull(),
            "external_state": "",
            "origin": NSNull()
        ]
    }

    // MARK: - Agenda

    func testAgendaSendsTheRangeAndDecodesTheThreeLanes() async throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let end = start.addingTimeInterval(86_400)
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json([
                "events": [self.eventJSON()],
                "tasks": [self.taskJSON(id: "t-focus")],
                "due_tasks": [self.taskJSON(id: "t-due")],
                "duplicates": [[
                    "id": "d1", "task_id": "t-due", "event_id": "e1", "title": "Reunión",
                    "event_title": "Reunión con el cliente", "task_title": "Llamar al cliente",
                    "at": "2026-09-30T14:00:00+02:00", "status": "suggested", "reason": "misma hora"
                ]]
            ])
        }

        let agenda = try await makeClient().agenda(from: start, to: end)

        XCTAssertEqual(agenda.events.count, 1)
        XCTAssertEqual(agenda.events.first?.title, "Reunión con el cliente")
        XCTAssertEqual(agenda.events.first?.origin?.label, "Calendar · Trabajo")
        XCTAssertTrue(agenda.events.first?.isFromGoogle == true)
        XCTAssertEqual(agenda.tasks.count, 1)
        XCTAssertEqual(agenda.dueTasks.count, 1)
        XCTAssertEqual(agenda.duplicates.first?.taskTitle, "Llamar al cliente")
        XCTAssertTrue(agenda.duplicates.first?.isPending == true)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/v1/agenda")
        let query = try XCTUnwrap(request.url?.query)
        XCTAssertNotNil(
            query.range(of: "start=\\d{4}-\\d{2}-\\d{2}T\\d{2}", options: .regularExpression),
            "El rango va como instante ISO: \(query)"
        )
        XCTAssertNotNil(
            query.range(of: "end=\\d{4}-\\d{2}-\\d{2}T\\d{2}", options: .regularExpression),
            "El final también: \(query)"
        )
        XCTAssertFalse(query.contains("start=179"), "El rango no puede ir como número de segundos")
    }

    /// Los parámetros de la agenda salen de un único sitio y los usa **también**
    /// el diagnóstico del servidor. Si allí se escribieran a mano, la prueba
    /// podría mentir: comprobaría una URL que la pantalla no usa.
    func testAgendaQueryIsTheOneTheDiagnosisUses() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)

        let query = APIClient.agendaQuery(from: start, to: start.addingTimeInterval(86_400))

        XCTAssertEqual(query.map(\.name), ["start", "end"])
        XCTAssertEqual(query[0].value, "2026-09-21T14:13:20Z")
        XCTAssertEqual(query[1].value, "2026-09-22T14:13:20Z")
    }

    func testFocusBlockIsRecognised() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json([
                "events": [self.eventJSON()],
                "tasks": [],
                "due_tasks": [],
                "duplicates": []
            ])
        }
        let agenda = try await makeClient().agenda(from: Date(), to: Date().addingTimeInterval(3600))
        XCTAssertFalse(agenda.events[0].isFocusBlock, "Sin destino no es un bloque de foco")
    }

    // MARK: - Citas

    func testCreateEventSendsDatesAsISOStrings() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(status: 201, body: try! JSONSerialization.data(withJSONObject: self.eventJSON()))
        }

        let start = Date(timeIntervalSince1970: 1_790_000_000)
        _ = try await makeClient().createEvent(
            AgendaEventRequest(
                title: "Café con Marta",
                startsAt: start,
                endsAt: start.addingTimeInterval(3600),
                timezone: "Europe/Madrid",
                location: "Cafetería"
            )
        )

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/events")
        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: request))
        XCTAssertEqual(body["title"] as? String, "Café con Marta")
        XCTAssertEqual(body["timezone"] as? String, "Europe/Madrid")
        XCTAssertEqual(body["status"] as? String, "scheduled")
        let startsAt = try XCTUnwrap(body["starts_at"] as? String, "starts_at tiene que ser texto ISO, no un número")
        XCTAssertTrue(startsAt.contains("T"), "starts_at no es una fecha ISO: \(startsAt)")
        XCTAssertEqual(body["all_day"] as? Bool, false)
    }

    func testUpdateEventSendsTheVersion() async throws {
        StubURLProtocol.handler = { _ in StubURLProtocol.json(self.eventJSON()) }

        _ = try await makeClient().updateEvent(
            id: "e1",
            AgendaEventUpdate(
                title: "Reunión (movida)",
                startsAt: Date(),
                endsAt: Date().addingTimeInterval(1800),
                allDay: false,
                location: "",
                notes: "",
                status: "scheduled",
                expectedVersion: 3
            )
        )

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/api/v1/events/e1")
        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: request))
        XCTAssertEqual(body["expected_version"] as? Int, 3)
    }

    func testResolveDuplicateSendsTheDecision() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json([
                "id": "d1", "task_id": "t1", "event_id": "e1", "title": "Reunión",
                "event_title": "Reunión", "task_title": "Llamar", "at": NSNull(),
                "status": "linked", "reason": ""
            ])
        }

        let pair = try await makeClient().resolveDuplicate(
            DuplicateResolveRequest(taskId: "t1", eventId: "e1", choice: .same)
        )

        XCTAssertEqual(pair.status, "linked")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/agenda/duplicates/resolve")
        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: request))
        XCTAssertEqual(body["task_id"] as? String, "t1")
        XCTAssertEqual(body["event_id"] as? String, "e1")
        XCTAssertEqual(body["choice"] as? String, "same")
    }

    // MARK: - Acciones

    func testListTasksDecodesWhatMatters() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.jsonArray([
                self.taskJSON(),
                self.taskJSON(id: "t2", title: "Llamar al fisio", status: "done")
            ])
        }

        let tasks = try await makeClient().tasks()

        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].priority, 2)
        XCTAssertEqual(tasks[0].statusLabel, "Por hacer")
        XCTAssertTrue(tasks[0].isOpen)
        XCTAssertTrue(tasks[1].isDone)
        XCTAssertFalse(tasks[1].isOpen)
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/v1/tasks")
    }

    func testTaskStatusChangeSendsOnlyTheStatus() async throws {
        StubURLProtocol.handler = { _ in StubURLProtocol.json(self.taskJSON(status: "done")) }

        _ = try await makeClient().updateTask(id: "t1", TaskUpdateRequest.status("done", expectedVersion: 4))

        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: StubURLProtocol.lastRequest!))
        XCTAssertEqual(body["status"] as? String, "done")
        XCTAssertEqual(body["expected_version"] as? Int, 4)
        // Lo que no se toca no se envía: si no, un `null` borraría el vencimiento.
        XCTAssertNil(body["due_date"])
        XCTAssertNil(body["priority"])
        XCTAssertNil(body["title"])
    }

    func testTaskPatchDistinguishesClearFromUnchanged() async throws {
        StubURLProtocol.handler = { _ in StubURLProtocol.json(self.taskJSON()) }

        _ = try await makeClient().updateTask(
            id: "t1",
            TaskUpdateRequest(priority: .set(1), dueDate: .clear, context: .set("Casa"))
        )

        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: StubURLProtocol.lastRequest!))
        XCTAssertEqual(body["priority"] as? Int, 1)
        XCTAssertEqual(body["context"] as? String, "Casa")
        XCTAssertTrue(body["due_date"] is NSNull, "Vaciar el vencimiento tiene que mandar null")
        XCTAssertNil(body["status"], "El estado no se toca si no se pide")
    }

    func testCreateTaskSendsTheMinimum() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(status: 201, body: try! JSONSerialization.data(withJSONObject: self.taskJSON()))
        }

        _ = try await makeClient().createTask(TaskCreateRequest(title: "Pedir el certificado", priority: 2))

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/tasks")
        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: request))
        XCTAssertEqual(body["title"] as? String, "Pedir el certificado")
        XCTAssertEqual(body["priority"] as? Int, 2)
        XCTAssertEqual(body["status"] as? String, "todo")
        XCTAssertNil(body["due_date"])
    }

    // MARK: - Buscar y cronología

    func testSearchDecodesAndEscapes() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json([
                "query": "informe",
                "results": [[
                    "id": "t1", "kind": "task", "title": "Enviar el informe",
                    "excerpt": "Hacienda", "sensitivity": "standard"
                ]]
            ])
        }

        let results = try await makeClient().search("informe")

        XCTAssertEqual(results.query, "informe")
        XCTAssertEqual(results.results.first?.title, "Enviar el informe")
        XCTAssertEqual(results.grouped.first?.kind, "task")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/v1/search")
        XCTAssertEqual(request.url?.query, "q=informe")
    }

    func testTimelineSendsDaysAndKinds() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json([
                "start": "2026-09-23T00:00:00+00:00",
                "end": "2026-09-30T00:00:00+00:00",
                "days": 7,
                "items": [[
                    "id": "j1", "kind": "journal", "title": "Diario",
                    "occurred_at": "2026-09-30T21:30:00+00:00", "detail": "nota",
                    "ref_id": "j1", "sensitive": true
                ]],
                "counts": ["journal": 1]
            ])
        }

        let timeline = try await makeClient().timeline(days: 30, kinds: ["journal", "task"])

        XCTAssertEqual(timeline.days, 7)
        XCTAssertEqual(timeline.items.first?.kind, "journal")
        XCTAssertTrue(timeline.items.first?.sensitive == true)
        XCTAssertEqual(timeline.counts["journal"], 1)
        XCTAssertEqual(timeline.byDay.count, 1)
        let query = try XCTUnwrap(StubURLProtocol.lastRequest?.url?.query)
        XCTAssertTrue(query.contains("days=30"))
        XCTAssertTrue(query.contains("kinds=journal,task"))
        XCTAssertTrue(query.contains("include_sensitive=true"))
    }
}
