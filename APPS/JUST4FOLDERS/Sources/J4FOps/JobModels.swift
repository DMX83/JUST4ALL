import Foundation

public enum JobType: String, Codable {
    case copy
    case move
    case deleteTrash
    case deletePermanent
}

public enum JobState: String, Codable {
    case queued
    case running
    case paused
    case failed
    case done
    case cancelled
}

public enum ConflictPolicy: String, Codable {
    case overwrite
    case skip
    case rename
}

public enum DeletePreference: String, Codable {
    case trashIfPossible
    case permanent
}

public enum FsyncMode: String, Codable {
    case none
    case largeFiles
    case always
}

public struct JobExecutionOptions: Hashable, Codable {
    public let deletePreference: DeletePreference
    public let fsyncMode: FsyncMode
    public let fsyncLargeFileThresholdBytes: Int64

    public init(
        deletePreference: DeletePreference = .trashIfPossible,
        fsyncMode: FsyncMode = .largeFiles,
        fsyncLargeFileThresholdBytes: Int64 = 32 * 1024 * 1024
    ) {
        self.deletePreference = deletePreference
        self.fsyncMode = fsyncMode
        self.fsyncLargeFileThresholdBytes = max(1 * 1024 * 1024, fsyncLargeFileThresholdBytes)
    }
}

public enum JobEventKind: String, Codable {
    case queued
    case started
    case progress
    case paused
    case resumed
    case retry
    case failed
    case finished
    case cancelled
}

public struct JobEvent: Hashable, Codable {
    public let jobId: UUID
    public let kind: JobEventKind
    public let timestamp: Date
    public let message: String?
    public let snapshot: JobSnapshot?

    public init(
        jobId: UUID,
        kind: JobEventKind,
        timestamp: Date = Date(),
        message: String? = nil,
        snapshot: JobSnapshot? = nil
    ) {
        self.jobId = jobId
        self.kind = kind
        self.timestamp = timestamp
        self.message = message
        self.snapshot = snapshot
    }
}

public struct JobItem: Hashable, Codable {
    public let source: URL
    public let destinationDirectory: URL?

    public init(source: URL, destinationDirectory: URL? = nil) {
        self.source = source
        self.destinationDirectory = destinationDirectory
    }
}

public struct JobSnapshot: Identifiable, Hashable, Codable {
    public let id: UUID
    public let type: JobType
    public let state: JobState
    public let totalItems: Int
    public let processedItems: Int
    public let totalBytes: Int64
    public let processedBytes: Int64
    public let startedAt: Date?
    public let finishedAt: Date?
    public let lastError: String?
    public let currentItemPath: String?

    public init(
        id: UUID,
        type: JobType,
        state: JobState,
        totalItems: Int,
        processedItems: Int,
        totalBytes: Int64,
        processedBytes: Int64,
        startedAt: Date?,
        finishedAt: Date?,
        lastError: String?,
        currentItemPath: String?
    ) {
        self.id = id
        self.type = type
        self.state = state
        self.totalItems = totalItems
        self.processedItems = processedItems
        self.totalBytes = totalBytes
        self.processedBytes = processedBytes
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.lastError = lastError
        self.currentItemPath = currentItemPath
    }

    public var progress: Double {
        if totalBytes > 0 {
            return min(1.0, max(0.0, Double(processedBytes) / Double(totalBytes)))
        }
        guard totalItems > 0 else { return 0 }
        return min(1.0, max(0.0, Double(processedItems) / Double(totalItems)))
    }
}
