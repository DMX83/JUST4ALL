import Foundation
import SwiftUI

enum BatchItemStatus {
    case pending
    case processing
    case success
    case failed
    case cancelled
}

struct BatchItemResult {
    var status: BatchItemStatus
    var outputURL: URL?
    var errorMessage: String?
    var mode: EnhancementMode?
}

enum EnhancementMode: String {
    case local = "Procesado Pro"
    case ai = "IA"
    case reconstructAI = "Reconstruir IA"
}

struct BatchRunSnapshot {
    let mode: EnhancementMode
    let outputDirectory: URL?
    let preset: EnhancementPreset
    let format: OutputFormat
    let quality: Double
    let exportProfile: ExportProfile
}

@MainActor
final class BatchStateViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var processedCount = 0
    @Published var failedCount = 0
    @Published var progress: Double = 0
    @Published var logs: [String] = []
    @Published var batchResults: [URL: BatchItemResult] = [:]

    var batchTask: Task<Void, Never>?
    var cancelRequested = false

    func resetForNewRun(inputFiles: [URL]) {
        batchTask?.cancel()
        isProcessing = true
        processedCount = 0
        failedCount = 0
        progress = 0
        logs.removeAll()
        cancelRequested = false
        batchResults = Dictionary(
            uniqueKeysWithValues: inputFiles.map {
                ($0, BatchItemResult(status: .pending, outputURL: nil, errorMessage: nil, mode: nil))
            }
        )
    }

    func clearAll() {
        batchTask?.cancel()
        logs.removeAll()
        processedCount = 0
        failedCount = 0
        progress = 0
        batchResults.removeAll()
        cancelRequested = false
        isProcessing = false
    }

    func appendLog(_ message: String) {
        logs.insert(message, at: 0)
    }

    func markRemainingAsCancelled(files: [URL], startingAt index: Int) {
        guard index < files.count else { return }
        for candidate in files[index...] {
            guard let current = batchResults[candidate] else { continue }
            if current.status == .pending || current.status == .processing {
                batchResults[candidate] = BatchItemResult(
                    status: .cancelled,
                    outputURL: nil,
                    errorMessage: "Cancelado por usuario",
                    mode: current.mode
                )
            }
        }
    }

    func recomputeCounters(total: Int) {
        let values = Array(batchResults.values)
        processedCount = values.filter { $0.status == .success }.count
        failedCount = values.filter { $0.status == .failed }.count

        let terminal = values.filter { result in
            result.status == .success || result.status == .failed || result.status == .cancelled
        }.count

        progress = total > 0 ? Double(terminal) / Double(total) : 0
    }
}
