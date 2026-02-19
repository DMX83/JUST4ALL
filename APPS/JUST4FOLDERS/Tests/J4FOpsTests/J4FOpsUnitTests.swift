import Foundation
import XCTest
@testable import J4FOps

final class J4FOpsUnitTests: XCTestCase {
    func testClassifyBySizeSeparatesSmallAndBig() {
        let ops = [
            PlannedOperation(kind: .copy, source: URL(fileURLWithPath: "/tmp/a"), destination: URL(fileURLWithPath: "/tmp/b"), sizeBytes: 512_000),
            PlannedOperation(kind: .copy, source: URL(fileURLWithPath: "/tmp/c"), destination: URL(fileURLWithPath: "/tmp/d"), sizeBytes: 2_000_000),
        ]

        let classified = ExecutionPlanner.classifyBySize(ops)
        XCTAssertEqual(classified.small.count, 1)
        XCTAssertEqual(classified.big.count, 1)
        XCTAssertEqual(classified.small.first?.sizeBytes, 512_000)
        XCTAssertEqual(classified.big.first?.sizeBytes, 2_000_000)
    }

    func testConcurrencyControllerTuningRules() {
        let controller = ConcurrencyController(initialWorkers: 1, maxWorkers: 4)

        _ = controller.tune(with: TelemetryWindow(duration: 2, bytesProcessed: 10_000_000, averageLatencyMs: 25, retries: 0))
        let growth = controller.tune(with: TelemetryWindow(duration: 2, bytesProcessed: 13_000_000, averageLatencyMs: 20, retries: 0))
        XCTAssertEqual(growth.workers, 2)

        let drop = controller.tune(with: TelemetryWindow(duration: 2, bytesProcessed: 8_000_000, averageLatencyMs: 25, retries: 0))
        XCTAssertEqual(drop.workers, 1)

        let retryDrop = controller.tune(with: TelemetryWindow(duration: 2, bytesProcessed: 9_000_000, averageLatencyMs: 300, retries: 1))
        XCTAssertEqual(retryDrop.workers, 1)
        XCTAssertTrue(retryDrop.reducedForError)
    }

    func testBufferSizerPreferredRangeClamp() {
        BufferSizer.shared.setPreferredBigBytes(64 * 1024)
        XCTAssertEqual(BufferSizer.shared.currentBigBytes(), 1 * 1024 * 1024)

        BufferSizer.shared.setPreferredBigBytes(16 * 1024 * 1024)
        XCTAssertEqual(BufferSizer.shared.currentBigBytes(), 8 * 1024 * 1024)

        BufferSizer.shared.setPreferredBigBytes(5 * 1024 * 1024)
        XCTAssertEqual(BufferSizer.shared.currentBigBytes(), 5 * 1024 * 1024)
    }
}
