import Foundation

// MARK: - Root

public struct IndexRoot: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let path: String
    public let addedAt: Date

    public init(id: Int64, path: String, addedAt: Date) {
        self.id = id
        self.path = path
        self.addedAt = addedAt
    }
}

public enum IndexRootState: String, Sendable {
    case pending
    case crawling
    case ready
    case failed
}

public struct RootStatus: Sendable, Equatable {
    public let root: IndexRoot
    public let state: IndexRootState
    public let lastEventID: UInt64?
    public let scannedCount: Int64
    public let entryCount: Int64
}

// MARK: - Entries

public struct IndexEntry: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let rootID: Int64
    public let path: String
    public let name: String
    public let ext: String
    public let isDirectory: Bool
    public let sizeBytes: Int64
    public let modifiedAt: Date?
}

/// Entrada lista para escribir en el índice. `name`/`ext` se derivan del path.
public struct IndexEntryWrite: Sendable, Equatable {
    public let path: String
    public let name: String
    public let ext: String
    public let isDirectory: Bool
    public let sizeBytes: Int64
    public let modifiedAt: Date?

    public init(path: String, isDirectory: Bool, sizeBytes: Int64, modifiedAt: Date?) {
        let std = URL(fileURLWithPath: path).standardizedFileURL
        self.path = std.path
        self.name = std.lastPathComponent.isEmpty ? std.path : std.lastPathComponent
        self.ext = isDirectory ? "" : std.pathExtension.lowercased()
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
    }

    public init(url: URL, isDirectory: Bool, sizeBytes: Int64, modifiedAt: Date?) {
        self.init(path: url.path, isDirectory: isDirectory, sizeBytes: sizeBytes, modifiedAt: modifiedAt)
    }
}

// MARK: - Search

public struct IndexSearchFilters: Sendable, Equatable {
    public var rootID: Int64?
    /// Extensiones sin punto, en minúsculas. Si se especifica, restringe a ficheros (excluye carpetas).
    public var extensions: Set<String>?
    public var directoriesOnly: Bool?
    public var minSizeBytes: Int64?
    public var maxSizeBytes: Int64?
    public var modifiedAfter: Date?
    public var modifiedBefore: Date?
    /// Limita la búsqueda a una carpeta concreta (subárbol inclusivo).
    public var pathPrefix: String?

    public init() {}
}

public struct IndexSearchRequest: Sendable {
    public var query: String
    public var filters: IndexSearchFilters
    public var limit: Int
    public var includeContent: Bool

    public init(query: String, filters: IndexSearchFilters = .init(), limit: Int = 200, includeContent: Bool = false) {
        self.query = query
        self.filters = filters
        self.limit = limit
        self.includeContent = includeContent
    }
}

public struct IndexSearchHit: Sendable, Equatable {
    public let entry: IndexEntry
    public let score: Double
    public let matchedContent: Bool
    /// Fragmento del texto del documento con la coincidencia (solo matches por contenido).
    public let contentSnippet: String?
}

public struct CachedAnalysis: Sendable, Equatable {
    public let profileJSON: String?
    public let proposalJSON: String?
    public let filedPath: String?
}

public struct JournalEntry: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let timestamp: Date
    public let batchID: String
    public let sourcePath: String
    public let destinationPath: String
    public let categoryPath: String
    public let action: String
    public let state: String
    public let undoneAt: Date?

    public var fileName: String {
        (destinationPath as NSString).lastPathComponent
    }

    public var isUndoable: Bool {
        state == "applied" && (action == "move" || action == "quarantine" || action == "cold")
    }
}

public struct IndexStats: Sendable, Equatable {
    public let totalEntries: Int64
    public let totalFiles: Int64
    public let totalDirectories: Int64
}

/// Estadísticas del subárbol de una carpeta (para el explorador).
public struct DirectoryStats: Sendable, Equatable {
    public let fileCount: Int64
    public let directoryCount: Int64
    public let totalSizeBytes: Int64

    public init(fileCount: Int64, directoryCount: Int64, totalSizeBytes: Int64) {
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.totalSizeBytes = totalSizeBytes
    }
}

public enum IndexError: Error, LocalizedError {
    case openFailed(String)
    case sqlFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): return message
        case .sqlFailed(let message): return message
        }
    }
}
