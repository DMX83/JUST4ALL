import Foundation
import J4ICore
import J4IDocs

/// Asesor de clasificación documental sobre DeepSeek (JSON mode).
///
/// Privacidad: solo se envía una muestra de texto truncada (≤ 4000 chars) + metadatos mínimos
/// (nombre, extensión, tamaño, fechas/importes detectados localmente). El archivo nunca sale del equipo.
public struct DeepSeekFilingAdvisor: Sendable {
    public static let maxSampleCharacters = 4000

    private let client: DeepSeekClient

    public init(client: DeepSeekClient) {
        self.client = client
    }

    /// Crea el asesor si hay API key disponible (entorno o `.env.secrets`); si no, devuelve nil.
    public init?(apiKey: String? = DeepSeekKeyResolver.resolve()) {
        guard let apiKey, !apiKey.isEmpty else { return nil }
        self.client = DeepSeekClient(configuration: DeepSeekConfiguration(apiKey: apiKey))
    }

    public var isAvailable: Bool { true }

    public func suggest(
        profile: DocumentProfile,
        allowedCategories: [String] = DefaultTaxonomy.allRelativePaths
    ) async throws -> FilingProposal {
        let content = try await client.completeJSON(
            system: Self.systemPrompt,
            user: Self.userPrompt(profile: profile, allowedCategories: allowedCategories),
            maxTokens: 800,
            temperature: 0.1
        )
        return try Self.proposal(fromContent: content)
    }

    // MARK: - Prompt y parseo (testables sin red)

    public static var systemPrompt: String {
        """
        \(FilingSkill.assistantInstructions)

        Responde SIEMPRE en JSON válido, sin texto adicional, con este esquema exacto:
        {"category_path": "una de las categorías permitidas", "suggested_filename": "Titulo-Corto", "confidence": 0.0, "reason": "motivo breve", "issuer": "emisor o null", "document_date": "YYYY-MM-DD o null", "mode": "folder | split"}
        Reglas de formato: category_path debe ser EXACTAMENTE una de las categorías permitidas; suggested_filename en español, sin extensión, con guiones en lugar de espacios; confidence entre 0 y 1 (sé conservador si hay duda); document_date en formato YYYY-MM-DD si puede deducirse.
        Campo «mode» (solo carpetas): "folder" = la carpeta se archiva ENTERA en category_path (por defecto; úsalo cuando dudes o si los elementos guardan relación entre sí: mismo prefijo o producto, curso, serie, álbum, app portable con sus ficheros como exe+dll+recursos). "split" = cajón heterogéneo: procede archivar sus ficheros por separado porque NO comparten tema ni relación entre sí (nombre genérico tipo «Documents»); con "split", category_path se ignora (usa "99_SinClasificar").
        """
    }

    static func userPrompt(profile: DocumentProfile, allowedCategories: [String]) -> String {
        var lines: [String] = []
        lines.append("Categorías permitidas (elige una):")
        lines.append(contentsOf: allowedCategories.map { "- \($0)" })
        lines.append("")
        lines.append(profile.fileExtension.isEmpty ? "Carpeta (unidad completa):" : "Documento:")
        lines.append("- Nombre: \(profile.fileName)")
        if !profile.fileExtension.isEmpty {
            lines.append("- Extensión: \(profile.fileExtension)")
        }
        lines.append("- Tamaño: \(profile.fileSizeBytes) bytes")
        if let pageCount = profile.pageCount {
            lines.append("- Páginas: \(pageCount)")
        }
        if !profile.dates.isEmpty {
            lines.append("- Fechas detectadas: \(profile.dates.prefix(5).joined(separator: ", "))")
        }
        if !profile.amounts.isEmpty {
            lines.append("- Importes detectados: \(profile.amounts.prefix(5).joined(separator: ", "))")
        }
        if !profile.identifiers.isEmpty {
            lines.append("- Identificadores detectados: \(profile.identifiers.prefix(3).joined(separator: ", "))")
        }
        lines.append("")
        lines.append("Decisiones correctas ya validadas (usa el mismo criterio):")
        lines.append(contentsOf: FilingSkill.fewShotLines(limit: 8))
        lines.append("")
        lines.append("- Muestra de texto (truncada):")
        let sample = String(profile.textSample.prefix(maxSampleCharacters))
        if sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("(sin texto extraíble: clasifica a partir del nombre, la extensión y los metadatos; sé conservador con la confianza)")
        } else {
            lines.append(sample)
        }
        lines.append("")
        lines.append("Devuelve el JSON de clasificación (formato json).")
        return lines.joined(separator: "\n")
    }

    /// Convierte el contenido devuelto por el modelo en una propuesta tipada.
    public static func proposal(fromContent content: String) throws -> FilingProposal {
        guard let jsonObject = extractJSONObject(from: content) else {
            throw DeepSeekError.invalidResponse("JSON no encontrado en la respuesta")
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: Data(jsonObject.utf8))
        } catch {
            throw DeepSeekError.invalidResponse("esquema inesperado en el JSON")
        }
        return FilingProposal(
            categoryPath: payload.category_path,
            suggestedTitle: payload.suggested_filename,
            confidence: min(max(payload.confidence ?? 0.5, 0), 1),
            reason: payload.reason ?? "clasificación IA",
            issuer: payload.issuer,
            documentDate: payload.document_date,
            source: .ai,
            folderStrategy: payload.mode?.lowercased() == "split" ? .split : nil
        )
    }

    static func extractJSONObject(from content: String) -> String? {
        guard let start = content.firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = start
        while index < content.endIndex {
            if content[index] == "{" { depth += 1 }
            if content[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(content[start...index])
                }
            }
            index = content.index(after: index)
        }
        return nil
    }

    struct Payload: Decodable {
        let category_path: String
        let suggested_filename: String?
        let confidence: Double?
        let reason: String?
        let issuer: String?
        let document_date: String?
        let mode: String?
    }
}
