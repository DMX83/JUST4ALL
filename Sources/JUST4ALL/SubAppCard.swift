import SwiftUI

struct SubAppCard: View {
    let app: SubApp
    let isSelected: Bool
    let isInstalled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(app.accent.opacity(0.2))
                            .frame(width: 42, height: 42)
                        Image(systemName: app.systemIcon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(app.accent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isInstalled ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(app.name)
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(app.subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                Text(isSelected ? "Seleccionada" : (isInstalled ? "Abrir" : "Ver detalles"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(app.accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? app.accent.opacity(0.6) : app.accent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
