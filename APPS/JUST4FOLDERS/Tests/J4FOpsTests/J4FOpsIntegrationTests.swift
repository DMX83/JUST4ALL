import Foundation
import Darwin
import XCTest
@testable import J4FOps

final class J4FOpsIntegrationTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        tempRoot = base.appendingPathComponent("j4f-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    func testCopyTreeJobCompletesAndWritesExpectedFiles() throws {
        let src = tempRoot.appendingPathComponent("src", isDirectory: true)
        let dst = tempRoot.appendingPathComponent("dst", isDirectory: true)
        try makeSampleTree(src: src)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)

        let queue = JobQueueService(maxConcurrent: 1)
        let items = [JobItem(source: src, destinationDirectory: dst)]
        let final = waitForTerminalSnapshot(queue: queue) {
            queue.enqueue(type: .copy, items: items, conflictPolicy: .overwrite)
        }

        XCTAssertEqual(final.state, .done)
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path), "Copy should preserve source.")

        let enumerator = FileManager.default.enumerator(at: dst, includingPropertiesForKeys: nil)
        var copiedNames: Set<String> = []
        while let next = enumerator?.nextObject() as? URL {
            copiedNames.insert(next.lastPathComponent)
        }

        XCTAssertTrue(copiedNames.contains("file-a.txt"))
        XCTAssertTrue(copiedNames.contains("file-b.txt"))
    }

    func testCopyTreeWithBigFileCopiesNestedContent() throws {
        let src = tempRoot.appendingPathComponent("src-big", isDirectory: true)
        let dst = tempRoot.appendingPathComponent("dst-big", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)

        let nested = src.appendingPathComponent("nested/deeper", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("small".utf8).write(to: nested.appendingPathComponent("small.txt"))
        let big = Data(repeating: 0x41, count: 2 * 1024 * 1024)
        try big.write(to: nested.appendingPathComponent("big.bin"))

        let queue = JobQueueService(maxConcurrent: 1)
        let items = [JobItem(source: src, destinationDirectory: dst)]
        let final = waitForTerminalSnapshot(queue: queue) {
            queue.enqueue(type: .copy, items: items, conflictPolicy: .overwrite)
        }

        XCTAssertEqual(final.state, .done)
        let copiedRoot = dst.appendingPathComponent("src-big", isDirectory: true)
        let copiedSmall = copiedRoot.appendingPathComponent("nested/deeper/small.txt")
        let copiedBig = copiedRoot.appendingPathComponent("nested/deeper/big.bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedSmall.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedBig.path))

        let copiedBigSize = try copiedBig.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        XCTAssertEqual(copiedBigSize, big.count)
    }

    func testMoveFileJobMovesAndRemovesSource() throws {
        let srcDir = tempRoot.appendingPathComponent("src2", isDirectory: true)
        let dstDir = tempRoot.appendingPathComponent("dst2", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)

        let sourceFile = srcDir.appendingPathComponent("move-me.txt")
        try Data("content".utf8).write(to: sourceFile)

        let queue = JobQueueService(maxConcurrent: 1)
        let items = [JobItem(source: sourceFile, destinationDirectory: dstDir)]
        let final = waitForTerminalSnapshot(queue: queue) {
            queue.enqueue(type: .move, items: items, conflictPolicy: .overwrite)
        }

        XCTAssertEqual(final.state, .done)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstDir.appendingPathComponent("move-me.txt").path))
    }

    func testDeletePermanentJobRemovesFile() throws {
        let dir = tempRoot.appendingPathComponent("delete", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let victim = dir.appendingPathComponent("victim.txt")
        try Data("bye".utf8).write(to: victim)

        let queue = JobQueueService(maxConcurrent: 1)
        let items = [JobItem(source: victim)]
        let final = waitForTerminalSnapshot(queue: queue) {
            queue.enqueue(type: .deletePermanent, items: items)
        }

        XCTAssertEqual(final.state, .done)
        XCTAssertFalse(FileManager.default.fileExists(atPath: victim.path))
    }

    // MARK: - v2.3.11 — copias rápidas (clon APFS + copyfile)

    /// Prueba de que la copia CLONA (APFS) y no mueve bytes: un clon no consume espacio en disco
    /// y conserva los metadatos. Antes, este mismo fichero se copiaba leyéndolo a memoria y
    /// escribiendo un temporal + rename (y se perdían los xattrs).
    func testFastCopyClonesFileWithoutSpendingDiskSpaceAndKeepsMetadata() throws {
        let src = tempRoot.appendingPathComponent("clone-src", isDirectory: true)
        let dst = tempRoot.appendingPathComponent("clone-dst", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)

        let bytes = 96 * 1024 * 1024
        let file = src.appendingPathComponent("grande.bin")
        try Data(repeating: 0x5A, count: bytes).write(to: file)

        let xattrOK = file.path.withCString { path in
            "j4f.bench".withCString { name in
                "valor".withCString { value in
                    setxattr(path, name, value, strlen(value), 0, 0) == 0
                }
            }
        }

        let freeBefore = try availableCapacity()
        let started = Date()
        let queue = JobQueueService(maxConcurrent: 2)
        let items = [JobItem(source: file, destinationDirectory: dst)]
        let final = waitForTerminalSnapshot(queue: queue) {
            queue.enqueue(type: .copy, items: items, conflictPolicy: .overwrite)
        }
        let elapsed = Date().timeIntervalSince(started)
        let freeAfter = try availableCapacity()
        let spent = freeBefore - freeAfter

        XCTAssertEqual(final.state, .done)
        let copied = dst.appendingPathComponent("grande.bin")
        XCTAssertEqual(try Data(contentsOf: copied).count, bytes, "contenido íntegro")
        print("[bench] clon de \(bytes / 1_048_576) MB: \(String(format: "%.3f", elapsed)) s · espacio consumido: \(spent / 1_048_576) MB")
        XCTAssertLessThan(spent, 32 * 1024 * 1024, "un clon no debe gastar el tamaño del fichero (96 MB)")

        if xattrOK {
            let preserved = copied.path.withCString { path in
                "j4f.bench".withCString { name in getxattr(path, name, nil, 0, 0, 0) > 0 }
            }
            XCTAssertTrue(preserved, "copyfile conserva los xattrs (el camino antiguo los perdía)")
        } else {
            print("[bench] no se pudo crear el xattr de prueba; se omite esa comprobación")
        }
    }

    /// Benchmark de los MECANISMOS aislados (mismo trabajo, sin el resto del motor): clon APFS
    /// (`clonefile`, lo que hace ahora el motor) vs el camino ANTERIOR de ficheros pequeños
    /// (`Data(contentsOf:)` + escritura atómica = temporal + rename, y sin xattrs).
    func testCloneMechanismBeatsLegacySmallFileCopy() throws {
        let src = tempRoot.appendingPathComponent("mini-src", isDirectory: true)
        let cloneDst = tempRoot.appendingPathComponent("mini-clone", isDirectory: true)
        let legacyDst = tempRoot.appendingPathComponent("mini-legacy", isDirectory: true)
        for dir in [src, cloneDst, legacyDst] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let count = 400
        let payload = Data(repeating: 0x42, count: 8 * 1024)
        var files: [URL] = []
        for index in 0..<count {
            let url = src.appendingPathComponent("f\(index).bin")
            try payload.write(to: url)
            files.append(url)
        }

        let cloneStart = Date()
        for url in files {
            let destination = cloneDst.appendingPathComponent(url.lastPathComponent)
            let result = url.path.withCString { source in
                destination.path.withCString { target in clonefile(source, target, 0) }
            }
            XCTAssertEqual(result, 0, "clonefile debe funcionar en el mismo volumen")
        }
        let cloneSeconds = Date().timeIntervalSince(cloneStart)

        let legacyStart = Date()
        for url in files {
            let destination = legacyDst.appendingPathComponent(url.lastPathComponent)
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            try data.write(to: destination, options: .atomic)
        }
        let legacySeconds = Date().timeIntervalSince(legacyStart)

        print(String(format: "[bench] mecanismo: %d ficheros de 8 KB → clon: %.3f s · camino anterior: %.3f s · mejora: %.1fx",
                     count, cloneSeconds, legacySeconds, legacySeconds / max(cloneSeconds, 0.0001)))
        XCTAssertLessThan(cloneSeconds, legacySeconds, "el clon debe ganar al camino antiguo")
        let copied = try Data(contentsOf: cloneDst.appendingPathComponent("f7.bin"))
        XCTAssertEqual(copied.count, payload.count, "el clon deja el contenido íntegro")
    }

    /// Benchmark del TRABAJO COMPLETO del motor (planificador + eventos + snapshots) con muchos
    /// ficheros pequeños: se imprime el número y se comprueba que acaba bien. Vigila el *overhead*
    /// del motor, que era el verdadero cuello (el progreso reescribía el JSON de jobs por item).
    func testEngineSmallFileJobThroughput() throws {
        let src = tempRoot.appendingPathComponent("many-src", isDirectory: true)
        let dst = tempRoot.appendingPathComponent("many-engine", isDirectory: true)
        for dir in [src, dst] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let count = 400
        let payload = Data(repeating: 0x42, count: 8 * 1024)
        for index in 0..<count {
            try payload.write(to: src.appendingPathComponent("f\(index).bin"))
        }

        let queue = JobQueueService(maxConcurrent: 4)
        let items = [JobItem(source: src, destinationDirectory: dst)]
        let start = Date()
        let final = waitForTerminalSnapshot(queue: queue) {
            queue.enqueue(type: .copy, items: items, conflictPolicy: .overwrite)
        }
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(final.state, .done)

        let copiedCount = Self.regularFileCount(under: dst)
        print(String(format: "[bench] motor completo: %d ficheros de 8 KB (incluye planificar, eventos y snapshots) → %.3f s (%.1f ms/fichero) · copiados: %d",
                     count, seconds, seconds * 1000 / Double(count), copiedCount))
        XCTAssertGreaterThanOrEqual(copiedCount, count)
    }

    /// Cuenta ficheros regulares de forma recursiva (el trabajo copia la carpeta DENTRO del destino).
    private static func regularFileCount(under root: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                total += 1
            }
        }
        return total
    }

    private func availableCapacity() throws -> Int64 {
        let values = try tempRoot.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func makeSampleTree(src: URL) throws {
        let nested = src.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: nested.appendingPathComponent("file-a.txt"))
        try Data("beta".utf8).write(to: nested.appendingPathComponent("file-b.txt"))
    }

    private func waitForTerminalSnapshot(queue: JobQueueService, enqueue: () -> UUID) -> JobSnapshot {
        let exp = expectation(description: "job-finished")
        var finalSnapshot: JobSnapshot?

        _ = queue.subscribeEvents { event in
            guard let snap = event.snapshot else { return }
            if snap.state == .done || snap.state == .failed || snap.state == .cancelled {
                finalSnapshot = snap
                exp.fulfill()
            }
        }

        _ = enqueue()
        wait(for: [exp], timeout: 25)
        guard let finalSnapshot else {
            XCTFail("No final snapshot")
            return JobSnapshot(
                id: UUID(),
                type: .copy,
                state: .failed,
                totalItems: 0,
                processedItems: 0,
                totalBytes: 0,
                processedBytes: 0,
                startedAt: nil,
                finishedAt: nil,
                lastError: "missing snapshot",
                currentItemPath: nil
            )
        }
        return finalSnapshot
    }
}
