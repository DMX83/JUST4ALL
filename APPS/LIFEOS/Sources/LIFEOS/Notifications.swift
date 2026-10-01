import Foundation
import LifeOSAPI
// `@preconcurrency`: `UNUserNotificationCenter` no es `Sendable` y se captura en
// cierres de continuación. No hay carrera real (se usa siempre desde el hilo
// principal), y así el aviso no ensucia la compilación.
@preconcurrency import UserNotifications

/// Convierte los avisos que calcula el servidor en notificaciones del sistema.
///
/// Éste es el hueco que la web no puede cubrir y lo dice ella misma: mientras
/// LifeOS no está abierto, sus recordatorios no pueden sonar. Con la app del Mac
/// sí, siempre que esté en marcha (aunque sea en segundo plano).
@MainActor
final class NotificationScheduler {
    private let identifierPrefix = "lifeos.reminder."

    /// Pide permiso una sola vez. Devuelve si finalmente hay permiso.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Reprograma los avisos: se retiran los pendientes propios y se vuelven a
    /// poner los que aún están en el futuro.
    func schedule(_ reminders: [ReminderItem]) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(self.identifierPrefix) }
            if !identifiers.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
            }
        }

        let now = Date()
        for reminder in reminders {
            let fireDate = reminder.remindAt > now ? reminder.remindAt : reminder.at
            let interval = fireDate.timeIntervalSince(now)
            guard interval > 1 else { continue }

            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.detail.isEmpty
                ? "\(LifeOSKind.label(for: reminder.kind)) en LifeOS"
                : reminder.detail
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + reminder.id,
                content: content,
                trigger: trigger
            )
            center.add(request) { _ in }
        }
    }

    func cancelAll() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(self.identifierPrefix) }
            guard !identifiers.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }
}
