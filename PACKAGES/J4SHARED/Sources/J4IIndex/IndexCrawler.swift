import Foundation
import J4ICore

public struct CrawlOptions: Sendable {
    public var includeHidden: Bool
    public var batchSize: Int
    public var pausePerBatchMilliseconds: UInt64

    public init(includeHidden: Bool = false, batchSize: Int = 500, pausePerBatchMilliseconds: UInt64 = 0) {
        self.includeHidden = includeHidden
        self.batchSize = max(1, batchSize)
        self.pausePerBatchMilliseconds = pausePerBatchMilliseconds
    }
}

public struct CrawlResult: Sendable {
    public let rootID: Int64
    public let scanned: Int64
    public let upserted: Int
    public let duration: TimeInterval
}

/// Crawler cooperativo del índice.
///
/// - Cancela vía `Task.cancel()` o `shouldCancel` (UI) sin corromper el índice:
///   el root queda en `.pending` y se puede relanzar.
/// - El estado del root lo transiciona este tipo: `.crawling` → `.ready` (o `.pending`/`.failed`).
public final class IndexCrawler: @unchecked Sendable {
    private let index: SearchIndex

    public init(index: SearchIndex) {
        self.index = index
    }

    @discardableResult
    public func crawl(
        rootID: Int64,
        rootPath: String,
        options: CrawlOptions = .init(),
        shouldCancel: (() -> Bool)? = nil,
        onProgress: (@Sendable (Int64) -> Void)? = nil
    ) async throws -> CrawlResult {
        let started = Date()
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let displayPath = (rootPath as NSString).abbreviatingWithTildeInPath
        J4Log.info(.index, "Indexando «\(displayPath)»…")
        try await index.setRootState(id: rootID, state: .crawling)
        do {
            let totals = try await enumerate(
                rootID: rootID,
                rootURL: rootURL,
                includeSelf: true,
                options: options,
                shouldCancel: shouldCancel,
                onProgress: onProgress
            )
            try await index.setRootState(id: rootID, state: .ready)
            let duration = Date().timeIntervalSince(started)
            J4Log.info(.index, "Indexación de «\(displayPath)» completada: \(totals.scanned) entrada(s) escaneada(s), \(totals.upserted) upsert(s) en \(String(format: "%.1f", duration)) s.")
            return CrawlResult(
                rootID: rootID,
                scanned: totals.scanned,
                upserted: totals.upserted,
                duration: duration
            )
        } catch is CancellationError {
            try? await index.setRootState(id: rootID, state: .pending)
            J4Log.warn(.index, "Indexación de «\(displayPath)» cancelada; quedará pendiente.")
            throw CancellationError()
        } catch {
            try? await index.setRootState(id: rootID, state: .failed)
            J4Log.error(.index, "Indexación de «\(displayPath)» falló: \(error.localizedDescription)")
            throw error
        }
    }

    /// Reindexado completo: limpia las entradas del root y vuelve a crawlear.
    @discardableResult
    public func reindex(
        rootID: Int64,
        rootPath: String,
        options: CrawlOptions = .init(),
        onProgress: (@Sendable (Int64) -> Void)? = nil
    ) async throws -> CrawlResult {
        J4Log.info(.index, "Reindexado completo (conservando textos y vectores por ruta) de «\((rootPath as NSString).abbreviatingWithTildeInPath)»…")
        try await index.preserveContentSnapshot(rootID: rootID)
        try await index.clearEntries(rootID: rootID)
        let result = try await crawl(rootID: rootID, rootPath: rootPath, options: options, onProgress: onProgress)
        try await index.restorePreservedContent(rootID: rootID)
        return result
    }

    /// Upsert de un subárbol sin tocar el estado del root (lo usa la ingesta FSEvents
    /// cuando aparece o se mueve un directorio dentro de un root ya crawleado).
    public func crawlSubtree(rootID: Int64, path: String, options: CrawlOptions = .init()) async throws {
        J4Log.debug(.index, "Indexando subárbol nuevo: «\((path as NSString).abbreviatingWithTildeInPath)».")
        let url = URL(fileURLWithPath: path, isDirectory: true)
        _ = try await enumerate(
            rootID: rootID,
            rootURL: url,
            includeSelf: true,
            options: options,
            shouldCancel: nil,
            onProgress: nil
        )
    }

    private func enumerate(
        rootID: Int64,
        rootURL: URL,
        includeSelf: Bool,
        options: CrawlOptions,
        shouldCancel: (() -> Bool)?,
        onProgress: (@Sendable (Int64) -> Void)?
    ) async throws -> (scanned: Int64, upserted: Int) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey, .fileSizeKey, .contentModificationDateKey]
        let keySet = Set(keys)

        var batch: [IndexEntryWrite] = []
        var scanned: Int64 = 0
        var upserted = 0

        if includeSelf {
            if let write = makeWrite(url: rootURL, forceDirectory: true) {
                batch.append(write)
                scanned += 1
            }
        }

        if let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) {
            while let next = enumerator.nextObject() {
                if shouldCancel?() == true { throw CancellationError() }
                try Task.checkCancellation()
                guard let url = next as? URL else { continue }

                let values = try? url.resourceValues(forKeys: keySet)
                if !options.includeHidden, values?.isHidden == true {
                    if values?.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                let isDirectory = values?.isDirectory == true
                let isRegularFile = values?.isRegularFile == true
                guard isDirectory || isRegularFile else { continue }

                batch.append(
                    IndexEntryWrite(
                        url: url,
                        isDirectory: isDirectory,
                        sizeBytes: Int64(values?.fileSize ?? 0),
                        modifiedAt: values?.contentModificationDate
                    )
                )
                scanned += 1

                if batch.count >= options.batchSize {
                    upserted += try await index.upsertEntries(rootID: rootID, batch)
                    batch.removeAll(keepingCapacity: true)
                    try await index.setRootCrawlProgress(id: rootID, scanned: scanned)
                    onProgress?(scanned)
                    if options.pausePerBatchMilliseconds > 0 {
                        try? await Task.sleep(nanoseconds: options.pausePerBatchMilliseconds * 1_000_000)
                    }
                }
            }
        }

        if !batch.isEmpty {
            upserted += try await index.upsertEntries(rootID: rootID, batch)
        }
        try await index.setRootCrawlProgress(id: rootID, scanned: scanned)
        onProgress?(scanned)
        return (scanned, upserted)
    }

    private func makeWrite(url: URL, forceDirectory: Bool = false) -> IndexEntryWrite? {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        let isDirectory = forceDirectory || values?.isDirectory == true
        return IndexEntryWrite(
            url: url,
            isDirectory: isDirectory,
            sizeBytes: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate
        )
    }
}
