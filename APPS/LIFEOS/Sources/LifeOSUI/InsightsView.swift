import LifeOSAPI
import LifeOSCore
import SwiftUI

/// Buscar y cronología: releer lo que ya existe.
///
/// Las dos caras leen datos que ya están en otras secciones (diario, agenda,
/// acciones, decisiones, métricas, capturas), así que **no inventan nada**: la
/// cronología los pone en el mismo eje temporal y la búsqueda devuelve el
/// resumen; para editar se abre en LifeOS.
public struct InsightsView: View {
    @ObservedObject private var model: LifeOSModel

    public init(model: LifeOSModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            InsightsContent(model: model)
        }
        .task {
            if model.timeline == nil { await model.loadTimeline() }
        }
    }
}

struct InsightsContent: View {
    @ObservedObject var model: LifeOSModel

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.l) {
            header
            switch model.insightMode {
            case .timeline:
                timelineControls
                timelineList
            case .search:
                searchBar
                searchList
            }
        }
        .padding(.horizontal, LifeOSSpace.xl)
        .padding(.vertical, LifeOSSpace.xl)
        .frame(maxWidth: 820, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(LifeOSTheme.canvas)
    }

    private var header: some View {
        LifeOSScreenHeader(
            eyebrow: model.insightMode == .timeline ? eyebrow : "Buscar",
            title: model.insightMode == .timeline ? "Lo que ha pasado" : "Encuentra cualquier cosa",
            detail: model.insightMode == .timeline
                ? "Cada línea es algo que ya existe en su sección, puesto en el tiempo. No se inventa nada."
                : "Se busca en el diario, las acciones, los eventos, las decisiones y las capturas. Lo sensible se marca."
        ) {
            modeSwitch
        }
    }

    private var eyebrow: String {
        guard let timeline = model.timeline else { return "Cronología" }
        let count = timeline.items.count
        return "Cronología · \(count == 1 ? "1 hecho" : "\(count) hechos") · \(timeline.days) días"
    }

    private var modeSwitch: some View {
        HStack(spacing: LifeOSSpace.xs) {
            ForEach(InsightMode.allCases) { mode in
                Button {
                    model.insightMode = mode
                } label: {
                    Text(mode.label)
                        .font(LifeOSFont.labelSmall)
                        .foregroundStyle(model.insightMode == mode ? LifeOSTheme.brandOnSoft : LifeOSTheme.textSecondary)
                        .padding(.horizontal, LifeOSSpace.m)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(model.insightMode == mode ? LifeOSTheme.brandSoft : LifeOSTheme.surface)
                        )
                        .overlay(Capsule().strokeBorder(LifeOSTheme.borderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Cronología

    private var timelineControls: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.s) {
            HStack(spacing: LifeOSSpace.xs) {
                Text("Periodo")
                    .font(LifeOSFont.caption)
                    .foregroundStyle(LifeOSTheme.textTertiary)
                ForEach([7, 30, 120], id: \.self) { days in
                    chip(
                        days == 7 ? "Última semana" : (days == 30 ? "Último mes" : "4 meses"),
                        selected: model.timelineDays == days
                    ) {
                        model.timelineDays = days
                        Task { await model.loadTimeline() }
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: LifeOSSpace.xs) {
                Text("Tipos")
                    .font(LifeOSFont.caption)
                    .foregroundStyle(LifeOSTheme.textTertiary)
                chip("Todos", selected: model.timelineKinds.isEmpty) {
                    model.timelineKinds = []
                    Task { await model.loadTimeline() }
                }
                ForEach(TimelineKind.allCases, id: \.self) { kind in
                    chip(
                        kind.label,
                        selected: model.timelineKinds.contains(kind.rawValue)
                    ) {
                        if model.timelineKinds.contains(kind.rawValue) {
                            model.timelineKinds.remove(kind.rawValue)
                        } else {
                            model.timelineKinds.insert(kind.rawValue)
                        }
                        Task { await model.loadTimeline() }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var timelineList: some View {
        if let timeline = model.timeline, !timeline.items.isEmpty {
            VStack(alignment: .leading, spacing: LifeOSSpace.l) {
                ForEach(timeline.byDay, id: \.day) { group in
                    LifeOSCard {
                        VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                            LifeOSSectionHeader(dayLabel(group.day), count: group.items.count)
                            VStack(alignment: .leading, spacing: LifeOSSpace.s) {
                                ForEach(group.items) { item in
                                    TimelineRow(item: item, model: model)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            LifeOSCard {
                LifeOSEmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "Nada en este periodo",
                    detail: "Prueba con más días o quita algún filtro de tipo."
                )
            }
        }
    }

    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Hoy" }
        if Calendar.current.isDateInYesterday(day) { return "Ayer" }
        return TimeFormatting.longDay(day).capitalizedFirst
    }

    // MARK: - Buscar

    private var searchBar: some View {
        HStack(spacing: LifeOSSpace.s) {
            LifeOSField("Buscar en LifeOS…", text: $model.searchText, submitLabel: "Buscar") {
                Task { await model.runSearch() }
            }
            Button("Buscar") { Task { await model.runSearch() } }
                .buttonStyle(LifeOSPrimaryButtonStyle())
                .disabled(model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
            if model.searchResults != nil {
                Button("Limpiar") { model.clearSearch() }
                    .buttonStyle(LifeOSGhostButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var searchList: some View {
        if let results = model.searchResults {
            if results.results.isEmpty {
                LifeOSCard {
                    LifeOSEmptyState(
                        systemImage: "magnifyingglass",
                        title: "Sin resultados para «\(results.query)»",
                        detail: "Prueba con menos palabras. Se busca en todo el espacio de trabajo."
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: LifeOSSpace.l) {
                    ForEach(results.grouped, id: \.kind) { group in
                        LifeOSCard {
                            VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                                LifeOSSectionHeader(LifeOSKind.label(for: group.kind), count: group.items.count)
                                VStack(alignment: .leading, spacing: LifeOSSpace.s) {
                                    ForEach(group.items) { result in
                                        SearchRow(result: result, model: model)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            LifeOSCard {
                LifeOSEmptyState(
                    systemImage: "text.magnifyingglass",
                    title: "Escribe algo para buscar",
                    detail: "Se busca en el diario, las acciones, los eventos, las decisiones y las capturas."
                )
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(LifeOSFont.labelSmall)
                .foregroundStyle(selected ? LifeOSTheme.brandOnSoft : LifeOSTheme.textSecondary)
                .padding(.horizontal, LifeOSSpace.m)
                .padding(.vertical, 5)
                .background(Capsule().fill(selected ? LifeOSTheme.brandSoft : LifeOSTheme.surface))
                .overlay(Capsule().strokeBorder(LifeOSTheme.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Piezas

/// Un hecho de la cronología.
struct TimelineRow: View {
    let item: TimelineItem
    @ObservedObject var model: LifeOSModel

    var body: some View {
        HStack(alignment: .top, spacing: LifeOSSpace.m) {
            Image(systemName: LifeOSKind.symbol(for: item.kind))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LifeOSTheme.brand)
                .frame(width: 20, height: 20)
                .background(Circle().fill(LifeOSTheme.brandSoft))

            VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
                Text(item.title)
                    .font(LifeOSFont.body)
                    .foregroundStyle(LifeOSTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: LifeOSSpace.s) {
                    Text(TimeFormatting.time(item.occurredAt))
                        .font(LifeOSFont.mono)
                        .foregroundStyle(LifeOSTheme.textTertiary)
                    LifeOSChip(LifeOSKind.label(for: item.kind), tone: .neutral)
                    if item.sensitive {
                        LifeOSChip("Privado", systemImage: "lock.fill", tone: .neutral)
                    }
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(LifeOSFont.caption)
                            .foregroundStyle(LifeOSTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, LifeOSSpace.xs)
    }
}

/// Un resultado de búsqueda: se lee aquí y se edita en LifeOS.
struct SearchRow: View {
    let result: SearchResult
    @ObservedObject var model: LifeOSModel

    var body: some View {
        Button {
            // La web es una sola página sin rutas por sección, así que se abre su
            // inicio: inventar `/ejecutar` daría un 404.
            model.openWeb()
        } label: {
            HStack(alignment: .top, spacing: LifeOSSpace.m) {
                Image(systemName: LifeOSKind.symbol(for: result.kind))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LifeOSTheme.textSecondary)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
                    Text(result.title)
                        .font(LifeOSFont.body)
                        .foregroundStyle(LifeOSTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                    if !result.excerpt.isEmpty {
                        Text(result.excerpt)
                            .font(LifeOSFont.bodySmall)
                            .foregroundStyle(LifeOSTheme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if result.isSensitive {
                        LifeOSChip("Privado", systemImage: "lock.fill", tone: .neutral)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LifeOSTheme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Abrir en LifeOS (la sección se elige allí)")
    }
}
