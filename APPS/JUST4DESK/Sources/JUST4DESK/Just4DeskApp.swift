import SwiftUI
import AppKit

@main
struct Just4DeskApp: App {
    @NSApplicationDelegateAdaptor(J4IAppDelegate.self) private var appDelegate
    /// Motor compartido (G1): «Inicio» y «Buscar» usan el mismo modelo (arranque idempotente).
    @StateObject private var engine = SearchViewModel()

    var body: some Scene {
        WindowGroup("JUST4DESK") {
            HomeView()
                .environmentObject(engine)
                .tint(J4I.brand)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        guard let window = NSApplication.shared.windows.first else { return }
                        window.title = "JUST4DESK"
                        window.makeKeyAndOrderFront(nil)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Abrir explorador") {
                    NotificationCenter.default.post(name: .j4iOpenExplorer, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
                Button("Por revisar") {
                    NotificationCenter.default.post(name: .j4iOpenReview, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Buscar…") {
                    NotificationCenter.default.post(name: .j4iOpenSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("Ir al buscador") {
                    NotificationCenter.default.post(name: .j4iFocusOmnibox, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                Button("Ver registro") {
                    NotificationCenter.default.post(name: .j4iShowLogViewer, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
                Button("Reglas aprendidas") {
                    NotificationCenter.default.post(name: .j4iOpenRules, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)
                Button("Ajustes de IA") {
                    SettingsTabRouter.pendingTab = "ai"
                    NotificationCenter.default.post(name: .j4iOpenAISettings, object: nil)
                    NotificationCenter.default.post(name: .j4iRequestOpenSettings, object: nil)
                    if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
                .keyboardShortcut("i", modifiers: .command)
                Button("Abrir ajustes") {
                    NotificationCenter.default.post(name: .j4iRequestOpenSettings, object: nil)
                    if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
                .keyboardShortcut("a", modifiers: .command)
            }
        }

        Window("Buscar", id: "search") {
            ContentView()
                .environmentObject(engine)
                .tint(J4I.brand)
        }
        .defaultSize(width: 1020, height: 680)

        Window("Explorador", id: "explorer") {
            ExplorerView()
                .tint(J4I.brand)
        }
        .defaultSize(width: 1080, height: 640)

        Window("Por revisar", id: "review") {
            ReviewView()
                .tint(J4I.brand)
        }
        .defaultSize(width: 820, height: 560)

        Window("Reglas", id: "rules") {
            RulesView()
                .tint(J4I.brand)
        }
        .defaultSize(width: 760, height: 560)

        Settings {
            SettingsView()
                .tint(J4I.brand)
        }
    }
}
