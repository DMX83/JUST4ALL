import SwiftUI

/// Contenido del icono de la barra de menús: las mismas acciones que el menú del Dock, para
/// levantar una subapp de un clic.
struct MenuBarContent: View {
    var body: some View {
        Button("Abrir JUST4ALL") {
            SubAppLauncher.revealMainWindow()
        }

        Divider()

        ForEach(SubAppsCatalog.items) { app in
            Button {
                SubAppLauncher.open(app)
            } label: {
                Label(app.name, systemImage: app.systemIcon)
            }
        }

        Divider()

        Button("Salir de JUST4ALL") {
            NSApp.terminate(nil)
        }
    }
}
