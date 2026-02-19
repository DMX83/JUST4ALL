import Foundation
import UniformTypeIdentifiers

public final class UTTypeDescriptionCache {
    private let capacity: Int
    private var storage: [String: (value: String, tick: UInt64)] = [:]
    private var tick: UInt64 = 0
    private let lock = NSLock()

    public init(capacity: Int = 1024) {
        self.capacity = max(128, capacity)
    }

    public func description(forFileExtension ext: String) -> String? {
        let key = ext.lowercased()
        if key.isEmpty { return nil }

        lock.lock()
        if var cached = storage[key] {
            tick &+= 1
            cached.tick = tick
            storage[key] = cached
            lock.unlock()
            return cached.value
        }
        lock.unlock()

        guard let type = UTType(filenameExtension: key),
              let description = type.localizedDescription else {
            return nil
        }

        lock.lock()
        tick &+= 1
        storage[key] = (description, tick)
        pruneIfNeeded()
        lock.unlock()

        return description
    }

    private func pruneIfNeeded() {
        guard storage.count > capacity else { return }
        let overflow = storage.count - capacity
        for _ in 0..<overflow {
            guard let oldestKey = storage.min(by: { $0.value.tick < $1.value.tick })?.key else {
                return
            }
            storage.removeValue(forKey: oldestKey)
        }
    }
}
