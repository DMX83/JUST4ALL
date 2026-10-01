import XCTest

import LifeOSAPI
import TestSupport

final class APIClientTests: XCTestCase {
    private let base = URL(string: "https://lifeos.example")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func makeClient(token: String? = nil) -> APIClient {
        APIClient(baseURL: base, token: token, session: StubURLProtocol.session())
    }

    // MARK: - Acceso nativo

    func testNativeLoginSendsCredentialsAndDecodesSession() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json([
                "token": "tok-123",
                "expires_in": 604800,
                "user": [
                    "id": "u1",
                    "username": "owner",
                    "display_name": "Andy",
                    "avatar_url": NSNull(),
                    "mfa_mode": "disabled"
                ]
            ])
        }

        let session = try await makeClient().nativeLogin(
            NativeLoginRequest(username: "owner", password: "secreta", mfaCode: "123456")
        )

        XCTAssertEqual(session.token, "tok-123")
        XCTAssertEqual(session.expiresIn, 604800)
        XCTAssertEqual(session.user.displayName, "Andy")
        XCTAssertFalse(session.user.hasMFA)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/auth/native/login")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: request))
        XCTAssertEqual(body["username"] as? String, "owner")
        XCTAssertEqual(body["password"] as? String, "secreta")
        XCTAssertEqual(body["mfa_code"] as? String, "123456")
    }

    func testNativeLoginOmitsEmptyMFACode() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json([
                "token": "t",
                "expires_in": 1,
                "user": ["id": "u", "username": "u", "display_name": "u", "mfa_mode": "disabled"]
            ])
        }

        _ = try await makeClient().nativeLogin(NativeLoginRequest(username: "a", password: "b"))

        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: StubURLProtocol.lastRequest!))
        XCTAssertNil(body["mfa_code"])
    }

    func testMissingNativeEndpointIsRecognised() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(status: 404, body: Data(#"{"detail":"Not Found"}"#.utf8))
        }

        do {
            _ = try await makeClient().nativeLogin(NativeLoginRequest(username: "a", password: "b"))
            XCTFail("Debería haber fallado")
        } catch let error as APIError {
            XCTAssertTrue(error.isMissingNativeSupport)
        }
    }

    // MARK: - Sesión

    func testAuthenticatedRequestsCarryBearerToken() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json([
                "date": "2026-09-30",
                "completed": [["id": "1", "title": "Cerrar la semana", "at": NSNull()]],
                "events": [],
                "open_tasks": 3,
                "pending_captures": 1,
                "journal_entry_id": NSNull(),
                "journal_entries": 0,
                "suggestion": "Queda poco para cerrar el día."
            ])
        }

        let dayClose = try await makeClient(token: "tok-abc").dayClose()

        XCTAssertEqual(dayClose.openTasks, 3)
        XCTAssertEqual(dayClose.pendingCaptures, 1)
        XCTAssertEqual(dayClose.completed.first?.title, "Cerrar la semana")
        XCTAssertEqual(dayClose.date, "2026-09-30")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-abc")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v1/day-close")
    }

    func testDayCloseDateQueryIsSent() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json([
                "date": "2026-09-29", "completed": [], "events": [],
                "open_tasks": 0, "pending_captures": 0, "journal_entries": 0, "suggestion": ""
            ])
        }

        _ = try await makeClient(token: "t").dayClose(date: "2026-09-29")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.query, "date=2026-09-29")
    }

    // MARK: - Captura

    func testCaptureSendsIdempotencyKeyAndDecodesSummary() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(
                status: 202,
                body: Data(#"{"id":"c1","status":"processing","proposal_id":null,"clarifying_question":"","manual_kind":""}"#.utf8)
            )
        }

        let summary = try await makeClient(token: "t").createCapture(
            content: "Comprar leche",
            sensitivity: "sensitive",
            idempotencyKey: "clave-fija"
        )

        XCTAssertEqual(summary.id, "c1")
        XCTAssertEqual(summary.status, "processing")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "clave-fija")
        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: request))
        XCTAssertEqual(body["content"] as? String, "Comprar leche")
        XCTAssertEqual(body["sensitivity"] as? String, "sensitive")
        XCTAssertEqual(body["channel"] as? String, "text")
    }

    func testProposalDecodesOperationsWithFreeFormPayload() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json([
                "id": "p1",
                "capture_id": "c1",
                "status": "pending",
                "explanation": "Parece una tarea y una idea.",
                "operations": [
                    [
                        "id": "op-1",
                        "operation": "create",
                        "entity_kind": "task",
                        "after": ["title": "Llamar al dentista", "due_date": "2026-10-01", "status": "inbox"],
                        "target_id": NSNull(),
                        "confidence": 0.82,
                        "dependencies": [],
                        "warnings": ["Revisa y confirma antes de guardar."]
                    ],
                    [
                        "id": "op-2",
                        "operation": "create",
                        "entity_kind": "metric_observation",
                        "after": ["metric_name": "Peso", "value": 78.5],
                        "confidence": 0.7,
                        "dependencies": ["op-1"],
                        "warnings": []
                    ]
                ]
            ])
        }

        let proposal = try await makeClient(token: "t").proposal(id: "p1")

        XCTAssertTrue(proposal.isOpen)
        XCTAssertEqual(proposal.operations.count, 2)

        let task = proposal.operations[0]
        XCTAssertEqual(task.title, "Llamar al dentista")
        XCTAssertEqual(task.entityKind, "task")
        XCTAssertEqual(task.confidenceLabel, "82 %")
        XCTAssertEqual(task.details, ["para 2026-10-01"])

        let metric = proposal.operations[1]
        XCTAssertEqual(metric.title, "Peso")
        XCTAssertEqual(metric.dependencies, ["op-1"])
        XCTAssertEqual(metric.details, ["valor 78.5"])
    }

    func testApplySendsOnlyChosenOperations() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json([
                "id": "p1", "capture_id": "c1", "status": "applied",
                "explanation": "", "operations": []
            ])
        }

        _ = try await makeClient(token: "t").apply(proposalId: "p1", operationIds: ["op-2", "op-3"])

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/v1/proposals/p1/apply")
        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: request))
        XCTAssertEqual(body["operation_ids"] as? [String], ["op-2", "op-3"])
    }

    func testClarificationSendsSnakeCaseKeys() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(
                status: 200,
                body: Data(#"{"id":"c1","status":"processing","proposal_id":"p9","clarifying_question":"","manual_kind":""}"#.utf8)
            )
        }

        _ = try await makeClient(token: "t").clarify(
            captureId: "c1",
            answer: "es una tarea",
            manualKind: "task"
        )

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/api/v1/captures/c1")
        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: request))
        XCTAssertEqual(body["clarification_answer"] as? String, "es una tarea")
        XCTAssertEqual(body["manual_kind"] as? String, "task")
    }

    // MARK: - Fechas y errores

    func testDecodesDatesWithAndWithoutFractionalSeconds() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json([
                "now": "2026-09-30T10:00:00+00:00",
                "window_hours": 24,
                "items": [
                    [
                        "id": "r1", "kind": "task", "title": "Con",
                        "at": "2026-09-30T11:30:00.123456+00:00",
                        "remind_at": "2026-09-30T11:15:00+00:00",
                        "minutes": 15, "detail": ""
                    ],
                    [
                        "id": "r2", "kind": "event", "title": "Sin",
                        "at": "2026-09-30T12:00:00Z",
                        "remind_at": "2026-09-30T11:45:00Z",
                        "minutes": 15, "detail": ""
                    ]
                ]
            ])
        }

        let reminders = try await makeClient(token: "t").upcomingReminders()

        XCTAssertEqual(reminders.items.count, 2)

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedFractional = try XCTUnwrap(withFraction.date(from: "2026-09-30T11:30:00.123456Z"))
        XCTAssertEqual(
            reminders.items[0].at.timeIntervalSince1970,
            expectedFractional.timeIntervalSince1970,
            accuracy: 0.0001
        )

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let expectedPlain = try XCTUnwrap(plain.date(from: "2026-09-30T12:00:00Z"))
        XCTAssertEqual(
            reminders.items[1].at.timeIntervalSince1970,
            expectedPlain.timeIntervalSince1970,
            accuracy: 0.0001
        )
    }

    func testServerProblemBecomesAReadableError() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(
                status: 409,
                headers: ["Content-Type": "application/problem+json"],
                body: Data(#"{"title":"Request failed","detail":"Google no está conectado"}"#.utf8)
            )
        }

        do {
            _ = try await makeClient(token: "t").dayClose()
            XCTFail("Debería haber fallado")
        } catch let error as APIError {
            XCTAssertEqual(error.errorDescription, "Google no está conectado")
            XCTAssertFalse(error.isNotAuthenticated)
        }
    }

    func testUnauthorizedIsReportedAsExpiredSession() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(status: 401, body: Data(#"{"detail":"Authentication required"}"#.utf8))
        }

        do {
            _ = try await makeClient(token: "viejo").me()
            XCTFail("Debería haber fallado")
        } catch let error as APIError {
            XCTAssertTrue(error.isNotAuthenticated)
        }
    }

    func testRateLimitExplainsItself() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(status: 429, body: Data(#"{"detail":"Too many login attempts"}"#.utf8))
        }

        do {
            _ = try await makeClient().nativeLogin(NativeLoginRequest(username: "a", password: "b"))
            XCTFail("Debería haber fallado")
        } catch let error as APIError {
            let message = try XCTUnwrap(error.errorDescription)
            XCTAssertTrue(message.contains("Demasiados intentos"))
            XCTAssertTrue(message.contains("Too many login attempts"))
        }
    }

    // MARK: - URL base

    func testSessionCookieParsing() {
        XCTAssertEqual(
            APIClient.sessionToken(fromSetCookie: "lifeos_session=abc123; Path=/; HttpOnly; SameSite=Strict"),
            "abc123"
        )
        XCTAssertEqual(
            APIClient.sessionToken(fromSetCookie: "otra=1; lifeos_session=xyz"),
            "xyz"
        )
        XCTAssertNil(APIClient.sessionToken(fromSetCookie: "otra=1; Path=/"))
        XCTAssertNil(APIClient.sessionToken(fromSetCookie: "lifeos_session=; Path=/"))
    }

    func testBaseURLWithPortAndTrailingSlashKeepsPort() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(status: 200, body: Data(#"{"ok":true}"#.utf8))
        }

        let client = APIClient(
            baseURL: URL(string: "http://192.168.100.15:8000/")!,
            session: StubURLProtocol.session()
        )
        await client.setToken("t")
        _ = try? await client.probeServer()

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.host, "192.168.100.15")
        XCTAssertEqual(request.url?.port, 8000)
        XCTAssertEqual(request.url?.path, "/health/live")
    }

    func testUserAgentIdentifiesTheApp() async throws {
        StubURLProtocol.handler = { _ in StubURLProtocol.Stub(status: 204) }

        try await makeClient(token: "t").logout()

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), APIClient.defaultUserAgent)
        XCTAssertTrue(APIClient.defaultUserAgent.hasPrefix("LifeOSMac/"))
    }
}
