import SwiftUI
import AppKit

final class Just4FoldersAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
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
