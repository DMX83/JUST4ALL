import Foundation
import UserNotifications
import J4ICore

/// N5 — Avisos del sistema: ««X» → «Y»» al terminar cada archivado.
///
/// Notas de entorno:
/// - Con la app instalada (bundle `.app` con identificador) usa `UNUserNotificationCenter` y
///   pide permiso la primera vez. En ejecución directa (`swift run`, sin bundle) no está
///   disponible: se deja una traza y se sigue sin avisos (no rompe nada).
/// - El interruptor vive en `UserDefaults` (`just4desk.notify.filing`, activado por defecto)
///   y se puede apagar desde Ajustes → Organización.
final class FilingNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = FilingNotifier()

    /// Clave del interruptor (la comparten Ajustes y este emisor).
    static let defaultsKey = "just4desk.notify.filing"

    private var activated = false

    var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Self.defaultsKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: Self.defaultsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.defaultsKey) }
    }

    /// ¿Puede usarse el centro de notificaciones? (requiere un bundle con identificador).
    var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    /// Configura el delegate y pide permiso (una sola vez por sesión; idempotente).
    func activate() {
        guard isAvailable else {
            J4Log.info(.app, "Avisos del sistema no disponibles en ejecución sin bundle .app (usa el DMG para verlos).")
            return
        }
        guard !activated else { return }
        activated = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                J4Log.warn(.app, "No se pudo pedir permiso para los avisos: \(error.localizedDescription)")
            } else {
                J4Log.info(.app, granted ? "Avisos del sistema autorizados." : "Avisos del sistema denegados en Ajustes del Sistema.")
            }
        }
    }

    /// Publica el aviso «archivado» (solo si el interruptor está activo y hay bundle).
    func notifyFiled(name: String, category: String) {
        guard isEnabled, isAvailable else { return }
        activate()
        let content = UNMutableNotificationContent()
        content.title = "Archivado"
        content.body = Self.body(name: name, category: category)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                J4Log.warn(.app, "No se pudo publicar el aviso: \(error.localizedDescription)")
            }
        }
    }

    /// Texto del aviso (separado para poder probarlo sin centro de notificaciones).
    static func body(name: String, category: String) -> String {
        "«\(name)» → «\(category)»"
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Con la app en primer plano los avisos también se muestran (banner + sonido).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
