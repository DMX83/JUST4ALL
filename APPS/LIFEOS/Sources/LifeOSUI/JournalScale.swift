import SwiftUI

/// La escala de 1 a 5 del **ánimo** y la **energía**: con color y con palabra.
///
/// ## Por qué lleva color (decisión del 30-sep-2026, a petición del dueño)
///
/// El ánimo y la energía son escalas ordinales: 5 siempre es «más» que 1. Pintarlas de
/// **rojo a verde** hace que el día se lea de un vistazo y es la convención que ya
/// conoce cualquiera que haya usado un registro de salud.
///
/// ## Lo que el color NO puede hacer solo
///
/// Rojo y verde son justo el par que no distingue alrededor del 8 % de los hombres
/// (deuteranopia), así que aquí el color es **refuerzo, nunca el único canal**:
///
/// · los puntos **encendidos** ya dicen el valor por su número (no hace falta el color),
/// · cada punto lleva su **palabra** en el `help` y en el lector de pantalla
///   («Ánimo 4 de 5: Bien»),
/// · el nivel elegido se **escribe** al lado de los puntos, en su color: quien no
///   distinga el rojo del verde lee «Bien» y sabe lo mismo,
/// · los puntos **sin elegir** conservan el anillo de su color, así que la escala
///   completa (rojo → verde) se ve aunque no haya nada seleccionado: funciona de leyenda.
///
/// ## Los tonos
///
/// Son dinámicos (claro/oscuro) como el resto de `LifeOSTheme`, con la misma receta
/// `adaptive`. Los extremos **reutilizan los tokens que ya existían** — el 1 es el rojo de
/// `danger` y el 5 el verde de `positive` — para no tener dos rojos distintos en la app.
///
/// ## Las palabras
///
/// Son **las mismas que la web** (`web/components/journal-view.tsx`, `MOOD_LABELS` y
/// `ENERGY_LABELS`): quien use la app y la web tiene que leer exactamente lo mismo.
public enum JournalScale {
    /// De qué escala se habla. No comparten palabras: «Bien» no significa lo mismo en
    /// energía que en ánimo.
    public enum Kind: Sendable {
        case mood
        case energy

        /// Cómo se llama la escala cuando hay que decirla en voz alta.
        public var name: String {
            switch self {
            case .mood: return "Ánimo"
            case .energy: return "Energía"
            }
        }
    }

    /// Los cinco niveles, en orden.
    public static let levels: [Int] = [1, 2, 3, 4, 5]

    /// Un escalón de la escala: el mismo color resuelto en claro y en oscuro.
    public struct Step: Sendable {
        public let light: String
        public let dark: String
    }

    /// De rojo (1) a verde (5).
    public static let steps: [Step] = [
        Step(light: "#c42b25", dark: "#ff453a"), // 1 · rojo (token `danger`)
        Step(light: "#d9730d", dark: "#ff9f0a"), // 2 · naranja
        Step(light: "#a98200", dark: "#ffd60a"), // 3 · ámbar
        Step(light: "#4f8f22", dark: "#a3e05a"), // 4 · verde claro
        Step(light: "#248a3d", dark: "#30d158")  // 5 · verde (token `positive`)
    ]

    /// El escalón al que corresponde un nivel (0 para el 1). Fuera de rango se **recorta**
    /// a los extremos en lugar de reventar: si un servidor manda un 7, se ve el 5.
    public static func stepIndex(for level: Int) -> Int {
        min(max(level, 1), steps.count) - 1
    }

    /// Color del nivel (1…5).
    public static func color(for level: Int) -> Color {
        let step = steps[stepIndex(for: level)]
        return adaptive(light: step.light, dark: step.dark)
    }

    /// La palabra del nivel, igual que en la web.
    public static func label(_ kind: Kind, for level: Int) -> String {
        guard levels.contains(level) else { return "\(level) de 5" }
        switch kind {
        case .mood:
            return ["Muy bajo", "Bajo", "Neutro", "Bien", "Muy bien"][level - 1]
        case .energy:
            return ["Sin energía", "Baja", "Media", "Alta", "Mucha"][level - 1]
        }
    }

    /// Lo que se lee en voz alta (lector de pantalla y `help`): **palabra y número**,
    /// porque el color no basta y el número solo tampoco dice si es bueno o malo.
    public static func spoken(_ kind: Kind, for level: Int) -> String {
        "\(kind.name) \(level) de 5: \(label(kind, for: level))"
    }
}
