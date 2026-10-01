import Foundation

/// Cuerpo `multipart/form-data` construido a mano.
///
/// Solo hace falta para subir la grabación de voz: un fichero y dos campos. Traer
/// una dependencia para esto sería peor que las veinte líneas que cuesta, y así
/// el formato (que es lo que el servidor valida) queda a la vista y con test.
public enum MultipartFormData {
    public static func makeBoundary() -> String {
        "lifeos-\(UUID().uuidString)"
    }

    /// Construye el cuerpo. Las líneas van con `\r\n`, que es lo que exige el
    /// formato (un `\n` a secas hace que algunos servidores no encuentren el
    /// límite).
    public static func build(
        boundary: String,
        fields: [(name: String, value: String)],
        file: (name: String, filename: String, mimeType: String, data: Data)
    ) -> Data {
        var body = Data()

        func append(_ text: String) {
            body.append(Data(text.utf8))
        }

        for field in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
            append("\(field.value)\r\n")
        }

        append("--\(boundary)\r\n")
        append(
            "Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\r\n"
        )
        append("Content-Type: \(file.mimeType)\r\n\r\n")
        body.append(file.data)
        append("\r\n")
        append("--\(boundary)--\r\n")

        return body
    }
}
