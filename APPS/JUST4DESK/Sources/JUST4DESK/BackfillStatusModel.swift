import Foundation
import J4IFiling
import J4IIndex

/// Estado de los rellenos (contenido y vectores) para Ajustes → Indexado (auditoría 28-sep, deuda #3).
/// `SearchViewModel` lo actualiza al ejecutar; las vistas solo lo observan.
@MainActor
final class BackfillStatusModel: ObservableObject {
    static let shared = BackfillStatusModel()

    struct Counts: Equatable {
        var contentWithText: Int64 = 0
        var contentAttemptedEmpty: Int64 = 0
        var contentPending: Int64 = 0
        var embedded: Int64 = 0
        var embeddedContent: Int64 = 0
        var files: Int64 = 0
    }

    @Published var counts = Counts()
    @Published var isContentRunning = false
    @Published var isSemanticRunning = false
    @Published var lastRunAt: Date?
    @Published var lastExtracted = 0
    @Published var lastEmpty = 0
    @Published var lastMissing = 0

    var isRunning: Bool { isContentRunning || isSemanticRunning }

    private init() {}

    /// Relee los conteos del índice (COUNTs baratos) para la tarjeta de Ajustes.
    func refreshCounts() async {
        let index = SearchIndex.shared
        if let stats = try? await index.contentStats(extensions: ContentBackfill.supportedExtensions) {
            counts.contentWithText = stats.withText
            counts.contentAttemptedEmpty = stats.attemptedEmpty
            counts.contentPending = stats.pending
        }
        if let totals = try? await index.semanticTotals() {
            counts.embedded = totals.embedded
            counts.embeddedContent = totals.contentEmbedded
            counts.files = totals.files
        }
    }

    /// Registra el resultado de una pasada de contenido (lo llama `SearchViewModel`).
    func recordContentRun(_ outcome: ContentBackfill.Outcome) {
        lastRunAt = Date()
        lastExtracted = outcome.extracted
        lastEmpty = outcome.empty
        lastMissing = outcome.missing
    }
}
