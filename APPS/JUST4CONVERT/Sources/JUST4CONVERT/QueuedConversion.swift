import Foundation

enum ConversionStatus: Equatable {
    case pending
    case processing
    case completed
    case failed(String)
    
    var displayName: String {
        switch self {
        case .pending:
            return "Pendiente"
        case .processing:
            return "Procesando..."
        case .completed:
            return "Completado"
        case .failed(let message):
            return "Error: \(message)"
        }
    }
}

class QueuedConversion: Identifiable, ObservableObject {
    let id = UUID()
    let inputURL: URL
    let outputDirectory: URL
    let conversionType: ConversionType
    @Published var conversionFormat: ConversionFormat
    @Published var settings: ConversionSettings
    let outputNameTemplate: String
    
    @Published var status: ConversionStatus = .pending
    @Published var progress: Double = 0.0
    @Published var outputURL: URL?
    @Published var startedAt: Date?
    @Published var estimatedRemaining: TimeInterval?
    
    var displayName: String {
        inputURL.lastPathComponent
    }
    
    init(
        inputURL: URL,
        outputDirectory: URL,
        conversionType: ConversionType,
        conversionFormat: ConversionFormat,
        settings: ConversionSettings,
        outputNameTemplate: String
    ) {
        self.inputURL = inputURL
        self.outputDirectory = outputDirectory
        self.conversionType = conversionType
        self.conversionFormat = conversionFormat
        self.settings = settings
        self.outputNameTemplate = outputNameTemplate
    }
}

@MainActor
class ConversionQueue: ObservableObject {
    @Published var items: [QueuedConversion] = []
    @Published var isProcessing = false
    @Published var currentIndex = 0
    
    private var currentTask: Task<Void, Never>?
    
    var currentItem: QueuedConversion? {
        guard currentIndex < items.count else { return nil }
        return items[currentIndex]
    }
    
    func addItem(_ item: QueuedConversion) {
        items.append(item)
    }
    
    func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        if currentIndex >= items.count {
            currentIndex = max(0, items.count - 1)
        }
    }
    
    func clear() {
        cancel()
        items.removeAll()
        currentIndex = 0
        isProcessing = false
    }
    
    func cancel() {
        currentTask?.cancel()
        if let currentItem = currentItem, currentItem.status == .processing {
            currentItem.status = .failed("Cancelado por el usuario")
        }
        isProcessing = false
    }
    
    func processQueue() {
        guard !isProcessing else { return }
        isProcessing = true
        
        currentTask = Task {
            defer { 
                isProcessing = false 
                currentTask = nil
            }
            
            for (index, item) in items.enumerated() {
                if Task.isCancelled { break }
                if case .completed = item.status { continue }
                
                currentIndex = index
                await processItem(item)
            }
        }
    }

    func retryItem(_ item: QueuedConversion) {
        guard !isProcessing else { return }
        isProcessing = true
        
        currentTask = Task {
            defer { 
                isProcessing = false 
                currentTask = nil
            }
            await processItem(item)
        }
    }

    private func processItem(_ item: QueuedConversion) async {
        if Task.isCancelled { return }
        
        item.status = .processing
        item.startedAt = Date()
        item.estimatedRemaining = nil
        item.progress = 0.0
        item.outputURL = nil

        do {
            let outputURL = try await Converter.convert(
                from: item.inputURL,
                to: item.outputDirectory,
                type: item.conversionType,
                format: item.conversionFormat,
                settings: item.settings,
                outputNameTemplate: item.outputNameTemplate,
                progressHandler: { progress in
                    Task { @MainActor in
                        item.progress = progress
                        if let startedAt = item.startedAt, progress > 0 {
                            let elapsed = Date().timeIntervalSince(startedAt)
                            let remaining = max(0, (elapsed / progress) - elapsed)
                            item.estimatedRemaining = remaining
                        }
                    }
                }
            )

            if Task.isCancelled {
                item.status = .failed("Cancelado")
                try? FileManager.default.removeItem(at: outputURL)
                return
            }

            item.outputURL = outputURL
            item.status = .completed
            item.progress = 1.0
            item.estimatedRemaining = 0
        } catch {
            item.status = .failed(error.localizedDescription)
            item.progress = 0.0
            item.estimatedRemaining = nil
        }
    }
    
    var totalProgress: Double {
        guard !items.isEmpty else { return 0.0 }
        let sum = items.reduce(0.0) { partial, item in
            partial + item.progress
        }
        return min(max(sum / Double(items.count), 0.0), 1.0)
    }
}
