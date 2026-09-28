import AppKit

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

    /// Color de marca: acento de selección, chips y estados activos.
    public static let brand = NSColor(srgbRed: 0.13, green: 0.55, blue: 0.52, alpha: 1.0)
    /// Fondo suave de marca (chips, resaltados).
    public static let brandSoft = brand.withAlphaComponent(0.16)

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
