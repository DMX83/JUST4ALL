import Foundation
import XCTest
@testable import J4FFileSystem

final class J4FFileSystemTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        tempRoot = base.appendingPathComponent("j4f-fs-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    func testURLMetadataLRUCacheStoresAndEvicts() {
        let cache = URLMetadataLRUCache(capacity: 256)
        for idx in 0..<300 {
            let snapshot = URLMetadataSnapshot(
                isDirectory: false,
                fileSize: Int64(idx),
                modifiedDate: Date(),
                isHidden: false,
                localizedTypeDescription: "File"
            )
            cache.set(snapshot, forPath: "/tmp/\(idx)")
        }

        XCTAssertNil(cache.value(forPath: "/tmp/0"))
        XCTAssertNotNil(cache.value(forPath: "/tmp/299"))
    }

    func testDirectoryListingRespectsIncludeHiddenFlag() throws {
        let visible = tempRoot.appendingPathComponent("visible.txt")
        let hidden = tempRoot.appendingPathComponent(".hidden.txt")
        try Data("a".utf8).write(to: visible)
        try Data("b".utf8).write(to: hidden)

        let cache = URLMetadataLRUCache(capacity: 256)
        var withoutHidden: [DirectoryEntry] = []
        _ = try DirectoryListingService.listIncremental(
            folder: tempRoot,
            includeHidden: false,
            batchSize: 64,
            metadataCache: cache
        ) { withoutHidden.append(contentsOf: $0) }

        XCTAssertEqual(withoutHidden.count, 1)
        XCTAssertEqual(withoutHidden.first?.url.lastPathComponent, "visible.txt")

        var withHidden: [DirectoryEntry] = []
        _ = try DirectoryListingService.listIncremental(
            folder: tempRoot,
            includeHidden: true,
            batchSize: 64,
            metadataCache: cache
        ) { withHidden.append(contentsOf: $0) }

        XCTAssertEqual(withHidden.count, 2)
    }

    func testListing100kFilesPerfWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["J4F_RUN_100K_PERF"] == "1" else {
            throw XCTSkip("Set J4F_RUN_100K_PERF=1 to run 100k perf test.")
        }

        let large = tempRoot.appendingPathComponent("large", isDirectory: true)
        try FileManager.default.createDirectory(at: large, withIntermediateDirectories: true)

        for idx in 0..<100_000 {
            let file = large.appendingPathComponent("f-\(idx).txt")
            FileManager.default.createFile(atPath: file.path, contents: Data(), attributes: nil)
        }

        let cache = URLMetadataLRUCache(capacity: 20_000)
        let start = Date()
        var listed = 0
        _ = try DirectoryListingService.listIncremental(
            folder: large,
            includeHidden: false,
            batchSize: 1024,
            metadataCache: cache
        ) { batch in
            listed += batch.count
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(listed, 100_000)
        XCTAssertLessThan(elapsed, 300, "100k listing took too long: \(elapsed)s")
    }
}
