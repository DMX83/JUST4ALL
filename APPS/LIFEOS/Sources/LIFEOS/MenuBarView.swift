import AppKit
import LifeOSAPI
import LifeOSUI
import SwiftUI

/// Menú de barra: el cierre del día sin abrir la ventana.
struct MenuBarView: View {
    @ObservedObject var model: LifeOSModel

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.m) {
            header

            if model.isSignedIn {
                metrics
                reminders
                queued
            } else {
                Text("Sin sesión. Abre LifeOS para entrar.")
                    .font(LifeOSFont.bodySmall)
                    .foregroundStyle(LifeOSTheme.textSecondary)
            }

            LifeOSDivider()
            actions
        }
        .padding(LifeOSSpace.l)
        .frame(width: 296)
        .background(LifeOSTheme.canvas)
        .task { await model.refresh() }
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(spacing: LifeOSSpace.s) {
            BrandMark(size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text("LifeOS")
                    .font(LifeOSFont.label)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                Text(TimeFormatting.longDay(Date()))
                    .font(LifeOSFont.caption)
                    .foregroundStyle(LifeOSTheme.textTertiary)
            }
            Spacer(minLength: 0)
            if model.busy {
                ProgressView().controlSize(.mini)
            }
        }
    }

    // MARK: - Cifras

    @ViewBuilder
    private var metrics: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            MetricLine(title: "Abiertas", value: model.dayClose?.openTasks ?? 0, tone: .accent)
            MetricLine(title: "Hechas hoy", value: model.dayClose?.completed.count ?? 0, tone: .positive)
            MetricLine(title: "Bandeja", value: model.dayClose?.pendingCaptures ?? 0, tone: .warning)
        }
    }

    // MARK: - Avisos

    @ViewBuilder
    private var reminders: some View {
        if !model.reminders.isEmpty {
            VStack(alignment: .leading, spacing: LifeOSSpace.s) {
                LifeOSSectionHeader("Próximos avisos")
                ForEach(model.reminders.prefix(3)) { reminder in
                    HStack(alignment: .top, spacing: LifeOSSpace.s) {
                        Text(TimeFormatting.time(reminder.at))
                            .font(LifeOSFont.mono)
                            .foregroundStyle(LifeOSTheme.textPrimary)
                        Text(reminder.title)
                            .font(LifeOSFont.bodySmall)
                            .foregroundStyle(LifeOSTheme.textSecondary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var queued: some View {
        if !model.queued.isEmpty {
            LifeOSChip("\(model.queued.count) sin enviar", systemImage: "wifi.slash", tone: .warning)
        }
    }

    // MARK: - Acciones

    private var actions: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
            ActionRow(title: "Capturar…", hint: "⌥Espacio", symbol: "square.and.pencil") {
                NSApp.activate(ignoringOtherApps: true)
                (NSApp.delegate as? AppDelegate)?.showQuickCapture()
            }
            ActionRow(title: "Abrir LifeOS", hint: "⌘1", symbol: "macwindow") {
                NSApp.activate(ignoringOtherApps: true)
            }
            ActionRow(title: "Actualizar", hint: "⌘R", symbol: "arrow.clockwise") {
                Task { await model.refresh() }
            }
            ActionRow(title: "Salir", hint: "", symbol: "power") {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - Piezas

private struct MetricLine: View {
    let title: String
    let value: Int
    let tone: LifeOSTone

    var body: some View {
        HStack(spacing: LifeOSSpace.s) {
            Circle()
                .fill(tone.foreground)
                .frame(width: 6, height: 6)
            Text(title)
                .font(LifeOSFont.bodySmall)
                .foregroundStyle(LifeOSTheme.textSecondary)
            Spacer(minLength: 0)
            Text("\(value)")
                .font(LifeOSFont.label)
                .foregroundStyle(LifeOSTheme.textPrimary)
                .monospacedDigit()
        }
    }
}

private struct ActionRow: View {
    let title: String
    let hint: String
    let symbol: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: LifeOSSpace.s) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14)
                    .foregroundStyle(LifeOSTheme.textSecondary)
                Text(title)
                    .font(LifeOSFont.bodySmall)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                Spacer(minLength: 0)
                if !hint.isEmpty {
                    Text(hint)
                        .font(LifeOSFont.caption)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                }
            }
            .padding(.horizontal, LifeOSSpace.s)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: LifeOSRadius.sm, style: .continuous)
                    .fill(hovering ? LifeOSTheme.elevated : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
