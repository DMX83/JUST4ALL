import Foundation

/// JSON arbitrario.
///
/// Las operaciones de una propuesta traen un campo `after` cuya forma depende
/// del tipo de entidad (`title` y `due_date` para una tarea, `metric_name` y
/// `value` para una métrica…), así que no se puede tipar de antemano. Se
/// conserva tal cual y se lee por clave cuando la interfaz lo necesita.
public enum JSONValue: Decodable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Valor JSON no soportado"
            )
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Texto legible para mostrar en pantalla (nunca para volver a interpretar).
    public var displayText: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value):
            return value ? "sí" : "no"
        case .null:
            return ""
        case .array(let items):
            return items.map(\.displayText).joined(separator: ", ")
        case .object(let fields):
            return fields
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.displayText)" }
                .joined(separator: " · ")
        }
    }
}
