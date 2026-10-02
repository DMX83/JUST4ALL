import SwiftUI

/// Puente entre los menús (Dock y barra de menús) y la ventana del hub.
///
/// Cuando desde fuera de la ventana se elige una subapp que no está instalada, aquí queda
/// apuntada para que la ventana la seleccione y abra su descarga: sin esto, elegirla en el
/// menú no haría nada visible.
final class HubBridge: ObservableObject {
    static let shared = HubBridge()

    @Published private(set) var pendingApp: SubApp?

    private init() {}

    func select(_ app: SubApp) {
        pendingApp = app
    }

    /// Devuelve la app pendiente y la olvida, para no repetir la acción.
    func takePendingApp() -> SubApp? {
        defer { pendingApp = nil }
        return pendingApp
    }
}
