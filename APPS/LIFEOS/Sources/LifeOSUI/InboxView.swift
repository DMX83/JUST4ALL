import LifeOSAPI
import SwiftUI

/// Bandeja: lo capturado que aún no se ha cerrado.
public struct InboxView: View {
    @ObservedObject private var model: LifeOSModel

    public init(model: LifeOSModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            InboxContent(model: model)
        }
    }
}

/// El contenido de la bandeja, sin el contenedor con scroll.
struct InboxContent: View {
    @ObservedObject var model: LifeOSModel

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.l) {
            header
            if model.inbox.count >= 100 {
                // El servidor devuelve como mucho las 100 capturas más recientes
                // (el tope se aplica antes del filtro), así que puede haber más.
                MessageRow(
                    text: "Se están mostrando las 100 capturas más recientes: puede haber más en la consola web.",
                    tone: .warning,
                    systemImage: "exclamationmark.triangle"
                )
            }
            list
            messages
        }
        .padding(.horizontal, LifeOSSpace.xl)
        .padding(.vertical, LifeOSSpace.xl)
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(LifeOSTheme.canvas)
    }

    private var header: some View {
        LifeOSScreenHeader(
            eyebrow: "Bandeja",
            title: model.inbox.isEmpty ? "Todo clasificado" : "\(model.inbox.count) por cerrar",
            detail: "Lo capturado esperando tu confirmación. Se clasifica en la web o aquí, al capturar."
        ) {
            Button {
                model.openWeb()
            } label: {
                Label("Consola web", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(LifeOSGhostButtonStyle())
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.inbox.isEmpty {
            LifeOSCard {
                LifeOSEmptyState(
                    systemImage: "tray",
                    title: "Bandeja vacía",
                    detail: "Todo lo capturado está clasificado. Buen trabajo."
                )
            }
        } else {
            VStack(spacing: LifeOSSpace.s) {
                ForEach(model.inbox) { capture in
                    CaptureRow(capture: capture)
                }
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let error = model.errorMessage {
            MessageRow(text: error, tone: .danger, systemImage: "exclamationmark.triangle.fill")
        }
    }
}

/// Una captura en la bandeja: estado, texto y procedencia.
struct CaptureRow: View {
    let capture: CaptureDetail

    @State private var hovering = false

    var body: some View {
        LifeOSCard(padding: LifeOSSpace.m) {
            VStack(alignment: .leading, spacing: LifeOSSpace.s) {
                HStack(spacing: LifeOSSpace.s) {
                    statusChip
                    if capture.isSensitive {
                        LifeOSChip("Sensible", systemImage: "lock.fill", tone: .warning)
                    }
                    if capture.channel == "audio" {
                        LifeOSChip("Voz", systemImage: "waveform", tone: .accent)
                    }
                    Spacer(minLength: 0)
                    Text(TimeFormatting.relative(capture.createdAt))
                        .font(LifeOSFont.caption)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                }

                Text(capture.content)
                    .font(LifeOSFont.body)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !capture.clarifyingQuestion.isEmpty {
                    HStack(alignment: .top, spacing: LifeOSSpace.xs) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(LifeOSTheme.warning)
                        Text(capture.clarifyingQuestion)
                            .font(LifeOSFont.caption)
                            .foregroundStyle(LifeOSTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: LifeOSRadius.card, style: .continuous)
                .fill(hovering ? LifeOSTheme.surface : LifeOSTheme.surface)
        )
        .onHover { hovering = $0 }
        .animation(LifeOSMotion.standard, value: hovering)
    }

    @ViewBuilder
    private var statusChip: some View {
        switch capture.status {
        case "applied":
            LifeOSChip("Guardada", systemImage: "checkmark", tone: .positive)
        case "rejected":
            LifeOSChip("Descartada", systemImage: "xmark", tone: .neutral)
        case "needs_clarification":
            LifeOSChip("Hace falta un dato", systemImage: "questionmark", tone: .warning)
        case "failed":
            LifeOSChip("No se pudo clasificar", systemImage: "exclamationmark.triangle.fill", tone: .danger)
        default:
            LifeOSChip("Por clasificar", systemImage: "clock.fill", tone: .accent)
        }
    }
}
