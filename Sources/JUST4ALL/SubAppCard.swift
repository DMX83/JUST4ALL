import SwiftUI

/// Tarjeta de una subapp en la rejilla: icono, nombre, resumen y en qué estado está.
///
/// Todas miden lo mismo y el nombre va en una sola línea: antes la tarjeta crecía con el
/// texto y «JUST4CONVERT» se partía por la mitad al quedarse sin sitio.
struct SubAppCard: View {
    let app: SubApp
    let state: SubAppState
    let isSelected: Bool
    let shortcutHint: String?
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    IconTile(symbol: app.systemIcon, accent: app.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name)
                            .font(HubDesign.cardTitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .truncationMode(.tail)
                        Text(app.subtitle)
                            .font(HubDesign.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    StateBadge(state: state, compact: true)
                    Spacer(minLength: 0)
                    if let shortcutHint {
                        Text(shortcutHint)
                            .font(HubDesign.mono)
                            .foregroundStyle(.tertiary)
                            .opacity(isSelected ? 1 : 0.5)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: HubDesign.cardHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: HubDesign.corner, style: .continuous)
                    .fill(.background)
                    .shadow(
                        color: .black.opacity(isSelected ? 0.18 : (isHovering ? 0.12 : 0.07)),
                        radius: isSelected ? 10 : (isHovering ? 7 : 4),
                        y: isSelected ? 3 : 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: HubDesign.corner, style: .continuous)
                    .strokeBorder(
                        isSelected ? app.accent : Color.primary.opacity(isHovering ? 0.18 : 0.09),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: HubDesign.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(app.name). \(app.subtitle). \(state.label)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
