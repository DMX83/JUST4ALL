import Foundation

/// v2.0 — Expansión semántica de consultas con IA: convierte «los papeles del seguro del coche»
/// en términos concretos de búsqueda («poliza», «seguro», «coche»…) para el índice FTS5.
/// Sin clave (`DEEPSEEK_API_KEY` o `.env.secrets`) no se construye: la búsqueda queda normal.
public protocol QueryExpanding: Sendable {
    func expand(query: String) async throws -> [String]
}

public struct DeepSeekQueryExpander: QueryExpanding, Sendable {

    public enum ExpandError: Error, LocalizedError {
        case invalidResponse(String)
        case http(Int, String)
        case missingContent

        public var errorDescription: String? {
            switch self {
            case .invalidResponse(let detail): return "Respuesta de IA no válida: \(detail)"
            case .http(let code, let message): return "La IA respondió HTTP \(code): \(message)"
            case .missingContent: return "La IA no devolvió términos."
            }
        }
    }

    private let apiKey: String
    private let baseURL: URL
    private let model: String
    private let session: URLSession

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

    public func expand(query: String) async throws -> [String] {
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "max_tokens": 200,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": query]
            ]
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExpandError.invalidResponse("sin respuesta HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ExpandError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let content = try DeepSeekFilingAdvice.extractContent(from: data)
        return try Self.terms(fromContent: content)
    }

    // MARK: - Prompt y parseo (testables sin red)

    static let systemPrompt = """
    Convierte la consulta del usuario en 2-4 términos de búsqueda EN ESPAÑOL para localizar \
    ficheros por su NOMBRE: palabras clave concretas (sustantivos), sin artículos ni preposiciones. \
    Responde SIEMPRE en JSON válido, sin texto adicional: {"terms": ["termino1", "termino2"]}.
    """

    static func terms(fromContent content: String) throws -> [String] {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["terms"] as? [String] else {
            throw ExpandError.invalidResponse(content.prefix(120).description)
        }
        let cleaned = raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0.count >= 2 }
        guard !cleaned.isEmpty else { throw ExpandError.missingContent }
        var unique: [String] = []
        for term in cleaned where !unique.contains(term) {
            unique.append(term)
        }
        return Array(unique.prefix(4))
    }
}
