import SwiftUI
import AppKit

final class Just4FoldersAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.configureSharedLogging()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    /// Los motores compartidos (J4IIndex/J4Log) escriben su registro según `J4I_LOG_FILE`:
    /// en JUST4FOLDERS va a su propio archivo (no al de JUST4DESK) y con su propio subdominio.
    private static func configureSharedLogging() {
        let environment = ProcessInfo.processInfo.environment
        if environment["J4I_LOG_FILE"] == nil {
            let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
            setenv("J4I_LOG_FILE", base.appendingPathComponent("Logs/JUST4FOLDERS/just4folders.log").path, 1)
        }
        if environment["J4I_LOG_SUBSYSTEM"] == nil {
            setenv("J4I_LOG_SUBSYSTEM", "com.dmx83.just4folders", 1)
        }
    }
}

extension Notification.Name {
    /// v1.2 — alterna la vista aplanada del panel activo (menú Navegación, ⌥⌘F).
    static let j4fToggleFlatView = Notification.Name("j4f.toggleFlatView")
    /// v1.2 — renombrado en lote del panel activo (menú Operaciones, ⇧⌘R).
    static let j4fBatchRename = Notification.Name("j4f.batchRename")
    /// v1.2 — búsqueda de duplicados bajo la carpeta del panel activo (menú Operaciones, ⇧⌘D).
    static let j4fFindDuplicates = Notification.Name("j4f.findDuplicates")
}

@main
struct Just4FoldersApp: App {
    @NSApplicationDelegateAdaptor(Just4FoldersAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        Settings {
            SettingsView()
        }
        .commands {
            CommandMenu("Navegacion") {
                Button("Ir a ruta") {
                    NotificationCenter.default.post(name: .j4fFocusPathBar, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
                Button("Vista aplanada (panel activo)") {
                    NotificationCenter.default.post(name: .j4fToggleFlatView, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
            }
            CommandMenu("Operaciones") {
                Button("Renombrar en lote…") {
                    NotificationCenter.default.post(name: .j4fBatchRename, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Buscar duplicados…") {
                    NotificationCenter.default.post(name: .j4fFindDuplicates, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
}
