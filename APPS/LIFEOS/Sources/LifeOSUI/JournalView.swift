import LifeOSAPI
import LifeOSCore
import SwiftUI

/// Diario: escribir el día, con ánimo y energía opcionales.
///
/// Dos reglas del producto que la interfaz respeta:
///   · **Privado por defecto** (sensibilidad `sensitive`): no sale a proveedores de IA externos.
///   · **El texto no se reescribe nunca.** Si empiezas con `@hora:22:30` o `@fecha:20-09-2026`, eso manda; las
///     referencias a acciones y eventos se declaran aparte para que el vínculo sea real.
public struct JournalView: View {
    @ObservedObject private var model: LifeOSModel

    public init(model: LifeOSModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            JournalContent(model: model)
        }
    }
}

/// El contenido del diario, sin el contenedor con scroll.
struct JournalContent: View {
    @ObservedObject var model: LifeOSModel
    @Environment(\.lifeOSFlatSurfaces) private var renderMode
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.l) {
            header
            composer
            entries
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
            title: model.journalEditing == nil ? "Tu día, por escrito" : "Editando una entrada",
            detail: model.journalEditing == nil
                ? "El diario es privado: no se envía a ningún proveedor de IA."
                : "Corrige lo que quieras. El texto se guarda tal cual lo escribas."
        ) {
            if model.journalEditing != nil {
                Button("Cancelar edición") { model.cancelJournalEdit() }
                    .buttonStyle(LifeOSGhostButtonStyle())
            }
        }
    }

    private var eyebrow: String {
        let count = model.journal.count
        let suffix = count == 1 ? "1 entrada" : "\(count) entradas"
        return "Diario · \(suffix)"
    }

    // MARK: - Compositor

    private var composer: some View {
        LifeOSCard {
            VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                LifeOSField("Título (opcional)", text: $model.journalTitle)

                editor

                scheduleHint

                HStack(alignment: .center, spacing: LifeOSSpace.l) {
                    MoodPicker(title: "Ánimo", kind: .mood, value: $model.journalMood)
                    MoodPicker(title: "Energía", kind: .energy, value: $model.journalEnergy)
                    Spacer(minLength: 0)
                    Button {
                        if model.journalPickerOpen {
                            model.closeJournalPicker()
                        } else {
                            model.openJournalPicker()
                        }
                    } label: {
                        Label("Mencionar", systemImage: "at")
                    }
                    .buttonStyle(LifeOSSecondaryButtonStyle())
                }

                if model.journalPickerOpen {
                    JournalMentionPanel(
                        candidates: model.journalCandidates,
                        query: model.journalPickerQuery ?? "",
                        loading: model.journalCandidatesLoading,
                        onSelect: { model.applyJournalCandidate($0) },
                        onClose: { model.closeJournalPicker() }
                    )
                }

                if !model.journalMentions.isEmpty {
                    mentions
                }

                if !model.journalUnlinked.isEmpty {
                    MessageRow(
                        text: mentionWarning,
                        tone: .warning,
                        systemImage: "link.badge.plus"
                    )
                }

                footer
            }
        }
    }

    /// Qué hará la cabecera de la entrada (`@hora:` / `@fecha:`) al guardar.
    ///
    /// El servidor aplica esas reglas, así que aquí se ve **antes** de guardar si se entendió:
    /// es el mismo aviso que da la web. Sin él, un token mal escrito se queda en el texto, la
    /// entrada se guarda con la hora actual y parece que el diario ignora lo que escribes
    /// (pasó el 30-sep-2026 con «@Time:1100»).
    @ViewBuilder
    private var scheduleHint: some View {
        let schedule = JournalLeadHeader.schedule(in: model.journalText)
        if schedule.hasValue {
            Label {
                Text(scheduleSummary(schedule))
            } icon: {
                Image(systemName: "clock.badge.checkmark")
            }
            .font(LifeOSFont.caption)
            .foregroundStyle(LifeOSTheme.textSecondary)
        } else if let invalid = schedule.invalid {
            Label {
                Text("No entiendo \u{AB}\(invalid)\u{BB} como hora ni como fecha: no cambiará nada de la entrada. Se escribe @hora:11:00 (o también @hora:1100).")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(LifeOSFont.caption)
            .foregroundStyle(LifeOSTheme.warning)
        } else {
            Label {
                Text("La hora y el día se fijan al principio del texto: @hora:22:30 (o @hora:2230) y, si es de otro día, @fecha:20-09-2026.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(LifeOSFont.caption)
            .foregroundStyle(LifeOSTheme.textTertiary)
        }
    }

    /// «Se guardará como entrada de hoy a las 11:00.» / «… del 30 de septiembre a las 11:00.»
    private func scheduleSummary(_ schedule: JournalLeadHeader.Schedule) -> String {
        var text = schedule.year != nil
            ? "Se guardará como entrada del \(dayText(schedule))"
            : "Se guardará como entrada de hoy"
        if let hour = schedule.hour {
            text += " a las " + String(format: "%02d:%02d", hour, schedule.minute ?? 0)
        } else {
            text += " (sin hora concreta)"
        }
        return text + "."
    }

    /// El día que manda la cabecera, o «hoy» si sólo se fijó la hora.
    private func dayText(_ schedule: JournalLeadHeader.Schedule) -> String {
        guard let year = schedule.year, let month = schedule.month, let day = schedule.day,
              let date = Calendar.current.date(
                  from: DateComponents(year: year, month: month, day: day)
              ) else {
            return "hoy"
        }
        return TimeFormatting.shortDay(date)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if model.journalText.isEmpty {
                Text("¿Qué ha pasado hoy? Escribe como quieras…")
                    .font(LifeOSFont.bodyLarge)
                    .foregroundStyle(LifeOSTheme.textTertiary)
                    .padding(.horizontal, LifeOSSpace.s)
                    .padding(.vertical, LifeOSSpace.s)
                    .allowsHitTesting(false)
            }
            if renderMode {
                Text(model.journalText)
                    .font(LifeOSFont.bodyLarge)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                    .padding(LifeOSSpace.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextEditor(text: $model.journalText)
                    .font(LifeOSFont.bodyLarge)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(LifeOSSpace.xs)
                    .focused($editorFocused)
            }
        }
        .frame(minHeight: 140, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: LifeOSRadius.lg, style: .continuous)
                .fill(LifeOSTheme.elevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LifeOSRadius.lg, style: .continuous)
                .strokeBorder(
                    editorFocused && !renderMode ? LifeOSTheme.focusRing : Color.clear,
                    lineWidth: 2
                )
        )
        .animation(LifeOSMotion.standard, value: editorFocused)
    }

    /// Aviso de menciones escritas a mano que no están vinculadas. Se recorta lo
    /// que se enseña: como la sintaxis no tiene cierre, una mención escrita a
    /// mano se lee hasta la siguiente arroba, y repetir aquí toda la frase
    /// sobraría.
    private var mentionWarning: String {
        let shown = model.journalUnlinked
            .map { $0.count > 40 ? String($0.prefix(40)) + "…" : $0 }
            .joined(separator: ", ")
        let many = model.journalUnlinked.count == 1
            ? "Hay una mención escrita a mano sin vincular"
            : "Hay \(model.journalUnlinked.count) menciones escritas a mano sin vincular"
        return "\(many): \(shown). Usa «Mencionar» para que el vínculo sea real; si no, se quedan como texto."
    }

    /// Referencias ya vinculadas a acciones o eventos. Se pueden quitar sin
    /// tocar el texto (el texto escrito se respeta).
    private var mentions: some View {
        HStack(spacing: LifeOSSpace.s) {
            Text("Referencias")
                .font(LifeOSFont.caption)
                .foregroundStyle(LifeOSTheme.textTertiary)
            ForEach(model.journalMentions) { mention in
                Button {
                    model.removeJournalMention(mention)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: LifeOSKind.symbol(for: mention.kind))
                            .font(.system(size: 9, weight: .bold))
                        Text(mention.text)
                            .font(LifeOSFont.labelSmall)
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(LifeOSTheme.brandOnSoft)
                .padding(.horizontal, LifeOSSpace.m)
                .padding(.vertical, 5)
                .background(Capsule().fill(LifeOSTheme.brandSoft))
                .help("Quitar la referencia (el texto se queda como está)")
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: LifeOSSpace.s) {
            HStack(spacing: LifeOSSpace.xs) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("Privado")
                    .font(LifeOSFont.labelSmall)
            }
            .foregroundStyle(LifeOSTheme.textSecondary)
            .padding(.horizontal, LifeOSSpace.m)
            .padding(.vertical, 5)
            .background(Capsule().fill(LifeOSTheme.elevated))

            Spacer(minLength: 0)

            if model.busy {
                ProgressView().controlSize(.small)
            }

            Text("⌘↩")
                .font(LifeOSFont.caption)
                .foregroundStyle(LifeOSTheme.textTertiary)

            Button(model.journalEditing == nil ? "Guardar" : "Guardar cambios") {
                Task { await model.saveJournalEntry() }
            }
            .buttonStyle(LifeOSPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canSaveJournalEntry)
        }
    }

    // MARK: - Entradas

    @ViewBuilder
    private var entries: some View {
        if model.journal.isEmpty {
            LifeOSCard {
                LifeOSEmptyState(
                    systemImage: "book.closed",
                    title: "Todavía no has escrito nada",
                    detail: "Escribe la primera entrada arriba. Con una frase basta."
                )
            }
        } else {
            VStack(alignment: .leading, spacing: LifeOSSpace.l) {
                ForEach(model.journalByDay, id: \.day) { group in
                    VStack(alignment: .leading, spacing: LifeOSSpace.s) {
                        LifeOSSectionHeader(dayLabel(group.day), count: group.entries.count)
                        ForEach(group.entries) { entry in
                            JournalEntryRow(
                                entry: entry,
                                isOpen: model.journalOpen == entry.id,
                                onToggle: { model.toggleJournalEntry(entry) },
                                onEdit: { model.editJournalEntry(entry) },
                                onDelete: { Task { await model.deleteJournalEntry(entry) } }
                            )
                        }
                    }
                }
            }
        }
    }

    private func dayLabel(_ raw: String) -> String {
        guard let day = TimeFormatting.day(from: raw) else { return raw }
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Hoy" }
        if calendar.isDateInYesterday(day) { return "Ayer" }
        return TimeFormatting.longDay(day)
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

/// El texto de una entrada, con las menciones (`@tarea:` / `@evento:`) pintadas
/// como etiquetas en vez de enseñar el código. El texto guardado no se toca:
/// esto es sólo cómo se lee.
struct JournalBodyText {
    static func attributed(_ content: String, known: [JournalMention] = []) -> AttributedString {
        var output = AttributedString()
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            if index > 0 { output += AttributedString("\n") }
            for segment in JournalText.segments(in: String(line), known: known) {
                switch segment {
                case .text(let text):
                    output += AttributedString(text)
                case .reference(_, let label, let trailing):
                    var mention = AttributedString(label + trailing)
                    mention.foregroundColor = LifeOSTheme.brandOnSoft
                    mention.backgroundColor = LifeOSTheme.brandSoft
                    output += mention
                }
            }
        }
        return output
    }
}

/// Selector de referencias: se abre al escribir `@…` o con el botón «Mencionar».
///
/// Sin elegir nada no se vincula nada: una mención escrita a mano se queda como
/// texto y se avisa (`unresolved_references`), que es lo que hace la web.
struct JournalMentionPanel: View {
    let candidates: [JournalReferenceCandidate]
    let query: String
    let loading: Bool
    let onSelect: (JournalReferenceCandidate) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: LifeOSSpace.s) {
                Text(headline)
                    .font(LifeOSFont.labelSmall)
                    .foregroundStyle(LifeOSTheme.textSecondary)
                Spacer(minLength: 0)
                Button("Cerrar") { onClose() }
                    .buttonStyle(LifeOSGhostButtonStyle())
            }
            .padding(.horizontal, LifeOSSpace.m)
            .padding(.vertical, LifeOSSpace.s)

            LifeOSDivider()

            if candidates.isEmpty {
                Text(loading ? "Buscando…" : "Sin coincidencias. Prueba con otras palabras.")
                    .font(LifeOSFont.bodySmall)
                    .foregroundStyle(LifeOSTheme.textTertiary)
                    .padding(LifeOSSpace.m)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(candidates) { candidate in
                        Button {
                            onSelect(candidate)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: LifeOSSpace.s) {
                                Text(Self.kindLabel(candidate.kind))
                                    .font(LifeOSFont.labelSmall)
                                    .foregroundStyle(LifeOSTheme.brandOnSoft)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(LifeOSTheme.brandSoft))
                                Text(candidate.label)
                                    .font(LifeOSFont.body)
                                    .foregroundStyle(LifeOSTheme.textPrimary)
                                if !candidate.detail.isEmpty {
                                    Text(candidate.detail)
                                        .font(LifeOSFont.caption)
                                        .foregroundStyle(LifeOSTheme.textTertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, LifeOSSpace.m)
                            .padding(.vertical, LifeOSSpace.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if candidate.id != candidates.last?.id { LifeOSDivider() }
                    }
                }
            }

            LifeOSDivider()
            Text("Elige a qué te refieres: se escribe «@tarea:» o «@evento:» y queda vinculado de verdad.")
                .font(LifeOSFont.caption)
                .foregroundStyle(LifeOSTheme.textTertiary)
                .padding(.horizontal, LifeOSSpace.m)
                .padding(.vertical, LifeOSSpace.s)
        }
        .background(
            RoundedRectangle(cornerRadius: LifeOSRadius.lg, style: .continuous)
                .fill(LifeOSTheme.elevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LifeOSRadius.lg, style: .continuous)
                .strokeBorder(LifeOSTheme.borderDefault, lineWidth: 1)
        )
    }

    private var headline: String {
        if loading { return "Buscando…" }
        if candidates.isEmpty { return query.isEmpty ? "Acciones y eventos" : "Sin coincidencias" }
        return query.isEmpty ? "Acciones y eventos" : "Resultados para «\(query)»"
    }

    static func kindLabel(_ kind: String) -> String {
        kind == "event" ? "Evento" : "Tarea"
    }
}

/// Ánimo o energía, de 1 a 5. Se puede dejar en blanco volviendo a pulsar.
///
/// Los puntos van de **rojo a verde** (`JournalScale`): el color dice hacia dónde vas y el
/// número de puntos encendidos dice cuánto. El nivel elegido se **escribe** al lado en su
/// color, para quien no distinga el rojo del verde; los puntos sin encender conservan el
/// anillo de su color, así que la escala entera se ve aunque no haya nada elegido.
struct MoodPicker: View {
    let title: String
    let kind: JournalScale.Kind
    @Binding var value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
            Text(title)
                .font(LifeOSFont.caption)
                .foregroundStyle(LifeOSTheme.textTertiary)
            HStack(spacing: LifeOSSpace.xs) {
                ForEach(JournalScale.levels, id: \.self) { level in
                    Button {
                        value = value == level ? nil : level
                    } label: {
                        Circle()
                            .fill(isOn(level) ? JournalScale.color(for: level) : LifeOSTheme.elevated)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle().strokeBorder(
                                    isOn(level)
                                        ? Color.clear
                                        : JournalScale.color(for: level).opacity(0.35),
                                    lineWidth: 1.5
                                )
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("\(JournalScale.spoken(kind, for: level)) · clic para ponerlo, otra vez para quitarlo")
                    .accessibilityLabel(JournalScale.spoken(kind, for: level))
                    .accessibilityAddTraits(level == value ? .isSelected : [])
                }
                if let current = value {
                    // La palabra es el canal que no depende del color.
                    Text(JournalScale.label(kind, for: current))
                        .font(LifeOSFont.caption)
                        .foregroundStyle(JournalScale.color(for: current))
                        .padding(.leading, LifeOSSpace.xxs)
                    Button("Quitar") { value = nil }
                        .buttonStyle(LifeOSGhostButtonStyle())
                        .font(LifeOSFont.caption)
                }
            }
        }
    }

    private func isOn(_ level: Int) -> Bool {
        guard let value else { return false }
        return level <= value
    }
}

/// Una entrada del diario: cerrada es un renglón; abierta, el texto completo.
struct JournalEntryRow: View {
    let entry: JournalEntry
    let isOpen: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var confirmingDelete = false

    var body: some View {
        LifeOSCard(padding: LifeOSSpace.m) {
            VStack(alignment: .leading, spacing: LifeOSSpace.s) {
                summary
                if isOpen { detail }
            }
        }
        .onHover { hovering = $0 }
        .animation(LifeOSMotion.standard, value: hovering)
        .confirmationDialog(
            "¿Mover esta entrada a la papelera?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("A la papelera", role: .destructive) { onDelete() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se puede recuperar desde la web durante 30 días.")
        }
    }

    private var summary: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: LifeOSSpace.m) {
                Text(TimeFormatting.time(entry.occurredAt ?? entry.createdAt))
                    .font(LifeOSFont.mono)
                    .foregroundStyle(LifeOSTheme.textSecondary)
                    .padding(.horizontal, LifeOSSpace.s)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: LifeOSRadius.sm, style: .continuous)
                            .fill(LifeOSTheme.elevated)
                    )

                VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
                    Text(entry.heading)
                        .font(LifeOSFont.body)
                        .foregroundStyle(LifeOSTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(isOpen ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: LifeOSSpace.s) {
                        if entry.mood != nil || entry.energy != nil {
                            metres
                        }
                        if entry.isPrivate {
                            LifeOSChip("Privado", systemImage: "lock.fill", tone: .neutral)
                        }
                        ForEach(entry.references) { reference in
                            LifeOSChip(
                                reference.title,
                                systemImage: LifeOSKind.symbol(for: reference.kind),
                                tone: reference.isMissing ? .warning : .accent
                            )
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LifeOSTheme.textTertiary)
                    .padding(.top, 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.m) {
            LifeOSDivider()
            if !entry.leadTokens.isEmpty {
                // Los tokens del principio ya son la hora y el día de la entrada:
                // se enseñan, pero fuera del texto para que el texto se lea.
                Text(entry.leadTokens.joined(separator: "   "))
                    .font(LifeOSFont.mono)
                    .foregroundStyle(LifeOSTheme.textTertiary)
            }
            Text(JournalBodyText.attributed(entry.body, known: entry.mentions))
                .font(LifeOSFont.bodyLarge)
                .foregroundStyle(LifeOSTheme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !entry.unresolvedReferences.isEmpty {
                MessageRow(
                    text: "Referencias que no se pudieron vincular (el destino se borró, no es una acción ni un evento, o es de otro espacio): \(entry.unresolvedReferences.joined(separator: ", ")). El texto de la entrada no se ha tocado.",
                    tone: .warning,
                    systemImage: "link.badge.plus"
                )
            }

            HStack(spacing: LifeOSSpace.s) {
                Button("Editar") { onEdit() }
                    .buttonStyle(LifeOSSecondaryButtonStyle())
                Button("A la papelera") { confirmingDelete = true }
                    .buttonStyle(LifeOSGhostButtonStyle(tone: .danger))
                Spacer(minLength: 0)
                Text("Guardada el \(TimeFormatting.shortDate(entry.createdAt))")
                    .font(LifeOSFont.caption)
                    .foregroundStyle(LifeOSTheme.textTertiary)
            }
        }
    }

    /// El ánimo y la energía de la fila cerrada: el número **con su color**, porque en una
    /// lista el color se lee antes que el número. El punto es pequeño a propósito (7 pt):
    /// tiñe sin robarle protagonismo al texto de la entrada.
    private var metres: some View {
        HStack(spacing: LifeOSSpace.m) {
            if let mood = entry.mood {
                metre("ánimo", level: mood, kind: .mood)
            }
            if let energy = entry.energy {
                metre("energía", level: energy, kind: .energy)
            }
        }
    }

    private func metre(_ title: String, level: Int, kind: JournalScale.Kind) -> some View {
        HStack(spacing: LifeOSSpace.xs) {
            Circle()
                .fill(JournalScale.color(for: level))
                .frame(width: 7, height: 7)
            Text("\(title) \(level)/5")
                .font(LifeOSFont.caption)
                .foregroundStyle(LifeOSTheme.textTertiary)
        }
        .help(JournalScale.spoken(kind, for: level))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JournalScale.spoken(kind, for: level))
    }
}
