import XCTest
import CoreImage
@testable import JUST4PICT

final class ImageEnhancerDiagnosticsTests: XCTestCase {
    func testDetectsPortraitAndProducesMeasurableChangeForUserSample() throws {
        let inputURL = try primarySampleImageURL()
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw XCTSkip("Sample image not available in this environment")
        }

        let enhancer = ImageEnhancer()
        let detectedScene = enhancer.detectSceneType(inputURL: inputURL)
        XCTAssertEqual(detectedScene, .portrait)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        try enhancer.enhance(
            inputURL: inputURL,
            outputURL: outputURL,
            preset: .portrait,
            quality: 0.88,
            format: .png
        )

        defer { try? FileManager.default.removeItem(at: outputURL) }

        let originalStats = try averageRGBA(for: inputURL)
        let enhancedStats = try averageRGBA(for: outputURL)

        let delta = abs(originalStats.r - enhancedStats.r)
            + abs(originalStats.g - enhancedStats.g)
            + abs(originalStats.b - enhancedStats.b)
            + abs(originalStats.a - enhancedStats.a)

        print("DIAG scene=\(String(describing: detectedScene))")
        print("DIAG original=\(originalStats)")
        print("DIAG enhanced=\(enhancedStats)")
        print("DIAG delta=\(delta)")

        XCTAssertGreaterThan(delta, 0.02, "The generated output should differ measurably from the input")
    }

    func testWritesRepoSampleOutputsForQuickQA() throws {
        let inputURLs = try sampleImageURLs()
        guard !inputURLs.isEmpty else {
            throw XCTSkip("No sample images available in this environment")
        }

        let enhancer = ImageEnhancer()
        let outputDirectory = try sampleOutputDirectory()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for inputURL in inputURLs {
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            let outputURL = outputDirectory.appendingPathComponent("\(baseName)-pro-sample.png")
            try? FileManager.default.removeItem(at: outputURL)

            try enhancer.enhance(
                inputURL: inputURL,
                outputURL: outputURL,
                preset: .auto,
                quality: 0.95,
                format: .png
            )

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
            print("QA_OUTPUT \(outputURL.path)")
        }
    }

    private func primarySampleImageURL() throws -> URL {
        let samples = try sampleImageURLs()
        if let portrait = samples.first(where: { $0.lastPathComponent == "PHOTO-2026-03-18-22-18-19 2.jpg" }) {
            return portrait
        }

        guard let first = samples.first else {
            let packageRoot = try packageRootURL()
            return packageRoot
                .appendingPathComponent("images", isDirectory: true)
                .appendingPathComponent("PHOTO-2026-03-18-22-18-19 2.jpg")
        }
        return first
    }

    private func sampleImageURLs() throws -> [URL] {
        let imagesDirectory = try imagesDirectoryURL()
        let fileManager = FileManager.default
        let urls = try fileManager.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let supported = Set(["jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff"])
        return urls
            .filter {
                guard let values = try? $0.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else {
                    return false
                }
                return supported.contains($0.pathExtension.lowercased())
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func imagesDirectoryURL() throws -> URL {
        try packageRootURL().appendingPathComponent("images", isDirectory: true)
    }

    private func packageRootURL() throws -> URL {
        let fileURL = URL(fileURLWithPath: #filePath)
        return fileURL
            .deletingLastPathComponent()   // JUST4PICTTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // JUST4PICT
    }

    private func sampleOutputDirectory() throws -> URL {
        try packageRootURL()
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent("test", isDirectory: true)
    }

    private func averageRGBA(for url: URL) throws -> (r: Double, g: Double, b: Double, a: Double) {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw XCTSkip("Could not load image at \(url.path)")
        }

        let extent = image.extent.integral
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = extent

        let context = CIContext(options: [.cacheIntermediates: false])
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            filter.outputImage ?? image,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return (
            Double(bitmap[0]) / 255.0,
            Double(bitmap[1]) / 255.0,
            Double(bitmap[2]) / 255.0,
            Double(bitmap[3]) / 255.0
        )
    }
}
