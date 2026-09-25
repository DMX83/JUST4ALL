import Foundation

/// Propuesta de archivado para un documento (cruda, sin validar contra la taxonomía).
public struct FilingProposal: Sendable, Equatable, Codable {
    public var categoryPath: String
    public var suggestedTitle: String?
    public var confidence: Double
    public var reason: String
    public var issuer: String?
    public var documentDate: String?
    public var source: FilingProposalSource
    /// Solo para carpetas: `whole` (mover entera) o `split` (desglosar por ficheros). `nil` = entera.
    public var folderStrategy: FolderFilingStrategy?

    public init(
        categoryPath: String,
        suggestedTitle: String? = nil,
        confidence: Double,
        reason: String,
        issuer: String? = nil,
        documentDate: String? = nil,
        source: FilingProposalSource,
        folderStrategy: FolderFilingStrategy? = nil
    ) {
        self.categoryPath = categoryPath
        self.suggestedTitle = suggestedTitle
        self.confidence = confidence
        self.reason = reason
        self.issuer = issuer
        self.documentDate = documentDate
        self.source = source
        self.folderStrategy = folderStrategy
    }
}

public enum FilingProposalSource: String, Sendable, Codable {
    case ai
    case rules
    case fallback
    /// Clasificación resuelta con la base de conocimiento local aprendida (sin llamada a la IA).
    case knowledge
}

/// Estrategia de archivado de una carpeta decidida por la IA (campo «mode» del contrato JSON):
/// entera (por defecto) o desglosada en sus elementos («cajón heterogéneo»).
public enum FolderFilingStrategy: String, Sendable, Codable {
    case whole
    case split
}

/// Plan validado: categoría ∈ taxonomía y nombre saneado.
public struct FilingPlan: Sendable, Equatable {
    public let categoryRelativePath: String
    public let fileName: String
    public let confidence: Double
    public let reason: String
    public let source: FilingProposalSource

    public init(categoryRelativePath: String, fileName: String, confidence: Double, reason: String, source: FilingProposalSource) {
        self.categoryRelativePath = categoryRelativePath
        self.fileName = fileName
        self.confidence = confidence
        self.reason = reason
        self.source = source
    }

    public var isQuarantine: Bool {
        categoryRelativePath == DefaultTaxonomy.quarantineRelativePath
    }
}
