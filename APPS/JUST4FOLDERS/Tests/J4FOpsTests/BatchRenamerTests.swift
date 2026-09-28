import XCTest
@testable import J4FOps

final class BatchRenamerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4f-rename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String, contents: String = "x") throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try contents.data(using: .utf8)?.write(to: url)
        return url
    }

    func testPlainReplaceKeepsExtension() throws {
        let file = try makeFile("foto.jpg")
        let plan = BatchRenamer.plan(urls: [file], options: .init(find: "foto", replace: "imagen"))
        XCTAssertEqual(plan.first?.status, .rename(to: "imagen.jpg"))
    }

    func testIncludeExtensionReplacesInFullName() throws {
        let file = try makeFile("foto.jpg")
        let plan = BatchRenamer.plan(
            urls: [file],
            options: .init(find: "jpg", replace: "png", includeExtension: true)
        )
        XCTAssertEqual(plan.first?.status, .rename(to: "foto.png"))
    }

    func testRegexWithCaptureGroups() throws {
        let file = try makeFile("IMG_001.JPG")
        let plan = BatchRenamer.plan(
            urls: [file],
            options: .init(find: "(\\d+)", replace: "N$1", useRegex: true)
        )
        XCTAssertEqual(plan.first?.status, .rename(to: "IMG_N001.JPG"))
    }

    func testInvalidRegexMarksEverything() throws {
        let file = try makeFile("a.txt")
        let plan = BatchRenamer.plan(urls: [file], options: .init(find: "(", replace: "x", useRegex: true))
        XCTAssertEqual(plan.first?.errorMessage, "Expresión regular no válida")
    }

    func testInternalCollisionIsDetected() throws {
        let a = try makeFile("aaa.txt")
        let b = try makeFile("bbb.txt")
        // Regex que lleva ambos al mismo nombre.
        let plan = BatchRenamer.plan(
            urls: [a, b],
            options: .init(find: "^[ab]+", replace: "x", useRegex: true)
        )
        XCTAssertEqual(plan[0].status, .rename(to: "x.txt"))
        XCTAssertEqual(plan[1].errorMessage, "Colisión con «aaa.txt» del lote")
    }

    func testExistingTargetBlocksUnlessInBatch() throws {
        let source = try makeFile("uno.txt")
        _ = try makeFile("dos.txt")
        let plan = BatchRenamer.plan(urls: [source], options: .init(find: "uno", replace: "dos"))
        XCTAssertEqual(plan.first?.errorMessage, "Ya existe «dos.txt»")
    }

    func testUnchangedWhenNothingMatches() throws {
        let file = try makeFile("estable.txt")
        let plan = BatchRenamer.plan(urls: [file], options: .init(find: "zzz", replace: "yyy"))
        XCTAssertEqual(plan.first?.status, .unchanged)
    }

    func testApplySwapsNamesWithoutClash() throws {
        let a = try makeFile("a.txt", contents: "AAA")
        let b = try makeFile("b.txt", contents: "BBB")
        // Intercambio puro: apply debe pasarlo por nombres temporales.
        let plan = [
            BatchRenamer.ItemPlan(url: a, status: .rename(to: "b.txt")),
            BatchRenamer.ItemPlan(url: b, status: .rename(to: "a.txt"))
        ]

        let result = BatchRenamer.apply(plan)
        XCTAssertEqual(result.renamed, 2)
        XCTAssertTrue(result.failures.isEmpty)

        let newA = tempDir.appendingPathComponent("a.txt")
        let newB = tempDir.appendingPathComponent("b.txt")
        XCTAssertEqual(try String(contentsOf: newA, encoding: .utf8), "BBB", "el antiguo b.txt ahora se llama a.txt")
        XCTAssertEqual(try String(contentsOf: newB, encoding: .utf8), "AAA", "el antiguo a.txt ahora se llama b.txt")
    }
}
