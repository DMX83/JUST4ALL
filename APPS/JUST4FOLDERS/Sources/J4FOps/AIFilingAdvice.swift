import Foundation
import J4ICore

/// v2.0 — Asesor opcional de clasificación (DeepSeek, JSON mode) para los «dudosos».
///
/// Privacidad: solo sale del equipo el **nombre** del fichero y la lista de categorías
/// permitidas (nunca el contenido). Sin clave (`DEEPSEEK_API_KEY` o `.env.secrets`) no se
/// construye: la ordenación se queda en las reglas locales.
public protocol FilingAdvising: Sendable {
    func propose(fileName: String, allowedCategories: [String]) async throws -> FilingProposal
}

public struct DeepSeekFilingAdvice: FilingAdvising, Sendable {

    public enum AdviceError: Error, LocalizedError {
        case invalidResponse(String)
        case http(Int, String)
        case missingContent

        public var errorDescription: String? {
            switch self {
            case .invalidResponse(let detail): return "Respuesta de DeepSeek no válida: \(detail)"
            case .http(let code, let message): return "DeepSeek respondió HTTP \(code): \(message)"
            case .missingContent: return "DeepSeek no devolvió contenido."
            }
        }
    }

    private let apiKey: String
    private let baseURL: URL
    private let model: String
    private let session: URLSession

    /// Clave disponible (entorno → `.env.secrets` hacia arriba, como JUST4DESK).
    public static func configuredKey(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let key = environment["DEEPSEEK_API_KEY"], !key.isEmpty {
            return key
        }
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            Bundle.main.bundleURL
        ]
        for start in candidates {
            if let file = findEnvSecrets(startingAt: start), let key = readKey(from: file) {
                return key
            }
        }
        return nil
    }

    public init?(
        apiKey: String? = DeepSeekFilingAdvice.configuredKey(),
        baseURL: URL = URL(string: "https://api.deepseek.com")!,
        model: String = ProcessInfo.processInfo.environment["DEEPSEEK_MODEL"] ?? "deepseek-chat",
        session: URLSession = .shared
    ) {
        guard let apiKey, !apiKey.isEmpty else { return nil }
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

    public func propose(fileName: String, allowedCategories: [String]) async throws -> FilingProposal {
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "max_tokens": 300,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": Self.userPrompt(fileName: fileName, allowedCategories: allowedCategories)]
            ]
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 25

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AdviceError.invalidResponse("sin respuesta HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AdviceError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let content = try Self.extractContent(from: data)
        return try Self.proposal(fromContent: content)
    }

    // MARK: - Prompt y parseo (testables sin red)

    static let systemPrompt = """
    Eres un archivador documental doméstico. Dado el NOMBRE de un fichero, elige la categoría \
    más probable de la lista permitida. Responde SIEMPRE en JSON válido, sin texto adicional, \
    con el esquema exacto: {"category_path": "una de las categorías permitidas", "confidence": 0.0, \
    "reason": "motivo breve"}. Reglas: category_path debe ser EXACTAMENTE una de las categorías \
    permitidas; confidence entre 0 y 1 (sé conservador: si dudas, baja confianza); el motivo en \
    español, máximo 12 palabras. Si nada encaja, usa "99_SinClasificar" con confidence baja.
    """

    static func userPrompt(fileName: String, allowedCategories: [String]) -> String {
        var lines = ["Categorías permitidas (elige una):"]
        lines.append(contentsOf: allowedCategories.map { "- \($0)" })
        lines.append("")
        lines.append("Fichero: \(fileName)")
        return lines.joined(separator: "\n")
    }

    /// Extrae `choices[0].message.content` del sobre de la API.
    static func extractContent(from data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw AdviceError.missingContent
        }
        return content
    }

    /// Convierte el JSON del modelo en una propuesta (confianza recortada a 0…1).
    static func proposal(fromContent content: String) throws -> FilingProposal {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let category = (object["category_path"] as? String) ?? (object["category"] as? String),
              !category.isEmpty else {
            throw AdviceError.invalidResponse(content.prefix(120).description)
        }
        let confidence = (object["confidence"] as? Double)
            ?? Double((object["confidence"] as? String) ?? "")
            ?? 0
        let reason = (object["reason"] as? String) ?? "propuesta IA"
        return FilingProposal(
            categoryPath: category,
            suggestedTitle: object["suggested_filename"] as? String ?? object["suggested_title"] as? String,
            confidence: min(max(confidence, 0), 1),
            reason: reason,
            issuer: nil,
            documentDate: nil,
            source: .ai
        )
    }

    // MARK: - Clave desde .env.secrets

    static func findEnvSecrets(startingAt url: URL, maxLevels: Int = 10) -> URL? {
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
