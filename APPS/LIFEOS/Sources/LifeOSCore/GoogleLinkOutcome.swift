import Foundation

/// Cómo acabó el intento de vincular Google con la cuenta que ya está dentro.
///
/// Llega como el valor de `linked` en la vuelta a la app (`lifeos://auth?linked=…`)
/// porque hay desenlaces que **no** son errores técnicos sino explicaciones: que
/// esa cuenta de Google ya sea de otra persona, por ejemplo.
public enum GoogleLinkOutcome: String, Sendable, Equatable {
    /// Vinculada. A partir de ahora, entrar con Google lleva a esta cuenta.
    case ok
    /// Ya estaba vinculada a esta misma cuenta de Google.
    case already
    /// Esa cuenta de Google ya está vinculada a **otro** usuario de este servidor.
    case taken
    /// Esta cuenta ya tiene otra identidad de Google vinculada.
    case conflict
    /// El `state` caducó entre abrir la ventana y volver (10 minutos).
    case expired
    /// El servidor contestó algo que esta versión de la app no conoce.
    case unknown

    public var didLink: Bool {
        self == .ok || self == .already
    }

    /// Lo que se le cuenta a la persona. Sin jerga: qué ha pasado y qué hacer.
    public var message: String {
        switch self {
        case .ok:
            return "Listo: esta cuenta entra también con Google."
        case .already:
            return "Ya tenías esta cuenta de Google vinculada; no había nada que hacer."
        case .taken:
            return "Esa cuenta de Google ya está vinculada a otro usuario de este servidor. Entra con Google con tu cuenta de siempre, o usa otra cuenta de Google."
        case .conflict:
            return "Esta cuenta ya tiene otra cuenta de Google vinculada. Para cambiarla hay que quitarla antes (pídelo desde la web)."
        case .expired:
            return "Se tardó demasiado y el permiso caducó. Inténtalo otra vez."
        case .unknown:
            return "El servidor contestó algo que esta versión de la app no entiende. Actualiza la app."
        }
    }
}
