import Foundation
import J4FFileSystem

public struct VolumeProfile: Hashable {
    public let mountPoint: String
    public let fileSystemType: String
    public let chunkSizeBytes: Int
    public let maxConcurrentJobs: Int

    public var isLikelySlow: Bool {
        maxConcurrentJobs == 1
    }
}

public final class VolumeScheduler {
    public static let shared = VolumeScheduler()

    private let lock = NSLock()
    private var semaphores: [String: DispatchSemaphore] = [:]
    private var limits: [String: Int] = [:]

    private init() {}

    public func profile(forPath path: String) -> VolumeProfile {
        let url = URL(fileURLWithPath: path)
        guard let probe = VolumeProfileProbe.probe(for: url) else {
            return VolumeProfile(mountPoint: "/", fileSystemType: "unknown", chunkSizeBytes: 512 * 1024, maxConcurrentJobs: 1)
        }

        switch probe.kind {
        case .networkLike:
            return VolumeProfile(mountPoint: probe.mountPoint, fileSystemType: probe.fileSystemType, chunkSizeBytes: 256 * 1024, maxConcurrentJobs: 1)
        case .hddLike:
            return VolumeProfile(mountPoint: probe.mountPoint, fileSystemType: probe.fileSystemType, chunkSizeBytes: 384 * 1024, maxConcurrentJobs: 1)
        case .ssdLike:
            return VolumeProfile(mountPoint: probe.mountPoint, fileSystemType: probe.fileSystemType, chunkSizeBytes: 1024 * 1024, maxConcurrentJobs: 2)
        case .unknown:
            return VolumeProfile(mountPoint: probe.mountPoint, fileSystemType: probe.fileSystemType, chunkSizeBytes: 512 * 1024, maxConcurrentJobs: 1)
        }
    }

    public func performScheduled<T>(forPath path: String, _ work: () throws -> T) throws -> T {
        let profile = profile(forPath: path)
        let semaphore = semaphoreForMount(profile.mountPoint, limit: profile.maxConcurrentJobs)
        semaphore.wait()
        defer { semaphore.signal() }
        return try work()
    }

    private func semaphoreForMount(_ mount: String, limit: Int) -> DispatchSemaphore {
        lock.lock()
        defer { lock.unlock() }

        if let existing = semaphores[mount], limits[mount] == limit {
            return existing
        }

        let semaphore = DispatchSemaphore(value: max(1, limit))
        semaphores[mount] = semaphore
        limits[mount] = max(1, limit)
        return semaphore
    }
}
