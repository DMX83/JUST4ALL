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
        WindowGroup("JUST4PICT \(BuildInfo.displayLabel)") {
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
                        window.title = "JUST4PICT \(BuildInfo.displayLabel)"
                        window.makeKeyAndOrderFront(nil)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
