import Foundation
import J4ICore

public struct DeepSeekConfiguration: Sendable {
    public var apiKey: String
    public var baseURL: URL
    public var model: String
    public var timeout: TimeInterval

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.deepseek.com")!,
        model: String = "deepseek-flash",
        timeout: TimeInterval = 40
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.timeout = timeout
    }
}

/// Resolución de la API key: entorno `DEEPSEEK_API_KEY` y, si no, `.env.secrets` hacia arriba.
public enum DeepSeekKeyResolver {
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startingAt url: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) -> String? {
        if let key = environment["DEEPSEEK_API_KEY"], !key.isEmpty {
            return key
        }
        if let file = findEnvSecretsFile(startingAt: url), let key = readKey(from: file) {
            return key
        }
        if let file = findEnvSecretsFile(startingAt: Bundle.main.bundleURL), let key = readKey(from: file) {
            return key
        }
        return nil
    }

    static func findEnvSecretsFile(startingAt url: URL, maxLevels: Int = 10) -> URL? {
        var current = url.standardizedFileURL
        for _ in 0..<maxLevels {
            let candidate = current.appendingPathComponent(".env.secrets", isDirectory: false)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    static func readKey(from fileURL: URL) -> String? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        for rawLine in content.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), line.contains("=") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "DEEPSEEK_API_KEY" else { continue }
            return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }
}

public enum DeepSeekError: Error, LocalizedError {
    case missingAPIKey
    case httpError(Int, String)
    case emptyResponse
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Falta la clave de DeepSeek (DEEPSEEK_API_KEY o .env.secrets)."
        case .httpError(let code, let message):
            return "DeepSeek respondió con error HTTP \(code): \(message)"
        case .emptyResponse:
            return "DeepSeek devolvió una respuesta vacía."
        case .invalidResponse(let detail):
            return "Respuesta de DeepSeek no válida: \(detail)"
        }
    }
}

/// Cliente mínimo de la API de DeepSeek (formato OpenAI, JSON mode).
public struct DeepSeekClient: Sendable {
    public let configuration: DeepSeekConfiguration

    public init(configuration: DeepSeekConfiguration) {
        self.configuration = configuration
    }

    /// Chat completion en JSON mode. Devuelve el contenido (string JSON) del primer choice.
    /// Reintenta una vez si la respuesta llega vacía (comportamiento documentado de la API).
    public func completeJSON(
        system: String,
        user: String,
        maxTokens: Int = 800,
        temperature: Double = 0.1
    ) async throws -> String {
        do {
            return try await performRequest(system: system, user: user, maxTokens: maxTokens, temperature: temperature)
        } catch DeepSeekError.emptyResponse {
            J4Log.warn(.ai, "La IA devolvió una respuesta vacía; reintentando una vez…")
            return try await performRequest(system: system, user: user, maxTokens: maxTokens, temperature: temperature)
        }
    }

    private func performRequest(system: String, user: String, maxTokens: Int, temperature: Double) async throws -> String {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        let body = RequestBody(
            model: configuration.model,
            messages: [
                RequestBody.Message(role: "system", content: system),
                RequestBody.Message(role: "user", content: user)
            ],
            temperature: temperature,
            max_tokens: maxTokens,
            response_format: RequestBody.ResponseFormat(type: "json_object"),
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse("respuesta no HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data.prefix(300), encoding: .utf8) ?? ""
            J4Log.error(.ai, "DeepSeek respondió HTTP \(http.statusCode).")
            throw DeepSeekError.httpError(http.statusCode, message)
        }

        let decoded: ResponseBody
        do {
            decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw DeepSeekError.invalidResponse("no se pudo decodificar la respuesta")
        }
        let content = decoded.choices.first?.message.content ?? ""
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekError.emptyResponse
        }
        // Contabilidad real de tokens (el reintento por respuesta vacía suma las dos llamadas).
        if let usage = decoded.usage {
            let total = usage.total_tokens ?? ((usage.prompt_tokens ?? 0) + (usage.completion_tokens ?? 0))
            AIControlCenter.shared.registerTokens(total)
        }
        return content
    }

    // MARK: - DTOs

    struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct ResponseFormat: Encodable {
            let type: String
        }
        let model: String
        let messages: [Message]
        let temperature: Double
        let max_tokens: Int
        let response_format: ResponseFormat
        let stream: Bool
    }

    struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        struct Usage: Decodable {
            let prompt_tokens: Int?
            let completion_tokens: Int?
            let total_tokens: Int?
        }
        let choices: [Choice]
        let usage: Usage?
    }
}
