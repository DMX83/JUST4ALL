import LifeOSAPI
import LifeOSCore
import SwiftUI

// Piezas del flujo de captura, compartidas por la ventana y el panel flotante.

// MARK: - Revisión de la propuesta

/// Propuesta del clasificador: nada se guarda sin que la persona lo elija.
struct ProposalReview: View {
    let proposal: Proposal
    let selection: Set<String>
    let onToggle: (String) -> Void
    let onApply: () -> Void
    let onReject: () -> Void
    var busy: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            LifeOSSectionHeader("Propuesta de LifeOS", count: proposal.operations.count)

            LifeOSCard(padding: LifeOSSpace.m) {
                VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                    if !proposal.explanation.isEmpty {
                        Text(proposal.explanation)
                            .font(LifeOSFont.bodySmall)
                            .foregroundStyle(LifeOSTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: LifeOSSpace.s) {
                        ForEach(proposal.operations) { operation in
                            OperationRow(
                                operation: operation,
                                isSelected: selection.contains(operation.id),
                                onToggle: { onToggle(operation.id) }
                            )
                        }
                    }

                    footer
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: LifeOSSpace.s) {
            Button(applyTitle) { onApply() }
                .buttonStyle(LifeOSPrimaryButtonStyle())
                .disabled(selection.isEmpty || busy)
                .opacity(selection.isEmpty || busy ? 0.5 : 1)

            Button("Descartar") { onReject() }
                .buttonStyle(LifeOSGhostButtonStyle())
                .disabled(busy)

            Spacer(minLength: 0)

            if busy {
                ProgressView().controlSize(.small)
            } else {
                Text("\(selection.count) de \(proposal.operations.count)")
                    .font(LifeOSFont.caption)
                    .foregroundStyle(LifeOSTheme.textTertiary)
            }
        }
    }

    private var applyTitle: String {
        selection.count == proposal.operations.count
            ? "Guardar todo"
            : "Guardar seleccionadas"
    }
}

/// Una operación propuesta: tipo, título, detalle y confianza.
struct OperationRow: View {
    let operation: ProposalOperation
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: LifeOSSpace.m) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? LifeOSTheme.brand : LifeOSTheme.borderStrong)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
                    HStack(spacing: LifeOSSpace.s) {
                        LifeOSChip(
                            LifeOSKind.label(for: operation.entityKind),
                            systemImage: LifeOSKind.symbol(for: operation.entityKind)
                        )
                        ConfidenceBar(value: operation.confidence)
                        Spacer(minLength: 0)
                        if operation.operation != "create" {
                            LifeOSChip(operation.operation == "link" ? "Relacionar" : "Actualizar", tone: .neutral)
                        }
                    }
                    Text(operation.title)
                        .font(LifeOSFont.body)
                        .foregroundStyle(LifeOSTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !operation.details.isEmpty {
                        Text(operation.details.joined(separator: " · "))
                            .font(LifeOSFont.caption)
                            .foregroundStyle(LifeOSTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(LifeOSSpace.m)
            .background(
                RoundedRectangle(cornerRadius: LifeOSRadius.md, style: .continuous)
                    .fill(isSelected ? LifeOSTheme.brandSoft.opacity(0.6) : LifeOSTheme.elevated.opacity(hovering ? 1 : 0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LifeOSRadius.md, style: .continuous)
                    .strokeBorder(isSelected ? LifeOSTheme.brand.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(LifeOSMotion.standard, value: hovering)
        .animation(LifeOSMotion.standard, value: isSelected)
    }
}

/// Confianza de la propuesta, en una barra corta y su porcentaje.
struct ConfidenceBar: View {
    let value: Double

    var body: some View {
        HStack(spacing: LifeOSSpace.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(LifeOSTheme.borderSubtle)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(2, geometry.size.width * clamped))
                }
            }
            .frame(width: 44, height: 4)
            Text("\(Int((clamped * 100).rounded())) %")
                .font(LifeOSFont.caption)
                .foregroundStyle(LifeOSTheme.textTertiary)
                .monospacedDigit()
        }
        .help("Confianza de la propuesta")
    }

    private var clamped: Double { min(max(value, 0), 1) }

    private var tint: Color {
        switch clamped {
        case ..<0.5: return LifeOSTheme.warning
        case ..<0.75: return LifeOSTheme.info
        default: return LifeOSTheme.positive
        }
    }
}

// MARK: - Aclaración

/// El servidor pide un dato antes de clasificar, o se elige el tipo a mano.
struct ClarificationCard: View {
    let question: String
    let onSubmit: (String, String?) -> Void
    var busy: Bool = false

    @State private var answer = ""
    @State private var kind = "task"

    private let kinds = [
        ("task", "Tarea"), ("idea", "Idea"), ("event", "Evento"), ("note", "Nota"),
        ("objective", "Objetivo"), ("project", "Proyecto"), ("area", "Área"),
        ("decision", "Decisión"), ("knowledge", "Conocimiento")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            LifeOSSectionHeader("Hace falta un poco más")
            LifeOSCard {
                VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                    Text(question)
                        .font(LifeOSFont.body)
                        .foregroundStyle(LifeOSTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    LifeOSField("Tu respuesta", text: $answer, submitLabel: "Continuar") {
                        onSubmit(answer, kind)
                    }

                    VStack(alignment: .leading, spacing: LifeOSSpace.s) {
                        Text("O guárdalo directamente como")
                            .font(LifeOSFont.caption)
                            .foregroundStyle(LifeOSTheme.textSecondary)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 92, maximum: 140), spacing: LifeOSSpace.s)],
                            alignment: .leading,
                            spacing: LifeOSSpace.s
                        ) {
                            ForEach(kinds, id: \.0) { item in
                                KindChip(
                                    title: item.1,
                                    symbol: LifeOSKind.symbol(for: item.0),
                                    isSelected: kind == item.0
                                ) {
                                    kind = item.0
                                }
                            }
                        }
                    }

                    HStack {
                        Spacer(minLength: 0)
                        if busy { ProgressView().controlSize(.small) }
                        Button("Continuar") { onSubmit(answer, kind) }
                            .buttonStyle(LifeOSPrimaryButtonStyle())
                            .disabled(busy)
                    }
                }
            }
        }
    }
}

struct KindChip: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LifeOSSpace.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(LifeOSFont.labelSmall)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? LifeOSTheme.onBrand : LifeOSTheme.textSecondary)
            .padding(.horizontal, LifeOSSpace.m)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(isSelected ? LifeOSTheme.brand : LifeOSTheme.elevated))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(LifeOSMotion.standard, value: isSelected)
    }
}

// MARK: - Cola sin conexión

/// Aviso de que la captura quedó guardada en el Mac.
struct QueuedCard: View {
    let item: OutboxItem
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            LifeOSSectionHeader("Guardada en tu Mac")
            LifeOSCard {
                VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                    HStack(spacing: LifeOSSpace.s) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LifeOSTheme.warning)
                        Text("No hubo conexión con LifeOS")
                            .font(LifeOSFont.label)
                            .foregroundStyle(LifeOSTheme.textPrimary)
                    }
                    Text(item.content)
                        .font(LifeOSFont.body)
                        .foregroundStyle(LifeOSTheme.textSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Saldrá sola al volver la red y no se duplicará.")
                        .font(LifeOSFont.caption)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                    Button("Reintentar ahora", action: onRetry)
                        .buttonStyle(LifeOSSecondaryButtonStyle())
                }
            }
        }
    }
}

// MARK: - Indicador de trabajo

/// Fila de «trabajando» con el acento del sistema.
struct WorkingRow: View {
    let text: String

    var body: some View {
        HStack(spacing: LifeOSSpace.s) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(LifeOSFont.bodySmall)
                .foregroundStyle(LifeOSTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LifeOSSpace.m)
        .padding(.vertical, LifeOSSpace.s)
        .background(
            RoundedRectangle(cornerRadius: LifeOSRadius.md, style: .continuous)
                .fill(LifeOSTheme.brandSoft.opacity(0.5))
        )
    }
}
