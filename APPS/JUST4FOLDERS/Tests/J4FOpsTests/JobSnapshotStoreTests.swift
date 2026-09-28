import XCTest
@testable import J4FOps

final class JobSnapshotStoreTests: XCTestCase {
    private func makeStore() -> (JobSnapshotStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4f-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (JobSnapshotStore(fileURL: dir.appendingPathComponent("job-snapshots.json")), dir)
    }

    private func snapshot(id: UUID = UUID(), state: JobState, startedAt: Date? = nil, finishedAt: Date? = nil) -> JobSnapshot {
        JobSnapshot(
            id: id,
            type: .copy,
            state: state,
            totalItems: 1,
            processedItems: 0,
            totalBytes: 0,
            processedBytes: 0,
            startedAt: startedAt,
            finishedAt: finishedAt,
            lastError: nil,
            currentItemPath: nil
        )
    }

    func testItemsDiaryRoundtrip() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let jobId = UUID()
        let items = [
            JobItem(source: URL(fileURLWithPath: "/tmp/origen/a.txt"), destinationDirectory: URL(fileURLWithPath: "/tmp/destino")),
            JobItem(source: URL(fileURLWithPath: "/tmp/origen/b.txt"), destinationDirectory: nil)
        ]
        XCTAssertFalse(store.hasItems(jobId: jobId))
        store.saveItems(items, jobId: jobId)
        XCTAssertTrue(store.hasItems(jobId: jobId))
        XCTAssertEqual(store.loadItems(jobId: jobId), items)
        store.removeItems(jobId: jobId)
        XCTAssertFalse(store.hasItems(jobId: jobId))
        XCTAssertNil(store.loadItems(jobId: jobId))
    }

    func testTerminalSnapshotsArePrunedButActiveKept() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // 60 terminales antiguos + 1 activo; al guardar uno nuevo, la poda deja 50 terminales.
        for index in 0..<60 {
            let when = Date().addingTimeInterval(TimeInterval(-index * 60))
            store.save(snapshot(state: .done, finishedAt: when))
        }
        let activeId = UUID()
        store.save(snapshot(id: activeId, state: .running, startedAt: Date()))
        store.save(snapshot(state: .done, finishedAt: Date()))

        let all = store.loadAll()
        XCTAssertTrue(all.contains(where: { $0.id == activeId }), "el snapshot activo nunca se poda")
        let terminal = all.filter { $0.state == .done || $0.state == .cancelled || $0.state == .failed }
        XCTAssertLessThanOrEqual(terminal.count, JobSnapshotStore.maxTerminalSnapshots)
        XCTAssertGreaterThan(terminal.count, 0)
    }

    func testActiveSnapshotsSurviveManySaves() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let runningId = UUID()
        store.save(snapshot(id: runningId, state: .running, startedAt: Date()))
        for index in 0..<80 {
            store.save(snapshot(state: .cancelled, finishedAt: Date().addingTimeInterval(TimeInterval(-index))))
        }
        let all = store.loadAll()
        XCTAssertEqual(all.filter { $0.id == runningId }.count, 1)
        XCTAssertLessThanOrEqual(all.count, JobSnapshotStore.maxTerminalSnapshots + 1)
    }
}
