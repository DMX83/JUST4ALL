import AppKit
import Carbon.HIToolbox
import LifeOSAPI
import LifeOSCore
import LifeOSUI
import SwiftUI

@main
struct LifeOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = LifeOSModel()

    var body: some Scene {
        WindowGroup("LifeOS", id: "home") {
            RootView(model: model)
                .onAppear { appDelegate.attach(model: model) }
                .task { await model.start() }
        }
        .defaultSize(width: 940, height: 620)
        .commands { commands }

        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            // La cifra de pendientes en el propio icono: la bandeja se mira de un
            // vistazo sin abrir nada.
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .frame(width: 560, height: 480)
        }
    }

    @CommandsBuilder
    private var commands: some Commands {
        CommandGroup(after: .newItem) {
            Button("Capturar…") {
                appDelegate.showQuickCapture()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Button("Actualizar") {
                Task { await model.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        CommandGroup(after: .appInfo) {
            Button("Abrir la consola de LifeOS en el navegador") {
                model.openWeb()
            }
        }
    }
}

/// Ciclo de vida: atajo global, panel de captura y avisos.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// ⌥Espacio, como en el buscador rápido de JUST4DESK.
    private static let hotKeyCode = UInt32(kVK_Space)
    private static let hotKeyModifiers = UInt32(optionKey)

    private let panel = QuickCapturePanelController()
    private let notifications = NotificationScheduler()
    private let intake = IntakeCoordinator()
    private var hotKey: GlobalHotKey?
    private weak var model: LifeOSModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // La app vive en el menú de barra: cerrar la ventana no la termina.
        NSApp.setActivationPolicy(.regular)
        applyAppearanceOverride()
        // El menú Servicios lee el Info.plist; esto refresca la lista sin esperar
        // a que el sistema vuelva a leerla.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// `LIFEOS --appearance dark|light` fija la apariencia sólo para esta
    /// instancia. Es una ayuda de desarrollo: permite revisar los dos temas sin
    /// cambiar el aspecto del Mac entero.
    private func applyAppearanceOverride() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--appearance"), index + 1 < arguments.count else {
            return
        }
        switch arguments[index + 1].lowercased() {
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        default:
            break
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func attach(model: LifeOSModel) {
        guard self.model == nil else { return }
        self.model = model
        panel.attach(model: model)
        intake.attach(model: model, panel: panel)

        model.remindersDidUpdate = { [weak self] reminders in
            guard let self else { return }
            guard model.notifyReminders else {
                self.notifications.cancelAll()
                return
            }
            self.notifications.schedule(reminders)
        }

        // Las dos preferencias se aplican en caliente: cambiar el atajo o el
        // arranque no debería exigir reiniciar la app.
        model.hotKeyPreferenceChanged = { [weak self] enabled in
            enabled ? self?.registerHotKey() : self?.unregisterHotKey()
        }
        model.launchAtLoginChanged = { [weak self] enabled in
            self?.applyLaunchAtLogin(enabled)
        }

        if model.hotKeyEnabled {
            registerHotKey()
        }
        applyLaunchAtLogin(model.launchAtLogin)
        Task { await notifications.requestAuthorization() }

        // `LIFEOS --quick-capture` abre directamente el panel de captura: sirve
        // para lanzarlo desde un script o un lanzador externo (y para las
        // capturas de validación).
        if CommandLine.arguments.contains("--quick-capture") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showQuickCapture()
            }
        }
    }

    func showQuickCapture() {
        panel.toggle()
    }

    // MARK: - Enviar a LifeOS

    /// Abrir un fichero con LifeOS (doble clic, «Abrir con», arrastrar al icono).
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { await intake.accept(files: urls) }
    }

    /// Menú Servicios → «Capturar en LifeOS».
    ///
    /// `NSServices` del `Info.plist` apunta a `sendSelection:` y el sistema pasa
    /// el portapapeles con lo seleccionado. El `userData` y el `error` son parte
    /// de la firma que espera AppKit aunque aquí no se usen.
    @objc func sendSelection(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let text = SelectionReader.text(from: pboard)
        guard let text else {
            error.pointee = "LifeOS espera texto: lo seleccionado no lo es." as NSString
            return
        }
        Task { await intake.accept(text: text) }
    }

    // MARK: - Atajo global

    private func registerHotKey() {
        guard hotKey == nil else { return }
        hotKey = GlobalHotKey(
            keyCode: Self.hotKeyCode,
            modifiers: Self.hotKeyModifiers
        ) { [weak self] in
            self?.showQuickCapture()
        }
    }

    private func unregisterHotKey() {
        hotKey?.release()
        hotKey = nil
    }

    // MARK: - Arranque al iniciar sesión

    private func applyLaunchAtLogin(_ enabled: Bool) {
        if let problem = LaunchAtLogin.apply(enabled) {
            model?.errorMessage = problem
        }
    }
}
