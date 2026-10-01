import Foundation

// Acciones («Ejecutar»): lo que hay que hacer, con o sin hora.
//
// El servidor ordena por estado, luego por vencimiento y luego por prioridad, y
// devuelve también de dónde viene cada copia (`external_state`): si vino de
// Google Tasks y allí ya no está (`missing`) o si cambió en los dos sitios
// (`conflict`). La app lo enseña, no lo reinterpreta ni lo resuelve sola.

public struct LifeOSTask: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    /// 1 (más alta) … 5 (más baja). Por defecto 3.
    public let priority: Int
    public let dueDate: Date?
    public let estimateMinutes: Int?
    public let context: String
    public let scheduledStart: Date?
    public let scheduledEnd: Date?
    public let recurrenceRule: String
    /// Minutos antes del inicio para recordar.
    public let reminders: [Int]
    public let energy: String
    public let status: String
    public let objectiveIds: [String]
    public let blocked: Bool
    public let completedAt: Date?
    public let version: Int
    public let source: String
    public let externalId: String?
    /// `""` si es de LifeOS; si vino de Google: `synced`, `missing` o `conflict`.
    public let externalState: String
    public let origin: LifeOSOrigin?

    public var isDone: Bool { status == "done" }
    public var isCancelled: Bool { status == "cancelled" }
    public var isOpen: Bool { !isDone && !isCancelled }
    public var isFromGoogle: Bool { source == "google" || externalId != nil }
    /// Una acción con hora reservada es un bloque de foco.
    public var isScheduled: Bool { scheduledStart != nil }

    /// `inbox`, `todo`, `doing`, `done`, `cancelled`.
    public var statusLabel: String {
        switch status {
        case "inbox": return "Sin clasificar"
        case "todo": return "Por hacer"
        case "doing": return "En curso"
        case "done": return "Hecha"
        case "cancelled": return "Descartada"
        default: return status
        }
    }

    /// Lo que hay que saber de la copia de Google, si la hay.
    public var externalWarning: String? {
        switch externalState {
        case "missing": return "Ya no está en Google"
        case "conflict": return "Cambió en Google y aquí"
        default: return nil
        }
    }
}

// MARK: - Peticiones

/// Alta de una acción.
public struct TaskCreateRequest: Encodable, Sendable {
    public let title: String
    public let priority: Int
    public let dueDate: Date?
    public let context: String
    public let status: String

    public init(
        title: String,
        priority: Int = 3,
        dueDate: Date? = nil,
        context: String = "",
        status: String = "todo"
    ) {
        self.title = title
        self.priority = priority
        self.dueDate = dueDate
        self.context = context
        self.status = status
    }
}

/// Cambios sobre una acción.
///
/// Los campos que se pueden **vaciar** (vencimiento, contexto, prioridad) usan
/// `Patch`: en el `PATCH` del servidor, omitir significa «no lo toques» y
/// mandar `null` significa «bórralo». Confundirlos borraría datos, así que la
/// diferencia se hace explícita en el tipo.
public struct TaskUpdateRequest: Encodable, Sendable {
    public var title: String?
    public var status: String?
    public var priority: Patch<Int>
    public var dueDate: Patch<Date>
    public var context: Patch<String>
    public var scheduledStart: Patch<Date>
    public var expectedVersion: Int?

    private enum CodingKeys: String, CodingKey {
        case title
        case status
        case priority
        case dueDate = "due_date"
        case context
        case scheduledStart = "scheduled_start"
        case expectedVersion = "expected_version"
    }

    public init(
        title: String? = nil,
        status: String? = nil,
        priority: Patch<Int> = .unchanged,
        dueDate: Patch<Date> = .unchanged,
        context: Patch<String> = .unchanged,
        scheduledStart: Patch<Date> = .unchanged,
        expectedVersion: Int? = nil
    ) {
        self.title = title
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.context = context
        self.scheduledStart = scheduledStart
        self.expectedVersion = expectedVersion
    }

    /// Atajo para lo que se hace todo el rato: cambiar de estado.
    public static func status(_ status: String, expectedVersion: Int?) -> TaskUpdateRequest {
        TaskUpdateRequest(status: status, expectedVersion: expectedVersion)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(expectedVersion, forKey: .expectedVersion)
        try priority.write(into: &container, forKey: .priority)
        try dueDate.write(into: &container, forKey: .dueDate)
        try context.write(into: &container, forKey: .context)
        try scheduledStart.write(into: &container, forKey: .scheduledStart)
    }
}
