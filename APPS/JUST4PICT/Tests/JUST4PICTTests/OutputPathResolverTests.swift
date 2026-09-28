import XCTest
@testable import JUST4PICT

final class OutputPathResolverTests: XCTestCase {
    private let directory = URL(fileURLWithPath: "/tmp/j4pict-tests", isDirectory: true)
    private let input = URL(fileURLWithPath: "/tmp/j4pict-tests/foto.jpg")

    func testSuffixMatchesModeConventions() {
        XCTAssertEqual(OutputPathResolver.suffix(for: .local), "-enhanced")
        XCTAssertEqual(OutputPathResolver.suffix(for: .ai), "-enhanced_ia")
        XCTAssertEqual(OutputPathResolver.suffix(for: .reconstructAI), "-reconstruct_ia")
    }

    func testUniqueOutputURLBuildsVersionedName() {
        let url = OutputPathResolver.uniqueOutputURL(
            for: input,
            in: directory,
            format: .png,
            mode: .local,
            buildStamp: "build 42",
            fileExists: { _ in false }
        )
        XCTAssertEqual(url.lastPathComponent, "foto-enhanced-build_42.png")
        XCTAssertEqual(url.deletingLastPathComponent().path, directory.path)
    }

    func testUniqueOutputURLAppendsCounterOnCollision() {
        let existing: Set<String> = [
            "foto-enhanced_ia-build_42.png",
            "foto-enhanced_ia-build_42-1.png"
        ]
        let url = OutputPathResolver.uniqueOutputURL(
            for: input,
            in: directory,
            format: .png,
            mode: .ai,
            buildStamp: "build 42",
            fileExists: { existing.contains(URL(fileURLWithPath: $0).lastPathComponent) }
        )
        XCTAssertEqual(url.lastPathComponent, "foto-enhanced_ia-build_42-2.png")
    }

    func testReconstructionUsesOwnSuffixAndExtension() {
        let url = OutputPathResolver.uniqueOutputURL(
            for: input,
            in: directory,
            format: .heic,
            mode: .reconstructAI,
            buildStamp: "local",
            fileExists: { _ in false }
        )
        XCTAssertEqual(url.lastPathComponent, "foto-reconstruct_ia-local.heic")
    }
}
