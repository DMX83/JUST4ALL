import Foundation

import LifeOSAPI

// Piezas de la agenda, las acciones y la búsqueda que son de la interfaz (no del
// contrato): filtros, formularios en edición y modos de la pantalla.

/// Filtro por origen: todo, lo que nació en LifeOS o lo que vino de Google.
public enum AgendaOriginFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case lifeos
    case google

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "Todo"
        case .lifeos: return "LifeOS"
        case .google: return "Google"
        }
    }
}

/// Qué acciones se están mirando.
public enum TaskFilter: String, CaseIterable, Identifiable, Sendable {
    case open
    case today
    case all
    case done

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .open: return "Abiertas"
        case .today: return "Hoy y atrasadas"
        case .all: return "Todas"
        case .done: return "Terminadas"
        }
    }
}

/// Las dos caras de la pantalla de buscar: buscar y releer la cronología.
public enum InsightMode: String, CaseIterable, Identifiable, Sendable {
    case timeline
    case search

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .timeline: return "Cronología"
        case .search: return "Buscar"
        }
    }
}

/// Formulario de una cita o de un bloque de foco. Si `id` no es `nil`, se está
/// editando; si es `nil`, se está creando.
public struct EventDraft: Identifiable, Sendable {
    public var id: String?
    public var title: String
    public var startsAt: Date
    public var endsAt: Date
    public var allDay: Bool
    public var location: String
    public var notes: String
    public var version: Int?

    public init(
        id: String? = nil,
        title: String = "",
        startsAt: Date = Date(),
        endsAt: Date = Date().addingTimeInterval(3600),
        allDay: Bool = false,
        location: String = "",
        notes: String = "",
        version: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.allDay = allDay
        self.location = location
        self.notes = notes
        self.version = version
    }

    public var isEditing: Bool { id != nil }
}

/// Formulario de una acción nueva.
public struct TaskDraft: Identifiable, Sendable {
    public var id: String { "task-draft" }
    public var title: String
    public var priority: Int
    public var dueDate: Date?
    public var context: String

    public init(title: String = "", priority: Int = 3, dueDate: Date? = nil, context: String = "") {
        self.title = title
        self.priority = priority
        self.dueDate = dueDate
        self.context = context
    }
}
