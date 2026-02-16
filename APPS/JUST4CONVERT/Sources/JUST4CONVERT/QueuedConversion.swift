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
    @Published var completedAt: Date?
    @Published var estimatedRemaining: TimeInterval?
    
    var displayName: String {
        inputURL.lastPathComponent
    }
    
    var durationDisplay: String? {
        guard let startedAt, let completedAt else { return nil }
        let duration = completedAt.timeIntervalSince(startedAt)
        if duration < 1 {
            return "<1s"
        } else if duration < 60 {
            return String(format: "%.0fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%dm %ds", minutes, seconds)
        }
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

final class ProgressThrottler {
    private let minInterval: TimeInterval
    private let minDelta: Double
    private let lock = NSLock()
    private var lastUpdateTime: TimeInterval = 0
    private var lastProgress: Double = 0

    init(minInterval: TimeInterval, minDelta: Double) {
        self.minInterval = minInterval
        self.minDelta = minDelta
    }

    func shouldUpdate(progress: Double) -> Bool {
        let now = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }

        let delta = abs(progress - lastProgress)
        if progress >= 1.0 || delta >= minDelta || (now - lastUpdateTime) >= minInterval {
            lastUpdateTime = now
            lastProgress = progress
            return true
        }
        return false
    }
}

class ConversionQueue: ObservableObject {
    @Published var items: [QueuedConversion] = []
    @Published var isProcessing = false
    @Published var currentIndex = 0
    @Published var completedCount = 0
    @Published var remainingCount = 0
    @Published var maxConcurrent = ConversionQueue.defaultMaxConcurrent
    @Published var queueStartedAt: Date?
    @Published var queueCompletedAt: Date?
    
    private var currentTask: Task<Void, Never>?
    private let progressMinInterval: TimeInterval = 0.2
    private let progressMinDelta: Double = 0.01

    static var defaultMaxConcurrent: Int {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        return max(1, Int(Double(cores) * 0.8))
    }
    
    var currentItem: QueuedConversion? {
        guard currentIndex < items.count else { return nil }
        return items[currentIndex]
    }
    
    @MainActor
    func addItem(_ item: QueuedConversion) {
        items.append(item)
        updateCounts()
    }
    
    @MainActor
    func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        if currentIndex >= items.count {
            currentIndex = max(0, items.count - 1)
        }
        updateCounts()
    }
    
    @MainActor
    func clear() {
        cancel()
        items.removeAll()
        currentIndex = 0
        isProcessing = false
        queueStartedAt = nil
        queueCompletedAt = nil
        updateCounts()
    }
    
    @MainActor
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        for item in items {
            if case .processing = item.status {
                item.status = .failed("Cancelado por el usuario")
            }
        }
        isProcessing = false
        updateCounts()
    }
    
    @MainActor
    func processQueue() {
        guard !isProcessing else { return }
        isProcessing = true
        queueStartedAt = Date()
        queueCompletedAt = nil
        updateCounts()

        let itemsSnapshot = items
        let maxConcurrent = max(1, self.maxConcurrent)
        let minInterval = progressMinInterval
        let minDelta = progressMinDelta

        currentTask = Task.detached(priority: .utility) { [weak self] in
            await QueueWorker.run(
                items: itemsSnapshot,
                maxConcurrent: maxConcurrent,
                progressMinInterval: minInterval,
                progressMinDelta: minDelta,
                onItemCompleted: {
                    await MainActor.run {
                        self?.updateCounts()
                    }
                }
            )

            await MainActor.run {
                guard let self else { return }
                self.isProcessing = false
                self.currentTask = nil
                self.updateCounts()
            }
        }
    }

    @MainActor
    func retryItem(_ item: QueuedConversion) {
        guard !isProcessing else { return }
        isProcessing = true
        updateCounts()

        let minInterval = progressMinInterval
        let minDelta = progressMinDelta
        
        currentTask = Task.detached(priority: .utility) { [weak self] in
            await QueueWorker.run(
                items: [item],
                maxConcurrent: 1,
                progressMinInterval: minInterval,
                progressMinDelta: minDelta,
                onItemCompleted: {
                    await MainActor.run {
                        self?.updateCounts()
                    }
                }
            )

            await MainActor.run {
                guard let self else { return }
                self.isProcessing = false
                self.currentTask = nil
                self.updateCounts()
            }
        }
    }

    @MainActor
    private func updateCounts() {
        let completed = items.filter { item in
            if case .completed = item.status {
                return true
            }
            return false
        }.count
        completedCount = completed
        remainingCount = items.count - completed
        
        // Mark queue as completed when all items are done
        if remainingCount == 0 && !items.isEmpty && queueCompletedAt == nil {
            queueCompletedAt = Date()
        }
    }
    
    var totalDurationDisplay: String? {
        guard let queueStartedAt else { return nil }
        let completedAt = queueCompletedAt ?? Date()
        let duration = completedAt.timeIntervalSince(queueStartedAt)
        
        if duration < 1 {
            return "<1s"
        } else if duration < 60 {
            return String(format: "%.0fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%dm %ds", minutes, seconds)
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

private enum QueueWorker {
    static func run(
        items: [QueuedConversion],
        maxConcurrent: Int,
        progressMinInterval: TimeInterval,
        progressMinDelta: Double,
        onItemCompleted: @escaping () async -> Void
    ) async {
        let pendingItems = items.filter { item in
            if case .completed = item.status {
                return false
            }
            return true
        }

        var iterator = pendingItems.makeIterator()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<maxConcurrent {
                if let item = iterator.next() {
                    group.addTask {
                        await process(
                            item: item,
                            progressMinInterval: progressMinInterval,
                            progressMinDelta: progressMinDelta,
                            onItemCompleted: onItemCompleted
                        )
                    }
                }
            }

            while await group.next() != nil {
                if Task.isCancelled { break }
                if let item = iterator.next() {
                    group.addTask {
                        await process(
                            item: item,
                            progressMinInterval: progressMinInterval,
                            progressMinDelta: progressMinDelta,
                            onItemCompleted: onItemCompleted
                        )
                    }
                }
            }
        }
    }

    private static func process(
        item: QueuedConversion,
        progressMinInterval: TimeInterval,
        progressMinDelta: Double,
        onItemCompleted: @escaping () async -> Void
    ) async {
        if Task.isCancelled { return }

        await MainActor.run {
            item.status = .processing
            item.startedAt = Date()
            item.estimatedRemaining = nil
            item.progress = 0.0
            item.outputURL = nil
        }

        let throttler = ProgressThrottler(minInterval: progressMinInterval, minDelta: progressMinDelta)

        do {
            let outputURL = try await Converter.convert(
                from: item.inputURL,
                to: item.outputDirectory,
                type: item.conversionType,
                format: item.conversionFormat,
                settings: item.settings,
                outputNameTemplate: item.outputNameTemplate,
                progressHandler: { progress in
                    guard throttler.shouldUpdate(progress: progress) else { return }
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
                try? FileManager.default.removeItem(at: outputURL)
                await MainActor.run {
                    item.status = .failed("Cancelado")
                }
                await onItemCompleted()
                return
            }

            await MainActor.run {
                item.outputURL = outputURL
                item.status = .completed
                item.completedAt = Date()
                item.progress = 1.0
                item.estimatedRemaining = 0
            }
        } catch {
            await MainActor.run {
                item.status = .failed(error.localizedDescription)
                item.progress = 0.0
                item.estimatedRemaining = nil
            }
        }

        await onItemCompleted()
    }
}
