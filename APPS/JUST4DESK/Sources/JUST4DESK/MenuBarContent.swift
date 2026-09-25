import AppKit
import SwiftUI

/// G4 — Menú de barra: estado y acciones rápidas sin abrir ninguna ventana.
///
/// Se refresca al abrir el menú (`.task`) para que el contador de pendientes y la actividad
/// estén al día; los toggles llaman directamente al motor compartido.
struct MenuBarContent: View {
    @EnvironmentObject private var viewModel: SearchViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button("Abrir JUST4DESK") {
                openWindow(id: "home")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button(viewModel.quarantineCount > 0 ? "Por revisar (\(viewModel.quarantineCount))…" : "Por revisar…") {
                openWindow(id: "review")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Buscar…") {
                openWindow(id: "search")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Reglas…") {
                openWindow(id: "rules")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Toggle("Organización pausada", isOn: Binding(
                get: { viewModel.organizationPaused },
                set: { newValue in
                    if newValue != viewModel.organizationPaused {
                        viewModel.toggleOrganizationPaused()
                    }
                }
            ))
            Toggle("Modo simulación", isOn: Binding(
                get: { viewModel.simulationMode },
                set: { newValue in
                    if newValue != viewModel.simulationMode {
                        viewModel.simulationMode = newValue
                    }
                }
            ))
            Divider()
            Text("Hoy: \(viewModel.organizedTodayCount) archivado(s) · \(viewModel.quarantineCount) por revisar")
            Divider()
            Button("Ajustes…") {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .j4iRequestOpenSettings, object: nil)
                if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                    _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            }
            Button("Salir de JUST4DESK") {
                NSApp.terminate(nil)
            }
        }
        .task {
            await viewModel.refreshActivity()
        }
    }
}
