import Foundation

// Buscar y cronología.
//
// Las dos leen lo que ya existe en otras secciones, así que **no inventan nada**:
// la cronología pone en el mismo eje temporal filas que ya están en el diario, la
// agenda, la ejecución, las decisiones, las métricas y las capturas.

/// Un hecho con fecha dentro de la vida del espacio.
public struct TimelineItem: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let occurredAt: Date
    public let detail: String
    /// La entidad de la que sale, para poder abrirla.
    public let refId: String?
    public let sensitive: Bool
}

public struct Timeline: Decodable, Sendable {
    public let start: Date
    public let end: Date
    public let days: Int
    public let items: [TimelineItem]
    /// Cuántos elementos de cada tipo: `{"journal": 3, "task": 12, …}`.
    public let counts: [String: Int]

    /// Los elementos agrupados por día (del más reciente al más antiguo).
    public var byDay: [(day: Date, items: [TimelineItem])] {
        let calendar = Calendar.current
        var order: [Date] = []
        var groups: [Date: [TimelineItem]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.occurredAt)
            if groups[day] == nil {
                order.append(day)
                groups[day] = []
            }
            groups[day]?.append(item)
        }
        return order.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }
}

/// Un resultado de búsqueda. Es un resumen: se abre en LifeOS para editarlo.
public struct SearchResult: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let excerpt: String
    public let sensitivity: String

    public var isSensitive: Bool { sensitivity == "sensitive" }
}

public struct SearchResults: Decodable, Sendable {
    public let query: String
    public let results: [SearchResult]

    public var grouped: [(kind: String, items: [SearchResult])] {
        var order: [String] = []
        var groups: [String: [SearchResult]] = [:]
        for result in results {
            if groups[result.kind] == nil {
                order.append(result.kind)
                groups[result.kind] = []
            }
            groups[result.kind]?.append(result)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}

/// Los tipos que la cronología sabe leer (`kinds` de `GET /timeline`).
public enum TimelineKind: String, CaseIterable, Sendable {
    case journal
    case event
    case task
    case decision
    case metric
    case capture

    public var label: String {
        switch self {
        case .journal: return "Diario"
        case .event: return "Eventos"
        case .task: return "Acciones"
        case .decision: return "Decisiones"
        case .metric: return "Métricas"
        case .capture: return "Capturas"
        }
    }

    public var symbol: String { LifeOSKind.symbol(for: rawValue) }
}
