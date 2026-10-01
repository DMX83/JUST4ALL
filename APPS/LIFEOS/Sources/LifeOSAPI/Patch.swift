import Foundation

/// Un campo de un `PATCH` que puede pedir tres cosas distintas.
///
/// En el servidor, **omitir un campo significa «no lo toques»**
/// (`model_dump(exclude_unset=True)`), así que hay tres estados y no dos:
///
/// - `.unchanged`: no se envía el campo.
/// - `.clear`: se envía `null` (para borrar un vencimiento, por ejemplo).
/// - `.set(valor)`: se envía el valor.
///
/// Mezclar los dos últimos sería un fallo de datos: mandar `null` «porque no lo
/// puse» borraría el vencimiento que ya tenía la acción.
public enum Patch<Value: Encodable & Sendable>: Sendable {
    case unchanged
    case clear
    case set(Value)

    /// ¿Hay que tocar el campo?
    public var isChanged: Bool {
        if case .unchanged = self { return false }
        return true
    }
}

extension Patch where Value: Equatable {
    /// Atajo para formularios: si el valor nuevo es igual al de partida, no se
    /// toca (y el PATCH envía menos cosas).
    public static func changing(from old: Value?, to new: Value?) -> Patch<Value> {
        if old == new { return .unchanged }
        guard let new else { return .clear }
        return .set(new)
    }
}

extension Patch {
    /// Escribe el campo: nada si no cambia, `null` si se vacía, el valor si se
    /// pone. El `container` va `inout` porque `KeyedEncodingContainer` es un
    /// tipo valor.
    public func write<Key: CodingKey>(
        into container: inout KeyedEncodingContainer<Key>,
        forKey key: Key
    ) throws {
        switch self {
        case .unchanged:
            break
        case .clear:
            try container.encodeNil(forKey: key)
        case .set(let value):
            try container.encode(value, forKey: key)
        }
    }
}
