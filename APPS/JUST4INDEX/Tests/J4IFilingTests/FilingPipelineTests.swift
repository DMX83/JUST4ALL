import XCTest
import J4ICore
import J4IIndex
@testable import J4IFiling

final class FilingPipelineTests: XCTestCase {
    private actor ConcurrencyProbe {
        private(set) var active = 0
        private(set) var peak = 0
        private(set) var total = 0

        func enter() {
            active += 1
            total += 1
            peak = max(peak, active)
        }

        func exit() {
            active -= 1
        }
    }

    func testConcurrencyLimiterBoundsParallelism() async {
        let limiter = ConcurrencyLimiter(limit: 2)
        let probe = ConcurrencyProbe()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await limiter.withSlot {
                        await probe.enter()
                        try? await Task.sleep(for: .milliseconds(40))
                        await probe.exit()
                    }
                }
            }
        }

        let peak = await probe.peak
        let total = await probe.total
        let active = await probe.active
        XCTAssertEqual(total, 8, "todas las operaciones deben ejecutarse")
        XCTAssertEqual(active, 0, "no deben quedar slots ocupados")
        XCTAssertLessThanOrEqual(peak, 2, "nunca más de 2 a la vez")
        XCTAssertGreaterThan(peak, 1, "debe haber paralelismo real (2 a la vez)")
    }

    func testPipelineProcessesFilesThroughCoordinator() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4i-pipeline-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootURL = tempDir.appendingPathComponent("organizado", isDirectory: true)
        let sourceURL = tempDir.appendingPathComponent("entrada", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)

        let index = SearchIndex(databaseURL: tempDir.appendingPathComponent("index.sqlite"))
        let coordinator = FilingCoordinator(index: index, rootURL: rootURL, simulationMode: false, advisor: nil)
        let pipeline = FilingPipeline(coordinator: coordinator, maxConcurrent: 2)

        var urls: [URL] = []
        for number in 1...4 {
            let url = sourceURL.appendingPathComponent("Factura-Luz-\(number).txt")
            try "Factura de electricidad nº \(number). Importe \(number)5,00 €".write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }

        let outcomes = await withTaskGroup(of: FilingCoordinator.Outcome.self) { group in
            for url in urls {
                group.addTask { await pipeline.process(url) }
            }
            var result: [FilingCoordinator.Outcome] = []
            for await outcome in group { result.append(outcome) }
            return result
        }

        XCTAssertEqual(outcomes.count, 4)
        XCTAssertTrue(outcomes.allSatisfy { $0.action == "move" })
        XCTAssertTrue(outcomes.allSatisfy { $0.categoryPath == "01_Fiscal/Facturas" })
        XCTAssertTrue(outcomes.allSatisfy { FileManager.default.fileExists(atPath: $0.destinationPath) })

        let journal = try await index.journalRecent(limit: 10)
        XCTAssertEqual(journal.count, 4)
    }
}
