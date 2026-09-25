import AppKit
import Carbon.HIToolbox
import Foundation
import J4ICore

/// Delegate de la app.
///
/// Instala un monitor local de `NSEvent` para los atajos globales (⌘E explorador, ⌘R revisar
/// sin clasificar, ⌘L registro, ⌘I ajustes de IA,
/// ⌘A ajustes — ⌘, también —): los
/// key equivalents del menú no son fiables cuando el binario se ejecuta directamente
/// (sin bundle `.app`), así que la captura se hace a nivel de eventos de la app.
/// Los comandos del menú Ver siguen existiendo para que los atajos se vean.
final class J4IAppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?
    private var quickSearch: QuickSearchPanelController?
    private var quickSearchHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.isARepeat,
                  let key = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else {
                return event
            }
            switch key {
            case "a":
                // Nota: sin passthrough de «Seleccionar todo» — el buscador autoenfocado lo
                // interceptaba casi siempre; ⌘A abre Ajustes en toda la app (decisión del usuario).
                J4Log.debug(.app, "Atajo ⌘A: abrir ajustes.")
                self.openSettings()
                return nil
            case "e":
                J4Log.debug(.app, "Atajo ⌘E: abrir explorador.")
                NotificationCenter.default.post(name: .j4iOpenExplorer, object: nil)
                return nil
            case "r":
                J4Log.debug(.app, "Atajo ⌘R: por revisar.")
                NotificationCenter.default.post(name: .j4iOpenReview, object: nil)
                return nil
            case "l":
                J4Log.debug(.app, "Atajo ⌘L: ver registro.")
                NotificationCenter.default.post(name: .j4iShowLogViewer, object: nil)
                return nil
            case "i":
                J4Log.debug(.app, "Atajo ⌘I: ajustes de IA.")
                SettingsTabRouter.pendingTab = "ai"
                NotificationCenter.default.post(name: .j4iOpenAISettings, object: nil)
                self.openSettings()
                return nil
            case ",":
                J4Log.debug(.app, "Atajo ⌘,: abrir ajustes.")
                self.openSettings()
                return nil
            default:
                return event
            }
        }

        // G4 — presencia: buscador rápido global (⌥Espacio) disponible desde cualquier app.
        let panelController = QuickSearchPanelController()
        quickSearch = panelController
        quickSearchHotKey = GlobalHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak panelController] in
            Task { @MainActor in panelController?.toggle() }
        }
        if quickSearchHotKey == nil {
            J4Log.warn(.app, "No se pudo registrar el atajo global ⌥Espacio (¿conflicto con otra app?)")
        } else {
            J4Log.info(.app, "Atajo global ⌥Espacio activo (buscador rápido).")
        }
    }

    /// G4 — «Enviar a JUST4DESK» desde el Finder (arrastrar al icono del Dock): los ficheros van
    /// al pipeline de archivado como si los soltaran en la carpeta de entrada (journal + undo).
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        J4Log.info(.app, "Enviados desde el Finder: \(files.count) elemento(s).")
        NotificationCenter.default.post(name: .j4iIngestFiles, object: files)
    }

    /// Abre la ventana de Ajustes con varias rutas (en ejecución directa, sin bundle `.app`, los
    /// selectores clásicos pueden responder sin mostrar nada):
    /// 1) notificación a `ContentView`, que usa la API moderna `openSettings` de SwiftUI (macOS 14+);
    /// 2) selectores clásicos (`showSettingsWindow:` / `showPreferencesWindow:`);
    /// 3) ítem ⌘, del menú de la aplicación. Cada ruta deja traza en el registro.
    private func openSettings() {
        NotificationCenter.default.post(name: .j4iRequestOpenSettings, object: nil)
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            J4Log.debug(.app, "Ajustes: abiertos por selector «showSettingsWindow:».")
            return
        }
        if NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) {
            J4Log.debug(.app, "Ajustes: abiertos por selector «showPreferencesWindow:».")
            return
        }
        if let appMenu = NSApp.mainMenu?.items.first?.submenu {
            for item in appMenu.items where item.keyEquivalent == "," {
                if let action = item.action {
                    NSApp.sendAction(action, to: item.target, from: item)
                    J4Log.debug(.app, "Ajustes: abiertos por ítem del menú ⌘,.")
                    return
                }
            }
        }
        J4Log.warn(.app, "Ajustes: solicitados sin confirmar por ninguna ruta clásica (ver traza de SwiftUI).")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
