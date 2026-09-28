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
                .keyboardShortcut("l", modifiers: [.command])
            }
        }
    }
}
