import Foundation
import J4FFileSystem
import os

public final class JobQueueService {
    public typealias UpdateHandler = @MainActor (JobSnapshot) -> Void

    private let logger = Logger(subsystem: "com.dmx83.just4folders", category: "job-queue")
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var jobs: [UUID: ManagedJob] = [:]
    private let eventEmitter = EventStreamEmitter()
    private let snapshotStore = JobSnapshotStore()

    public init(maxConcurrent: Int = max(1, Int(Double(ProcessInfo.processInfo.activeProcessorCount) * 0.8))) {
        queue.name = "j4f.job.queue"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = maxConcurrent
    }

    @discardableResult
    public func enqueue(
        type: JobType,
        items: [JobItem],
        conflictPolicy: ConflictPolicy = .rename,
        options: JobExecutionOptions = JobExecutionOptions(),
        onUpdate: UpdateHandler? = nil
    ) -> UUID {
        let id = UUID()
        let managed = ManagedJob(
            id: id,
            type: type,
            items: items,
            conflictPolicy: conflictPolicy,
            options: options,
            onUpdate: onUpdate,
            logger: logger,
            eventEmitter: eventEmitter,
            snapshotStore: snapshotStore
        )

        lock.lock()
        jobs[id] = managed
        lock.unlock()

        queue.addOperation(managed.operation)
        managed.emitQueued()
        return id
    }

    public func cancel(jobId: UUID) {
        lock.lock()
        let managed = jobs[jobId]
        lock.unlock()
        managed?.cancel()
    }

    public func pause(jobId: UUID) {
        lock.lock()
        let managed = jobs[jobId]
        lock.unlock()
        managed?.pause()
    }

    public func resume(jobId: UUID) {
        lock.lock()
        let managed = jobs[jobId]
        lock.unlock()
        managed?.resume()
    }

    public func snapshot(jobId: UUID) -> JobSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return jobs[jobId]?.snapshot()
    }

    public func persistedSnapshots() -> [JobSnapshot] {
        snapshotStore.loadAll()
    }

    @discardableResult
    public func subscribeEvents(_ handler: @escaping EventStreamEmitter.EventHandler) -> UUID {
        eventEmitter.subscribe(handler)
    }

    public func unsubscribeEvents(_ token: UUID) {
        eventEmitter.unsubscribe(token)
    }
}

private final class ManagedJob {
    let operation: BlockOperation

    private let id: UUID
    private let type: JobType
    private let items: [JobItem]
    private let conflictPolicy: ConflictPolicy
    private let options: JobExecutionOptions
    private let onUpdate: JobQueueService.UpdateHandler?
    private let logger: Logger
    private let eventEmitter: EventStreamEmitter
    private let snapshotStore: JobSnapshotStore

    private let stateLock = NSLock()
    private let pauseCondition = NSCondition()
    private var pauseRequested = false
    private var state: JobState = .queued
    private var processed = 0
    private var processedBytes: Int64 = 0
    private var totalBytes: Int64 = 0
    private var startedAt: Date?
    private var finishedAt: Date?
    private var lastError: String?
    private var currentItemPath: String?

    init(
        id: UUID,
        type: JobType,
        items: [JobItem],
        conflictPolicy: ConflictPolicy,
        options: JobExecutionOptions,
        onUpdate: JobQueueService.UpdateHandler?,
        logger: Logger,
        eventEmitter: EventStreamEmitter,
        snapshotStore: JobSnapshotStore
    ) {
        self.id = id
        self.type = type
        self.items = items
        self.conflictPolicy = conflictPolicy
        self.options = options
        self.onUpdate = onUpdate
        self.logger = logger
        self.eventEmitter = eventEmitter
        self.snapshotStore = snapshotStore

        operation = BlockOperation()
        operation.addExecutionBlock { [weak self] in
            self?.run()
        }
    }

    func cancel() {
        operation.cancel()
        resume() // ensure paused workers can exit quickly.
    }

    func pause() {
        pauseCondition.lock()
        pauseRequested = true
        pauseCondition.unlock()
    }

    func resume() {
        pauseCondition.lock()
        pauseRequested = false
        pauseCondition.broadcast()
        pauseCondition.unlock()
    }

    func emitQueued() {
        emit(stateOverride: .queued, eventKind: .queued)
    }

    func snapshot() -> JobSnapshot {
        stateLock.lock()
        defer { stateLock.unlock() }
        return JobSnapshot(
            id: id,
            type: type,
            state: state,
            totalItems: items.count,
            processedItems: processed,
            totalBytes: totalBytes,
            processedBytes: processedBytes,
            startedAt: startedAt,
            finishedAt: finishedAt,
            lastError: lastError,
            currentItemPath: currentItemPath
        )
    }

    private func run() {
        setState(.running)
        stateLock.lock()
        startedAt = Date()
        stateLock.unlock()
        emit(eventKind: .started)

        do {
            try preflightVolumeChecks()
        } catch {
            fail(with: error.localizedDescription)
            return
        }

        let fm = FileManager.default

        if type == .copy || type == .move {
            do {
                let plan = try ExecutionPlanner.buildPlan(type: type, items: items, conflictPolicy: conflictPolicy, fileManager: fm)
                stateLock.lock()
                totalBytes = (plan.bigPhase + plan.smallPhase).reduce(0) { $0 + $1.sizeBytes }
                stateLock.unlock()
                emit(eventKind: .progress)

                try executeAdaptivePlan(plan: plan, fileManager: fm)
            } catch {
                if isCancellationError(error) {
                    cancelNow()
                    return
                }
                fail(with: error.localizedDescription)
                return
            }
        } else {
            stateLock.lock()
            totalBytes = estimateTotalBytes()
            stateLock.unlock()
            emit(eventKind: .progress)

            do {
                try executeNonPlannedItems(fileManager: fm)
            } catch {
                if isCancellationError(error) {
                    cancelNow()
                    return
                }
                fail(with: error.localizedDescription)
                return
            }
        }

        setState(.done)
        stateLock.lock()
        finishedAt = Date()
        stateLock.unlock()
        emit(eventKind: .finished)
    }

    private func executeAdaptivePlan(plan: ExecutionPlan, fileManager fm: FileManager) throws {
        for mkdir in plan.mkdirs {
            try ensureCanProceed()
            try fm.createDirectory(at: mkdir.destination, withIntermediateDirectories: true)
        }

        let firstDestination = (plan.bigPhase.first ?? plan.smallPhase.first)?.destination.deletingLastPathComponent()
        let profileKind = firstDestination.flatMap { VolumeProfileProbe.probe(for: $0)?.kind } ?? .unknown
        let bootstrap = SchedulerBootstrap.make(profile: profileKind)
        let controller = ConcurrencyController(initialWorkers: bootstrap.initialWorkers, maxWorkers: bootstrap.maxWorkers)
        let sampler = TelemetryWindowSampler(windowSeconds: 2.5)

        var bigIndex = 0
        var smallIndex = 0
        var smallLaneEnabled = plan.bigPhase.isEmpty

        while bigIndex < plan.bigPhase.count || smallIndex < plan.smallPhase.count {
            try ensureCanProceed()

            let remainingBig = plan.bigPhase.count - bigIndex
            if !smallLaneEnabled {
                if remainingBig == 0 {
                    smallLaneEnabled = true
                } else if bootstrap.profile == .ssdLike {
                    let ratio = Double(remainingBig) / Double(max(1, plan.bigPhase.count))
                    if ratio < 0.20 {
                        smallLaneEnabled = true
                    }
                }
            }

            let workers = controller.workers
            var batch: [PlannedOperation] = []

            if smallLaneEnabled,
               remainingBig > 0,
               smallIndex < plan.smallPhase.count,
               bootstrap.profile == .ssdLike,
               workers > 1 {
                batch.append(plan.smallPhase[smallIndex])
                smallIndex += 1
            }

            while batch.count < workers {
                if bigIndex < plan.bigPhase.count {
                    batch.append(plan.bigPhase[bigIndex])
                    bigIndex += 1
                } else if smallLaneEnabled, smallIndex < plan.smallPhase.count {
                    batch.append(plan.smallPhase[smallIndex])
                    smallIndex += 1
                } else {
                    break
                }
            }

            if batch.isEmpty { continue }

            let batchQueue = OperationQueue()
            batchQueue.name = "j4f.job.batch"
            batchQueue.qualityOfService = .utility
            batchQueue.maxConcurrentOperationCount = min(workers, batch.count)

            let fatalLock = NSLock()
            var fatalError: Error?

            for op in batch {
                batchQueue.addOperation { [weak self] in
                    guard let self else { return }
                    let started = Date()
                    var opBytes: Int64 = 0
                    var retried = false

                    do {
                        try self.ensureCanProceed()
                        try self.executePlannedOperation(op, fileManager: fm) { copied in
                            opBytes += copied
                            self.stateLock.lock()
                            self.processedBytes += copied
                            self.stateLock.unlock()
                            self.emit(eventKind: .progress)
                        }

                        self.stateLock.lock()
                        self.processed += 1
                        self.stateLock.unlock()
                        self.emit(eventKind: .progress)
                    } catch {
                        if let ns = error as NSError?, ns.domain == "J4FOps", ns.code == 2004 {
                            retried = true
                            self.stateLock.lock()
                            self.processed += 1
                            self.stateLock.unlock()
                            self.emit(eventKind: .retry, message: error.localizedDescription)
                        } else {
                            fatalLock.lock()
                            if fatalError == nil { fatalError = error }
                            fatalLock.unlock()
                        }
                    }

                    let latencyMs = Date().timeIntervalSince(started) * 1000.0
                    sampler.record(bytes: opBytes, latencyMs: latencyMs, retried: retried)
                }
            }

            batchQueue.waitUntilAllOperationsAreFinished()
            if let fatalError {
                throw fatalError
            }

            if let window = sampler.flushIfReady() {
                let tuning = controller.tune(with: window)
                BufferSizer.shared.tune(window: window, reducedForError: tuning.reducedForError, profile: bootstrap.profile)
                logger.log(
                    "Adaptive window: throughput=\(window.throughputBytesPerSecond, privacy: .public)B/s latency=\(window.averageLatencyMs, privacy: .public)ms retries=\(window.retries) workers=\(tuning.workers) bigBuffer=\(BufferSizer.shared.currentBigBytes())"
                )
            }
        }
    }

    private func executePlannedOperation(_ op: PlannedOperation, fileManager fm: FileManager, onBytesCopied: @escaping (Int64) -> Void) throws {
        stateLock.lock()
        currentItemPath = op.source?.path ?? op.destination.path
        stateLock.unlock()

        switch op.kind {
        case .copy:
            guard let src = op.source else { return }
            let lane: SchedulerLane = op.sizeBytes <= ExecutionPlanner.smallThresholdBytes ? .small : .big
            try Self.copyToTarget(
                source: src,
                target: op.destination,
                lane: lane,
                options: options,
                onBytesCopied: onBytesCopied,
                cooperativeCheck: { [weak self] in try self?.ensureCanProceed() }
            ) { [weak self] attempt, error in
                self?.emit(eventKind: .retry, message: "retry \(attempt): \(error.localizedDescription)")
            }
        case .move:
            guard let src = op.source else { return }
            let lane: SchedulerLane = op.sizeBytes <= ExecutionPlanner.smallThresholdBytes ? .small : .big
            try Self.moveToTarget(
                source: src,
                target: op.destination,
                lane: lane,
                options: options,
                onBytesCopied: onBytesCopied,
                cooperativeCheck: { [weak self] in try self?.ensureCanProceed() }
            ) { [weak self] attempt, error in
                self?.emit(eventKind: .retry, message: "retry \(attempt): \(error.localizedDescription)")
            }
        case .mkdir:
            try fm.createDirectory(at: op.destination, withIntermediateDirectories: true)
        }
    }

    private func executeNonPlannedItems(fileManager fm: FileManager) throws {
        for item in items {
            try ensureCanProceed()

            stateLock.lock()
            currentItemPath = item.source.path
            stateLock.unlock()

            switch type {
            case .copy:
                guard let destination = item.destinationDirectory else {
                    throw NSError(domain: "J4FOps", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Copy requiere destinationDirectory."])
                }
                try Self.copyItem(
                    item.source,
                    toDirectory: destination,
                    policy: conflictPolicy,
                    fm: fm,
                    options: options,
                    onBytesCopied: { [weak self] copied in
                        guard let self else { return }
                        self.stateLock.lock()
                        self.processedBytes += copied
                        self.stateLock.unlock()
                        self.emit(eventKind: .progress)
                    },
                    cooperativeCheck: { [weak self] in try self?.ensureCanProceed() }
                ) { [weak self] attempt, error in
                    self?.emit(eventKind: .retry, message: "retry \(attempt): \(error.localizedDescription)")
                }
            case .move:
                guard let destination = item.destinationDirectory else {
                    throw NSError(domain: "J4FOps", code: 2002, userInfo: [NSLocalizedDescriptionKey: "Move requiere destinationDirectory."])
                }
                try Self.moveItem(
                    item.source,
                    toDirectory: destination,
                    policy: conflictPolicy,
                    fm: fm,
                    options: options,
                    onBytesCopied: { [weak self] copied in
                        guard let self else { return }
                        self.stateLock.lock()
                        self.processedBytes += copied
                        self.stateLock.unlock()
                        self.emit(eventKind: .progress)
                    },
                    cooperativeCheck: { [weak self] in try self?.ensureCanProceed() }
                ) { [weak self] attempt, error in
                    self?.emit(eventKind: .retry, message: "retry \(attempt): \(error.localizedDescription)")
                }
            case .deleteTrash:
                try Self.deleteItem(at: item.source, preference: options.deletePreference, fm: fm)
                stateLock.lock()
                processedBytes = min(totalBytes, processedBytes + Self.fileSizeIfRegularFile(item.source))
                stateLock.unlock()
            case .deletePermanent:
                try Self.deleteItem(at: item.source, preference: .permanent, fm: fm)
                stateLock.lock()
                processedBytes = min(totalBytes, processedBytes + Self.fileSizeIfRegularFile(item.source))
                stateLock.unlock()
            }

            stateLock.lock()
            processed += 1
            stateLock.unlock()
            emit(eventKind: .progress)
        }
    }

    private func preflightVolumeChecks() throws {
        switch type {
        case .copy, .move:
            let destinations = Set(items.compactMap { $0.destinationDirectory?.standardizedFileURL.path })
            for path in destinations {
                let dst = URL(fileURLWithPath: path)
                try MountFlagsCheck.ensureWritableDestination(dst)
                if let profile = VolumeProfileProbe.probe(for: dst) {
                    logger.log(
                        "Preflight volume: mount=\(profile.mountPoint, privacy: .public) fs=\(profile.fileSystemType, privacy: .public) kind=\(profile.kind.rawValue, privacy: .public) ro=\(profile.isReadOnly) removable=\(profile.isRemovable)"
                    )
                }
            }
        case .deleteTrash, .deletePermanent:
            break
        }
    }

    private func estimateTotalBytes() -> Int64 {
        items.reduce(into: Int64(0)) { partial, item in
            partial += Self.fileSizeIfRegularFile(item.source)
        }
    }

    private static func fileSizeIfRegularFile(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        if values?.isRegularFile == true {
            return Int64(values?.fileSize ?? 0)
        }
        return 0
    }

    private func ensureCanProceed() throws {
        if operation.isCancelled {
            throw cancellationError()
        }

        var emittedPaused = false
        pauseCondition.lock()
        while pauseRequested {
            if !emittedPaused {
                setState(.paused)
                emit(eventKind: .paused)
                emittedPaused = true
            }
            pauseCondition.wait()
            if operation.isCancelled {
                pauseCondition.unlock()
                throw cancellationError()
            }
        }
        pauseCondition.unlock()

        if emittedPaused {
            setState(.running)
            emit(eventKind: .resumed)
        }
    }

    private func cancellationError() -> NSError {
        NSError(domain: "J4FOps", code: 2099, userInfo: [NSLocalizedDescriptionKey: "Operacion cancelada por usuario."])
    }

    private func isCancellationError(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == "J4FOps" && ns.code == 2099
    }

    private func cancelNow() {
        setState(.cancelled)
        stateLock.lock()
        finishedAt = Date()
        stateLock.unlock()
        emit(eventKind: .cancelled)
    }

    private func fail(with message: String) {
        logger.error("Job \(self.id.uuidString, privacy: .public) failed: \(message, privacy: .public)")
        stateLock.lock()
        lastError = message
        finishedAt = Date()
        stateLock.unlock()
        setState(.failed)
        emit(eventKind: .failed, message: message)
    }

    private func setState(_ newState: JobState) {
        stateLock.lock()
        state = newState
        stateLock.unlock()
    }

    private func emit(stateOverride: JobState? = nil, eventKind: JobEventKind? = nil, message: String? = nil) {
        var snap = snapshot()
        if let override = stateOverride {
            snap = JobSnapshot(
                id: snap.id,
                type: snap.type,
                state: override,
                totalItems: snap.totalItems,
                processedItems: snap.processedItems,
                totalBytes: snap.totalBytes,
                processedBytes: snap.processedBytes,
                startedAt: snap.startedAt,
                finishedAt: snap.finishedAt,
                lastError: snap.lastError,
                currentItemPath: snap.currentItemPath
            )
        }

        snapshotStore.save(snap)

        if let eventKind {
            eventEmitter.emit(
                JobEvent(
                    jobId: id,
                    kind: eventKind,
                    message: message,
                    snapshot: snap
                )
            )
        }

        guard let onUpdate else { return }
        Task { @MainActor in
            onUpdate(snap)
        }
    }

    private static func copyItem(
        _ source: URL,
        toDirectory destinationDirectory: URL,
        policy: ConflictPolicy,
        fm: FileManager,
        options: JobExecutionOptions,
        onBytesCopied: @escaping (Int64) -> Void,
        cooperativeCheck: @escaping () throws -> Void,
        onRetry: @escaping (Int, Error) -> Void
    ) throws {
        try VolumeScheduler.shared.performScheduled(forPath: destinationDirectory.path) {
            try cooperativeCheck()
            let proposed = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            let finalDestination = try resolveConflict(target: proposed, policy: policy, fm: fm)
            try copyToTarget(
                source: source,
                target: finalDestination,
                lane: laneForSource(source),
                options: options,
                onBytesCopied: onBytesCopied,
                cooperativeCheck: cooperativeCheck,
                onRetry: onRetry
            )
        }
    }

    private static func moveItem(
        _ source: URL,
        toDirectory destinationDirectory: URL,
        policy: ConflictPolicy,
        fm: FileManager,
        options: JobExecutionOptions,
        onBytesCopied: @escaping (Int64) -> Void,
        cooperativeCheck: @escaping () throws -> Void,
        onRetry: @escaping (Int, Error) -> Void
    ) throws {
        try VolumeScheduler.shared.performScheduled(forPath: destinationDirectory.path) {
            try cooperativeCheck()
            let proposed = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            let finalDestination = try resolveConflict(target: proposed, policy: policy, fm: fm)
            try moveToTarget(
                source: source,
                target: finalDestination,
                lane: laneForSource(source),
                options: options,
                onBytesCopied: onBytesCopied,
                cooperativeCheck: cooperativeCheck,
                onRetry: onRetry
            )
        }
    }

    private static func copyToTarget(
        source: URL,
        target: URL,
        lane: SchedulerLane,
        options: JobExecutionOptions,
        onBytesCopied: @escaping (Int64) -> Void,
        cooperativeCheck: @escaping () throws -> Void,
        onRetry: @escaping (Int, Error) -> Void
    ) throws {
        let fm = FileManager.default
        let parent = target.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        if (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            try cooperativeCheck()
            try fm.copyItem(at: source, to: target)
            onBytesCopied(fileSizeIfRegularFile(source))
            return
        }

        let sourceSize = fileSizeIfRegularFile(source)
        if sourceSize <= ExecutionPlanner.smallThresholdBytes {
            try copySmallFile(
                source: source,
                destination: target,
                onBytesCopied: onBytesCopied,
                cooperativeCheck: cooperativeCheck,
                onRetry: onRetry
            )
            return
        }

        let profile = VolumeScheduler.shared.profile(forPath: parent.path)
        let adaptiveChunk = lane == .small ? BufferSizer.shared.recommendedChunkSize(for: .small) : BufferSizer.shared.recommendedChunkSize(for: .big)
        let chunk = min(adaptiveChunk, max(64 * 1024, profile.chunkSizeBytes * 8))
        try copyBigFileWithRetry(
            source: source,
            destination: target,
            sourceSize: sourceSize,
            chunkSize: chunk,
            lane: lane,
            options: options,
            onBytesCopied: onBytesCopied,
            cooperativeCheck: cooperativeCheck,
            onRetry: onRetry
        )
    }

    private static func moveToTarget(
        source: URL,
        target: URL,
        lane: SchedulerLane,
        options: JobExecutionOptions,
        onBytesCopied: @escaping (Int64) -> Void,
        cooperativeCheck: @escaping () throws -> Void,
        onRetry: @escaping (Int, Error) -> Void
    ) throws {
        let fm = FileManager.default
        let parent = target.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        do {
            try cooperativeCheck()
            try fm.moveItem(at: source, to: target)
            onBytesCopied(fileSizeIfRegularFile(target))
        } catch {
            if (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try cooperativeCheck()
                try fm.copyItem(at: source, to: target)
                onBytesCopied(fileSizeIfRegularFile(source))
            } else {
                let sourceSize = fileSizeIfRegularFile(source)
                if sourceSize <= ExecutionPlanner.smallThresholdBytes {
                    try copySmallFile(
                        source: source,
                        destination: target,
                        onBytesCopied: onBytesCopied,
                        cooperativeCheck: cooperativeCheck,
                        onRetry: onRetry
                    )
                } else {
                    let profile = VolumeScheduler.shared.profile(forPath: parent.path)
                    let adaptiveChunk = lane == .small ? BufferSizer.shared.recommendedChunkSize(for: .small) : BufferSizer.shared.recommendedChunkSize(for: .big)
                    let chunk = min(adaptiveChunk, max(64 * 1024, profile.chunkSizeBytes * 8))
                    try copyBigFileWithRetry(
                        source: source,
                        destination: target,
                        sourceSize: sourceSize,
                        chunkSize: chunk,
                        lane: lane,
                        options: options,
                        onBytesCopied: onBytesCopied,
                        cooperativeCheck: cooperativeCheck,
                        onRetry: onRetry
                    )
                }
            }
            try cooperativeCheck()
            try fm.removeItem(at: source)
        }
    }

    private static func copySmallFile(
        source: URL,
        destination: URL,
        onBytesCopied: @escaping (Int64) -> Void,
        cooperativeCheck: @escaping () throws -> Void,
        onRetry: @escaping (Int, Error) -> Void
    ) throws {
        let fm = FileManager.default
        try withRetry(maxAttempts: 3, onRetry: onRetry) {
            try cooperativeCheck()
            if fm.fileExists(atPath: destination.path) {
                try? fm.removeItem(at: destination)
            }
            do {
                let bytes = try Data(contentsOf: source, options: [.mappedIfSafe])
                try cooperativeCheck()
                try bytes.write(to: destination, options: .atomic)
                onBytesCopied(Int64(bytes.count))
            } catch {
                if fm.fileExists(atPath: destination.path) {
                    try? fm.removeItem(at: destination)
                }
                throw error
            }
        }
    }

    private static func copyBigFileWithRetry(
        source: URL,
        destination: URL,
        sourceSize: Int64,
        chunkSize: Int,
        lane: SchedulerLane,
        options: JobExecutionOptions,
        onBytesCopied: @escaping (Int64) -> Void,
        cooperativeCheck: @escaping () throws -> Void,
        onRetry: @escaping (Int, Error) -> Void
    ) throws {
        let fm = FileManager.default
        try withRetry(maxAttempts: 3, onRetry: onRetry) {
            try cooperativeCheck()
            if fm.fileExists(atPath: destination.path) {
                try? fm.removeItem(at: destination)
            }
            do {
                try streamCopyFile(
                    source: source,
                    destination: destination,
                    sourceSize: sourceSize,
                    chunkSize: chunkSize,
                    lane: lane,
                    options: options,
                    onBytesCopied: onBytesCopied,
                    cooperativeCheck: cooperativeCheck
                )
            } catch {
                if fm.fileExists(atPath: destination.path) {
                    try? fm.removeItem(at: destination)
                }
                throw error
            }
        }
    }

    private static func streamCopyFile(
        source: URL,
        destination: URL,
        sourceSize: Int64,
        chunkSize: Int,
        lane: SchedulerLane,
        options: JobExecutionOptions,
        onBytesCopied: @escaping (Int64) -> Void,
        cooperativeCheck: @escaping () throws -> Void
    ) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: destination.path) {
            fm.createFile(atPath: destination.path, contents: nil)
        } else {
            try? fm.removeItem(at: destination)
            fm.createFile(atPath: destination.path, contents: nil)
        }

        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)

        defer {
            try? input.close()
            try? output.close()
        }

        let pool = AdaptiveBufferPool.shared
        let bufferClass: BufferClass = (lane == .small) ? .small : .big
        let buffer = pool.acquire(bufferClass: bufferClass, preferredBytes: chunkSize)
        defer { pool.release(buffer) }

        let readSize = min(max(64 * 1024, chunkSize), buffer.count)

        while true {
            try cooperativeCheck()
            let data = try input.read(upToCount: readSize) ?? Data()
            if data.isEmpty {
                break
            }
            try output.write(contentsOf: data)
            onBytesCopied(Int64(data.count))
        }

        if shouldFsync(mode: options.fsyncMode, sourceSize: sourceSize, threshold: options.fsyncLargeFileThresholdBytes) {
            try output.synchronize()
        }
    }

    private static func shouldFsync(mode: FsyncMode, sourceSize: Int64, threshold: Int64) -> Bool {
        switch mode {
        case .none:
            return false
        case .always:
            return true
        case .largeFiles:
            return sourceSize >= threshold
        }
    }

    private static func withRetry(maxAttempts: Int, onRetry: @escaping (Int, Error) -> Void, _ work: () throws -> Void) throws {
        let attempts = max(1, maxAttempts)
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                try work()
                return
            } catch {
                lastError = error
                if attempt < attempts {
                    onRetry(attempt, error)
                }
                if attempt == attempts {
                    break
                }
            }
        }

        throw lastError ?? NSError(domain: "J4FOps", code: 2020, userInfo: [NSLocalizedDescriptionKey: "Retry agotado sin detalle de error."])
    }

    private static func laneForSource(_ source: URL) -> SchedulerLane {
        let size = fileSizeIfRegularFile(source)
        return size <= ExecutionPlanner.smallThresholdBytes ? .small : .big
    }

    private static func resolveConflict(target: URL, policy: ConflictPolicy, fm: FileManager) throws -> URL {
        guard fm.fileExists(atPath: target.path) else { return target }

        switch policy {
        case .overwrite:
            try fm.removeItem(at: target)
            return target
        case .skip:
            throw NSError(domain: "J4FOps", code: 2004, userInfo: [NSLocalizedDescriptionKey: "Conflicto omitido: \(target.lastPathComponent)"])
        case .rename:
            let base = target.deletingPathExtension().lastPathComponent
            let ext = target.pathExtension
            var idx = 1
            while true {
                let name = ext.isEmpty ? "\(base)-\(idx)" : "\(base)-\(idx).\(ext)"
                let candidate = target.deletingLastPathComponent().appendingPathComponent(name)
                if !fm.fileExists(atPath: candidate.path) {
                    return candidate
                }
                idx += 1
            }
        }
    }

    private static func deleteItem(at source: URL, preference: DeletePreference, fm: FileManager) throws {
        switch preference {
        case .permanent:
            try fm.removeItem(at: source)
        case .trashIfPossible:
            do {
                var resulting: NSURL?
                try fm.trashItem(at: source, resultingItemURL: &resulting)
            } catch {
                try fm.removeItem(at: source)
            }
        }
    }
}
