import Foundation
import J4ICore

/// Ejecuta el archivado físico (mkdirs + move) con colisión resuelta y sin sobreescritura.
/// Nunca borra: solo mueve. El undo restaura el fichero a su ruta original.
public struct FilingExecutor: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public struct ExecutionResult: Sendable, Equatable {
        public let destinationURL: URL
        public let categoryRelativePath: String
        public let containedCollision: Bool
    }

    public func execute(plan: FilingPlan, sourceURL: URL) throws -> ExecutionResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw NSError(domain: "J4IFiling", code: 4500, userInfo: [NSLocalizedDescriptionKey: "El fichero de origen ya no existe."])
        }
        let categoryURL = rootURL.appendingPathComponent(plan.categoryRelativePath, isDirectory: true)
        try fileManager.createDirectory(at: categoryURL, withIntermediateDirectories: true)
        let destination = Self.availableDestination(in: categoryURL, fileName: plan.fileName, fileManager: fileManager)
        try fileManager.moveItem(at: sourceURL, to: destination.url)
        return ExecutionResult(
            destinationURL: destination.url,
            categoryRelativePath: plan.categoryRelativePath,
            containedCollision: destination.adjusted
        )
    }

    /// Mueve un fichero ya existente a una categoría del árbol (uso manual: revisión de pendientes).
    /// Mismas garantías que el archivado: mkdirs, colisión resuelta (`-1`, `-2`…) y sin sobreescribir.
    public func move(sourceURL: URL, to categoryRelativePath: String) throws -> ExecutionResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw NSError(domain: "J4IFiling", code: 4503, userInfo: [NSLocalizedDescriptionKey: "El fichero de origen ya no existe."])
        }
        let categoryURL = rootURL.appendingPathComponent(categoryRelativePath, isDirectory: true)
        try fileManager.createDirectory(at: categoryURL, withIntermediateDirectories: true)
        let destination = Self.availableDestination(in: categoryURL, fileName: sourceURL.lastPathComponent, fileManager: fileManager)
        try fileManager.moveItem(at: sourceURL, to: destination.url)
        return ExecutionResult(
            destinationURL: destination.url,
            categoryRelativePath: categoryRelativePath,
            containedCollision: destination.adjusted
        )
    }

    /// Deshace un archivado: devuelve el fichero a su ruta original (solo si es seguro).
    public func undo(destinationURL: URL, originalURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw NSError(domain: "J4IFiling", code: 4501, userInfo: [NSLocalizedDescriptionKey: "El fichero archivado ya no existe; no se puede deshacer."])
        }
        guard !fileManager.fileExists(atPath: originalURL.path) else {
            throw NSError(domain: "J4IFiling", code: 4502, userInfo: [NSLocalizedDescriptionKey: "Ya existe un fichero en la ruta original; no se restaura automáticamente."])
        }
        try fileManager.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: destinationURL, to: originalURL)
    }

    /// Primer nombre libre en el directorio: `nombre.ext`, `nombre-1.ext`, `nombre-2.ext`, …
    static func availableDestination(in directory: URL, fileName: String, fileManager: FileManager) -> (url: URL, adjusted: Bool) {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var counter = 0
        while fileManager.fileExists(atPath: candidate.path), counter < 500 {
            counter += 1
            let name = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            candidate = directory.appendingPathComponent(name)
        }
        return (candidate, counter > 0)
    }
}
