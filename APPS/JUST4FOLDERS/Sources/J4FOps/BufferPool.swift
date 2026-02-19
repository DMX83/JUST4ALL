import Foundation

public enum BufferClass {
    case small
    case big
}

public final class MemoryBudgetManager {
    public static let shared = MemoryBudgetManager(totalBudgetBytes: 512 * 1024 * 1024)

    public let totalBudgetBytes: Int

    private let condition = NSCondition()
    private var allocatedBytes: Int = 0

    public init(totalBudgetBytes: Int) {
        self.totalBudgetBytes = max(1, totalBudgetBytes)
    }

    public func reserve(bytes: Int) {
        let needed = max(64 * 1024, bytes)
        condition.lock()
        defer { condition.unlock() }

        while allocatedBytes + needed > totalBudgetBytes {
            condition.wait()
        }
        allocatedBytes += needed
    }

    public func release(bytes: Int) {
        let released = max(64 * 1024, bytes)
        condition.lock()
        allocatedBytes = max(0, allocatedBytes - released)
        condition.broadcast()
        condition.unlock()
    }
}

public final class AdaptiveBufferPool {
    public static let shared = AdaptiveBufferPool(memory: .shared)

    private let memory: MemoryBudgetManager
    private let lock = NSLock()
    private var pool: [Int: [Data]] = [:]

    public init(memory: MemoryBudgetManager) {
        self.memory = memory
    }

    public func acquire(bufferClass: BufferClass, preferredBytes: Int) -> Data {
        let size = normalizedSize(for: bufferClass, preferredBytes: preferredBytes)

        lock.lock()
        if var cached = pool[size], let buffer = cached.popLast() {
            pool[size] = cached
            lock.unlock()
            return buffer
        }
        lock.unlock()

        memory.reserve(bytes: size)
        return Data(count: size)
    }

    public func release(_ buffer: Data, keepInPool: Bool = true) {
        let size = max(64 * 1024, buffer.count)
        if keepInPool {
            lock.lock()
            var bucket = pool[size] ?? []
            bucket.append(buffer)
            pool[size] = bucket
            lock.unlock()
            return
        }

        memory.release(bytes: size)
    }

    private func normalizedSize(for bufferClass: BufferClass, preferredBytes: Int) -> Int {
        switch bufferClass {
        case .small:
            return 1 * 1024 * 1024
        case .big:
            // Big lane supports adaptive range up to 8MB.
            let raw = max(1 * 1024 * 1024, min(8 * 1024 * 1024, preferredBytes))
            let mb = max(1, Int(round(Double(raw) / Double(1024 * 1024))))
            return mb * 1024 * 1024
        }
    }
}
