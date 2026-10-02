import SwiftUI
import AppKit

@main
struct Just4PictApp: App {
    private let launchSessionID = UUID()

    init() {
        // Modo CLI (`just4pict-cli`): si el primer argumento es un comando conocido se ejecuta
        // el lote SIN UI y se sale. Sin argumentos (o con algo que no es un comando, p. ej. la
        // ruta de un documento al abrir la app) arranca la interfaz normal.
        let arguments = Array(CommandLine.arguments.dropFirst())
        if Just4PictCLI.isCLIInvocation(arguments) {
            exit(Just4PictCLI.run(arguments: arguments))
        }
    }

    var body: some Scene {
        // El sello de compilación vive en el tooltip del título, no en la barra: al usuario no
        // le dice nada y ensuciaba la única línea que se lee de un vistazo.
        WindowGroup("JUST4PICT") {
            ContentView(
                initialFormat: .preferredDefault,
                initialQuality: OutputFormat.preferredQualityDefault
            )
                .id(launchSessionID)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        guard let window = NSApplication.shared.windows.first else { return }
                        window.title = "JUST4PICT"
                        window.makeKeyAndOrderFront(nil)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
