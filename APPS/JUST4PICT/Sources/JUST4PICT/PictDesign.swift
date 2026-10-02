import SwiftUI

/// El lenguaje visual de JUST4PICT: una escala de tipos, unas medidas y las tres piezas que
/// comparten todas las secciones (título, tarjeta y estado vacío).
///
/// Antes cada sección se pintaba a mano con `Color(.controlBackgroundColor)` y textos de
/// tamaños sueltos, y los huecos sin contenido quedaban como cajas negras.
enum PictDesign {
    static let title = Font.system(size: 26, weight: .bold)
    static let sectionTitle = Font.system(size: 11, weight: .semibold)
    static let body = Font.system(size: 12.5)
    static let caption = Font.system(size: 11)
    static let mono = Font.system(size: 11, design: .monospaced)

    static let radius: CGFloat = 12
    /// Alto máximo de las cajas con lista (imágenes, actividad).
    static let listMaxHeight: CGFloat = 170

    /// Fondo de una caja de contenido.
    static var boxFill: some ShapeStyle { .quaternary.opacity(0.35) }
}

/// Sección con título y contenido, todo dentro de una tarjeta.
struct PictSection<Content: View, Trailing: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(PictDesign.sectionTitle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                trailing
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PictDesign.radius, style: .continuous)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PictDesign.radius, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        )
    }
}

extension PictSection where Trailing == EmptyView {
    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, content: content, trailing: { EmptyView() })
    }
}

/// Caja «todavía no hay nada»: un icono y una frase en vez de un hueco oscuro.
struct PictEmptyState: View {
    let symbol: String
    let title: String
    var hint: String?

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(PictDesign.body)
                .foregroundStyle(.secondary)
            if let hint {
                Text(hint)
                    .font(PictDesign.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: PictDesign.radius, style: .continuous)
                .fill(PictDesign.boxFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PictDesign.radius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(.tertiary)
        )
    }
}
