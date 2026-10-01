import AppKit
import SwiftUI

// Componentes del sistema visual. Las vistas no pintan colores sueltos: eligen
// uno de estos. Si algo falta aquí, se añade aquí.

// MARK: - Marca

/// Marca de la app: diana con el acento de LifeOS sobre disco (DS-018 la quiere
/// circular). El aro tiene que verse: sin él parece un botón de grabar.
public struct BrandMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 34) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [LifeOSTheme.brandHi, LifeOSTheme.brand],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(Color.white.opacity(0.92), lineWidth: max(1.5, size * 0.062))
                .padding(size * 0.27)
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.13, height: size * 0.13)
        }
        .frame(width: size, height: size)
        .lifeOSShadow(.sm)
    }
}

// MARK: - Superficies

/// Tarjeta: superficie con borde de un pelo y sombra suave.
///
/// `accent` sirve para lo que pide atención: **tiñe el borde**, no el fondo. Un
/// fondo de color fuerte deja el texto ilegible (pasó con el aviso de duplicados).
public struct LifeOSCard<Content: View>: View {
    private let padding: CGFloat
    private let tint: Color?
    private let accent: Color?
    private let content: Content

    public init(
        padding: CGFloat = LifeOSSpace.l,
        tint: Color? = nil,
        accent: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.tint = tint
        self.accent = accent
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LifeOSRadius.card, style: .continuous)
                    .fill(tint ?? LifeOSTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LifeOSRadius.card, style: .continuous)
                    .strokeBorder(
                        accent ?? LifeOSTheme.borderSubtle,
                        lineWidth: accent == nil ? 1 : 1.5
                    )
            )
            .lifeOSShadow(.sm)
    }
}

/// Menú de fila («⋯») de una lista.
///
/// Fuera de pantalla AppKit no pinta los menús (salen como un bloque amarillo),
/// así que en modo render se dibuja sólo el icono: las imágenes de revisión
/// siguen sirviendo para juzgar el diseño.
public struct LifeOSRowMenu<Content: View>: View {
    @Environment(\.lifeOSFlatSurfaces) private var renderMode
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        if renderMode {
            icon
                .frame(width: 24, height: 20)
        } else {
            Menu { content } label: { icon }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
        }
    }

    private var icon: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(LifeOSTheme.textTertiary)
    }
}

/// Encabezado de sección: `eyebrow` en mayúsculas + contador opcional.
public struct LifeOSSectionHeader: View {
    private let title: String
    private let count: Int?

    public init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LifeOSSpace.s) {
            Text(title.uppercased())
                .font(LifeOSFont.eyebrow)
                .kerning(LifeOSTracking.eyebrow)
                .foregroundStyle(LifeOSTheme.textTertiary)
            if let count, count > 0 {
                Text("\(count)")
                    .font(LifeOSFont.caption)
                    .foregroundStyle(LifeOSTheme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(LifeOSTheme.elevated))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Etiquetas

/// Tono semántico de una etiqueta o un aviso.
public enum LifeOSTone {
    case accent
    case neutral
    case positive
    case warning
    case danger
    case info

    public var foreground: Color {
        switch self {
        case .accent: return LifeOSTheme.brandOnSoft
        case .neutral: return LifeOSTheme.textSecondary
        case .positive: return LifeOSTheme.positive
        case .warning: return LifeOSTheme.warning
        case .danger: return LifeOSTheme.danger
        case .info: return LifeOSTheme.info
        }
    }

    public var background: Color {
        switch self {
        case .accent: return LifeOSTheme.brandSoft
        case .neutral: return LifeOSTheme.elevated
        case .positive: return LifeOSTheme.positiveSoft
        case .warning: return LifeOSTheme.warningSoft
        case .danger: return LifeOSTheme.dangerSoft
        case .info: return LifeOSTheme.infoSoft
        }
    }
}

/// Etiqueta compacta (tipo de entidad, estado, sensibilidad).
public struct LifeOSChip: View {
    private let text: String
    private let systemImage: String?
    private let tone: LifeOSTone
    private let strong: Bool

    public init(_ text: String, systemImage: String? = nil, tone: LifeOSTone = .accent, strong: Bool = false) {
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
        self.strong = strong
    }

    /// Compatibilidad con el tono explícito por color.
    public init(_ text: String, systemImage: String? = nil, tint: Color) {
        self.init(text, systemImage: systemImage, tone: LifeOSTone.nearest(to: tint))
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(LifeOSFont.labelSmall)
        }
        .foregroundStyle(strong ? LifeOSTheme.onBrand : tone.foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(strong ? LifeOSTheme.brand : tone.background))
    }
}

public extension LifeOSTone {
    /// Traduce un color concreto al tono semántico más cercano, para no romper
    /// las llamadas antiguas que pasaban `Color`.
    static func nearest(to color: Color) -> LifeOSTone {
        switch color {
        case LifeOSTheme.brand: return .accent
        case LifeOSTheme.positive: return .positive
        case LifeOSTheme.warning: return .warning
        case LifeOSTheme.danger: return .danger
        case LifeOSTheme.info: return .info
        default: return .neutral
        }
    }
}

/// Punto de estado con texto, para listas densas.
public struct LifeOSStatusDot: View {
    private let text: String
    private let tone: LifeOSTone

    public init(_ text: String, tone: LifeOSTone) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tone.foreground)
                .frame(width: 6, height: 6)
            Text(text)
                .font(LifeOSFont.labelSmall)
                .foregroundStyle(tone.foreground)
        }
    }
}

// MARK: - Avisos

/// Mensaje de error o confirmación, con el color semántico del sistema.
public struct MessageRow: View {
    private let text: String
    private let tone: LifeOSTone
    private let systemImage: String

    public init(text: String, tone: LifeOSTone, systemImage: String) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
    }

    /// Compatibilidad con el tono por color.
    public init(text: String, tint: Color, systemImage: String) {
        self.init(text: text, tone: .nearest(to: tint), systemImage: systemImage)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: LifeOSSpace.s) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone.foreground)
            Text(text)
                .font(LifeOSFont.bodySmall)
                .foregroundStyle(LifeOSTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LifeOSSpace.m)
        .padding(.vertical, LifeOSSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LifeOSRadius.md, style: .continuous)
                .fill(tone.background)
        )
    }
}

// MARK: - Vacíos

public struct LifeOSEmptyState: View {
    private let systemImage: String
    private let title: String
    private let detail: String

    public init(systemImage: String, title: String, detail: String) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: LifeOSSpace.s) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(LifeOSTheme.textTertiary)
            Text(title)
                .font(LifeOSFont.label)
                .foregroundStyle(LifeOSTheme.textPrimary)
            Text(detail)
                .font(LifeOSFont.bodySmall)
                .foregroundStyle(LifeOSTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LifeOSSpace.xl)
        .padding(.horizontal, LifeOSSpace.l)
    }
}

// MARK: - Cifras

/// Cifra con su etiqueta, para la cabecera de «Hoy».
///
/// Con `action` se comporta como un botón: las cifras que llevan a alguna parte
/// se pulsan.
public struct LifeOSMetricTile: View {
    private let title: String
    private let value: Int
    private let systemImage: String
    private let tone: LifeOSTone
    private let action: (() -> Void)?

    public init(
        title: String,
        value: Int,
        systemImage: String,
        tone: LifeOSTone = .accent,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tone = tone
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { tile }
                .buttonStyle(.plain)
                .help("Abrir \(title)")
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            HStack(spacing: LifeOSSpace.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tone.foreground)
                Text(title)
                    .font(LifeOSFont.labelSmall)
                    .foregroundStyle(LifeOSTheme.textSecondary)
                Spacer(minLength: 0)
            }
            Text("\(value)")
                .font(LifeOSFont.metric)
                .foregroundStyle(LifeOSTheme.textPrimary)
        }
        .padding(.horizontal, LifeOSSpace.m)
        .padding(.vertical, LifeOSSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LifeOSRadius.card, style: .continuous)
                .fill(LifeOSTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LifeOSRadius.card, style: .continuous)
                .strokeBorder(LifeOSTheme.borderSubtle, lineWidth: 1)
        )
        .lifeOSShadow(.xs)
        .contentShape(RoundedRectangle(cornerRadius: LifeOSRadius.card, style: .continuous))
    }
}

// MARK: - Botones

/// Botón principal: píldora con el acento de la marca.
///
/// Deshabilitado no se ve «apagado a medias» sino inerte: una píldora neutra, para
/// que nadie se quede pulsando un botón que no hace nada.
public struct LifeOSPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PrimaryLabel(configuration: configuration)
    }

    private struct PrimaryLabel: View {
        let configuration: LifeOSPrimaryButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(LifeOSFont.label)
                .foregroundStyle(isEnabled ? LifeOSTheme.onBrand : LifeOSTheme.textTertiary)
                .padding(.horizontal, LifeOSSpace.l)
                .padding(.vertical, 7)
                .background(Capsule().fill(fill))
                .opacity(configuration.isPressed ? 0.92 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(LifeOSMotion.standard, value: configuration.isPressed)
        }

        private var fill: Color {
            guard isEnabled else { return LifeOSTheme.elevated }
            return configuration.isPressed ? LifeOSTheme.brandHi : LifeOSTheme.brand
        }
    }
}

/// Botón secundario: píldora con acento suave.
public struct LifeOSSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LifeOSFont.label)
            .foregroundStyle(LifeOSTheme.brandOnSoft)
            .padding(.horizontal, LifeOSSpace.l)
            .padding(.vertical, 7)
            .background(Capsule().fill(configuration.isPressed ? LifeOSTheme.brandSoft.opacity(0.7) : LifeOSTheme.brandSoft))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(LifeOSMotion.standard, value: configuration.isPressed)
    }
}

/// Botón discreto: texto con realce al pasar por encima.
///
/// El realce necesita estado, y un `ButtonStyle` no puede guardarlo; por eso el
/// estilo devuelve una vista propia que sí lo tiene.
public struct LifeOSGhostButtonStyle: ButtonStyle {
    private let tone: LifeOSTone?

    /// Con `tone` el botón se tiñe: `.danger` para lo que borra, para que se vea
    /// que hace daño antes de pulsarlo.
    public init(tone: LifeOSTone? = nil) {
        self.tone = tone
    }

    public func makeBody(configuration: Configuration) -> some View {
        GhostLabel(configuration: configuration, tone: tone)
    }

    private struct GhostLabel: View {
        let configuration: LifeOSGhostButtonStyle.Configuration
        let tone: LifeOSTone?
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(LifeOSFont.label)
                .foregroundStyle(foreground)
                .padding(.horizontal, LifeOSSpace.m)
                .padding(.vertical, 6)
                .background(Capsule().fill(hovering ? background : Color.clear))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(LifeOSMotion.standard, value: hovering)
        }

        private var foreground: Color {
            if let tone { return tone.foreground }
            return hovering ? LifeOSTheme.textPrimary : LifeOSTheme.textSecondary
        }

        private var background: Color {
            if let tone { return tone.background }
            return LifeOSTheme.elevated
        }
    }
}

// MARK: - Campos

/// Campo de texto del sistema: radio grande, borde de un pelo y anillo de foco
/// propio (DS-008), en vez del rectángulo por defecto de macOS.
public struct LifeOSField: View {
    private let placeholder: String
    @Binding private var text: String
    private let isSecure: Bool
    private let submitLabel: String?
    private let onSubmit: (() -> Void)?

    @FocusState private var focused: Bool
    // Fuera de pantalla, AppKit no puede pintar campos de texto (salen como un
    // bloque amarillo): en modo render se dibuja el mismo aspecto sin control.
    @Environment(\.lifeOSFlatSurfaces) private var renderMode

    public init(
        _ placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false,
        submitLabel: String? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: LifeOSSpace.s) {
            if renderMode {
                renderedValue
            } else {
                field
                    .textFieldStyle(.plain)
                    .font(LifeOSFont.body)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                    .focused($focused)
                    .onSubmit { onSubmit?() }
            }
            if let submitLabel, !text.isEmpty {
                Button(submitLabel) { onSubmit?() }
                    .buttonStyle(LifeOSPrimaryButtonStyle())
            }
        }
        .padding(.horizontal, LifeOSSpace.m)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: LifeOSRadius.lg, style: .continuous)
                .fill(LifeOSTheme.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LifeOSRadius.lg, style: .continuous)
                .strokeBorder(
                    focused && !renderMode ? LifeOSTheme.focusRing : LifeOSTheme.borderSubtle,
                    lineWidth: focused && !renderMode ? 2 : 1
                )
        )
        .animation(LifeOSMotion.standard, value: focused)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    @ViewBuilder
    private var renderedValue: some View {
        Text(displayValue)
            .font(LifeOSFont.body)
            .foregroundStyle(text.isEmpty ? LifeOSTheme.textTertiary : LifeOSTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayValue: String {
        guard !text.isEmpty else { return placeholder }
        return isSecure ? String(repeating: "\u{2022}", count: min(text.count, 14)) : text
    }

    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
        }
    }
}

// MARK: - Filas

/// Fila de «etiqueta: valor» para Ajustes.
public struct LifeOSRow: View {
    private let title: String
    private let value: String
    private let tone: LifeOSTone

    public init(_ title: String, value: String, tone: LifeOSTone = .neutral) {
        self.title = title
        self.value = value
        self.tone = tone
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LifeOSSpace.s) {
            Text(title)
                .font(LifeOSFont.bodySmall)
                .foregroundStyle(LifeOSTheme.textSecondary)
            Spacer(minLength: LifeOSSpace.s)
            Text(value)
                .font(LifeOSFont.bodySmall)
                .foregroundStyle(tone == .neutral ? LifeOSTheme.textPrimary : tone.foreground)
                .textSelection(.enabled)
        }
    }
}

/// Separador de un pelo, alineado con el texto.
public struct LifeOSDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(LifeOSTheme.borderSubtle)
            .frame(height: 1)
    }
}

// MARK: - Encabezado de ventana

/// Cabecera de sección: eyebrow, título grande y una frase de contexto.
public struct LifeOSScreenHeader<Trailing: View>: View {
    private let eyebrow: String
    private let title: String
    private let detail: String?
    private let trailing: Trailing

    public init(
        eyebrow: String,
        title: String,
        detail: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            Text(eyebrow.uppercased())
                .font(LifeOSFont.eyebrow)
                .kerning(LifeOSTracking.eyebrow)
                .foregroundStyle(LifeOSTheme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: LifeOSSpace.s) {
                Text(title)
                    .font(LifeOSFont.screenTitle)
                    .kerning(LifeOSTracking.heading)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                Spacer(minLength: 0)
                trailing
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(LifeOSFont.bodySmall)
                    .foregroundStyle(LifeOSTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

public extension LifeOSScreenHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, detail: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, detail: detail) { EmptyView() }
    }
}
