import Foundation

/// Las convenciones de JSON de la API, en un solo sitio.
///
/// El servidor (FastAPI) escribe `snake_case` y fechas ISO-8601 con o sin
/// fracción de segundo, y espera lo mismo de vuelta. Tenerlo aquí evita que cada
/// parte lo configure a su manera: si un sitio codifica fechas como número y otro
/// las lee como texto, el fallo aparece lejos de la causa.
public enum LifeOSJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: raw) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Fecha no reconocida: \(raw)"
            )
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        // Los cuerpos que llevan fechas (eventos, acciones) tienen que viajar en
        // ISO-8601, no como número: el esquema del servidor espera una fecha con
        // zona, y `deferredToDate` mandaría un `Double` de segundos desde 2001.
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
