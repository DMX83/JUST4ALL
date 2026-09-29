import Foundation

/// v2.3.15 — Contrato explícito de qué tecla hace qué en la navegación del commander.
///
/// Nació de un malentendido real con el usuario: pidió «Return para volver» cuando la tecla que
/// usaba era **Retroceso (⌫)**. Además, en teclados **estilo Windows** la tecla grande está
/// rotulada «Enter» y muchos modelos la reportan a macOS como el **Enter del teclado numérico**
/// (keyCode 76 + `.numericPad`). Dejarlo aquí en un único sitio hace que el comportamiento sea
/// testeable y que nadie tenga que adivinarlo leyendo el monitor de teclas.
public enum KeyNavigationKeys {
    /// **Return / Enter** (36, y 76 del teclado numérico): **abrir** la selección — entrar en la
    /// carpeta o abrir el fichero con su app. Exactamente lo mismo que el doble clic, **F4** y
    /// **⌘↓**.
    public static let openSelection: Set<UInt16> = [36, 76]

    /// **Retroceso ⌫** (51): **volver a la ubicación anterior** (historial atrás; si no hay
    /// historial, subir un nivel). Es la convención de Windows Explorer y de muchos gestores de
    /// ficheros. Con el filtro rápido activo, ⌫ borra el último carácter del filtro.
    public static let goBack: Set<UInt16> = [51]

    /// ¿Este keyCode abre la selección? (Return / Enter / Enter del teclado numérico)
    public static func opensSelection(_ keyCode: UInt16) -> Bool {
        openSelection.contains(keyCode)
    }

    /// ¿Este keyCode vuelve a la ubicación anterior? (Retroceso ⌫)
    public static func goesBack(_ keyCode: UInt16) -> Bool {
        goBack.contains(keyCode)
    }
}
