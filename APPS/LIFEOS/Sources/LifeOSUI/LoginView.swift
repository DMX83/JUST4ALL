import AppKit
import LifeOSAPI
import SwiftUI

/// Puerta de entrada: panel de cristal sobre el lienzo con el acento de la marca,
/// con Google como opción principal y usuario/contraseña (con TOTP) para el resto.
public struct LoginView: View {
    @ObservedObject private var model: LifeOSModel

    public init(model: LifeOSModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            LoginCanvas()
            ScrollView {
                LoginPanel(model: model)
                    .frame(maxWidth: 420)
                    .padding(.vertical, LifeOSSpace.xxl)
                    .padding(.horizontal, LifeOSSpace.l)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Lienzo con el resplandor de marca en la parte alta.
struct LoginCanvas: View {
    var body: some View {
        LifeOSTheme.canvas
            .overlay(alignment: .top) {
                RadialGradient(
                    colors: [LifeOSTheme.brand.opacity(0.18), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 340
                )
                .frame(height: 420)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }
}

/// El panel de entrada, sin el contenedor con scroll (así se puede renderizar
/// fuera de pantalla para la revisión de diseño).
struct LoginPanel: View {
    @ObservedObject var model: LifeOSModel

    @State private var username = ""
    @State private var password = ""
    @State private var mfaCode = ""
    @State private var showPasswordForm = true
    @State private var showServerForm = false
    @State private var showSessionForm = false
    @State private var webSession = ""
    @FocusState private var firstFieldFocused: Bool
    @Environment(\.lifeOSFlatSurfaces) private var flatSurfaces

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.l) {
            brand
                .frame(maxWidth: .infinity)
            Divider()
                .overlay(LifeOSTheme.borderSubtle)
                .frame(maxWidth: .infinity)
            googleButton
            passwordSection
            serverSection
            messages
        }
        .padding(LifeOSSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LifeOSRadius.xl, style: .continuous)
                .fill(flatSurfaces ? AnyShapeStyle(LifeOSTheme.surface) : AnyShapeStyle(.regularMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LifeOSRadius.xl, style: .continuous)
                .strokeBorder(LifeOSTheme.borderSubtle, lineWidth: 1)
        )
        .lifeOSShadow(.lg)
    }

    // MARK: - Marca

    private var brand: some View {
        VStack(spacing: LifeOSSpace.m) {
            BrandMark(size: 58)
            VStack(spacing: LifeOSSpace.xs) {
                Text("LifeOS")
                    .font(LifeOSFont.display)
                    .kerning(LifeOSTracking.heading)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                Text("Tu organizador personal, en el Mac.")
                    .font(LifeOSFont.bodySmall)
                    .foregroundStyle(LifeOSTheme.textSecondary)
            }
        }
        .padding(.bottom, LifeOSSpace.xs)
    }

    // MARK: - Google

    private var googleButton: some View {
        VStack(spacing: LifeOSSpace.s) {
            Button {
                Task { await model.signInWithGoogle(anchor: NSApp.keyWindow) }
            } label: {
                ZStack {
                    HStack(spacing: LifeOSSpace.s) {
                        Image(systemName: "g.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(LifeOSTheme.info, LifeOSTheme.infoSoft)
                        Text("Continuar con Google")
                    }
                    if model.busy {
                        HStack {
                            Spacer(minLength: 0)
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
            }
            .buttonStyle(LifeOSSecondaryButtonStyle())
            .disabled(model.busy)

            Text("Igual que en la web. Se abre la ventana de Google y vuelves aquí.")
                .font(LifeOSFont.caption)
                .foregroundStyle(LifeOSTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Usuario y contraseña

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.m) {
            Button {
                withAnimation(LifeOSMotion.standard) { showPasswordForm.toggle() }
                if showPasswordForm { firstFieldFocused = true }
            } label: {
                HStack(spacing: LifeOSSpace.xs) {
                    Image(systemName: showPasswordForm ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("Entrar con usuario y contraseña")
                }
            }
            .buttonStyle(LifeOSGhostButtonStyle())
            .padding(.leading, -LifeOSSpace.m)

            if showPasswordForm {
                VStack(spacing: LifeOSSpace.s) {
                    // El servidor busca por **usuario**, no por correo: se dice
                    // como es para no mandar a nadie a un 401 por el email.
                    LifeOSField("Usuario", text: $username, submitLabel: "Entrar") {
                        submitPassword()
                    }
                    .focused($firstFieldFocused)
                    LifeOSField("Contraseña", text: $password, isSecure: true, submitLabel: "Entrar") {
                        submitPassword()
                    }
                    LifeOSField("Código de verificación (si lo tienes)", text: $mfaCode) {
                        submitPassword()
                    }

                    Button {
                        submitPassword()
                    } label: {
                        Text("Entrar")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LifeOSPrimaryButtonStyle())
                    .disabled(model.busy || username.isEmpty || password.isEmpty)

                    webSessionSection
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Entrar con la sesión que ya tienes abierta en la web.
    ///
    /// Nace de un caso real: en un servidor sin el parche del flujo nativo no hay
    /// Google desde la app, y si nunca has puesto contraseña no hay otra puerta.
    /// La sesión de la web vale igual (el servidor acepta la cookie o un Bearer
    /// con el mismo valor), así que se puede pegar aquí.
    private var webSessionSection: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            LifeOSDivider()
            Button {
                withAnimation(LifeOSMotion.standard) { showSessionForm.toggle() }
            } label: {
                HStack(spacing: LifeOSSpace.xs) {
                    Image(systemName: showSessionForm ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("Usar la sesión que ya tengo en la web")
                }
            }
            .buttonStyle(LifeOSGhostButtonStyle())
            .padding(.leading, -LifeOSSpace.m)

            if showSessionForm {
                VStack(alignment: .leading, spacing: LifeOSSpace.s) {
                    Text("En el navegador: entra en LifeOS → inspeccionar → Aplicación/Almacenamiento → Cookies → copia el valor de `lifeos_session`.")
                        .font(LifeOSFont.caption)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    LifeOSField("Valor de lifeos_session", text: $webSession, isSecure: true, submitLabel: "Usar esta sesión") {
                        submitWebSession()
                    }
                    Button("Usar esta sesión") { submitWebSession() }
                        .buttonStyle(LifeOSSecondaryButtonStyle())
                        .disabled(model.busy || webSession.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func submitPassword() {
        guard !username.isEmpty, !password.isEmpty else { return }
        Task { await model.signIn(username: username, password: password, mfaCode: mfaCode) }
    }

    private func submitWebSession() {
        let token = webSession.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        Task {
            await model.adoptSession(token: token)
            webSession = ""
        }
    }

    // MARK: - Servidor

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.m) {
            Button {
                withAnimation(LifeOSMotion.standard) { showServerForm.toggle() }
            } label: {
                HStack(spacing: LifeOSSpace.xs) {
                    Image(systemName: showServerForm ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("Servidor")
                    Text(model.serverURL.absoluteString)
                        .font(LifeOSFont.caption)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                }
            }
            .buttonStyle(LifeOSGhostButtonStyle())
            .padding(.leading, -LifeOSSpace.m)

            if showServerForm {
                VStack(alignment: .leading, spacing: LifeOSSpace.s) {
                    LifeOSField("https://lifeos.perlatec.net", text: $model.serverText)
                    HStack(spacing: LifeOSSpace.s) {
                        Button("Probar") { Task { _ = await model.probeServer() } }
                            .buttonStyle(LifeOSGhostButtonStyle())
                        Button("Cambiar servidor") { Task { await model.applyServerChange() } }
                            .buttonStyle(LifeOSSecondaryButtonStyle())
                    }
                    Text("Vale el dominio público o el de tu red local (por ejemplo http://192.168.100.15:8000).")
                        .font(LifeOSFont.caption)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Mensajes

    @ViewBuilder
    private var messages: some View {
        if let error = model.errorMessage {
            MessageRow(text: error, tone: .danger, systemImage: "exclamationmark.triangle.fill")
        }
        if let status = model.statusMessage {
            MessageRow(text: status, tone: .positive, systemImage: "checkmark.circle.fill")
        }
    }
}
