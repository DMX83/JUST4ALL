import XCTest

import LifeOSAPI
import LifeOSCore
import TestSupport

/// Adoptar una sesión que ya existía (la de la web).
///
/// Es la puerta que queda cuando el servidor no tiene el flujo nativo y la cuenta
/// se creó con Google: el mismo valor de la cookie sirve como `Bearer`. Lo que se
/// comprueba aquí es que **no se guarda una sesión que no vale**: eso dejaría la
/// app con una sesión rota en el llavero y errores raros después.
final class AdoptSessionTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { StubURLProtocol.reset() }
    }

    @MainActor
    private func makeService(credentials: CredentialsStore) -> AuthService {
        let client = APIClient(
            baseURL: URL(string: "https://lifeos.example")!,
            session: StubURLProtocol.session()
        )
        return AuthService(client: client, credentials: credentials)
    }

    private func makeCredentials() -> CredentialsStore {
        CredentialsStore(service: "com.dmx83.lifeos.adopttests.\(UUID().uuidString)")
    }

    @MainActor
    func testAdoptingAValidSessionStoresIt() async throws {
        let credentials = makeCredentials()
        defer { try? credentials.delete() }
        StubURLProtocol.handler = { _ in
            StubURLProtocol.json([
                "id": "u1",
                "username": "andy",
                "display_name": "Andy",
                "mfa_mode": "disabled"
            ])
        }

        let user = try await makeService(credentials: credentials).adoptSession(token: "  sesion-de-la-web  ")

        XCTAssertEqual(user.username, "andy")
        XCTAssertEqual(try credentials.token(), "sesion-de-la-web", "Se guarda sin espacios de sobra")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/v1/auth/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sesion-de-la-web")
    }

    @MainActor
    func testAdoptingASessionThatDoesNotWorkKeepsItOutOfTheKeychain() async {
        let credentials = makeCredentials()
        defer { try? credentials.delete() }
        StubURLProtocol.handler = { _ in StubURLProtocol.text(#"{"detail":"Invalid session"}"#, status: 401) }

        do {
            _ = try await makeService(credentials: credentials).adoptSession(token: "caducada")
            XCTFail("Debería haber fallado")
        } catch let error as APIError {
            XCTAssertTrue(error.isNotAuthenticated, "Un 401 es «esa sesión no vale aquí»")
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
        XCTAssertNil(try? credentials.token() ?? nil, "Una sesión que no vale no se guarda")
    }

    @MainActor
    func testEmptySessionIsRejectedWithoutTouchingTheNetwork() async {
        let credentials = makeCredentials()
        defer { try? credentials.delete() }
        StubURLProtocol.handler = { _ in XCTFail("No debería salir a la red"); return StubURLProtocol.text("{}", status: 200) }

        do {
            _ = try await makeService(credentials: credentials).adoptSession(token: "   ")
            XCTFail("Debería haber fallado")
        } catch let error as APIError {
            XCTAssertTrue(error.isNotAuthenticated)
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }
}
