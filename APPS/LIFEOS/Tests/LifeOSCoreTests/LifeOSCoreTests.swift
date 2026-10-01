import XCTest

import LifeOSAPI
import LifeOSCore
import TestSupport

// MARK: - Ajustes

final class SettingsStoreTests: XCTestCase {
    private func makeStore() -> SettingsStore {
        let defaults = UserDefaults(suiteName: "lifeos.tests.\(UUID().uuidString)")!
        return SettingsStore(defaults: defaults)
    }

    func testDefaultServerIsThePublicOne() {
        XCTAssertEqual(makeStore().baseURLString, SettingsStore.defaultBaseURLString)
    }

    func testNormalizeAcceptsWhatPeopleActuallyType() {
        XCTAssertEqual(
            SettingsStore.normalize("lifeos.perlatec.net")?.absoluteString,
            "https://lifeos.perlatec.net"
        )
        XCTAssertEqual(
            SettingsStore.normalize("  https://lifeos.perlatec.net/  ")?.absoluteString,
            "https://lifeos.perlatec.net"
        )
        XCTAssertEqual(
            SettingsStore.normalize("http://192.168.100.15:8000")?.port,
            8000
        )
        XCTAssertNil(SettingsStore.normalize("   "))
        XCTAssertNil(SettingsStore.normalize("https://"))
    }

    func testPreferencesRoundTrip() {
        let store = makeStore()
        store.sensitiveByDefault = true
        store.notifyReminders = false
        XCTAssertTrue(store.sensitiveByDefault)
        XCTAssertFalse(store.notifyReminders)
    }
}

// MARK: - Cola sin conexión

final class OutboxStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifeos-outbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fileURL() -> URL {
        directory.appendingPathComponent("outbox.json")
    }

    func testEnqueueKeepsOrderAndContent() async {
        let store = OutboxStore(fileURL: fileURL())
        let first = await store.enqueue(content: "Comprar leche", sensitivity: "standard")
        _ = await store.enqueue(content: "Idea para la web", sensitivity: "sensitive")

        let pending = await store.pending()
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(pending.first?.content, "Comprar leche")
        XCTAssertEqual(pending.last?.sensitivity, "sensitive")
        XCTAssertFalse(first.id.isEmpty)
    }

    func testQueueSurvivesRestart() async {
        let first = OutboxStore(fileURL: fileURL())
        let item = await first.enqueue(content: "Llamar al dentista", sensitivity: "standard")

        // Otra instancia sobre el mismo fichero: así se comporta tras reiniciar.
        let second = OutboxStore(fileURL: fileURL())
        let pending = await second.pending()

        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.id, item.id)
        XCTAssertEqual(pending.first?.content, "Llamar al dentista")
    }

    func testRemoveAndAttemptTracking() async {
        let store = OutboxStore(fileURL: fileURL())
        let item = await store.enqueue(content: "Algo", sensitivity: "standard")

        await store.markAttempt(id: item.id, error: "Sin red")
        var pending = await store.pending()
        XCTAssertEqual(pending.first?.attempts, 1)
        XCTAssertEqual(pending.first?.lastError, "Sin red")

        await store.remove(id: item.id)
        pending = await store.pending()
        XCTAssertTrue(pending.isEmpty)
    }

    func testCorruptFileDoesNotBlockCapturing() async throws {
        try Data("no soy json".utf8).write(to: fileURL())
        let store = OutboxStore(fileURL: fileURL())

        let initial = await store.count()
        XCTAssertEqual(initial, 0)
        _ = await store.enqueue(content: "Sigue funcionando", sensitivity: "standard")
        let after = await store.count()
        XCTAssertEqual(after, 1)
    }
}

// MARK: - Sesión

@MainActor
final class AuthServiceTests: XCTestCase {
    private let base = URL(string: "https://lifeos.example")!
    private var credentials: CredentialsStore!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        credentials = CredentialsStore(
            service: "com.dmx83.lifeos.tests.\(UUID().uuidString)",
            account: "token"
        )
    }

    override func tearDown() {
        try? credentials.delete()
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func session(
        token: String = "tok",
        username: String = "owner",
        displayName: String = "Andy",
        status: Int = 200
    ) -> StubURLProtocol.Stub {
        StubURLProtocol.json([
            "token": token,
            "expires_in": 604800,
            "user": [
                "id": "u1",
                "username": username,
                "display_name": displayName,
                "mfa_mode": "disabled"
            ]
        ], status: status)
    }

    func testNativeSignInStoresTokenAndConfiguresClient() async throws {
        let client = APIClient(baseURL: base, session: StubURLProtocol.session())
        let auth = AuthService(client: client, credentials: credentials)
        StubURLProtocol.handler = { _ in self.session(token: "tok-nativo") }

        let user = try await auth.signIn(username: "owner", password: "secreta")

        XCTAssertEqual(user.displayName, "Andy")
        XCTAssertEqual(try credentials.token(), "tok-nativo")
        let configured = await client.currentToken()
        XCTAssertEqual(configured, "tok-nativo")
        StubURLProtocol.reset()

        // Y el token se usa de verdad en la siguiente llamada.
        StubURLProtocol.handler = { _ in StubURLProtocol.json(["id": "u1", "username": "owner", "display_name": "Andy", "mfa_mode": "disabled"]) }
        _ = try await client.me()
        XCTAssertEqual(
            StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer tok-nativo"
        )
    }

    func testFallsBackToTheWebEndpointWhenTheServerIsOlder() async throws {
        let client = APIClient(baseURL: base, session: StubURLProtocol.session())
        let auth = AuthService(client: client, credentials: credentials)

        StubURLProtocol.handler = { request in
            if request.url?.path == "/api/v1/auth/native/login" {
                return StubURLProtocol.text(#"{"detail":"Not Found"}"#, status: 404)
            }
            if request.url?.path == "/api/v1/auth/login" {
                return StubURLProtocol.Stub(
                    status: 200,
                    headers: [
                        "Content-Type": "application/json",
                        "Set-Cookie": "lifeos_session=tok-cookie; Path=/; HttpOnly; SameSite=Strict"
                    ],
                    body: Data(#"{"id":"u1","username":"owner","display_name":"Andy","mfa_mode":"disabled"}"#.utf8)
                )
            }
            return StubURLProtocol.json(["id": "u1", "username": "owner", "display_name": "Andy", "mfa_mode": "disabled"])
        }

        let user = try await auth.signIn(username: "owner", password: "secreta")

        XCTAssertEqual(user.displayName, "Andy")
        XCTAssertEqual(try credentials.token(), "tok-cookie")
        let configured = await client.currentToken()
        XCTAssertEqual(configured, "tok-cookie")
        XCTAssertEqual(
            StubURLProtocol.requests.map(\.url?.path),
            ["/api/v1/auth/native/login", "/api/v1/auth/login", "/api/v1/auth/me"]
        )
    }

    func testSignInWithGoogleExchangesTheOneTimeCode() async throws {
        let client = APIClient(baseURL: base, session: StubURLProtocol.session())
        let auth = AuthService(client: client, credentials: credentials)
        StubURLProtocol.handler = { _ in self.session(token: "tok-google") }

        // Se simula lo que hace el flujo tras volver de Google.
        let exchanged = try await client.exchange(code: "code-1")

        XCTAssertEqual(exchanged.token, "tok-google")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/v1/auth/native/exchange")
        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: request))
        XCTAssertEqual(body["code"] as? String, "code-1")
        _ = auth
    }

    func testRestoreSessionReturnsNilWithoutToken() async {
        let client = APIClient(baseURL: base, session: StubURLProtocol.session())
        let auth = AuthService(client: client, credentials: credentials)

        let user = await auth.restoreSession()

        XCTAssertNil(user)
        XCTAssertNil(auth.lastRestoreError)
        XCTAssertNil(StubURLProtocol.lastRequest)
    }

    func testRestoreSessionDiscardsARejectedToken() async throws {
        try credentials.save(token: "viejo")
        let client = APIClient(baseURL: base, session: StubURLProtocol.session())
        let auth = AuthService(client: client, credentials: credentials)
        StubURLProtocol.handler = { _ in StubURLProtocol.text(#"{"detail":"Authentication required"}"#, status: 401) }

        let user = await auth.restoreSession()

        XCTAssertNil(user)
        XCTAssertNil(try credentials.token())
    }

    func testRestoreSessionKeepsTokenWhenTheServerIsUnreachable() async throws {
        try credentials.save(token: "bueno")
        let client = APIClient(baseURL: base, session: StubURLProtocol.session())
        let auth = AuthService(client: client, credentials: credentials)
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }

        let user = await auth.restoreSession()

        XCTAssertNil(user)
        XCTAssertEqual(try credentials.token(), "bueno")
        XCTAssertNotNil(auth.lastRestoreError)
    }
}

// MARK: - Ciclo de captura

final class LifeOSServiceTests: XCTestCase {
    private let base = URL(string: "https://lifeos.example")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func makeService() -> (LifeOSService, OutboxStore) {
        let outbox = OutboxStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("lifeos-service-\(UUID().uuidString).json")
        )
        let client = APIClient(baseURL: base, token: "t", session: StubURLProtocol.session())
        return (LifeOSService(client: client, outbox: outbox), outbox)
    }

    func testOfflineCaptureGoesToTheOutbox() async throws {
        let (service, _) = makeService()
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        let outcome = try await service.capture("Idea sin cobertura", sensitivity: "standard")

        guard case .queued(let item) = outcome else {
            return XCTFail("Debería haberse encolado")
        }
        XCTAssertEqual(item.content, "Idea sin cobertura")
        let pending = await service.pendingCount()
        XCTAssertEqual(pending, 1)
    }

    func testRejectedCredentialsAreNotQueued() async throws {
        let (service, _) = makeService()
        StubURLProtocol.handler = { _ in StubURLProtocol.text(#"{"detail":"Authentication required"}"#, status: 401) }

        do {
            _ = try await service.capture("Hola", sensitivity: "standard")
            XCTFail("Debería haber fallado")
        } catch let error as APIError {
            XCTAssertTrue(error.isNotAuthenticated)
        }
        let pending = await service.pendingCount()
        XCTAssertEqual(pending, 0)
    }

    func testFlushSendsQueuedCapturesWithTheirOriginalKey() async throws {
        let (service, outbox) = makeService()
        let item = await outbox.enqueue(content: "Guardada ayer", sensitivity: "sensitive")

        var seenKeys: [String] = []
        StubURLProtocol.handler = { request in
            if let key = request.value(forHTTPHeaderField: "Idempotency-Key") {
                seenKeys.append(key)
            }
            return StubURLProtocol.Stub(
                status: 202,
                body: Data(#"{"id":"c9","status":"processing","proposal_id":null,"clarifying_question":"","manual_kind":""}"#.utf8)
            )
        }

        let sent = await service.flushOutbox()

        XCTAssertEqual(sent, 1)
        let pending = await service.pendingCount()
        XCTAssertEqual(pending, 0)
        // La clave es la del elemento encolado: reintentar no duplica nada.
        XCTAssertEqual(seenKeys, [item.id])
        let body = try XCTUnwrap(StubURLProtocol.bodyJSON(of: StubURLProtocol.lastRequest!))
        XCTAssertEqual(body["sensitivity"] as? String, "sensitive")
    }

    func testFlushKeepsTheItemWhenItStillFails() async throws {
        let (service, outbox) = makeService()
        _ = await outbox.enqueue(content: "Sigue sin salir", sensitivity: "standard")
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }

        let sent = await service.flushOutbox()

        XCTAssertEqual(sent, 0)
        let pending = await service.pendingCaptures()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.attempts, 1)
        XCTAssertNotNil(pending.first?.lastError)
    }

    func testAwaitProposalPollsUntilTheWorkerFinishes() async throws {
        let (service, _) = makeService()
        var captureCalls = 0
        StubURLProtocol.handler = { request in
            if request.url?.path == "/api/v1/captures/c1" {
                captureCalls += 1
                // El servidor devuelve CaptureResponse aquí (sin `content`):
                // sólo la lista de capturas trae el detalle completo.
                let proposalId = captureCalls >= 2 ? "\"p1\"" : "null"
                let json = """
                {"id":"c1","status":"processing","proposal_id":\(proposalId),"clarifying_question":"","manual_kind":""}
                """
                return StubURLProtocol.Stub(status: 200, body: Data(json.utf8))
            }
            if request.url?.path == "/api/v1/proposals/p1" {
                return StubURLProtocol.json([
                    "id": "p1", "capture_id": "c1", "status": "pending",
                    "explanation": "", "operations": []
                ])
            }
            return StubURLProtocol.text("{}", status: 404)
        }

        let proposal = try await service.awaitProposal(
            captureId: "c1",
            attempts: 5,
            interval: .milliseconds(1)
        )

        XCTAssertEqual(proposal?.id, "p1")
        XCTAssertEqual(captureCalls, 2)
    }

    func testInboxShowsOnlyWhatIsStillOpen() async throws {
        let (service, _) = makeService()
        StubURLProtocol.handler = { _ in
            StubURLProtocol.jsonArray([
                [
                    "id": "c1", "status": "applied", "proposal_id": "p1",
                    "clarifying_question": "", "manual_kind": "", "content": "ya hecha",
                    "channel": "text", "sensitivity": "standard", "original_filename": "",
                    "original_preserved": false, "created_at": "2026-09-30T10:00:00+00:00"
                ],
                [
                    "id": "c2", "status": "processing", "proposal_id": NSNull(),
                    "clarifying_question": "", "manual_kind": "", "content": "pendiente",
                    "channel": "text", "sensitivity": "standard", "original_filename": "",
                    "original_preserved": false, "created_at": "2026-09-30T11:00:00+00:00"
                ]
            ])
        }

        let pending = try await service.inbox(pendingOnly: true)
        let all = try await service.inbox(pendingOnly: false)

        XCTAssertEqual(pending.map(\.id), ["c2"])
        XCTAssertEqual(all.count, 2)
    }
}
