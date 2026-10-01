import AppKit
import LifeOSAPI
import SwiftUI

/// Ajustes: servidor, preferencias, sesión y — muy importante — qué NO hace esta
/// app, para que nadie espere encontrarse aquí la consola completa.
public struct SettingsView: View {
    @ObservedObject private var model: LifeOSModel

    public init(model: LifeOSModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            SettingsContent(model: model)
        }
    }
}

/// El contenido de Ajustes, sin el contenedor con scroll.
struct SettingsContent: View {
    @ObservedObject var model: LifeOSModel

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.l) {
            header
            serverCard
            DoctorCard(model: model)
            preferencesCard
            sessionCard
            scopeCard
            messages
        }
        .padding(.horizontal, LifeOSSpace.xl)
        .padding(.vertical, LifeOSSpace.xl)
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(LifeOSTheme.canvas)
    }

    private var header: some View {
        LifeOSScreenHeader(
            eyebrow: "Ajustes",
            title: "Configuración",
            detail: "La app habla con tu servidor de LifeOS. Aquí se cambia cuál y cómo se comporta."
        )
    }

    // MARK: - Servidor

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            LifeOSSectionHeader("Servidor")
            LifeOSCard {
                VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                    LifeOSField("https://lifeos.perlatec.net", text: $model.serverText)
                    Text("Puedes usar el dominio público o el de tu red local (por ejemplo http://192.168.100.15:8000).")
                        .font(LifeOSFont.caption)
                        .foregroundStyle(LifeOSTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: LifeOSSpace.s) {
                        Button("Probar conexión") { Task { _ = await model.probeServer() } }
                            .buttonStyle(LifeOSGhostButtonStyle())
                        Button("Cambiar servidor") { Task { await model.applyServerChange() } }
                            .buttonStyle(LifeOSSecondaryButtonStyle())
                        Spacer(minLength: 0)
                    }
                    Text("Cambiar de servidor cierra la sesión: el token pertenece al servidor anterior.")
                        .font(LifeOSFont.caption)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                }
            }
        }
    }

    // MARK: - Preferencias

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            LifeOSSectionHeader("Preferencias")
            LifeOSCard {
                VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                    PreferenceRow(
                        title: "Marcar como sensible por defecto",
                        detail: "Lo sensible se guarda en LifeOS, pero no se envía a proveedores de IA externos.",
                        isOn: $model.sensitiveByDefault
                    )
                    LifeOSDivider()
                    PreferenceRow(
                        title: "Avisarme de los recordatorios",
                        detail: "Con la app abierta (aunque sea en segundo plano) los avisos suenan en el sistema.",
                        isOn: $model.notifyReminders
                    )
                    LifeOSDivider()
                    PreferenceRow(
                        title: "Atajo ⌥Espacio",
                        detail: "Abre la captura rápida desde cualquier app. El atajo es global: si otra app usa el mismo (JUST4DESK lo hace), desactívalo aquí.",
                        isOn: $model.hotKeyEnabled
                    )
                    LifeOSDivider()
                    PreferenceRow(
                        title: "Abrir al iniciar sesión",
                        detail: "LifeOS se abre con el Mac, para que los avisos lleguen. También se puede quitar desde «Ítems de inicio» del sistema.",
                        isOn: $model.launchAtLogin
                    )
                    HStack {
                        Spacer(minLength: 0)
                        Button("Guardar preferencias") { model.savePreferences() }
                            .buttonStyle(LifeOSPrimaryButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - Sesión

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            LifeOSSectionHeader("Sesión")
            LifeOSCard {
                VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                    VStack(spacing: LifeOSSpace.s) {
                        LifeOSRow("Cuenta", value: model.user?.displayName ?? "Sin sesión")
                        LifeOSRow("Usuario", value: model.user?.username ?? "—")
                        LifeOSRow(
                            "Verificación en dos pasos",
                            value: (model.user?.hasMFA ?? false) ? "Activada" : "Desactivada"
                        )
                        LifeOSRow("Servidor", value: model.serverURL.absoluteString)
                        LifeOSRow(
                            "Entrar con Google",
                            value: (model.user?.hasGoogle ?? false) ? "Vinculado" : "No vinculado"
                        )
                    }

                    if model.isSignedIn, model.user?.hasGoogle != true {
                        VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
                            Button("Vincular con Google") {
                                Task { await model.linkGoogle() }
                            }
                            .buttonStyle(LifeOSSecondaryButtonStyle())
                            .disabled(model.busy)
                            Text("Si entraste con Google sin vincularlo, LifeOS te creó una cuenta aparte. Vincular deja esta cuenta como la que responde a ese Google: al entrar con Google volverás aquí, con tus datos.")
                                .font(LifeOSFont.caption)
                                .foregroundStyle(LifeOSTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    LifeOSDivider()

                    HStack(spacing: LifeOSSpace.s) {
                        Button("Abrir LifeOS en el navegador") { model.openWeb() }
                            .buttonStyle(LifeOSGhostButtonStyle())
                        Spacer(minLength: 0)
                        Button("Cerrar sesión") { Task { await model.signOut() } }
                            .buttonStyle(LifeOSSecondaryButtonStyle())
                            .disabled(!model.isSignedIn)
                    }

                    Text("El token se guarda en el llavero del Mac y se puede revocar desde Ajustes → Dispositivos en la web.")
                        .font(LifeOSFont.caption)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Alcance

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            LifeOSSectionHeader("Qué hace esta app")
            LifeOSCard {
                VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                    ScopeLine(
                        symbol: "checkmark.circle.fill",
                        tone: .positive,
                        text: "Cubre el ciclo diario: capturar, confirmar lo que LifeOS propone, tu día y la bandeja. Con ⌥Espacio desde cualquier aplicación y avisos del sistema."
                    )
                    ScopeLine(
                        symbol: "arrow.up.right.square",
                        tone: .accent,
                        text: "Objetivos, métricas, conocimiento, documentos, conectores de Google y copia portable siguen en la consola web, a un clic."
                    )
                    ScopeLine(
                        symbol: "server.rack",
                        tone: .warning,
                        text: "Necesita el servidor de LifeOS: sin él no puede funcionar, a diferencia del resto de aplicaciones de JUST4ALL."
                    )
                }
            }
        }
    }

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

// MARK: - Piezas

struct PreferenceRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: LifeOSSpace.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LifeOSFont.body)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                Text(detail)
                    .font(LifeOSFont.caption)
                    .foregroundStyle(LifeOSTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: LifeOSSpace.s)
            LifeOSSwitch(isOn: $isOn)
        }
    }
}

/// Interruptor del sistema, con versión estática para la revisión de diseño
/// (fuera de pantalla AppKit no pinta los controles).
struct LifeOSSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.lifeOSFlatSurfaces) private var renderMode

    var body: some View {
        if renderMode {
            Capsule()
                .fill(isOn ? LifeOSTheme.brand : LifeOSTheme.borderStrong)
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .padding(2)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                }
        } else {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(LifeOSTheme.brand)
        }
    }
}

struct ScopeLine: View {
    let symbol: String
    let tone: LifeOSTone
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: LifeOSSpace.s) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tone.foreground)
                .padding(.top, 2)
            Text(text)
                .font(LifeOSFont.bodySmall)
                .foregroundStyle(LifeOSTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
