import Foundation
import ServiceManagement

/// Abrir LifeOS al iniciar sesión en el Mac.
///
/// Se usa `SMAppService.mainApp` (macOS 13+) y no un `LaunchAgent` propio: así el
/// sistema lo enseña en **Ajustes → General → Ítems de inicio**, el usuario puede
/// quitarlo desde ahí, y la app no deja ficheros sueltos en `~/Library`.
///
/// Ojo: un `SMAppService` registra **la app en la ruta donde está**. Si se
/// registra desde una carpeta de compilación y luego se mueve el `.app`, macOS
/// no encontrará nada; por eso el mensaje de error lo dice en vez de callarse.
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Aplica la preferencia. Devuelve el motivo si no se pudo, `nil` si fue bien.
    @discardableResult
    public static func apply(_ enabled: Bool) -> String? {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return nil }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return nil }
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            if enabled {
                return """
                    No se pudo hacer que LifeOS se abra al iniciar sesión: \(error.localizedDescription). \
                    Si la app se está ejecutando desde una carpeta de compilación, muévela a Aplicaciones \
                    y vuelve a intentarlo.
                    """
            }
            return "No se pudo quitar el arranque automático: \(error.localizedDescription)"
        }
    }
}
