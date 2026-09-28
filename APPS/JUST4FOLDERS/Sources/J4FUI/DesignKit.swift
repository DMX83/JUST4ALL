import AppKit

/// v2.1.1 — Estilos visuales de la app (elegibles en Ajustes ▸ Apariencia).
///
/// Cada estilo define el color de marca con el que se acentúan chips, estados activos y
/// controles (el `J4FDesign` lo lee en vivo, sin recompilar ni reiniciar).
public enum J4FVisualStyle: String, CaseIterable, Identifiable, Sendable {
    case esmeralda
    case oceano
    case amatista
    case grafito
    case sistema

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .esmeralda: return "Esmeralda"
        case .oceano: return "Océano"
        case .amatista: return "Amatista"
        case .grafito: return "Grafito"
        case .sistema: return "Color del sistema"
        }
    }

    public var detail: String {
        switch self {
        case .esmeralda: return "Verde azulado de serie: sobrio y con personalidad."
        case .oceano: return "Azul profundo, cercano al Finder pero con más carácter."
        case .amatista: return "Morado suave, para un toque más distintivo."
        case .grafito: return "Neutro monócromo, sin acento de color."
        case .sistema: return "Usa el color de acento configurado en macOS."
        }
    }

    public var brand: NSColor {
        switch self {
        case .esmeralda: return NSColor(srgbRed: 0.13, green: 0.55, blue: 0.52, alpha: 1.0)
        case .oceano: return NSColor(srgbRed: 0.10, green: 0.45, blue: 0.82, alpha: 1.0)
        case .amatista: return NSColor(srgbRed: 0.50, green: 0.33, blue: 0.75, alpha: 1.0)
        case .grafito: return NSColor(srgbRed: 0.38, green: 0.40, blue: 0.43, alpha: 1.0)
        case .sistema: return .controlAccentColor
        }
    }
}

/// v2.1 — Sistema visual de JUST4FOLDERS (J4FUI).
///
/// Tokens y componentes compartidos para dar identidad a la app **sin cambiar su layout**:
/// espacio, radios, color de marca (teal) y tipografías semánticas. Espejo del `J4I`
/// DesignKit de JUST4DESK, adaptado al tono de un commander de ficheros.
public enum J4FDesign {

    // MARK: - Tokens

    public enum Space {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
    }

    public enum Radius {
        public static let small: CGFloat = 6
        public static let medium: CGFloat = 10
    }

    // MARK: - Estilos visuales

    /// Estilo activo: lo fija el commander al arrancar y al cambiar en Ajustes.
    public static var currentStyle: J4FVisualStyle = .esmeralda

    /// Color de marca: acento de selección, chips y estados activos (según el estilo activo).
    public static var brand: NSColor { currentStyle.brand }
    /// Fondo suave de marca (chips, resaltados).
    public static var brandSoft: NSColor { brand.withAlphaComponent(0.16) }

    // MARK: - Tipografía semántica

    public static func titleFont() -> NSFont { .systemFont(ofSize: 12.5, weight: .semibold) }
    public static func captionFont() -> NSFont { .systemFont(ofSize: 11) }
    public static func microFont() -> NSFont { .systemFont(ofSize: 10.5, weight: .medium) }

    // MARK: - Componentes

    /// Tarjeta suave: fondo de control translúcido, borde sutil y radio.
    public static func styleCard(_ view: NSView, radius: CGFloat = Radius.medium) {
        view.wantsLayer = true
        view.layer?.cornerRadius = radius
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
    }
}
