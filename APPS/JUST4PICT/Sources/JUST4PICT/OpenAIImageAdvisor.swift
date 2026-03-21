import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum OpenAIAdvisorError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case cannotPrepareImage(URL)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No se encontró OPENAI_API_KEY en variables de entorno o .env.secrets"
        case .invalidResponse:
            return "Respuesta inválida desde OpenAI"
        case .cannotPrepareImage(let url):
            return "No se pudo preparar la imagen para análisis IA: \(url.lastPathComponent)"
        case .apiError(let message):
            return "OpenAI error: \(message)"
        }
    }
}

struct AIImageRecommendation {
    let preset: EnhancementPreset?
    let quality: Double?
    let reason: String
    let hdPrompt: String
    let tuning: AIEnhancementTuning?
    let recipe: EnhancementRecipe?
    let rawContent: String
}

final class OpenAIImageAdvisor {
    private let model: String

    init(model: String = "gpt-4o-mini") {
        self.model = model
    }

    func recommendHD(
        inputURL: URL,
        fileName: String,
        width: Int,
        height: Int,
        currentPreset: EnhancementPreset,
        currentFormat: OutputFormat
    ) async throws -> AIImageRecommendation {
        guard let apiKey = Self.resolveAPIKey(), !apiKey.isEmpty else {
            throw OpenAIAdvisorError.missingAPIKey
        }

        let prompt = Self.defaultHDPrompt(
            fileName: fileName,
            width: width,
            height: height,
            currentPreset: currentPreset,
            currentFormat: currentFormat
        )

        let imageDataURL = try Self.makeAnalysisImageDataURL(inputURL: inputURL)

        let system = """
        Eres un experto senior en mejora fotografica profesional para una app macOS.
        Analiza la IMAGEN REAL, no solo el nombre o dimensiones.
        Tu objetivo es decidir la mejor receta local para mejorar la foto sin cambiar identidad, composicion ni realismo.
        Prioriza:
        - textura natural
        - color realista
        - detalle fino sin halos
        - reduccion de ruido sin plastificar
        - exportacion de alta calidad
        Devuelve SOLO JSON valido segun el schema.
        """

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatCompletionsVisionRequest(
            model: model,
            temperature: 0.0,
            response_format: .recipeSchema,
            messages: [
                .init(role: "system", content: [.text(system)]),
                .init(role: "user", content: [
                    .text(prompt),
                    .imageURL(imageDataURL, detail: "high")
                ])
            ]
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            if let apiErr = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw OpenAIAdvisorError.apiError(apiErr.error.message)
            }
            throw OpenAIAdvisorError.apiError("HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionsVisionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw OpenAIAdvisorError.invalidResponse
        }

        let jsonChunk = Self.extractJSONObject(from: content) ?? content
        guard let payloadData = jsonChunk.data(using: .utf8),
              let payload = try? JSONDecoder().decode(AIRecommendationPayload.self, from: payloadData)
        else {
            throw OpenAIAdvisorError.invalidResponse
        }

        let recipe = payload.recipe.clamped()
        let mappedPreset = Self.mapPreset(recipe.preset)
        let mappedQuality = min(max(recipe.exportQuality, 0.92), 1.0)

        return AIImageRecommendation(
            preset: mappedPreset,
            quality: mappedQuality,
            reason: recipe.objective,
            hdPrompt: payload.hdPrompt,
            tuning: recipe.tuning,
            recipe: recipe,
            rawContent: content
        )
    }

    static func defaultHDPrompt(
        fileName: String,
        width: Int,
        height: Int,
        currentPreset: EnhancementPreset,
        currentFormat: OutputFormat
    ) -> String {
        """
        Analiza esta imagen real y decide la mejor receta de mejora local para un resultado excepcional y natural.
        Archivo: \(fileName)
        Resolución actual: \(width)x\(height)
        Preset actual: \(currentPreset.rawValue)
        Formato actual: \(currentFormat.rawValue)

        Objetivo técnico obligatorio:
        1) Mejorar nitidez de detalle fino sin halos ni edge ringing.
        2) Reducir ruido cromático y de luminancia preservando textura real.
        3) Ajustar microcontraste y rango dinámico para lectura clara de detalle.
        4) Corregir color de forma neutra y natural, evitando sobresaturación.
        5) Maximizar calidad de export (calidad alta), minimizando artefactos de compresión.
        6) Si la resolución es baja, decidir si conviene upscale realista.
        7) Si el rostro está realmente degradado, indicar restauración facial opcional; si no, dejarla desactivada.
        """
    }

    static func resolveAPIKey() -> String? {
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            return envKey
        }

        guard let envFile = findEnvSecretsFile() else {
            return nil
        }

        guard let text = try? String(contentsOf: envFile, encoding: .utf8) else {
            return nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\"") && value.hasSuffix("\"") {
                value.removeFirst()
                value.removeLast()
            }
            if key == "OPENAI_API_KEY", !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private static func findEnvSecretsFile() -> URL? {
        var candidates: [URL] = []
        let fm = FileManager.default

        var current = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            candidates.append(current.appendingPathComponent(".env.secrets"))
            current.deleteLastPathComponent()
        }

        var bundleCursor = Bundle.main.bundleURL.standardizedFileURL
        for _ in 0..<10 {
            candidates.append(bundleCursor.appendingPathComponent(".env.secrets"))
            bundleCursor.deleteLastPathComponent()
        }

        for fileURL in candidates where fm.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }

    private static func makeAnalysisImageDataURL(inputURL: URL) throws -> String {
        let maxDimension = 1536
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil) else {
            throw OpenAIAdvisorError.cannotPrepareImage(inputURL)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw OpenAIAdvisorError.cannotPrepareImage(inputURL)
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else {
            throw OpenAIAdvisorError.cannotPrepareImage(inputURL)
        }

        return "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
    }

    private static func mapPreset(_ value: String) -> EnhancementPreset? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "auto": return .auto
        case "retrato", "portrait": return .portrait
        case "paisaje", "landscape": return .landscape
        case "documento", "document": return .document
        case "ecommerce", "e-commerce": return .ecommerce
        default: return nil
        }
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}")
        else {
            return nil
        }
        return String(text[start...end])
    }
}

private struct ChatCompletionsVisionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: [Content]
    }

    struct Content: Encodable {
        struct ImageURL: Encodable {
            let url: String
            let detail: String
        }

        let type: String
        let text: String?
        let image_url: ImageURL?

        static func text(_ text: String) -> Content {
            Content(type: "text", text: text, image_url: nil)
        }

        static func imageURL(_ url: String, detail: String) -> Content {
            Content(type: "image_url", text: nil, image_url: .init(url: url, detail: detail))
        }
    }

    struct ResponseFormat: Encodable {
        struct JSONSchemaEnvelope: Encodable {
            struct JSONSchemaDefinition: Encodable {
                let name: String
                let strict: Bool
                let schema: JSONValue
            }

            let type: String
            let json_schema: JSONSchemaDefinition
        }

        let type: String
        let json_schema: JSONSchemaEnvelope.JSONSchemaDefinition?

        static var recipeSchema: ResponseFormat {
            ResponseFormat(
                type: "json_schema",
                json_schema: .init(
                    name: "enhancement_recipe",
                    strict: true,
                    schema: recipeRootSchema()
                )
            )
        }

        private static func recipeRootSchema() -> JSONValue {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "hdPrompt": .object(["type": .string("string")]),
                    "recipe": recipeObjectSchema()
                ]),
                "required": .array([.string("hdPrompt"), .string("recipe")])
            ])
        }

        private static func recipeObjectSchema() -> JSONValue {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "scene": .object(["type": .string("string")]),
                    "objective": .object(["type": .string("string")]),
                    "preset": .object(["type": .string("string")]),
                    "exportFormat": .object(["type": .string("string")]),
                    "exportQuality": .object(["type": .string("number")]),
                    "tuning": tuningSchema(),
                    "upscale": upscaleSchema(),
                    "faceRestore": faceRestoreSchema()
                ]),
                "required": .array([.string("scene"), .string("objective"), .string("preset"), .string("exportFormat"), .string("exportQuality"), .string("tuning"), .string("upscale"), .string("faceRestore")])
            ])
        }

        private static func tuningSchema() -> JSONValue {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "shadowAmount": .object(["type": .string("number")]),
                    "highlightAmount": .object(["type": .string("number")]),
                    "vibrance": .object(["type": .string("number")]),
                    "sharpen": .object(["type": .string("number")]),
                    "sharpenRadius": .object(["type": .string("number")]),
                    "contrast": .object(["type": .string("number")]),
                    "saturation": .object(["type": .string("number")]),
                    "exposureEV": .object(["type": .string("number")])
                ]),
                "required": .array([.string("shadowAmount"), .string("highlightAmount"), .string("vibrance"), .string("sharpen"), .string("sharpenRadius"), .string("contrast"), .string("saturation"), .string("exposureEV")])
            ])
        }

        private static func upscaleSchema() -> JSONValue {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "enabled": .object(["type": .string("boolean")]),
                    "targetLongSide": .object([
                        "anyOf": .array([
                            .object(["type": .string("integer")]),
                            .object(["type": .string("null")])
                        ])
                    ])
                ]),
                "required": .array([.string("enabled"), .string("targetLongSide")])
            ])
        }

        private static func faceRestoreSchema() -> JSONValue {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "enabled": .object(["type": .string("boolean")]),
                    "strength": .object([
                        "anyOf": .array([
                            .object(["type": .string("number")]),
                            .object(["type": .string("null")])
                        ])
                    ])
                ]),
                "required": .array([.string("enabled"), .string("strength")])
            ])
        }
    }

    let model: String
    let temperature: Double
    let response_format: ResponseFormat
    let messages: [Message]
}

private enum JSONValue: Encodable {
    case string(String)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .object(let value):
            var container = encoder.container(keyedBy: AnyCodingKey.self)
            for (key, item) in value {
                try container.encode(item, forKey: AnyCodingKey(key))
            }
        case .array(let value):
            var container = encoder.unkeyedContainer()
            for item in value {
                try container.encode(item)
            }
        }
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private struct ChatCompletionsVisionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct AIRecommendationPayload: Decodable {
    let hdPrompt: String
    let recipe: EnhancementRecipe
}

private struct APIErrorResponse: Decodable {
    struct APIErrorBody: Decodable {
        let message: String
    }

    let error: APIErrorBody
}
