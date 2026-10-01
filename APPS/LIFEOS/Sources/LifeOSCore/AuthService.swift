import AppKit
import Foundation
import LifeOSAPI

/// Cómo se entra a LifeOS: con Google (igual que la web) o con usuario y
/// contraseña, con segundo factor si la cuenta lo tiene activo.
///
/// En los dos casos el resultado es el mismo: un token de sesión en el llavero y
/// el cliente HTTP configurado con `Bearer`.
@MainActor
public final class AuthService {
    private let client: APIClient
    private let credentials: CredentialsStore
    private let google = GoogleSignInController()

    public init(client: APIClient, credentials: CredentialsStore = CredentialsStore()) {
        self.client = client
        self.credentials = credentials
    }

    // MARK: - Acceso

    @discardableResult
    public func signIn(username: String, password: String, mfaCode: String? = nil) async throws -> LifeOSUser {
        let payload = NativeLoginRequest(username: username, password: password, mfaCode: normalized(mfaCode))
        do {
            let session = try await client.nativeLogin(payload)
            return try await adopt(session)
        } catch let error as APIError where error.isMissingNativeSupport {
            // El servidor todavía no expone el flujo nativo: se usa el mismo
            // endpoint que la web y se recupera el token de su cookie.
            let legacy = LegacyLoginRequest(username: username, password: password, mfaCode: normalized(mfaCode))
            let token = try await client.legacyLogin(
                username: legacy.username,
                password: legacy.password,
                mfaCode: legacy.mfaCode
            )
            try credentials.save(token: token)
            await client.setToken(token)
            return try await client.me()
        }
    }

    @discardableResult
    public func signInWithGoogle(anchor: NSWindow? = nil) async throws -> LifeOSUser {
        let baseURL = await client.currentBaseURL()
        let code = try await google.signIn(baseURL: baseURL, anchor: anchor)
        let session = try await client.exchange(code: code)
        return try await adopt(session)
    }

    /// Vincula Google con la cuenta que ya tiene sesión.
    ///
    /// No cambia de sesión ni de datos: solo deja puesto el `google_sub` de esta
    /// cuenta, para que la próxima vez entrar con Google lleve **aquí** y no a una
    /// cuenta nueva y vacía.
    @discardableResult
    public func linkGoogle(anchor: NSWindow? = nil) async throws -> GoogleLinkOutcome {
        let start = try await client.googleLinkStart()
        guard let url = URL(string: start.authorizeUrl) else {
            throw APIError.invalidBaseURL(start.authorizeUrl)
        }
        return try await google.link(url: url, anchor: anchor)
    }

    /// Adopta una sesión que ya existía fuera de la app.
    ///
    /// Sirve para el caso real de un servidor **sin el parche del flujo nativo**:
    /// si ya has entrado en la web, la app puede usar esa misma sesión en vez de
    /// pedirte la contraseña. Se comprueba contra `/auth/me` antes de guardarla:
    /// una sesión que no vale no se queda en el llavero.
    @discardableResult
    public func adoptSession(token: String) async throws -> LifeOSUser {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw APIError.server(status: 401, title: "Sin sesión", detail: "No has pegado ninguna sesión.")
        }
        await client.setToken(clean)
        do {
            let user = try await client.me()
            try credentials.save(token: clean)
            return user
        } catch {
            await client.setToken(nil)
            throw error
        }
    }

    /// Recupera la sesión guardada al abrir la app. Devuelve `nil` si no hay
    /// token o si el servidor ya no lo acepta.
    ///
    /// Si había token pero el servidor no responde, se conserva la sesión y se
    /// deja el motivo en `lastRestoreError`: no es lo mismo «no has entrado
    /// nunca» que «tu Mac no llega al servidor».
    public private(set) var lastRestoreError: String?

    public func restoreSession() async -> LifeOSUser? {
        lastRestoreError = nil
        guard let token = try? credentials.token(), !token.isEmpty else { return nil }
        await client.setToken(token)
        do {
            return try await client.me()
        } catch let error as APIError where error.isNotAuthenticated {
            try? credentials.delete()
            await client.setToken(nil)
            return nil
        } catch {
            lastRestoreError = (error as? LocalizedError)?.errorDescription
                ?? "No se pudo comprobar la sesión."
            return nil
        }
    }

    public func signOut() async {
        try? await client.logout()
        try? credentials.delete()
        await client.setToken(nil)
    }

    // MARK: - Cambio de servidor

    public func changeServer(to url: URL) async {
        try? credentials.delete()
        await client.setToken(nil)
        await client.setBaseURL(url)
    }

    // MARK: - Apoyo

    private func adopt(_ session: NativeSession) async throws -> LifeOSUser {
        try credentials.save(token: session.token)
        await client.setToken(session.token)
        return session.user
    }

    /// El segundo factor se envía sólo si tiene pinta de código; si no, el
    /// servidor responde «MFA requerido» y la interfaz pide el código.
    private func normalized(_ code: String?) -> String? {
        let trimmed = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
