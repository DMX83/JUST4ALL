import Foundation
import J4FFileSystem

public struct PlannedOperation: Hashable {
    public enum Kind: String {
        case mkdir
        case copy
        case move
    }

    public let kind: Kind
    public let source: URL?
    public let destination: URL
    public let sizeBytes: Int64

    public init(kind: Kind, source: URL?, destination: URL, sizeBytes: Int64 = 0) {
        self.kind = kind
        self.source = source
        self.destination = destination
        self.sizeBytes = sizeBytes
    }
}

public struct ExecutionPlan: Hashable {
    public let mkdirs: [PlannedOperation]
    public let bigPhase: [PlannedOperation]
    public let smallPhase: [PlannedOperation]

    public init(mkdirs: [PlannedOperation], bigPhase: [PlannedOperation], smallPhase: [PlannedOperation]) {
        self.mkdirs = mkdirs
        self.bigPhase = bigPhase
        self.smallPhase = smallPhase
    }
}

public enum ExecutionPlanner {
    public static let smallThresholdBytes: Int64 = 1 * 1024 * 1024

    public static func buildPlan(
        type: JobType,
        items: [JobItem],
        conflictPolicy: ConflictPolicy,
        fileManager: FileManager = .default
    ) throws -> ExecutionPlan {
        guard type == .copy || type == .move else {
            return ExecutionPlan(mkdirs: [], bigPhase: [], smallPhase: [])
        }

        var mkdirSet: Set<String> = []
        var fileOps: [PlannedOperation] = []

        for item in items {
            guard let destRoot = item.destinationDirectory else { continue }
            let sourceRoot = item.source
            let sourceRootName = sourceRoot.lastPathComponent
            let rootValues = try sourceRoot.resourceValues(forKeys: [.isDirectoryKey])

            if rootValues.isDirectory == true {
                let destinationRoot = destRoot.appendingPathComponent(sourceRootName, isDirectory: true)
                let sourceCanonical = sourceRoot.resolvingSymlinksInPath().standardizedFileURL
                let sourceComponents = sourceCanonical.pathComponents
                try FileEnumerationStream.stream(roots: [sourceRoot], includeHidden: false) { node in
                    let nodeCanonical = node.url.resolvingSymlinksInPath().standardizedFileURL
                    let nodeComponents = nodeCanonical.pathComponents
                    let trimmed: String
                    if nodeComponents.starts(with: sourceComponents) {
                        let relativeComponents = nodeComponents.dropFirst(sourceComponents.count)
                        trimmed = relativeComponents.joined(separator: "/")
                    } else {
                        let relative = node.url.path.replacingOccurrences(of: sourceRoot.path, with: "")
                        trimmed = relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
                    }
                    let target = trimmed.isEmpty ? destinationRoot : destinationRoot.appendingPathComponent(trimmed, isDirectory: node.isDirectory)

                    if node.isDirectory {
                        mkdirSet.insert(target.standardizedFileURL.path)
                    } else {
                        let conflictResolved = try resolveConflict(target: target, policy: conflictPolicy, fm: fileManager)
                        fileOps.append(PlannedOperation(kind: type == .copy ? .copy : .move, source: node.url, destination: conflictResolved, sizeBytes: node.sizeBytes))
                        mkdirSet.insert(conflictResolved.deletingLastPathComponent().standardizedFileURL.path)
                    }
                }
            } else {
                let proposed = destRoot.appendingPathComponent(sourceRootName)
                let target = try resolveConflict(target: proposed, policy: conflictPolicy, fm: fileManager)
                let size = Int64((try sourceRoot.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                fileOps.append(PlannedOperation(kind: type == .copy ? .copy : .move, source: sourceRoot, destination: target, sizeBytes: size))
                mkdirSet.insert(target.deletingLastPathComponent().standardizedFileURL.path)
            }
        }

        let mkdirs = mkdirSet
            .sorted { lhs, rhs in
                let lhsDepth = lhs.split(separator: "/").count
                let rhsDepth = rhs.split(separator: "/").count
                if lhsDepth == rhsDepth { return lhs < rhs }
                return lhsDepth < rhsDepth
            }
            .map { path in PlannedOperation(kind: .mkdir, source: nil, destination: URL(fileURLWithPath: path), sizeBytes: 0) }

        let classified = classifyBySize(fileOps)

        return ExecutionPlan(
            mkdirs: mkdirs,
            bigPhase: classified.big,
            smallPhase: classified.small
        )
    }

    public static func classifyBySize(_ operations: [PlannedOperation]) -> (small: [PlannedOperation], big: [PlannedOperation]) {
        var small: [PlannedOperation] = []
        var big: [PlannedOperation] = []
        for op in operations {
            if op.sizeBytes <= smallThresholdBytes {
                small.append(op)
            } else {
                big.append(op)
            }
        }
        return (small: small, big: big)
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
}
