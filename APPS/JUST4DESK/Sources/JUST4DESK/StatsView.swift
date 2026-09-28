import SwiftUI
import J4IAI
import J4ICore
import J4IIndex

/// N7 — Panel de estadísticas: qué hizo la app (archivados / por revisar / deshechos), de dónde
/// salió cada decisión (IA / reglas / conocimiento / manual) y cuánto costó la IA.
///
/// Todos los datos son locales (journal de operaciones + contadores de `AIControlCenter`);
/// nada sale del Mac.
struct StatsView: View {
    private enum StatsRange: String, CaseIterable, Identifiable {
        case days14 = "14 días"
        case days30 = "30 días"
        case days90 = "90 días"

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .days14: return 14
            case .days30: return 30
            case .days90: return 90
            }
        }
    }

    @EnvironmentObject private var engine: SearchViewModel
    @State private var range: StatsRange = .days14
    @State private var stats: SearchIndex.JournalStats?
    @State private var indexStats: IndexStats?
    @State private var aiUsage = AIControlCenter.shared.usage()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: J4I.Space.l) {
                header
                summaryCards
                sourceCard
                activityCard
                footer
            }
            .padding(J4I.Space.l)
        }
        .frame(minWidth: 660, minHeight: 580)
        .task { await reload() }
        .onChange(of: range) { _, _ in Task { await reload() } }
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(spacing: J4I.Space.m) {
            SectionHeader("Estadísticas", systemImage: "chart.bar.xaxis")
            Spacer()
            Picker("", selection: $range) {
                ForEach(StatsRange.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
    }

    // MARK: - Resumen

    private var summaryCards: some View {
        HStack(spacing: J4I.Space.m) {
            statCard(title: "Archivados", value: "\(stats?.archived ?? 0)", systemImage: "tray.and.arrow.down", tint: J4I.success)
            statCard(title: "Por revisar", value: "\(stats?.quarantined ?? 0)", systemImage: "questionmark.folder", tint: J4I.warning)
            statCard(title: "Deshechos", value: undoLabel, systemImage: "arrow.uturn.backward", tint: J4I.brand)
            statCard(title: "IA hoy", value: "\(aiUsage.callsToday)/\(aiUsage.dailyLimit)", systemImage: "sparkles", tint: J4I.brand)
        }
    }

    private var undoLabel: String {
        guard let stats else { return "0" }
        let undoable = stats.archived + stats.quarantined + stats.cold
        guard undoable > 0 else { return "\(stats.undone)" }
        let percent = Int((Double(stats.undone) / Double(undoable) * 100).rounded())
        return "\(stats.undone) · \(percent) %"
    }

    private func statCard(title: String, value: String, systemImage: String, tint: Color) -> some View {
        J4ICard {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Fuentes de decisión

    private var sourceCard: some View {
        J4ICard {
            VStack(alignment: .leading, spacing: J4I.Space.m) {
                SectionHeader("De dónde salió cada decisión", systemImage: "point.3.connected.trianglepath.dotted")
                if let stats, !stats.bySource.isEmpty {
                    let total = max(1, stats.bySource.values.reduce(0, +))
                    ForEach(sourceRows(stats), id: \.key) { row in
                        sourceRow(label: Self.sourceLabel(row.key), count: row.count, total: total)
                    }
                } else {
                    Text("Todavía no hay archivados ni «por revisar» en este periodo.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sourceRows(_ stats: SearchIndex.JournalStats) -> [(key: String, count: Int)] {
        stats.bySource
            .map { (key: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Etiqueta legible de la fuente de decisión (rawValue del journal).
    static func sourceLabel(_ raw: String) -> String {
        switch raw {
        case "ai": return "IA (DeepSeek)"
        case "rules": return "Reglas locales"
        case "knowledge": return "Conocimiento local"
        case "fallback": return "Sin coincidencia"
        case "manual": return "Manual (revisión)"
        case "(sin dato)": return "Histórico (antes de N7)"
        default: return raw
        }
    }

    private func sourceRow(label: String, count: Int, total: Int) -> some View {
        HStack(spacing: J4I.Space.s) {
            Text(label)
                .font(.system(size: 12))
                .frame(width: 170, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(J4I.hairline.opacity(0.35))
                    Capsule()
                        .fill(J4I.brand.opacity(0.75))
                        .frame(width: max(4, geometry.size.width * CGFloat(count) / CGFloat(total)))
                }
            }
            .frame(height: 8)
            Text("\(count) · \(Int((Double(count) / Double(total) * 100).rounded())) %")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .trailing)
        }
    }

    // MARK: - Actividad por día

    private var activityCard: some View {
        J4ICard {
            VStack(alignment: .leading, spacing: J4I.Space.m) {
                SectionHeader("Archivados por día", systemImage: "calendar")
                if let stats, !stats.days.isEmpty {
                    dailyBars(stats.days)
                } else {
                    Text("Sin actividad en el periodo.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func dailyBars(_ days: [SearchIndex.JournalStats.DayCount]) -> some View {
        let maxValue = max(1, days.map(\.archived).max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(days, id: \.dayKey) { day in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day.archived > 0 ? J4I.brand.opacity(0.85) : J4I.hairline.opacity(0.25))
                            .frame(height: max(4, 72 * CGFloat(day.archived) / CGFloat(maxValue)))
                        if day.quarantined > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(J4I.warning.opacity(0.8))
                                .frame(height: max(2, 22 * CGFloat(day.quarantined) / CGFloat(maxValue)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(day.dayKey): \(day.archived) archivado(s), \(day.quarantined) por revisar")
                }
            }
            .frame(height: 100, alignment: .bottom)
            HStack {
                Text(days.first?.dayKey ?? "")
                Spacer()
                Text(days.last?.dayKey ?? "")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            HStack(spacing: 14) {
                legendChip(color: J4I.brand.opacity(0.85), text: "archivados")
                legendChip(color: J4I.warning.opacity(0.8), text: "por revisar")
            }
        }
    }

    private func legendChip(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 10, height: 6)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pie

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let indexStats {
                Text("Índice: \(indexStats.totalEntries.formatted()) entradas (\(indexStats.totalFiles.formatted()) ficheros) · vectores semánticos: \(engine.semanticEmbeddedCount)/\(engine.semanticFileCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text("Datos 100 % locales (journal de operaciones y contadores de IA); nada sale del Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Carga

    private func reload() async {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let since = Calendar.current.date(byAdding: .day, value: -(range.days - 1), to: startOfToday) ?? startOfToday
        stats = try? await SearchIndex.shared.journalStats(since: since)
        indexStats = try? await SearchIndex.shared.stats()
        aiUsage = AIControlCenter.shared.usage()
    }
}
