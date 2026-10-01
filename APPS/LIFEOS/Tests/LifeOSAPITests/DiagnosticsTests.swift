import XCTest

import LifeOSAPI
import TestSupport

/// La pieza con la que el diagnóstico mira un servidor.
///
/// Tiene que separar «no está» (404), «falta entrar» (401) y «contesta algo que no
/// encaja» (200 con otro JSON). Eso es lo que después permite decir en Ajustes qué
/// pasa exactamente en vez de «algo falló».
final class DiagnosticsTests: XCTestCase {
    private let base = URL(string: "https://lifeos.example")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func makeClient() -> APIClient {
        APIClient(baseURL: base, token: "t", session: StubURLProtocol.session())
    }

    private struct Item: Decodable, Sendable {
        let id: String
        let title: String
    }

    func testProbeReportsContractMismatchOnTwoHundred() async {
        StubURLProtocol.handler = { _ in StubURLProtocol.text(#"{"items":[{"uid":"1"}]}"#, status: 200) }

        let result = await makeClient().probe([Item].self, path: "/api/v1/things")

        guard case .contract = result.outcome else {
            return XCTFail("Debería ser un problema de contrato: \(result.outcome)")
        }
        XCTAssertFalse(result.isOK)
    }

    func testProbeReportsHTTPStatus() async {
        StubURLProtocol.handler = { _ in StubURLProtocol.text(#"{"detail":"Not Found"}"#, status: 404) }

        let result = await makeClient().probe([Item].self, path: "/api/v1/things")

        XCTAssertEqual(result.outcome, .http(404))
    }

    func testProbeReportsTransportFailure() async {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }

        let result = await makeClient().probe([Item].self, path: "/api/v1/things")

        guard case .transport = result.outcome else {
            return XCTFail("Debería ser un fallo de transporte: \(result.outcome)")
        }
    }

    func testProbeIsOKWhenTheJSONFits() async {
        StubURLProtocol.handler = { _ in StubURLProtocol.jsonArray([["id": "1", "title": "Algo"]]) }

        let result = await makeClient().probe([Item].self, path: "/api/v1/things")

        XCTAssertEqual(result.outcome, .ok)
        XCTAssertEqual(result.summary.hasPrefix("bien"), true)
    }

    func testStatusDistinguishesExistenceWithoutASession() async {
        StubURLProtocol.handler = { request in
            if request.url?.path == "/api/v1/journal" {
                return StubURLProtocol.text(#"{"detail":"Unauthorized"}"#, status: 401)
            }
            return StubURLProtocol.text(#"{"detail":"Not Found"}"#, status: 404)
        }
        let client = makeClient()
        let existing = await client.status(path: "/api/v1/journal")
        let missing = await client.status(path: "/api/v1/inventado")

        XCTAssertEqual(existing, 401, "Existe, pero pide sesión")
        XCTAssertEqual(missing, 404, "Esa versión no lo tiene")
    }

    func testStatusDoesNotSendTheSession() async {
        StubURLProtocol.handler = { _ in StubURLProtocol.text("{}", status: 401) }

        _ = await makeClient().status(path: "/api/v1/agenda")

        guard let request = StubURLProtocol.lastRequest else {
            return XCTFail("No se registró la petición")
        }
        XCTAssertNil(
            request.value(forHTTPHeaderField: "Authorization"),
            "Para saber si un endpoint existe no se manda la sesión: un 401 es la respuesta útil"
        )
    }
}
