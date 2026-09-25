import Foundation

/// Perfil de análisis local de un documento.
public struct DocumentProfile: Sendable, Equatable, Codable {
    public var fileName: String
    public var fileExtension: String
    public var fileSizeBytes: Int64
    public var contentHash: String
    public var hasTextLayer: Bool
    public var usedOCR: Bool
    public var pageCount: Int?
    public var textLength: Int
    public var textSample: String
    public var dates: [String]
    public var amounts: [String]
    public var identifiers: [String]
    public var analyzedAt: Date

    public init(
        fileName: String,
        fileExtension: String,
        fileSizeBytes: Int64,
        contentHash: String,
        hasTextLayer: Bool,
        usedOCR: Bool,
        pageCount: Int?,
        textLength: Int,
        textSample: String,
        dates: [String],
        amounts: [String],
        identifiers: [String],
        analyzedAt: Date
    ) {
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.fileSizeBytes = fileSizeBytes
        self.contentHash = contentHash
        self.hasTextLayer = hasTextLayer
        self.usedOCR = usedOCR
        self.pageCount = pageCount
        self.textLength = textLength
        self.textSample = textSample
        self.dates = dates
        self.amounts = amounts
        self.identifiers = identifiers
        self.analyzedAt = analyzedAt
    }
}
