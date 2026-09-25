import AppKit
import SwiftUI

/// Sistema de diseño de JUST4INDEX (F15.0).
///
/// Objetivo: una identidad coherente y «vendible» sin pelearse con macOS — materiales y
/// jerarquía nativos, pero con marca propia (índigo), radios y espaciados consistentes y
/// componentes reutilizables (chip, tarjeta, cabeceras, estados vacíos, píldoras de estado).
///
/// Reglas de la casa:
/// - Los colores son de sistema (`NSColor`): se adaptan solos a claro/oscuro y a la vibrancy.
/// - Los radios salen de `J4I.Radius`; los huecos, de `J4I.Space`; nada ad-hoc.
/// - Los títulos usan `design: .rounded`; los números, cifras tabulares.
enum J4I {

    // MARK: - Espaciado y radios

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
    }

    // MARK: - Colores

    /// Color de marca (índigo del sistema; se adapta a claro/oscuro).
    static var brand: Color { Color(nsColor: .systemIndigo) }
    /// Marca al 14 % — fondos suaves de selección y realces.
    static var brandSoft: Color { Color(nsColor: .systemIndigo).opacity(0.14) }
    /// Degradado de la marca (logos y estados vacíos).
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [Color(nsColor: .systemIndigo), Color(nsColor: .systemPurple)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var success: Color { Color(nsColor: .systemGreen) }
    static var warning: Color { Color(nsColor: .systemOrange) }
    static var danger: Color { Color(nsColor: .systemRed) }

    /// Superficie elevada (tarjetas sobre el fondo de la ventana).
    static var surface: Color { Color(nsColor: .controlBackgroundColor) }
    /// Pozo (campos de texto, listas hundidas).
    static var well: Color { Color(nsColor: .textBackgroundColor) }
    /// Filete de 1 px (bordes de tarjetas y separadores internos).
    static var hairline: Color { Color(nsColor: .separatorColor) }

    /// Sombra de tarjeta (muy sutil, dos capas).
    static var cardShadow: Color { Color.black.opacity(0.06) }
}

// MARK: - Marca

/// Marca de la app: cuadro redondeado con degradado índigo→violeta y el glifo (documento + lupa).
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(J4I.brandGradient)
            .overlay(
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: J4I.brand.opacity(0.35), radius: size * 0.2, y: size * 0.08)
            .accessibilityLabel("JUST4INDEX")
    }
}

// MARK: - Chips (filtros, toggles y menús)

/// Contenido visual de un chip, reutilizable dentro de botones y menús.
struct ChipLabel: View {
    let title: String
    var systemImage: String?
    var selected = false
    var hovering = false
    /// Marca de verificación a la izquierda (chips de estado on/off).
    var hasCheckmark = false
    /// Chevron a la derecha (chips que abren un desplegable).
    var showsChevron = false

    var body: some View {
        HStack(spacing: 5) {
            if hasCheckmark {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(selected ? Color.white : J4I.brand)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 10)
            }
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
            }
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .fixedSize()
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, hasCheckmark ? 8 : 10)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(
                selected
                    ? J4I.brand
                    : (hovering ? Color.primary.opacity(0.10) : Color.primary.opacity(0.055))
            )
        )
        .overlay(
            Capsule().strokeBorder(
                selected ? Color.clear : J4I.hairline.opacity(0.55)
            )
        )
        .contentShape(Capsule())
    }
}

/// Chip accionable (filtro de tipo, etc.).
struct Chip: View {
    let title: String
    var systemImage: String?
    var selected = false
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ChipLabel(title: title, systemImage: systemImage, selected: selected, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: selected)
        .help(help)
    }
}

/// Chip conmutable (opciones on/off estilo «Solo carpetas», «En contenido»).
struct ToggleChip: View {
    let title: String
    var systemImage: String?
    @Binding var isOn: Bool
    var help: String = ""
    @State private var hovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ChipLabel(title: title, systemImage: systemImage, selected: isOn, hovering: hovering, hasCheckmark: true)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isOn)
        .help(help)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - Tarjetas

/// Tarjeta elevada: superficie, filete y sombra sutil.
struct J4ICard<Content: View>: View {
    var padding: CGFloat = J4I.Space.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: J4I.Radius.medium, style: .continuous)
                    .fill(J4I.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: J4I.Radius.medium, style: .continuous)
                    .strokeBorder(J4I.hairline.opacity(0.55))
            )
            .shadow(color: J4I.cardShadow, radius: 8, y: 2)
    }
}

// MARK: - Cabeceras

/// Cabecera de sección en versalitas («CARPETAS», «FICHEROS»…).
struct SectionHeader<Trailing: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, systemImage: String? = nil) {
        self.init(title: title, systemImage: systemImage) { EmptyView() }
    }
}

/// Fila de propiedades del inspector: etiqueta a la izquierda, valor alineado a la derecha.
struct PropertyRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .modifier(MonospacedIf(enabled: monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2.5)
    }
}

private struct MonospacedIf: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.monospacedDigit()
        } else {
            content
        }
    }
}

// MARK: - Estado

/// Píldora de estado con icono (organización activa/pausada, cuarentena…).
struct StatusPill: View {
    let systemImage: String
    let title: String
    var tint: Color = J4I.success
    var help: String = ""
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { pill }
                    .buttonStyle(.plain)
                    .help(help)
            } else {
                pill.help(help)
            }
        }
    }

    private var pill: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.13)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.25)))
    }
}

/// Estado vacío consistente: marca/icono en placa suave + título + mensaje + acciones.
struct J4IEmptyState<Actions: View>: View {
    let systemImage: String
    let title: String
    var message: String?
    var tint: Color = J4I.brand
    /// Si es `true`, dibuja la marca de la app en lugar del símbolo suelto.
    var usesBrandMark = false
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: J4I.Space.l) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 84, height: 84)
                if usesBrandMark {
                    BrandMark(size: 52)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(tint)
                }
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                if let message {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
            }
            if Actions.self != EmptyView.self {
                HStack(spacing: J4I.Space.s) { actions }
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(J4I.Space.xl)
    }
}

extension J4IEmptyState where Actions == EmptyView {
    init(systemImage: String, title: String, message: String? = nil, tint: Color = J4I.brand, usesBrandMark: Bool = false) {
        self.init(
            systemImage: systemImage,
            title: title,
            message: message,
            tint: tint,
            usesBrandMark: usesBrandMark
        ) { EmptyView() }
    }
}

// MARK: - Botones

/// Botón de icono «fantasma»: sin borde; se resalta al pasar el ratón.
struct GhostIconButton: View {
    let systemImage: String
    var help: String = ""
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: J4I.Radius.small, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.09) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary : Color.primary)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
        .help(help)
    }
}

/// Separador vertical fino para barras de herramientas y de estado.
struct ToolbarSeparator: View {
    var body: some View {
        Rectangle()
            .fill(J4I.hairline.opacity(0.7))
            .frame(width: 1, height: 14)
    }
}

// MARK: - Ayudas de texto

extension Text {
    /// Cifras tabulares (contadores que no bailan).
    func tabularDigits() -> Text {
        monospacedDigit()
    }
}

extension View {
    /// Título de sección/pantalla con el diseño redondeado de la marca.
    func j4iTitle() -> some View {
        font(.system(size: 15, weight: .semibold, design: .rounded))
    }
}
