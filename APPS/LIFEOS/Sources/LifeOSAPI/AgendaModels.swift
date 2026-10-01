import Foundation

// Agenda: lo que ocupa el tiempo.
//
// El servidor separa **tres carriles** y no los mezcla, porque son tres cosas
// distintas: un evento es una cita (`AgendaEvent`), un bloque de foco es tiempo
// reservado (una acción con `scheduled_start`) y un vencimiento es una acción con
// fecha pero sin hora (casi todas las de Google Tasks). Ninguno se inventa la
// hora que no tiene.
//
// Además devuelve los pares acción+evento que parecen la misma cosa para
// preguntarlo **una vez**: la decisión se guarda en el servidor (`same_as` /
// `distinct_from`) y no vuelve a preguntarse.

/// El destino de un bloque de foco (la acción, el objetivo o el proyecto al que
/// se dedica ese rato).
public struct FocusTarget: Decodable, Hashable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
}

/// De dónde vino una copia de Google, si vino de allí.
public struct LifeOSOrigin: Decodable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let kind: String
    public let direction: String
}

public struct AgendaEvent: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let startsAt: Date
    public let endsAt: Date
    public let allDay: Bool
    public let timezone: String
    public let location: String
    public let notes: String
    public let status: String
    public let sensitivity: String
    public let recurrenceRule: String
    public let reminders: [Int]
    public let focusTargetId: String?
    public let version: Int
    /// Si el evento es parte de una serie, cuál es su serie.
    public let recurrenceId: String?
    /// Si el evento se repite (viene de una regla).
    public let series: Bool
    public let focusTarget: FocusTarget?
    public let source: String
    public let externalId: String?
    public let externalState: String
    public let origin: LifeOSOrigin?

    /// Un bloque de foco es un evento con destino: tiempo reservado para algo.
    public var isFocusBlock: Bool { focusTarget != nil }

    public var isCancelled: Bool { status == "cancelled" }

    public var isFromGoogle: Bool { source == "google" || externalId != nil }

    /// Los eventos vienen ya expandidos por el servidor (las repeticiones se
    /// convierten en instancias), así que `id` puede repetirse: se usa junto a la
    /// hora de inicio para identificar la fila en la interfaz.
    public var rowID: String { "\(id)@\(startsAt.timeIntervalSince1970)" }
}

/// La respuesta de `GET /agenda`: los tres carriles y los pares por resolver.
public struct AgendaDay: Decodable, Sendable {
    public let events: [AgendaEvent]
    public let tasks: [LifeOSTask]
    public let dueTasks: [LifeOSTask]
    public let duplicates: [DuplicatePair]

    public var focusBlocks: [AgendaEvent] { events.filter(\.isFocusBlock) }
    public var appointments: [AgendaEvent] { events.filter { !$0.isFocusBlock && !$0.isCancelled } }
}

/// Dos elementos que podrían ser el mismo: una acción y un evento.
///
/// `status` es `suggested` (pregunta una vez), `linked` (son la misma cosa) o
/// `dismissed` (son cosas distintas).
public struct DuplicatePair: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let taskId: String
    public let eventId: String
    public let title: String
    public let eventTitle: String
    public let taskTitle: String
    public let at: Date?
    public let status: String
    public let reason: String

    public var isPending: Bool { status == "suggested" }
}

/// Decisión sobre un par: son la misma cosa, son distintas, o se olvida.
public enum DuplicateChoice: String, Encodable, Sendable, CaseIterable {
    case same
    case different
    case forget

    public var label: String {
        switch self {
        case .same: return "Son la misma"
        case .different: return "Son distintas"
        case .forget: return "No preguntar más"
        }
    }
}

// MARK: - Peticiones

/// Alta de una cita o de un bloque de foco.
public struct AgendaEventRequest: Encodable, Sendable {
    public let title: String
    public let startsAt: Date
    public let endsAt: Date
    public let allDay: Bool
    public let timezone: String
    public let location: String
    public let notes: String
    public let status: String
    public let sensitivity: String
    public let focusTargetId: String?

    public init(
        title: String,
        startsAt: Date,
        endsAt: Date,
        allDay: Bool = false,
        timezone: String = TimeZone.current.identifier,
        location: String = "",
        notes: String = "",
        status: String = "scheduled",
        sensitivity: String = "standard",
        focusTargetId: String? = nil
    ) {
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.allDay = allDay
        self.timezone = timezone
        self.location = location
        self.notes = notes
        self.status = status
        self.sensitivity = sensitivity
        self.focusTargetId = focusTargetId
    }
}

/// Edición de una cita. Se manda el formulario entero (lo que ves es lo que hay)
/// y `expectedVersion` para no pisar cambios de otro sitio.
public struct AgendaEventUpdate: Encodable, Sendable {
    public let title: String
    public let startsAt: Date
    public let endsAt: Date
    public let allDay: Bool
    public let location: String
    public let notes: String
    public let status: String
    public let expectedVersion: Int?

    public init(
        title: String,
        startsAt: Date,
        endsAt: Date,
        allDay: Bool,
        location: String,
        notes: String,
        status: String,
        expectedVersion: Int?
    ) {
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.allDay = allDay
        self.location = location
        self.notes = notes
        self.status = status
        self.expectedVersion = expectedVersion
    }
}

public struct DuplicateResolveRequest: Encodable, Sendable {
    public let taskId: String
    public let eventId: String
    public let choice: DuplicateChoice

    public init(taskId: String, eventId: String, choice: DuplicateChoice) {
        self.taskId = taskId
        self.eventId = eventId
        self.choice = choice
    }
}
