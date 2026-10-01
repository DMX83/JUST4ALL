import AppKit
import SwiftUI

// Sistema visual de LIFEOS para macOS.
//
// Traduce los tokens del sistema de diseño de LifeOS (`design-system/tokens/`)
// y la decisión DS-018 («rediseño estilo Apple») a Swift, con una diferencia
// obligada: aquí los colores son **dinámicos**. La web cambia de tema con una
// clase; una app de Mac tiene que seguir la apariencia del sistema sin que nadie
// toque nada, así que cada color tiene su valor en claro y en oscuro.
//
// Reglas que vienen del sistema de diseño y no se inventan aquí:
//   · Acento `#5e5ce6` (systemIndigo), no el violeta del manifiesto PWA.
//   · Radio: 6 / 10 / 14 / 18 / píldora.
//   · Sombras difusas y suaves, por jerarquía (xs → tarjeta, md → flotante).
//   · Tipografía del sistema con roles (display, heading, body, label, caption).
//   · DS-005: el texto secundario en claro es `#64707f` (contraste AA a 10–12 px).

// MARK: - Colores

/// Color con un valor distinto en claro y en oscuro, resuelto por macOS.
///
/// Es `internal` (no `private`) para que las escalas de la app — el ánimo y la energía de
/// `JournalScale` — añadan sus tonos con **la misma receta**, sin inventarse un segundo
/// modo de declarar colores.
func adaptive(light: String, dark: String) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(lifeOSHex: isDark ? dark : light)
    })
}

private extension NSColor {
    convenience init(lifeOSHex hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            srgbRed: CGFloat((value & 0xFF0000) >> 16) / 255,
            green: CGFloat((value & 0x00FF00) >> 8) / 255,
            blue: CGFloat(value & 0x0000FF) / 255,
            alpha: 1
        )
    }
}

public enum LifeOSTheme {
    /// Acento de la marca (`accent.600` del sistema de diseño).
    public static let brand = adaptive(light: "#5e5ce6", dark: "#5e5ce6")
    /// Acento al pasar por encima (`accent.500` claro, `accent.400` oscuro).
    public static let brandHi = adaptive(light: "#7c6df2", dark: "#9a8cff")
    /// Fondo de acento suave (chips, selección de barra lateral, operación elegida).
    /// En oscuro lleva tinte violeta: si fuera gris, «elegido» y «no elegido» se
    /// verían iguales.
    public static let brandSoft = adaptive(light: "#ece9ff", dark: "#282650")
    /// Texto sobre acento suave.
    public static let brandOnSoft = adaptive(light: "#4a48c7", dark: "#b9b0ff")

    /// Lienzo de la ventana.
    public static let canvas = adaptive(light: "#f5f5f7", dark: "#000000")
    /// Superficie de tarjeta.
    public static let surface = adaptive(light: "#ffffff", dark: "#1c1c1e")
    /// Superficie elevada (controles dentro de tarjetas, popovers).
    public static let elevated = adaptive(light: "#f2f2f7", dark: "#2c2c2e")
    /// Relleno de campos de texto.
    public static let field = adaptive(light: "#ffffff", dark: "#1c1c1e")

    /// Alias histórico del lienzo (lo usan las vistas como fondo de ventana).
    public static let background = canvas

    public static let borderSubtle = adaptive(light: "#e5e5ea", dark: "#2c2c2e")
    public static let borderDefault = adaptive(light: "#d1d1d6", dark: "#48484a")
    public static let borderStrong = adaptive(light: "#aeaeb2", dark: "#636366")
    /// Anillo de foco, distinto por tema (DS-008).
    public static let focusRing = adaptive(light: "#5e5ce6", dark: "#8b84ff")

    public static let textPrimary = adaptive(light: "#1d1d1f", dark: "#f5f5f7")
    /// DS-005: `#64707f` en claro para no fallar AA en texto de 10–12 px.
    public static let textSecondary = adaptive(light: "#64707f", dark: "#98989d")
    public static let textTertiary = adaptive(light: "#8e8e93", dark: "#8e8e93")

    public static let positive = adaptive(light: "#248a3d", dark: "#30d158")
    public static let positiveSoft = adaptive(light: "#e8f8ee", dark: "#18352a")
    public static let warning = adaptive(light: "#b25c00", dark: "#ff9f0a")
    public static let warningSoft = adaptive(light: "#fff4e6", dark: "#3a2c1a")
    public static let danger = adaptive(light: "#c42b25", dark: "#ff453a")
    public static let dangerSoft = adaptive(light: "#ffebeb", dark: "#3a1c1c")
    public static let info = adaptive(light: "#007aff", dark: "#0a84ff")
    public static let infoSoft = adaptive(light: "#eaf3ff", dark: "#1c2c4a")

    public static let onBrand = Color.white
}

// MARK: - Modo de render

/// Cuando se renderizan las vistas fuera de pantalla (revisión de diseño en un
/// test, sin ventana), los materiales del sistema no se pintan y salen negros.
/// Con esto se cambian por el color de superficie equivalente.
private struct FlatSurfacesKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var lifeOSFlatSurfaces: Bool {
        get { self[FlatSurfacesKey.self] }
        set { self[FlatSurfacesKey.self] = newValue }
    }
}

// MARK: - Espaciado, radios y sombras

/// Base de 4 px (DS-001).
public enum LifeOSSpace {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

/// Escala de radios (DS-002 + DS-018).
public enum LifeOSRadius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 14
    public static let xl: CGFloat = 18
    public static let pill: CGFloat = 999
    /// Alias: superficie de tarjeta.
    public static let card: CGFloat = lg
    /// Alias: panel flotante.
    public static let panel: CGFloat = xl
}

/// Sombras por jerarquía (DS-004), con los valores difusos de DS-018.
public enum LifeOSShadow {
    case xs
    case sm
    case md
    case lg

    var color: Color {
        Color.black.opacity(opacity)
    }

    private var opacity: Double {
        switch self {
        case .xs: return 0.06
        case .sm: return 0.05
        case .md: return 0.10
        case .lg: return 0.12
        }
    }

    var radius: CGFloat {
        switch self {
        case .xs: return 1.5
        case .sm: return 6
        case .md: return 14
        case .lg: return 22
        }
    }

    var offsetY: CGFloat {
        switch self {
        case .xs: return 1
        case .sm: return 2
        case .md: return 8
        case .lg: return 16
        }
    }
}

public extension View {
    /// Aplica una sombra del sistema.
    func lifeOSShadow(_ level: LifeOSShadow) -> some View {
        shadow(color: level.color, radius: level.radius, x: 0, y: level.offsetY)
    }
}

// MARK: - Tipografía

/// Roles tipográficos del sistema de diseño (DS-003), con las fuentes del
/// sistema. Son tamaños concretos a propósito: en macOS eso es lo que mantiene
/// la jerarquía estable entre ventanas.
public enum LifeOSFont {
    /// display/heading.xl — 28/800 (marca)
    public static let display = Font.system(size: 28, weight: .heavy)
    /// Título de pantalla — heading.lg del sistema (25/750): menos peso visual
    /// que la marca, que una app de uso diario no necesita gritar.
    public static let screenTitle = Font.system(size: 24, weight: .bold)
    /// heading.md — 20/750
    public static let title = Font.system(size: 20, weight: .bold)
    /// heading.xs — 15/700
    public static let subtitle = Font.system(size: 15, weight: .semibold)
    /// body.lg — 14/400
    public static let bodyLarge = Font.system(size: 14)
    /// body.md — 13/400
    public static let body = Font.system(size: 13)
    /// body.sm — 12/400
    public static let bodySmall = Font.system(size: 12)
    /// label.lg — 12/650
    public static let label = Font.system(size: 12, weight: .semibold)
    /// label.md — 11/650
    public static let labelSmall = Font.system(size: 11, weight: .semibold)
    /// caption — 10/600
    public static let caption = Font.system(size: 10, weight: .semibold)
    /// eyebrow — 10/800, mayúsculas, tracking amplio
    public static let eyebrow = Font.system(size: 10, weight: .heavy)
    /// Números alineados (cifras de tarjetas y horas).
    public static let metric = Font.system(size: 26, weight: .bold).monospacedDigit()
    public static let mono = Font.system(size: 12, weight: .medium, design: .monospaced)
}

/// Tracking del sistema para títulos (DS-018: display/heading con tracking
/// negativo) y para los eyebrows.
public enum LifeOSTracking {
    public static let heading: CGFloat = -0.6
    public static let eyebrow: CGFloat = 1.4
}

// MARK: - Movimiento (DS-013)

public enum LifeOSMotion {
    public static let fast: Double = 0.12
    public static let normal: Double = 0.20
    public static let slow: Double = 0.28

    /// `cubic-bezier(0.2, 0, 0, 1)` del sistema de diseño.
    public static var standard: Animation {
        .timingCurve(0.2, 0, 0, 1, duration: normal)
    }

    /// Respeta «Reducir movimiento» del sistema.
    public static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
