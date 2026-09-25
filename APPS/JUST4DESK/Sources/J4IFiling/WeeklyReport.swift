import Foundation
import J4ICore
import J4IIndex

/// G6 — Informe semanal (local y exportable): el «parte» de lo que hizo la app en los últimos días.
///
/// Se construye desde el journal (`ops_journal`), el conocimiento local y los contadores de IA;
/// **nada sale del Mac**. El resultado se puede copiar o exportar en Markdown.
public struct WeeklyReport: Sendable, Equatable {
    public struct CategoryCount: Sendable, Equatable {
        public let path: String
        public let count: Int
    }

    public let generatedAt: Date
    public let periodStart: Date
    public let periodEnd: Date
    public let filedCount: Int
    public let coldCount: Int
    public let quarantinedCount: Int
    public let undoneCount: Int
    public let movedBytes: Int64
    public let topCategories: [CategoryCount]
    public let promotedRulesThisWeek: Int
    public let knowledgeAppliedTotal: Int
    public let aiCallsTotal: Int
    public let aiTokensTotal: Int
    public let pendingReview: Int

    /// Ahorro estimado de tokens: clasificaciones resueltas sin IA × media de tokens por llamada.
    public var estimatedTokensSaved: Int {
        guard aiCallsTotal > 0, aiTokensTotal > 0 else { return 0 }
        return Int(Double(knowledgeAppliedTotal) * Double(aiTokensTotal) / Double(aiCallsTotal))
    }

    /// Informe listo para copiar/exportar (Markdown en español).
    public var markdown: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM yyyy"
        let bytesText = ByteCountFormatter.string(fromByteCount: movedBytes, countStyle: .file)

        var lines: [String] = []
        lines.append("# Informe semanal — JUST4DESK")
        lines.append("")
        lines.append("**Periodo:** \(formatter.string(from: periodStart)) → \(formatter.string(from: periodEnd))")
        lines.append("")
        lines.append("## Lo que hizo la app")
        lines.append("- Archivados: **\(filedCount)** · movidos a archivo en frío: **\(coldCount)**")
        lines.append("- Datos ordenados: **\(bytesText)** · deshechos: \(undoneCount)")
        lines.append("- Por revisar (ahora): **\(pendingReview)**")
        if !topCategories.isEmpty {
            lines.append("")
            lines.append("## Categorías con más actividad")
            for category in topCategories {
                lines.append("- \(category.path) — \(category.count)")
            }
        }
        lines.append("")
        lines.append("## Aprendizaje y ahorro")
        lines.append("- Reglas promovidas esta semana: **\(promotedRulesThisWeek)**")
        lines.append("- Clasificaciones sin IA (conocimiento local, total): **\(knowledgeAppliedTotal)**")
        if estimatedTokensSaved > 0 {
            lines.append("- Ahorro estimado de tokens: ~\(estimatedTokensSaved.formatted()) (media por llamada × usos locales)")
        }
        lines.append("- IA acumulada: \(aiCallsTotal.formatted()) llamada(s) · \(aiTokensTotal.formatted()) tokens")
        lines.append("")
        lines.append("_Generado por JUST4DESK el \(formatter.string(from: generatedAt)) · local, sin subir nada._")
        return lines.joined(separator: "\n")
    }

    /// Compone el informe de los últimos 7 días.
    public static func build(
        index: SearchIndex,
        rootURL: URL,
        knowledge: LocalKnowledgeStore = .shared,
        aiCallsTotal: Int,
        aiTokensTotal: Int,
        now: Date = Date()
    ) async -> WeeklyReport {
        let periodStart = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let entries = (try? await index.journalEntries(since: periodStart, until: now, limit: 5000)) ?? []

        var filed = 0
        var cold = 0
        var quarantined = 0
        var undone = 0
        var bytes: Int64 = 0
        var categories: [String: Int] = [:]

        for entry in entries {
            if entry.state == "undone" {
                undone += 1
                continue
            }
            switch entry.action {
            case "move":
                filed += 1
            case "cold":
                cold += 1
            case "quarantine":
                quarantined += 1
            default:
                continue
            }
            if entry.action != "quarantine" {
                categories[entry.categoryPath, default: 0] += 1
            }
            if entry.action == "move" || entry.action == "cold", let size = fileSize(atPath: entry.destinationPath) {
                bytes += size
            }
        }

        let topCategories = categories
            .map { CategoryCount(path: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.path < $1.path }
            .prefix(5)

        let promotedThisWeek = knowledge.rules().filter { $0.isPromoted && $0.lastSeen >= periodStart }.count
        let stats = knowledge.stats()
        let pending = QuarantineListing.itemURLs(rootURL: rootURL).count

        return WeeklyReport(
            generatedAt: now,
            periodStart: periodStart,
            periodEnd: now,
            filedCount: filed,
            coldCount: cold,
            quarantinedCount: quarantined,
            undoneCount: undone,
            movedBytes: bytes,
            topCategories: Array(topCategories),
            promotedRulesThisWeek: promotedThisWeek,
            knowledgeAppliedTotal: stats.appliedTotal,
            aiCallsTotal: aiCallsTotal,
            aiTokensTotal: aiTokensTotal,
            pendingReview: pending
        )
    }

    private static func fileSize(atPath path: String) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }
}
