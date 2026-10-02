import SwiftUI

@main
struct Just4AllApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: SubAppLauncher.mainWindowID) {
            ContentView()
        }
        .windowStyle(.titleBar)

        // Icono en la barra de menús (arriba, junto al reloj): un clic abre la lista de las
        // seis subapps para levantar la que quieras, sin pasar por la ventana.
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "square.grid.2x2.fill")
                .accessibilityLabel("JUST4ALL")
        }
        .menuBarExtraStyle(.menu)
    }
}
