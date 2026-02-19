import Foundation
import J4FFileSystem

public enum SchedulerLane: String {
    case big = "LaneBig"
    case small = "LaneSmall"
    case meta = "LaneMeta"
}

public struct SchedulerBootstrapConfig {
    public let profile: VolumeKind
    public let initialWorkers: Int
    public let maxWorkers: Int

    public init(profile: VolumeKind, initialWorkers: Int, maxWorkers: Int) {
        self.profile = profile
        self.initialWorkers = initialWorkers
        self.maxWorkers = maxWorkers
    }
}

public enum SchedulerBootstrap {
    public static func make(profile: VolumeKind) -> SchedulerBootstrapConfig {
        switch profile {
        case .ssdLike:
            return SchedulerBootstrapConfig(profile: profile, initialWorkers: 2, maxWorkers: 6)
        case .hddLike, .networkLike:
            return SchedulerBootstrapConfig(profile: profile, initialWorkers: 1, maxWorkers: 2)
        case .unknown:
            return SchedulerBootstrapConfig(profile: profile, initialWorkers: 1, maxWorkers: 3)
        }
    }
}

public struct TelemetryWindow {
    public let duration: TimeInterval
    public let bytesProcessed: Int64
    public let averageLatencyMs: Double
    public let retries: Int

    public var throughputBytesPerSecond: Double {
        guard duration > 0 else { return 0 }
        return Double(bytesProcessed) / duration
    }
}

public final class TelemetryWindowSampler {
    private let windowSeconds: TimeInterval
    private var windowStartedAt = Date()
    private var bytesProcessed: Int64 = 0
    private var retries = 0
    private var latencySamples: [Double] = []
    private let lock = NSLock()

    public init(windowSeconds: TimeInterval = 2.5) {
        self.windowSeconds = max(1.0, windowSeconds)
    }

    public func record(bytes: Int64, latencyMs: Double, retried: Bool) {
        lock.lock()
        bytesProcessed += bytes
        latencySamples.append(max(0, latencyMs))
        if retried { retries += 1 }
        lock.unlock()
    }

    public func flushIfReady(now: Date = Date()) -> TelemetryWindow? {
        lock.lock()
        defer { lock.unlock() }

        let elapsed = now.timeIntervalSince(windowStartedAt)
        guard elapsed >= windowSeconds else { return nil }

        let avgLatency = latencySamples.isEmpty ? 0 : (latencySamples.reduce(0, +) / Double(latencySamples.count))
        let window = TelemetryWindow(
            duration: elapsed,
            bytesProcessed: bytesProcessed,
            averageLatencyMs: avgLatency,
            retries: retries
        )

        windowStartedAt = now
        bytesProcessed = 0
        retries = 0
        latencySamples.removeAll(keepingCapacity: true)
        return window
    }
}

public final class ConcurrencyController {
    public private(set) var workers: Int

    private let minWorkers: Int
    private let maxWorkers: Int
    private var lastThroughput: Double?

    public init(initialWorkers: Int, minWorkers: Int = 1, maxWorkers: Int) {
        self.workers = max(minWorkers, min(maxWorkers, initialWorkers))
        self.minWorkers = max(1, minWorkers)
        self.maxWorkers = max(self.minWorkers, maxWorkers)
    }

    @discardableResult
    public func tune(with window: TelemetryWindow) -> (workers: Int, reducedForError: Bool) {
        let throughput = window.throughputBytesPerSecond

        if window.retries > 0 || window.averageLatencyMs > 180 {
            workers = max(minWorkers, workers - 1)
            lastThroughput = throughput
            return (workers, true)
        }

        if let last = lastThroughput, last > 0 {
            let growth = (throughput - last) / last
            if growth > 0.10 {
                workers = min(maxWorkers, workers + 1)
            } else if growth < -0.10 {
                workers = max(minWorkers, workers - 1)
            }
        }

        lastThroughput = throughput
        return (workers, false)
    }
}

public final class BufferSizer {
    public static let shared = BufferSizer()

    private let lock = NSLock()
    private var bigBytes: Int = 4 * 1024 * 1024

    private init() {}

    public func currentBigBytes() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return bigBytes
    }

    public func setPreferredBigBytes(_ bytes: Int) {
        lock.lock()
        bigBytes = max(1 * 1024 * 1024, min(8 * 1024 * 1024, bytes))
        lock.unlock()
    }

    public func recommendedChunkSize(for lane: SchedulerLane) -> Int {
        lock.lock()
        defer { lock.unlock() }
        switch lane {
        case .small:
            return 1 * 1024 * 1024
        case .big, .meta:
            return bigBytes
        }
    }

    public func tune(window: TelemetryWindow, reducedForError: Bool, profile: VolumeKind) {
        lock.lock()
        defer { lock.unlock() }

        if reducedForError {
            bigBytes = max(1 * 1024 * 1024, bigBytes - 1 * 1024 * 1024)
            return
        }

        if profile == .ssdLike && window.averageLatencyMs < 40 && window.throughputBytesPerSecond > 8_000_000 {
            bigBytes = min(8 * 1024 * 1024, bigBytes + 1 * 1024 * 1024)
        }
    }
}
