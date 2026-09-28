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
    /// v2.0 — ordenar (clasificar + mover) la carpeta del panel activo (menú Operaciones, ⌥⌘O).
    static let j4fOrderFolder = Notification.Name("j4f.orderFolder")
    /// v2.0 — deshacer la última ordenación (⌥⌘Z).
    static let j4fUndoOrdering = Notification.Name("j4f.undoOrdering")
    /// Ola 2 — vista previa lateral (⌥⌘P).
    static let j4fTogglePreview = Notification.Name("j4f.togglePreview")
    /// v2.2 — alterna un solo panel ⇄ dos paneles (⌘\).
    static let j4fToggleSinglePanel = Notification.Name("j4f.toggleSinglePanel")
    /// Ola 2 — pestañas: duplicar / renombrar / mover.
    static let j4fDuplicateTab = Notification.Name("j4f.duplicateTab")
    static let j4fRenameTab = Notification.Name("j4f.renameTab")
    static let j4fMoveTabLeft = Notification.Name("j4f.moveTabLeft")
    static let j4fMoveTabRight = Notification.Name("j4f.moveTabRight")
    /// Ola 3 — paleta de comandos (⌘K) y workspaces.
    static let j4fCommandPalette = Notification.Name("j4f.commandPalette")
    static let j4fWorkspaceSave = Notification.Name("j4f.workspaceSave")
    static let j4fWorkspaceRestoreLast = Notification.Name("j4f.workspaceRestoreLast")
    static let j4fWorkspaceRestore = Notification.Name("j4f.workspaceRestore")
    /// Ola 3 — vista en galería (⌥⌘G).
    static let j4fToggleGallery = Notification.Name("j4f.toggleGallery")
    static let j4fTogglePanelTree = Notification.Name("j4f.togglePanelTree")
    static let j4fGalleryThumbSize = Notification.Name("j4f.galleryThumbSize")
    static let j4fToggleSemanticSearch = Notification.Name("j4f.toggleSemanticSearch")
    static let j4fEditShortcuts = Notification.Name("j4f.editShortcuts")
}

@main
struct Just4FoldersApp: App {
    @NSApplicationDelegateAdaptor(Just4FoldersAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        // v2.1 — tamaño de apertura sensato para un commander de doble panel.
        .defaultSize(width: 1320, height: 860)
        Settings {
            SettingsView()
        }
        .commands {
            CommandMenu("Navegación") {
                Button("Ir a ruta") {
                    NotificationCenter.default.post(name: .j4fFocusPathBar, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
                Button("Vista aplanada (panel activo)") {
                    NotificationCenter.default.post(name: .j4fToggleFlatView, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
                Divider()
                Button("Vista previa lateral") {
                    NotificationCenter.default.post(name: .j4fTogglePreview, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                Button("Vista en galería") {
                    NotificationCenter.default.post(name: .j4fToggleGallery, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .option])
                Button("Árbol en el panel") {
                    NotificationCenter.default.post(name: .j4fTogglePanelTree, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
                Button("Un solo panel (Tab alterna izq/der)") {
                    NotificationCenter.default.post(name: .j4fToggleSinglePanel, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)
                Menu("Tamaño de miniaturas") {
                    Button("Pequeñas") { NotificationCenter.default.post(name: .j4fGalleryThumbSize, object: nil, userInfo: ["size": "S"]) }
                    Button("Medianas") { NotificationCenter.default.post(name: .j4fGalleryThumbSize, object: nil, userInfo: ["size": "M"]) }
                    Button("Grandes") { NotificationCenter.default.post(name: .j4fGalleryThumbSize, object: nil, userInfo: ["size": "L"]) }
                }
                Divider()
                Button("Paleta de comandos") {
                    NotificationCenter.default.post(name: .j4fCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                Menu("Pestañas") {
                    Button("Duplicar pestaña") {
                        NotificationCenter.default.post(name: .j4fDuplicateTab, object: nil)
                    }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                    Button("Renombrar pestaña…") {
                        NotificationCenter.default.post(name: .j4fRenameTab, object: nil)
                    }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                    Divider()
                    Button("Mover a la izquierda") {
                        NotificationCenter.default.post(name: .j4fMoveTabLeft, object: nil)
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                    Button("Mover a la derecha") {
                        NotificationCenter.default.post(name: .j4fMoveTabRight, object: nil)
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                }
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
                Divider()
                Button("Ordenar esta carpeta…") {
                    NotificationCenter.default.post(name: .j4fOrderFolder, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .option])
                Button("Deshacer última ordenación") {
                    NotificationCenter.default.post(name: .j4fUndoOrdering, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .option])
                Divider()
                Button("Búsqueda semántica (IA)") {
                    NotificationCenter.default.post(name: .j4fToggleSemanticSearch, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
                Button("Editar atajos…") {
                    NotificationCenter.default.post(name: .j4fEditShortcuts, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
                Divider()
                Button("Guardar workspace…") {
                    NotificationCenter.default.post(name: .j4fWorkspaceSave, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                Button("Restaurar último workspace") {
                    NotificationCenter.default.post(name: .j4fWorkspaceRestoreLast, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
            }
        }
    }
}
