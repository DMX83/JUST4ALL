import LifeOSAPI
import LifeOSCore
import SwiftUI

/// Agenda: lo que ocupa el tiempo, en tres carriles que no se mezclan.
///
/// Se mira **una semana** (los siete días de la tira) y se lee **un día**. Una
/// sola llamada al servidor trae la semana entera, así que cambiar de día es
/// instantáneo; sólo se vuelve al servidor al cambiar de semana o al crear algo.
public struct AgendaView: View {
    @ObservedObject private var model: LifeOSModel

    public init(model: LifeOSModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            AgendaContent(model: model)
        }
        .task { await model.loadAgenda() }
    }
}

struct AgendaContent: View {
    @ObservedObject var model: LifeOSModel
    @Environment(\.lifeOSFlatSurfaces) private var renderMode

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.l) {
            header
            weekStrip
            if let draft = model.eventDraft {
                EventForm(draft: draft, model: model)
            }
            duplicates
            lane(
                title: "Citas",
                empty: "Sin citas este día.",
                count: model.agendaAppointments.count
            ) {
                ForEach(model.agendaAppointments, id: \.rowID) { event in
                    EventRow(event: event, model: model, isFocusBlock: false)
                }
            }
            lane(
                title: "Bloques de foco",
                empty: "Sin tiempo reservado este día.",
                count: model.agendaFocusBlocks.count
            ) {
                ForEach(model.agendaFocusBlocks, id: \.rowID) { event in
                    EventRow(event: event, model: model, isFocusBlock: true)
                }
            }
            lane(
                title: "Vencimientos",
                empty: "Nada vence este día.",
                count: model.agendaDueTasks.count
            ) {
                ForEach(model.agendaDueTasks) { task in
                    TaskRow(task: task, model: model, showSchedule: false)
                }
            }
        }
        .padding(.horizontal, LifeOSSpace.xl)
        .padding(.vertical, LifeOSSpace.xl)
        .frame(maxWidth: 820, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(LifeOSTheme.canvas)
    }

    // MARK: - Cabecera

    private var header: some View {
        LifeOSScreenHeader(
            eyebrow: "Agenda · \(loadLabel)",
            title: dayTitle,
            detail: dayDetail
        ) {
            HStack(spacing: LifeOSSpace.s) {
                Button("Hoy") { Task { await model.selectAgendaDay(Date()) } }
                    .buttonStyle(LifeOSGhostButtonStyle())
                Button {
                    Task { await model.stepAgendaDay(-1) }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(LifeOSGhostButtonStyle())
                .help("Día anterior")
                Button {
                    Task { await model.stepAgendaDay(1) }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(LifeOSGhostButtonStyle())
                .help("Día siguiente")
                Button("Nueva cita") { model.startEvent(on: model.agendaDay, hour: nextHour) }
                    .buttonStyle(LifeOSPrimaryButtonStyle())
            }
        }
    }

    private var dayTitle: String {
        if Calendar.current.isDateInToday(model.agendaDay) {
            return "Hoy, " + TimeFormatting.shortDay(model.agendaDay)
        }
        return TimeFormatting.longDay(model.agendaDay).capitalizedFirst
    }

    private var dayDetail: String {
        let appointments = model.agendaAppointments.count
        let due = model.agendaDueTasks.count
        let focus = model.agendaFocusBlocks.count
        var parts: [String] = []
        if appointments > 0 { parts.append(appointments == 1 ? "1 cita" : "\(appointments) citas") }
        if focus > 0 { parts.append(focus == 1 ? "1 bloque de foco" : "\(focus) bloques de foco") }
        if due > 0 { parts.append(due == 1 ? "1 vencimiento" : "\(due) vencimientos") }
        if parts.isEmpty { return "Día libre. Buen momento para lo importante." }
        return parts.joined(separator: " · ")
    }

    private var loadLabel: String {
        let total = model.agendaWeek.reduce(0) { $0 + model.agendaLoad(of: $1) }
        return total == 1 ? "1 cosa esta semana" : "\(total) cosas esta semana"
    }

    private var nextHour: Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        return calendar.isDateInToday(model.agendaDay) ? min(hour + 1, 23) : 9
    }

    // MARK: - Tira de la semana

    private var weekStrip: some View {
        HStack(spacing: LifeOSSpace.s) {
            ForEach(model.agendaWeek, id: \.self) { day in
                weekChip(day)
            }
            Spacer(minLength: 0)
            originFilter
        }
    }

    private func weekChip(_ day: Date) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: model.agendaDay)
        let isToday = AgendaRange.isToday(day)
        let load = model.agendaLoad(of: day)
        return Button {
            Task { await model.selectAgendaDay(day) }
        } label: {
            VStack(spacing: 2) {
                Text(TimeFormatting.weekdayLetter(day).uppercased())
                    .font(LifeOSFont.caption)
                    .foregroundStyle(isSelected ? LifeOSTheme.brandOnSoft : LifeOSTheme.textTertiary)
                Text(TimeFormatting.dayNumber(day))
                    .font(LifeOSFont.label)
                    .foregroundStyle(isSelected ? LifeOSTheme.brandOnSoft : LifeOSTheme.textPrimary)
                Circle()
                    .fill(load > 0 ? (isSelected ? LifeOSTheme.brandOnSoft : LifeOSTheme.brand) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(minWidth: 42)
            .padding(.vertical, LifeOSSpace.s)
            .background(
                RoundedRectangle(cornerRadius: LifeOSRadius.md, style: .continuous)
                    .fill(isSelected ? LifeOSTheme.brandSoft : LifeOSTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LifeOSRadius.md, style: .continuous)
                    .strokeBorder(
                        isToday && !isSelected ? LifeOSTheme.brand.opacity(0.5) : LifeOSTheme.borderSubtle,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: LifeOSRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(TimeFormatting.longDay(day)) · \(load) cosas")
    }

    private var originFilter: some View {
        HStack(spacing: LifeOSSpace.xs) {
            ForEach(AgendaOriginFilter.allCases) { filter in
                Button {
                    model.agendaFilter = filter
                } label: {
                    Text(filter.label)
                        .font(LifeOSFont.labelSmall)
                        .foregroundStyle(model.agendaFilter == filter ? LifeOSTheme.brandOnSoft : LifeOSTheme.textSecondary)
                        .padding(.horizontal, LifeOSSpace.m)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(model.agendaFilter == filter ? LifeOSTheme.brandSoft : LifeOSTheme.surface)
                        )
                        .overlay(
                            Capsule().strokeBorder(LifeOSTheme.borderSubtle, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Pares por resolver

    @ViewBuilder
    private var duplicates: some View {
        if !model.agendaDuplicates.isEmpty {
            LifeOSCard(accent: LifeOSTheme.warning) {
                VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                    LifeOSSectionHeader("¿Es lo mismo?", count: model.agendaDuplicates.count)
                    Text("Aparecen como cita y como acción. Nada se fusiona ni se borra solo: lo decides tú, y la decisión se recuerda.")
                        .font(LifeOSFont.bodySmall)
                        .foregroundStyle(LifeOSTheme.textSecondary)
                    ForEach(model.agendaDuplicates) { pair in
                        DuplicateRow(pair: pair, model: model)
                    }
                }
            }
        }
    }

    // MARK: - Carriles

    private func lane<Content: View>(
        title: String,
        empty: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LifeOSCard {
            VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                LifeOSSectionHeader(title, count: count)
                if count == 0 {
                    Text(empty)
                        .font(LifeOSFont.bodySmall)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: LifeOSSpace.s) {
                        content()
                    }
                }
            }
        }
    }
}

// MARK: - Piezas

/// Una cita o un bloque de foco.
struct EventRow: View {
    let event: AgendaEvent
    @ObservedObject var model: LifeOSModel
    let isFocusBlock: Bool

    var body: some View {
        HStack(alignment: .top, spacing: LifeOSSpace.m) {
            VStack(alignment: .leading, spacing: 2) {
                hourLabel
                    .font(LifeOSFont.mono)
                    .foregroundStyle(LifeOSTheme.textSecondary)
                if event.series {
                    Image(systemName: "repeat")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LifeOSTheme.textTertiary)
                }
            }
            .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
                Text(event.title)
                    .font(LifeOSFont.body)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                HStack(spacing: LifeOSSpace.s) {
                    if let focus = event.focusTarget {
                        LifeOSChip("Enfoca a \(focus.title)", systemImage: LifeOSKind.symbol(for: focus.kind), tone: .accent)
                    }
                    if !event.location.isEmpty {
                        LifeOSChip(event.location, systemImage: "mappin.and.ellipse", tone: .neutral)
                    }
                    if let origin = event.origin, !origin.label.isEmpty {
                        LifeOSChip(origin.label, systemImage: "arrow.triangle.2.circlepath", tone: .info)
                    }
                }
            }

            Spacer(minLength: 0)

            LifeOSRowMenu {
                Button("Editar") { model.editEvent(event) }
                Button("Marcar como hecha") { Task { await model.completeEvent(event) } }
            }
        }
        .padding(.vertical, LifeOSSpace.xs)
    }

    /// La hora, en dos líneas si es un intervalo: en una sola se partía a media
    /// palabra en la columna.
    @ViewBuilder
    private var hourLabel: some View {
        if event.allDay {
            Text("Todo el día")
        } else if isFocusBlock {
            Text(TimeFormatting.time(event.startsAt))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(TimeFormatting.time(event.startsAt))
                Text("– " + TimeFormatting.time(event.endsAt))
                    .foregroundStyle(LifeOSTheme.textTertiary)
            }
        }
    }
}

/// Una acción: en la agenda (vencimientos, bloques) y en «Ejecutar».
struct TaskRow: View {
    let task: LifeOSTask
    @ObservedObject var model: LifeOSModel
    var showSchedule: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LifeOSSpace.m) {
            Button {
                Task { await model.toggleTask(task) }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(task.isDone ? LifeOSTheme.positive : LifeOSTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Reabrir" : "Marcar como hecha")

            VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
                Text(task.title)
                    .font(LifeOSFont.body)
                    .foregroundStyle(task.isDone ? LifeOSTheme.textTertiary : LifeOSTheme.textPrimary)
                    .strikethrough(task.isDone, color: LifeOSTheme.textTertiary)
                HStack(spacing: LifeOSSpace.s) {
                    if showSchedule, let start = task.scheduledStart {
                        LifeOSChip(TimeFormatting.time(start), systemImage: "clock", tone: .accent)
                    }
                    if let due = task.dueDate {
                        LifeOSChip(
                            TimeFormatting.relativeDue(due),
                            systemImage: "calendar",
                            tone: isOverdue(due) ? .danger : .neutral
                        )
                    }
                    if task.priority != 3 {
                        LifeOSChip("P\(task.priority)", systemImage: "flag", tone: task.priority <= 2 ? .warning : .neutral)
                    }
                    if !task.context.isEmpty {
                        LifeOSChip(task.context, systemImage: "tag", tone: .neutral)
                    }
                    if let warning = task.externalWarning {
                        LifeOSChip(warning, systemImage: "exclamationmark.triangle", tone: .warning)
                    } else if let origin = task.origin, !origin.label.isEmpty {
                        LifeOSChip(origin.label, systemImage: "arrow.triangle.2.circlepath", tone: .info)
                    }
                }
            }

            Spacer(minLength: 0)

            LifeOSRowMenu {
                Button("En curso") { Task { await model.setTaskStatus(task, "doing") } }
                Button("Por hacer") { Task { await model.setTaskStatus(task, "todo") } }
                Button("Sin clasificar") { Task { await model.setTaskStatus(task, "inbox") } }
                Divider()
                Button("Hecha") { Task { await model.setTaskStatus(task, "done") } }
                Button("Descartar") { Task { await model.setTaskStatus(task, "cancelled") } }
            }
        }
        .padding(.vertical, LifeOSSpace.xs)
    }

    private func isOverdue(_ due: Date) -> Bool {
        due < Date() && task.isOpen
    }
}

/// Un par acción+evento con sus tres decisiones.
struct DuplicateRow: View {
    let pair: DuplicatePair
    @ObservedObject var model: LifeOSModel

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            HStack(spacing: LifeOSSpace.s) {
                LifeOSChip(pair.taskTitle, systemImage: "checkmark.circle", tone: .accent)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LifeOSTheme.textTertiary)
                LifeOSChip(pair.eventTitle, systemImage: "calendar", tone: .info)
                Spacer(minLength: 0)
                if let at = pair.at {
                    Text(TimeFormatting.relative(at))
                        .font(LifeOSFont.caption)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                }
            }
            HStack(spacing: LifeOSSpace.s) {
                Button(DuplicateChoice.same.label) {
                    Task { await model.resolveDuplicate(pair, choice: .same) }
                }
                .buttonStyle(LifeOSSecondaryButtonStyle())
                ForEach([DuplicateChoice.different, .forget], id: \.self) { choice in
                    Button(choice.label) {
                        Task { await model.resolveDuplicate(pair, choice: choice) }
                    }
                    .buttonStyle(LifeOSGhostButtonStyle())
                }
                Spacer(minLength: 0)
            }
            .disabled(model.busy)
        }
        .padding(.vertical, LifeOSSpace.xs)
    }
}

/// Alta y edición de una cita o un bloque de foco.
struct EventForm: View {
    let draft: EventDraft
    @ObservedObject var model: LifeOSModel
    @Environment(\.lifeOSFlatSurfaces) private var renderMode

    var body: some View {
        LifeOSCard(accent: LifeOSTheme.brand) {
            VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                LifeOSSectionHeader(draft.isEditing ? "Editar cita" : "Nueva cita")
                LifeOSField("Título", text: binding(\.title))
                HStack(alignment: .bottom, spacing: LifeOSSpace.l) {
                    DateTimeField(title: "Empieza", date: binding(\.startsAt), renderMode: renderMode)
                    DateTimeField(title: "Termina", date: binding(\.endsAt), renderMode: renderMode)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: LifeOSSpace.s) {
                    Text("Todo el día")
                        .font(LifeOSFont.bodySmall)
                        .foregroundStyle(LifeOSTheme.textSecondary)
                    LifeOSSwitch(isOn: binding(\.allDay))
                    Spacer(minLength: 0)
                }
                LifeOSField("Lugar (opcional)", text: binding(\.location))
                if !model.canSaveEvent && draft.endsAt <= draft.startsAt {
                    MessageRow(
                        text: "La hora de fin tiene que ser posterior a la de inicio.",
                        tone: .warning,
                        systemImage: "exclamationmark.triangle"
                    )
                }
                HStack(spacing: LifeOSSpace.s) {
                    Spacer(minLength: 0)
                    Button("Cancelar") { model.cancelEventDraft() }
                        .buttonStyle(LifeOSGhostButtonStyle())
                    Button(draft.isEditing ? "Guardar cambios" : "Crear cita") {
                        Task { await model.saveEvent() }
                    }
                    .buttonStyle(LifeOSPrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canSaveEvent)
                }
            }
        }
    }

    private func binding<Value>(_ key: WritableKeyPath<EventDraft, Value>) -> Binding<Value> {
        Binding(
            get: { (model.eventDraft ?? draft)[keyPath: key] },
            set: { model.eventDraft?[keyPath: key] = $0 }
        )
    }
}

/// Fecha y hora juntas. Fuera de pantalla no se pueden pintar los controles de
/// AppKit, así que en modo render se dibuja el mismo aspecto sin control.
struct DateTimeField: View {
    let title: String
    @Binding var date: Date
    let renderMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
            Text(title)
                .font(LifeOSFont.caption)
                .foregroundStyle(LifeOSTheme.textTertiary)
            if renderMode {
                Text(TimeFormatting.dateAndTime(date))
                    .font(LifeOSFont.body)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                    .padding(.horizontal, LifeOSSpace.m)
                    .padding(.vertical, 6)
                    .frame(minWidth: 190, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: LifeOSRadius.md, style: .continuous)
                            .fill(LifeOSTheme.field)
                    )
            } else {
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.field)
            }
        }
    }
}
