import Foundation

/// Nombres de notificación usados como puente entre los comandos de menú/Ajustes
/// y la ventana principal (`SearchViewModel`).
extension Notification.Name {
    /// Abrir el explorador (comando de menú ⌘E).
    static let j4iOpenExplorer = Notification.Name("j4i.openExplorer")
    /// Abrir la cola de revisión de pendientes (comando de menú ⌘R).
    static let j4iOpenReview = Notification.Name("j4i.openReview")
    /// Abrir la ventana «Buscar» (comando de menú ⌘F).
    static let j4iOpenSearch = Notification.Name("j4i.openSearch")
    /// Enfocar el omnibox de «Inicio» (comando de menú ⌘K).
    static let j4iFocusOmnibox = Notification.Name("j4i.focusOmnibox")
    /// Mostrar el visor de registro (comando de menú ⌘L).
    static let j4iShowLogViewer = Notification.Name("j4i.showLogViewer")
    /// Abrir la ventana «Reglas» (comando de menú ⌘G).
    static let j4iOpenRules = Notification.Name("j4i.openRules")
    /// Abrir la ventana «Chat del archivo» (comando de menú ⇧⌘K).
    static let j4iOpenChat = Notification.Name("j4i.openChat")
    /// N8 — ⌘Z global: deshacer el último archivado (lo emite el monitor de atajos).
    static let j4iUndoLast = Notification.Name("j4i.undoLast")
    /// N7 — abrir la ventana «Estadísticas» (comando de menú ⌘T).
    static let j4iOpenStats = Notification.Name("j4i.openStats")
    /// Ficheros «enviados a JUST4DESK» desde el Finder (drop en el icono del Dock; object: [URL]).
    static let j4iIngestFiles = Notification.Name("j4i.ingestFiles")
    /// La configuración de archivado ha cambiado (la emite `SearchViewModel`; la escuchan Ajustes/explorador).
    static let j4iFilingConfigChanged = Notification.Name("j4i.filingConfigChanged")
    /// Ajustes → activar/desactivar modo simulación (object: Bool).
    static let j4iSetSimulationMode = Notification.Name("j4i.setSimulationMode")
    /// Ajustes → pausar/reanudar organización (object: Bool).
    static let j4iSetPaused = Notification.Name("j4i.setPaused")
    /// Ajustes → nueva carpeta de organización (object: String).
    static let j4iSetFilingRoot = Notification.Name("j4i.setFilingRoot")
    /// Ajustes → nueva carpeta de entrada (object: String).
    static let j4iSetSourceFolder = Notification.Name("j4i.setSourceFolder")
    /// Ajustes → añadir una carpeta de entrada (object: String); pueden coexistir varias (N4).
    static let j4iAddSourceFolder = Notification.Name("j4i.addSourceFolder")
    /// Ajustes → quitar una carpeta de entrada (object: String).
    static let j4iRemoveSourceFolder = Notification.Name("j4i.removeSourceFolder")
    /// Ajustes → activar/desactivar la IA de clasificación (object: Bool).
    static let j4iSetAIEnabled = Notification.Name("j4i.setAIEnabled")
    /// Ajustes → límite diario de llamadas a la IA (object: Int).
    static let j4iSetAIDailyLimit = Notification.Name("j4i.setAIDailyLimit")
    /// Abrir Ajustes en la pestaña «IA» (⌘I).
    static let j4iOpenAISettings = Notification.Name("j4i.openAISettings")
    /// Pedir la apertura de la ventana de Ajustes (la atiende ContentView con `openSettings` de SwiftUI).
    static let j4iRequestOpenSettings = Notification.Name("j4i.requestOpenSettings")
    /// Ajustes → añadir carpeta al índice (sin object).
    static let j4iRequestAddRoot = Notification.Name("j4i.requestAddRoot")
    /// Ajustes → reindexar una carpeta (object: Int64 rootID).
    static let j4iRequestRootReindex = Notification.Name("j4i.requestRootReindex")
    /// Ajustes → quitar una carpeta del índice (object: Int64 rootID).
    static let j4iRequestRootRemoval = Notification.Name("j4i.requestRootRemoval")
}

/// Router simple de la pestaña de Ajustes a mostrar.
///
/// El delegate (⌘I) deja aquí la intención y la vista la recoge: la ventana de `Settings` puede
/// no existir todavía cuando se pulsa el atajo, así que la notificación sola no basta.
/// Acceso siempre desde el hilo principal (eventos de teclado y ciclo de vida de SwiftUI).
enum SettingsTabRouter {
    static var pendingTab: String?
}
