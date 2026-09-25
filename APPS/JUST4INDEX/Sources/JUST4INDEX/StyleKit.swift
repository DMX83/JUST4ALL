import SwiftUI

/// Toques de estilo compartidos (F8.1): hover suave en filas y píldoras de atajos.

/// Fondo sutil al pasar el ratón por encima (filas de listas).
struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 6
    var intensity: Double = 0.06
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? intensity : 0))
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    /// Aplica un resaltado suave al pasar el ratón (filas de listas).
    func hoverHighlight(cornerRadius: CGFloat = 6, intensity: Double = 0.06) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, intensity: intensity))
    }
}

/// Tecla de atajo en estilo «keycap» (estados vacíos y ayudas).
struct KeycapBadge: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25))
                )
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
