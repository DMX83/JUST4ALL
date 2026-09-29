import XCTest
@testable import JUST4PICT
import CoreGraphics
import ImageIO

final class Just4PictCLITests: XCTestCase {

    // MARK: - Parseo

    func testIsCLIInvocation() {
        XCTAssertTrue(Just4PictCLI.isCLIInvocation(["enhance"]))
        XCTAssertTrue(Just4PictCLI.isCLIInvocation(["help"]))
        XCTAssertTrue(Just4PictCLI.isCLIInvocation(["--help"]))
        XCTAssertFalse(Just4PictCLI.isCLIInvocation([]))
        XCTAssertFalse(Just4PictCLI.isCLIInvocation(["/tmp/foto.jpg"]))
        XCTAssertFalse(Just4PictCLI.isCLIInvocation(["-psn_0_1"]))
    }

    func testParseEnhanceDefaults() throws {
        let command = try Just4PictCLI.parse(["enhance", "a.jpg", "b.png"])
        guard case .enhance(let options) = command else { return XCTFail("comando inesperado") }
        XCTAssertEqual(options.inputs, ["a.jpg", "b.png"])
        XCTAssertEqual(options.preset, .auto)
        XCTAssertEqual(options.format, .png)
        XCTAssertEqual(options.quality, 1.0)
        XCTAssertNil(options.outputDirectory)
        XCTAssertEqual(options.exportProfile, .original)
        XCTAssertNil(options.sceneOverride)
        XCTAssertFalse(options.json)
    }

    func testParseEnhanceAllFlags() throws {
        let command = try Just4PictCLI.parse([
            "enhance", "-p", "documento", "-f", "jpeg", "-q", "0.8",
            "-o", "/tmp/salida", "--profile", "weblite", "--scene", "oscura",
            "--json", "foto.jpg"
        ])
        guard case .enhance(let options) = command else { return XCTFail("comando inesperado") }
        XCTAssertEqual(options.preset, .document)
        XCTAssertEqual(options.format, .jpg)
        XCTAssertEqual(options.quality, 0.8, accuracy: 0.0001)
        XCTAssertEqual(options.outputDirectory, "/tmp/salida")
        XCTAssertEqual(options.exportProfile, .webLite)
        XCTAssertEqual(options.sceneOverride, .darkPhoto)
        XCTAssertTrue(options.json)
        XCTAssertEqual(options.inputs, ["foto.jpg"])
    }

    func testParsePresetAliases() {
        XCTAssertEqual(Just4PictCLI.preset(from: "Retrato"), .portrait)
        XCTAssertEqual(Just4PictCLI.preset(from: "landscape"), .landscape)
        XCTAssertEqual(Just4PictCLI.preset(from: "DOCUMENT"), .document)
        XCTAssertEqual(Just4PictCLI.preset(from: "ecommerce"), .ecommerce)
        XCTAssertNil(Just4PictCLI.preset(from: "otro"))
        XCTAssertEqual(Just4PictCLI.format(from: "JPEG"), .jpg)
        XCTAssertEqual(Just4PictCLI.format(from: "tif"), .tiff)
        XCTAssertEqual(Just4PictCLI.profile(from: "web-lite"), .webLite)
        XCTAssertEqual(Just4PictCLI.scene(from: "Generica"), .generic)
    }

    func testParseErrors() {
        XCTAssertThrowsError(try Just4PictCLI.parse(["fotico"])) { error in
            XCTAssertEqual(error as? Just4PictCLI.CLIError, .unknownCommand("fotico"))
        }
        XCTAssertThrowsError(try Just4PictCLI.parse(["enhance"])) { error in
            XCTAssertEqual(error as? Just4PictCLI.CLIError, .missingInputs)
        }
        XCTAssertThrowsError(try Just4PictCLI.parse(["enhance", "-p"])) { error in
            XCTAssertEqual(error as? Just4PictCLI.CLIError, .missingValue("-p"))
        }
        XCTAssertThrowsError(try Just4PictCLI.parse(["enhance", "-q", "2", "a.jpg"]))
        XCTAssertThrowsError(try Just4PictCLI.parse(["enhance", "--flag-raro", "a.jpg"]))
    }

    func testCommandParsingNoOp() throws {
        XCTAssertEqual(try Just4PictCLI.parse(["version"]), .version)
        XCTAssertEqual(try Just4PictCLI.parse(["help"]), .help)
        XCTAssertEqual(try Just4PictCLI.parse(["presets"]), .listPresets)
    }

    func testJSONSummary() {
        let json = Just4PictCLI.jsonSummary(created: ["/tmp/a.png", "/tmp/b.png"], failed: 1)
        XCTAssertEqual(json, "{\"created\":[\"/tmp/a.png\",\"/tmp/b.png\"],\"failed\":1}")
        XCTAssertEqual(Just4PictCLI.jsonSummary(created: [], failed: 0), "{\"created\":[],\"failed\":0}")
    }

    // MARK: - End to end (pipeline local real, sin IA)

    func testEnhanceEndToEndCreatesNewFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4p-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let inputURL = tempDir.appendingPathComponent("entrada.png")
        try Self.writeTestPNG(to: inputURL, width: 64, height: 48)

        let outputDir = tempDir.appendingPathComponent("salida", isDirectory: true)
        let code = Just4PictCLI.run(arguments: [
            "enhance", inputURL.path, "-p", "auto", "-f", "png", "-o", outputDir.path
        ])
        XCTAssertEqual(code, 0)

        let created = try FileManager.default.contentsOfDirectory(atPath: outputDir.path)
            .filter { $0.hasSuffix(".png") }
        XCTAssertEqual(created.count, 1, "debe crear exactamente un fichero nuevo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: inputURL.path), "el original no se toca")
    }

    func testEnhanceMissingInputFails() {
        let code = Just4PictCLI.run(arguments: ["enhance", "/tmp/no-existe-j4p-\(UUID().uuidString).png"])
        XCTAssertEqual(code, 3)
    }

    func testEnhanceBadUsageReturns2() {
        XCTAssertEqual(Just4PictCLI.run(arguments: ["enhance", "-p", "marciano", "x.png"]), 2)
        XCTAssertEqual(Just4PictCLI.run(arguments: ["comando-raro"]), 2)
    }

    // MARK: - Utilidades

    private static func writeTestPNG(to url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("no se pudo crear el CGContext")
        }
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw XCTSkip("no se pudo preparar la escritura PNG")
        }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
