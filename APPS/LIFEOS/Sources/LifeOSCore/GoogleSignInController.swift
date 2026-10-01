import AppKit
import AuthenticationServices
import Foundation
import LifeOSAPI

/// Error propio del acceso con Google, ya en lenguaje de persona.
public enum GoogleSignInError: Error, LocalizedError {
    case cancelled
    case unavailable(String)
    case missingCode
    case denied(String)
    /// El servidor no tiene el flujo nativo (le falta el parche).
    case serverWithoutNativeFlow(String)
    /// Se abrió la ventana pero no volvió nada en el tiempo previsto.
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Se canceló el acceso con Google."
        case .unavailable(let detail):
            return "No se pudo abrir la ventana de Google. \(detail)"
        case .missingCode:
            return "Google no devolvió el código de acceso."
        case .denied(let detail):
            return detail.isEmpty ? "Google rechazó el acceso." : detail
        case .serverWithoutNativeFlow(let server):
            return "Ese servidor (\(server)) todavía no sabe volver a la app con el acceso de Google: le falta desplegar el parche. Mientras tanto entra con usuario y contraseña, o abre «Entrar con usuario y contraseña» y usa «Usar la sesión que ya tengo en la web»."
        case .timedOut:
            return "La ventana de Google se quedó abierta sin volver. Si ese servidor no tiene el flujo nativo, usa «Usar la sesión que ya tengo en la web»; si sí lo tiene, inténtalo otra vez."
        }
    }
}

/// Acceso con Google replicando el flujo de la web, pero terminando en la app.
///
/// Se usa `ASWebAuthenticationSession` y no una vista web propia por un motivo
/// concreto: Google rechaza las peticiones de autorización hechas desde
/// navegadores incrustados («disallowed_useragent»). Esta sesión sí es un
/// navegador de verdad, así que el consentimiento funciona igual que en Safari.
///
/// El servidor cierra el flujo redirigiendo a `lifeos://auth?code=…` con un
/// código de un solo uso, que después se canjea por el token de sesión.
@MainActor
public final class GoogleSignInController: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let callbackScheme = "lifeos"

    /// Cuánto se espera a que el servidor devuelva el código. Sin esto, una
    /// ventana que se queda en la web deja la app esperando para siempre.
    public static let timeout: TimeInterval = 90

    private var session: ASWebAuthenticationSession?
    private weak var anchorWindow: NSWindow?

    /// Sesión de red para la comprobación previa. Se inyecta en las pruebas: un
    /// test no debería salir a internet (y menos a producción).
    private let network: URLSession

    public init(network: URLSession = .shared) {
        self.network = network
        super.init()
    }

    /// ¿Ese servidor sabe terminar el flujo en la app?
    ///
    /// Se pregunta antes de abrir nada: un servidor sin el parche redirige a la
    /// web (no a `lifeos://auth`), así que la ventana se quedaría abierta en la
    /// consola y la app esperando un código que nunca llega.
    public func nativeFlowAvailable(baseURL: URL) async -> Bool {
        let client = APIClient(baseURL: baseURL, session: network)
        // El endpoint solo acepta POST: si existe, un GET responde 405.
        switch await client.status(path: "/api/v1/auth/native/login") {
        case .some(let status):
            return status != 404
        case .none:
            // Sin respuesta no se puede asegurar: se deja intentar (mejor un
            // intento que un «no se puede» falso).
            return true
        }
    }

    public func signIn(baseURL: URL, anchor: NSWindow?) async throws -> String {
        guard let url = LifeOSEndpoint.googleAuthorizeURL(base: baseURL) else {
            throw APIError.invalidBaseURL(baseURL.absoluteString)
        }
        guard await nativeFlowAvailable(baseURL: baseURL) else {
            throw GoogleSignInError.serverWithoutNativeFlow(baseURL.host ?? baseURL.absoluteString)
        }
        guard case .code(let code) = try await authorize(url: url, anchor: anchor) else {
            throw GoogleSignInError.missingCode
        }
        return code
    }

    /// Vincula Google con la cuenta que ya está abierta en la app.
    ///
    /// Se usa la misma ventana de autorización, pero la vuelta trae
    /// `lifeos://auth?linked=…` en vez de un código: aquí no se entra, se dice
    /// quién es uno.
    public func link(url: URL, anchor: NSWindow?) async throws -> GoogleLinkOutcome {
        guard case .link(let status) = try await authorize(url: url, anchor: anchor) else {
            throw GoogleSignInError.missingCode
        }
        return GoogleLinkOutcome(rawValue: status) ?? .unknown
    }

    /// Abre la ventana de Google y espera a que vuelva algo a la app.
    private func authorize(url: URL, anchor: NSWindow?) async throws -> Callback {
        anchorWindow = anchor

        return try await withCheckedThrowingContinuation { continuation in
            // La continuación se resuelve **una sola vez**: pueden llegar el
            // callback y el tiempo límite a la vez, y resolverla dos veces
            // tumbaría la app.
            let state = ContinuationState()

            func finish(_ result: Result<Callback, Error>) {
                guard state.claim() else { return }
                continuation.resume(with: result)
            }

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: GoogleSignInController.callbackScheme
            ) { callbackURL, error in
                if let error {
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        finish(.failure(GoogleSignInError.cancelled))
                    } else {
                        finish(.failure(GoogleSignInError.unavailable(error.localizedDescription)))
                    }
                    return
                }
                guard let callbackURL else {
                    finish(.failure(GoogleSignInError.missingCode))
                    return
                }
                let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty {
                    finish(.success(.code(code)))
                    return
                }
                if let linked = items.first(where: { $0.name == "linked" })?.value, !linked.isEmpty {
                    finish(.success(.link(linked)))
                    return
                }
                let detail = items.first(where: { $0.name == "error" })?.value ?? ""
                finish(.failure(GoogleSignInError.denied(detail)))
            }

            session.presentationContextProvider = self
            // Reutiliza la sesión de Safari: si ya hay sesión de Google abierta,
            // el consentimiento es de un toque.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(GoogleSignInController.timeout * 1_000_000_000))
                guard !state.hasFinished else { return }
                self?.session?.cancel()
                self?.session = nil
                finish(.failure(GoogleSignInError.timedOut))
            }

            if !session.start() {
                finish(.failure(GoogleSignInError.unavailable(
                    "Ejecuta la app empaquetada (LIFEOS.app): el acceso con Google necesita un identificador de app."
                )))
            }
        }
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchorWindow ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }

    /// Lo que devuelve Google al volver a la app.
    public enum Callback: Equatable, Sendable {
        /// Un código de un solo uso para entrar.
        case code(String)
        /// El resultado de una vinculación (`ok`, `already`, `taken`…).
        case link(String)
    }
}

/// Marca de «esto ya se resolvió», para que el callback y el tiempo límite no
/// resuelvan la misma continuación dos veces.
///
/// Va con cerrojo —y no `@MainActor`— porque el callback de la sesión web llega
/// por un hilo que no es el principal.
private final class ContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    var hasFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}
