import Foundation
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
