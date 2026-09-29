import AppKit

/// v2.3.14 — Normalización de modificadores para los atajos «sin modificadores» (Return, Espacio,
/// Tab, F1–F12, filtro rápido…).
///
/// Motivo (incidencia real): en un teclado **estilo Windows** la tecla grande «Enter» puede llegar
/// a macOS como *Enter del teclado numérico* (keyCode 76) y **siempre** con el modificador
/// `.numericPad`; además macOS marca `.function` en F1–F12/flechas y `.capsLock` cuando el Bloqueo
/// de mayúsculas está activo. Con la comprobación antigua (`flags == []`) esas teclas no hacían
/// nada, sin ningún motivo visible para el usuario.
public enum KeyNavigationFlags {
    /// Modificadores «de ruido»: no expresan intención del usuario y no deben invalidar un atajo.
    public static let noise: NSEvent.ModifierFlags = [.capsLock, .numericPad, .function]

    /// Modificadores significativos (⌘ ⌥ ⇧ ⌃), descartando el ruido.
    public static func significant(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(noise)
    }
}
