import Foundation

// Modelos del subconjunto de la API de LifeOS que usa la app.
//
// La decodificación usa `convertFromSnakeCase`, así que los nombres de propiedad
// tienen que coincidir con la conversión del nombre en la API (`display_name` →
// `displayName`, `avatar_url` → `avatarUrl`). Los campos de fecha sin hora
// (`due_date`, `date`) se dejan como texto a propósito: son días, no instantes.

// MARK: - Sesión y usuario

public struct LifeOSUser: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let username: String
    public let displayName: String
    public let avatarUrl: String?
    public let mfaMode: String
    /// Si esta cuenta puede entrar con Google. Opcional a propósito: los
    /// servidores anteriores a este campo no lo mandan, y eso no puede romper el
    /// inicio de sesión. Lleva valor por defecto para no obligar a escribirlo en
    /// cada sitio que construye un usuario (pruebas, datos de ejemplo).
    public var googleLinked: Bool? = nil

    public var hasMFA: Bool { mfaMode != "disabled" }

    /// Si ya responde a un `sub` de Google (no tiene sentido ofrecer vincular).
    public var hasGoogle: Bool { googleLinked == true }
}

/// Lo que devuelve el servidor al empezar a **vincular** Google con la cuenta
/// que ya está dentro: la URL de Google y el `state` que la ata a esta sesión.
public struct GoogleLinkStart: Decodable, Sendable {
    public let authorizeUrl: String
    public let state: String
}

public struct NativeSession: Decodable, Sendable {
    public let token: String
    public let expiresIn: Int
    public let user: LifeOSUser
}

// MARK: - Cierre del día y avisos

public struct DayCloseItem: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let at: Date?
}

/// Lo que hace falta para cerrar la jornada. El servidor ya lo calcula en la
/// zona horaria del espacio: la app no reinterpreta nada.
public struct DayClose: Decodable, Sendable {
    public let date: String
    public let completed: [DayCloseItem]
    public let events: [DayCloseItem]
    public let openTasks: Int
    public let pendingCaptures: Int
    public let journalEntryId: String?
    public let journalEntries: Int
    public let suggestion: String
}

public struct ReminderItem: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let at: Date
    public let remindAt: Date
    public let minutes: Int
    public let detail: String
}

public struct UpcomingReminders: Decodable, Sendable {
    public let now: Date
    public let windowHours: Int
    public let items: [ReminderItem]
}

// MARK: - Capturas y propuestas

public struct CaptureSummary: Decodable, Hashable, Sendable {
    public let id: String
    public let status: String
    public let proposalId: String?
    public let clarifyingQuestion: String
    public let manualKind: String
}

public struct CaptureDetail: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let status: String
    public let proposalId: String?
    public let clarifyingQuestion: String
    public let manualKind: String
    public let content: String
    public let channel: String
    public let sensitivity: String
    public let originalFilename: String
    public let originalPreserved: Bool
    public let createdAt: Date

    public var isPending: Bool {
        status != "applied" && status != "rejected"
    }

    public var isSensitive: Bool { sensitivity == "sensitive" }
}

public struct ProposalOperation: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let operation: String
    public let entityKind: String
    public let after: [String: JSONValue]?
    public let targetId: String?
    public let sourceId: String?
    public let relationType: String?
    public let confidence: Double
    public let dependencies: [String]
    public let warnings: [String]

    /// Título propuesto, con el mismo criterio que el servidor.
    public var title: String {
        if let value = after?["title"]?.stringValue, !value.isEmpty {
            return value
        }
        if let metric = after?["metric_name"]?.stringValue, !metric.isEmpty {
            return metric
        }
        return "(sin título)"
    }

    /// Detalles útiles que acompañan a la operación (valor medido, nota, fecha).
    public var details: [String] {
        var parts: [String] = []
        if let value = after?["value"] { parts.append("valor \(value.displayText)") }
        if let due = after?["due_date"], case .string(let text) = due, !text.isEmpty {
            parts.append("para \(text)")
        }
        if let note = after?["note"]?.stringValue, !note.isEmpty { parts.append(note) }
        return parts
    }

    public var confidenceLabel: String {
        "\(Int((confidence * 100).rounded())) %"
    }
}

public struct Proposal: Decodable, Sendable {
    public let id: String
    public let captureId: String
    public let status: String
    public let operations: [ProposalOperation]
    public let explanation: String

    public var isOpen: Bool { status == "pending" || status == "partially_applied" }
}

// MARK: - Etiquetas de dominio

/// Vocabulario del clasificador de LifeOS traducido a la interfaz.
public enum LifeOSKind {
    public static func label(for kind: String) -> String {
        switch kind {
        case "task": return "Tarea"
        case "idea": return "Idea"
        case "event": return "Evento"
        case "note": return "Nota"
        case "objective": return "Objetivo"
        case "project": return "Proyecto"
        case "area": return "Área"
        case "decision": return "Decisión"
        case "knowledge": return "Conocimiento"
        case "metric_observation": return "Métrica"
        case "journal": return "Diario"
        case "capture": return "Captura"
        case "metric": return "Métrica"
        case "block": return "Bloque de foco"
        default: return kind
        }
    }

    public static func symbol(for kind: String) -> String {
        switch kind {
        case "task": return "checkmark.circle"
        case "idea": return "lightbulb"
        case "event": return "calendar"
        case "note": return "note.text"
        case "objective": return "target"
        case "project": return "square.stack.3d.up"
        case "area": return "square.grid.2x2"
        case "decision": return "arrow.triangle.branch"
        case "knowledge": return "book"
        case "metric_observation": return "chart.line.uptrend.xyaxis"
        case "journal": return "book.closed"
        case "capture": return "tray.and.arrow.down"
        case "metric": return "chart.line.uptrend.xyaxis"
        case "block": return "hourglass"
        default: return "circle"
        }
    }
}

// MARK: - Cuerpos de petición

public struct NativeLoginRequest: Encodable, Sendable {
    public let username: String
    public let password: String
    public let mfaCode: String?

    public init(username: String, password: String, mfaCode: String? = nil) {
        self.username = username
        self.password = password
        self.mfaCode = mfaCode
    }
}

public struct LegacyLoginRequest: Encodable, Sendable {
    public let username: String
    public let password: String
    public let mfaCode: String?

    public init(username: String, password: String, mfaCode: String? = nil) {
        self.username = username
        self.password = password
        self.mfaCode = mfaCode
    }
}

public struct ExchangeRequest: Encodable, Sendable {
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

public struct CaptureRequest: Encodable, Sendable {
    public let content: String
    public let sensitivity: String
    public let channel: String

    public init(content: String, sensitivity: String = "standard", channel: String = "text") {
        self.content = content
        self.sensitivity = sensitivity
        self.channel = channel
    }
}

public struct CaptureClarificationRequest: Encodable, Sendable {
    public let clarificationAnswer: String?
    public let manualKind: String?

    public init(answer: String? = nil, manualKind: String? = nil) {
        self.clarificationAnswer = answer
        self.manualKind = manualKind
    }
}

public struct ApplyProposalRequest: Encodable, Sendable {
    public let operationIds: [String]

    public init(operationIds: [String]) {
        self.operationIds = operationIds
    }
}
