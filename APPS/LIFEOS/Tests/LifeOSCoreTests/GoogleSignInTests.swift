import XCTest

import LifeOSAPI
import LifeOSCore
import TestSupport

/// El acceso con Google tiene que **no** abrir la ventana cuando el servidor no
/// puede terminar el flujo.
///
/// Pasó de verdad el 30-sep-2026 contra producción: sin el parche, el servidor
/// redirige a la web (no a `lifeos://auth`), la ventana se queda abierta en la
/// consola y la app esperaba un código que nunca llegaba. Hay que decirlo antes
/// de abrir nada.
@MainActor
final class GoogleSignInTests: XCTestCase {
    private let production = URL(string: "https://lifeos.perlatec.net")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func makeController() -> GoogleSignInController {
        GoogleSignInController(network: StubURLProtocol.session())
    }

    func testServerWithoutNativeFlowIsDetected() async {
        StubURLProtocol.handler = { _ in StubURLProtocol.text(#"{"detail":"Not Found"}"#, status: 404) }

        let available = await makeController().nativeFlowAvailable(baseURL: production)

        XCTAssertFalse(available, "Sin /auth/native/login no se puede completar el flujo en la app")
    }

    func testServerWithNativeFlowIsDetected() async {
        StubURLProtocol.handler = { _ in StubURLProtocol.text(#"{"detail":"Method Not Allowed"}"#, status: 405) }

        let available = await makeController().nativeFlowAvailable(baseURL: production)

        XCTAssertTrue(available, "Un 405 quiere decir que el endpoint existe (solo acepta POST)")
    }

    func testSignInFailsFastWhenTheServerCannotFinishTheFlow() async {
        StubURLProtocol.handler = { _ in StubURLProtocol.text(#"{"detail":"Not Found"}"#, status: 404) }

        do {
            _ = try await makeController().signIn(baseURL: production, anchor: nil)
            XCTFail("No debería intentarlo siquiera")
        } catch let error as GoogleSignInError {
            guard case .serverWithoutNativeFlow = error else {
                return XCTFail("Error inesperado: \(error)")
            }
            XCTAssertTrue(error.errorDescription?.contains("usuario y contraseña") == true, error.errorDescription ?? "")
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }

    func testTimeoutIsShortEnoughToNotStrandTheUser() {
        XCTAssertLessThanOrEqual(
            GoogleSignInController.timeout,
            120,
            "Más de dos minutos esperando una ventana que no responde es demasiado"
        )
    }
}
