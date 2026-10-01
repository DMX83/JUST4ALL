import LifeOSAPI
import LifeOSCore
import SwiftUI

/// «Hoy»: el cierre del día que ya calcula el servidor, más los avisos.
///
/// No inventa nada: si un dato no está, no hay tarjeta. Y todo viene resuelto en
/// la zona horaria del espacio de trabajo.
public struct TodayView: View {
    @ObservedObject private var model: LifeOSModel
    private let onOpen: ((MainView.Pane) -> Void)?

    public init(model: LifeOSModel, onOpen: ((MainView.Pane) -> Void)? = nil) {
        self.model = model
        self.onOpen = onOpen
    }

    public var body: some View {
        ScrollView {
            TodayContent(model: model, onOpen: onOpen)
        }
    }
}

/// El contenido de «Hoy», sin el contenedor con scroll: así se puede renderizar
/// fuera de pantalla para la revisión de diseño.
struct TodayContent: View {
    @ObservedObject var model: LifeOSModel
    var onOpen: ((MainView.Pane) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.l) {
            header
            metrics
            remindersSection
            eventsSection
            completedSection
            queuedSection
            messages
        }
        .padding(.horizontal, LifeOSSpace.xl)
        .padding(.vertical, LifeOSSpace.xl)
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(LifeOSTheme.canvas)
    }

    // MARK: - Cabecera

    private var header: some View {
        LifeOSScreenHeader(
            eyebrow: eyebrow,
            title: greeting,
            detail: model.dayClose?.suggestion
        ) {
            Button {
                Task { await model.refresh() }
            } label: {
                Label("Actualizar", systemImage: "arrow.clockwise")
            }
            .buttonStyle(LifeOSGhostButtonStyle())
            .disabled(model.busy)
        }
    }

    private var eyebrow: String {
        if let raw = model.dayClose?.date, let day = TimeFormatting.day(from: raw) {
            return "Hoy · " + TimeFormatting.longDay(day)
        }
        return "Hoy"
    }

    private var greeting: String {
        guard let name = model.user?.displayName, !name.isEmpty else { return "Tu día" }
        return "Hola, \(name)"
    }

    // MARK: - Cifras

    private var metrics: some View {
        HStack(spacing: LifeOSSpace.m) {
            LifeOSMetricTile(
                title: "Abiertas",
                value: model.dayClose?.openTasks ?? 0,
                systemImage: "checklist",
                tone: .accent,
                action: onOpen.map { open in { open(.tasks) } }
            )
            LifeOSMetricTile(
                title: "Citas hoy",
                value: model.agendaAppointments.count,
                systemImage: "calendar",
                tone: .info,
                action: onOpen.map { open in { open(.agenda) } }
            )
            LifeOSMetricTile(
                title: "Bandeja",
                value: model.dayClose?.pendingCaptures ?? 0,
                systemImage: "tray.full.fill",
                tone: (model.dayClose?.pendingCaptures ?? 0) > 0 ? .warning : .neutral,
                action: onOpen.map { open in { open(.inbox) } }
            )
            LifeOSMetricTile(
                title: "Diario",
                value: model.dayClose?.journalEntries ?? 0,
                systemImage: "book.closed.fill",
                tone: .positive,
                action: onOpen.map { open in { open(.journal) } }
            )
        }
    }

    // MARK: - Avisos

    private var remindersSection: some View {
        LifeOSSectionCard(
            title: "Avisos",
            count: model.reminders.count,
            isEmpty: model.reminders.isEmpty,
            empty: ("bell.slash", "Nada en las próximas horas", "Los recordatorios de acciones y eventos aparecen aquí.")
        ) {
            ForEach(model.reminders) { reminder in
                ReminderRow(reminder: reminder)
            }
        }
    }

    // MARK: - Agenda

    private var eventsSection: some View {
        LifeOSSectionCard(
            title: "Agenda de hoy",
            count: model.dayClose?.events.count,
            isEmpty: (model.dayClose?.events ?? []).isEmpty,
            empty: ("calendar", "Sin eventos hoy", "La agenda completa está en la consola web.")
        ) {
            ForEach(model.dayClose?.events ?? []) { item in
                DayCloseRow(item: item, systemImage: "calendar", tone: .accent)
            }
        }
    }

    // MARK: - Hecho

    private var completedSection: some View {
        LifeOSSectionCard(
            title: "Hecho hoy",
            count: model.dayClose?.completed.count,
            isEmpty: (model.dayClose?.completed ?? []).isEmpty,
            empty: ("checkmark.circle", "Todavía nada cerrado", "Lo que completes hoy aparecerá aquí.")
        ) {
            ForEach(model.dayClose?.completed ?? []) { item in
                DayCloseRow(item: item, systemImage: "checkmark", tone: .positive)
            }
        }
    }

    // MARK: - Sin enviar

    @ViewBuilder
    private var queuedSection: some View {
        if !model.queued.isEmpty {
            LifeOSSectionCard(
                title: "Sin enviar",
                count: model.queued.count,
                isEmpty: false,
                empty: ("", "", "")
            ) {
                ForEach(model.queued) { item in
                    QueuedRow(item: item)
                }
                Button("Enviar ahora") { Task { await model.flushOutbox() } }
                    .buttonStyle(LifeOSPrimaryButtonStyle())
                    .padding(.top, LifeOSSpace.xs)
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let error = model.errorMessage {
            MessageRow(text: error, tone: .danger, systemImage: "exclamationmark.triangle.fill")
        }
        if let status = model.statusMessage {
            MessageRow(text: status, tone: .positive, systemImage: "checkmark.circle.fill")
        }
    }
}

// MARK: - Piezas

/// Tarjeta de sección con encabezado, contador y estado vacío.
struct LifeOSSectionCard<Content: View>: View {
    let title: String
    let count: Int?
    let isEmpty: Bool
    let empty: (symbol: String, title: String, detail: String)
    private let content: Content

    init(
        title: String,
        count: Int?,
        isEmpty: Bool,
        empty: (symbol: String, title: String, detail: String),
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.count = count
        self.isEmpty = isEmpty
        self.empty = empty
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            LifeOSSectionHeader(title, count: count)
            LifeOSCard {
                if isEmpty {
                    LifeOSEmptyState(systemImage: empty.symbol, title: empty.title, detail: empty.detail)
                } else {
                    VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                        content
                    }
                }
            }
        }
    }
}

struct ReminderRow: View {
    let reminder: ReminderItem

    var body: some View {
        HStack(alignment: .top, spacing: LifeOSSpace.m) {
            Text(TimeFormatting.time(reminder.at))
                .font(LifeOSFont.mono)
                .foregroundStyle(LifeOSTheme.textPrimary)
                .padding(.horizontal, LifeOSSpace.s)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: LifeOSRadius.sm, style: .continuous)
                        .fill(LifeOSTheme.elevated)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(LifeOSFont.body)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: LifeOSSpace.xs) {
                    Text(LifeOSKind.label(for: reminder.kind))
                    Text("·")
                    Text("aviso \(reminder.minutes) min antes")
                    if !reminder.detail.isEmpty {
                        Text("·")
                        Text(reminder.detail)
                    }
                }
                .font(LifeOSFont.caption)
                .foregroundStyle(LifeOSTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct DayCloseRow: View {
    let item: DayCloseItem
    let systemImage: String
    let tone: LifeOSTone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LifeOSSpace.m) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tone.foreground)
                .frame(width: 14)
            Text(item.title)
                .font(LifeOSFont.body)
                .foregroundStyle(LifeOSTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: LifeOSSpace.s)
            if let at = item.at {
                Text(TimeFormatting.time(at))
                    .font(LifeOSFont.mono)
                    .foregroundStyle(LifeOSTheme.textTertiary)
            }
        }
    }
}

struct QueuedRow: View {
    let item: OutboxItem

    var body: some View {
        HStack(alignment: .top, spacing: LifeOSSpace.m) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LifeOSTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.content)
                    .font(LifeOSFont.body)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                    .lineLimit(3)
                Text(item.lastError ?? "Esperando conexión")
                    .font(LifeOSFont.caption)
                    .foregroundStyle(LifeOSTheme.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}
