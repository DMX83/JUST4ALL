import XCTest

import LifeOSAPI
import LifeOSCore
import TestSupport

/// El diagnóstico tiene que **distinguir** los tres casos que se parecen: servidor
/// antiguo (no tiene el endpoint), falta de sesión y contrato que no encaja. Si
/// los mezclara, el diagnóstico diría «algo falla» y no serviría para nada.
final class DoctorTests: XCTestCase {
    private let base = URL(string: "https://lifeos.example")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private var session: URLSession { StubURLProtocol.session() }

    private func reply(_ status: Int, _ json: String = "{}") -> StubURLProtocol.Stub {
        StubURLProtocol.Stub(status: status, body: Data(json.utf8))
    }

    private func check(_ checks: [DoctorCheck], id: String) -> DoctorCheck? {
        checks.first { $0.id == id }
    }

    // MARK: - Servidor mudo

    func testSilentServerStopsTheDiagnosisWithOneProblem() async {
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }

        let checks = await ServerDoctor.run(baseURL: base, token: nil, session: session)

        XCTAssertEqual(checks.count, 1, "Sin servidor no tiene sentido seguir")
        XCTAssertEqual(checks[0].level, .failure)
        XCTAssertTrue(checks[0].title.contains("No se puede hablar"), checks[0].title)
    }

    // MARK: - Sin sesión

    func testServerWithoutAnEndpointIsReportedAsOldVersion() async throws {
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            switch path {
            case "/health/ready": return self.reply(200, #"{"status":"ok"}"#)
            case "/openapi.json": return self.reply(404, #"{"detail":"Not Found"}"#)
            case "/api/v1/auth/native/login": return self.reply(405, #"{"detail":"Method Not Allowed"}"#)
            case "/api/v1/journal": return self.reply(404, #"{"detail":"Not Found"}"#)
            default: return self.reply(401, #"{"detail":"Unauthorized"}"#)
            }
        }

        let checks = await ServerDoctor.run(baseURL: base, token: nil, session: session)

        XCTAssertEqual(check(checks, id: "salud")?.level, .ok)
        let endpoints = try XCTUnwrap(check(checks, id: "endpoints"))
        XCTAssertEqual(endpoints.level, .failure)
        XCTAssertTrue(endpoints.detail.contains("/api/v1/journal"), endpoints.detail)
        XCTAssertEqual(check(checks, id: "acceso")?.level, .ok, "Un 405 quiere decir que /auth/native/login existe")
    }

    func testServerWithEverythingButNoNativeAccess() async {
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            switch path {
            case "/health/ready": return self.reply(200, #"{"status":"ok"}"#)
            case "/openapi.json": return self.reply(404, #"{"detail":"Not Found"}"#)
            case "/api/v1/auth/native/login": return self.reply(404, #"{"detail":"Not Found"}"#)
            default: return self.reply(401, #"{"detail":"Unauthorized"}"#)
            }
        }

        let checks = await ServerDoctor.run(baseURL: base, token: nil, session: session)

        XCTAssertEqual(check(checks, id: "endpoints")?.level, .ok)
        XCTAssertEqual(
            check(checks, id: "acceso")?.level,
            .warning,
            "Sin el parche el acceso es con usuario y contraseña: hay que decirlo"
        )
        XCTAssertEqual(check(checks, id: "sesion")?.level, .warning)
        XCTAssertFalse(checks.contains { $0.level == .failure })
    }

    // MARK: - Con sesión

    func testSessionFromAnotherServerSaysSoInsteadOfFailing() async {
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            switch path {
            case "/health/ready": return self.reply(200, #"{"status":"ok"}"#)
            case "/openapi.json": return self.reply(404, #"{"detail":"Not Found"}"#)
            case "/api/v1/auth/native/login": return self.reply(405, "{}")
            case "/api/v1/auth/me": return self.reply(401, #"{"detail":"Unauthorized"}"#)
            default: return self.reply(401, "{}")
            }
        }

        let checks = await ServerDoctor.run(baseURL: base, token: "de-otro-servidor", session: session)

        XCTAssertEqual(check(checks, id: "sesion")?.level, .warning)
        XCTAssertTrue(
            check(checks, id: "sesion")?.title.contains("no vale") == true,
            check(checks, id: "sesion")?.title ?? ""
        )
        XCTAssertTrue(
            check(checks, id: "sesion")?.detail.contains("401") == true,
            check(checks, id: "sesion")?.detail ?? ""
        )
        // Y no se sigue probando cada pantalla: no tiene sentido con una sesión que no vale.
        XCTAssertNil(check(checks, id: "/api/v1/tasks"))
    }

    func testSummaryCountsProblemsAndWarnings() {
        let ok = DoctorCheck(id: "a", title: "a", level: .ok, detail: "")
        let warning = DoctorCheck(id: "b", title: "b", level: .warning, detail: "")
        let failure = DoctorCheck(id: "c", title: "c", level: .failure, detail: "")

        XCTAssertEqual(ServerDoctor.summary([ok]), "todo bien")
        XCTAssertEqual(ServerDoctor.summary([ok, warning]), "1 aviso")
        XCTAssertEqual(ServerDoctor.summary([ok, warning, warning]), "2 avisos")
        XCTAssertEqual(ServerDoctor.summary([ok, failure, warning]), "1 problema")
    }

    // MARK: - La agenda se sondea con su intervalo

    /// `GET /agenda` responde **422** sin `start` y `end`, y son los únicos
    /// parámetros que no pueden ir escritos a mano: son los de la semana en que
    /// se ejecuta el diagnóstico.
    ///
    /// Sin esta prueba, el día que alguien añada la agenda al diagnóstico y se
    /// olvide del intervalo, la app diría «contrato roto» en un servidor perfecto.
    func testAgendaIsProbedWithItsRequiredRange() async {
        StubURLProtocol.handler = { request in
            let url = request.url ?? self.base
            switch url.path {
            case "/health/ready": return self.reply(200, #"{"status":"ok"}"#)
            case "/openapi.json": return self.reply(404, #"{"detail":"Not Found"}"#)
            case "/api/v1/auth/native/login": return self.reply(405, "{}")
            case "/api/v1/agenda":
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let names = Set(items.map(\.name))
                guard names.contains("start"), names.contains("end") else {
                    return self.reply(422, #"{"detail":"start y end son obligatorios"}"#)
                }
                return self.reply(200, #"{"events":[],"tasks":[],"due_tasks":[],"duplicates":[]}"#)
            default:
                return self.reply(
                    200,
                    #"{"id":"u1","username":"andy","display_name":"Andy","mfa_mode":"disabled"}"#
                )
            }
        }

        let checks = await ServerDoctor.run(baseURL: base, token: "vale", session: session)

        let agenda = check(checks, id: "/api/v1/agenda")
        XCTAssertEqual(agenda?.level, .ok, agenda?.detail ?? "la agenda no se comprobó")
    }
}
