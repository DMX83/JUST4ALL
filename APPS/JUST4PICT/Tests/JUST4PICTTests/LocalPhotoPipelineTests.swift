import XCTest
import CoreImage
import CoreImage.CIFilterBuiltins
@testable import JUST4PICT

final class LocalPhotoPipelineTests: XCTestCase {
    func testWhiteBalanceUsesHighlightReferenceWhenAvailable() {
        let pipeline = makePipeline()
        let analysis = PhotoAnalysis(
            averageRed: 0.62,
            averageGreen: 0.52,
            averageBlue: 0.48,
            highlightRed: 0.96,
            highlightGreen: 0.90,
            highlightBlue: 0.82,
            highlightCoverage: 0.24,
            averageLuminance: 0.58,
            averageSaturation: 0.18,
            isLowKey: false,
            isHighKey: false
        )

        let adjustment = pipeline.diagnosticWhiteBalanceAdjustment(for: analysis)

        XCTAssertNotNil(adjustment)
        XCTAssertEqual(adjustment?.usesHighlights, true)
        XCTAssertGreaterThan(adjustment?.temperatureOffset ?? 0.0, 100.0)
    }

    func testWhiteBalanceDoesNotTriggerWhenOnlySubjectsAreWarmAndHighlightsStayNeutral() {
        let pipeline = makePipeline()
        let analysis = PhotoAnalysis(
            averageRed: 0.64,
            averageGreen: 0.54,
            averageBlue: 0.46,
            highlightRed: 0.92,
            highlightGreen: 0.92,
            highlightBlue: 0.91,
            highlightCoverage: 0.20,
            averageLuminance: 0.60,
            averageSaturation: 0.20,
            isLowKey: false,
            isHighKey: false
        )

        XCTAssertNil(pipeline.diagnosticWhiteBalanceAdjustment(for: analysis))
    }

    func testWhiteBalanceFallsBackToGlobalReferenceWhenHighlightsAreInsufficient() {
        let pipeline = makePipeline()
        let analysis = PhotoAnalysis(
            averageRed: 0.60,
            averageGreen: 0.50,
            averageBlue: 0.44,
            highlightRed: 0.92,
            highlightGreen: 0.92,
            highlightBlue: 0.91,
            highlightCoverage: 0.03,
            averageLuminance: 0.54,
            averageSaturation: 0.16,
            isLowKey: false,
            isHighKey: false
        )

        let adjustment = pipeline.diagnosticWhiteBalanceAdjustment(for: analysis)

        XCTAssertNotNil(adjustment)
        XCTAssertEqual(adjustment?.usesHighlights, false)
    }

    func testLandscapeWhiteBalanceUsesCloudyHighlightsAtLowerCoverageAndStaysGentler() {
        let pipeline = makePipeline()
        let analysis = PhotoAnalysis(
            averageRed: 0.60,
            averageGreen: 0.54,
            averageBlue: 0.50,
            highlightRed: 0.84,
            highlightGreen: 0.85,
            highlightBlue: 0.89,
            highlightCoverage: 0.06,
            averageLuminance: 0.58,
            averageSaturation: 0.14,
            isLowKey: false,
            isHighKey: false
        )

        let landscapeAdjustment = pipeline.diagnosticWhiteBalanceAdjustment(for: analysis, scene: .landscape)
        let genericAdjustment = pipeline.diagnosticWhiteBalanceAdjustment(for: analysis, scene: .generic)

        XCTAssertNotNil(landscapeAdjustment)
        XCTAssertEqual(landscapeAdjustment?.usesHighlights, true)
        XCTAssertNotNil(genericAdjustment)
        XCTAssertEqual(genericAdjustment?.usesHighlights, false)
        XCTAssertLessThan(abs(landscapeAdjustment?.temperatureOffset ?? 0.0), abs(genericAdjustment?.temperatureOffset ?? 0.0))
    }

    func testSelectiveSharpenProducesMeasurableDeltaAgainstLegacySharpen() throws {
        let pipeline = makePipeline()
        let image = try makeRepoPortraitSampleImage()
        let selective = pipeline.diagnosticSelectiveSharpen(
            image: image,
            amount: 0.18,
            radius: 0.42,
            edgeBlurRadius: 5.5
        )
        let legacy = pipeline.diagnosticLegacySharpen(image: image, amount: 0.18)

        let deltaImage = selective.applyingFilter(
            "CIDifferenceBlendMode",
            parameters: [kCIInputBackgroundImageKey: legacy]
        )
        let deltaStats = try averageRGBA(for: deltaImage, crop: CGRect(x: 0, y: 0, width: image.extent.width, height: image.extent.height))
        let delta = deltaStats.r + deltaStats.g + deltaStats.b

        XCTAssertGreaterThan(delta, 0.0005)
    }

    private func makePipeline() -> LocalPhotoPipeline {
        let context = CIContext()
        return LocalPhotoPipeline(context: context, upscaleEngine: UpscaleEngine(context: context))
    }

    private func makeRepoPortraitSampleImage() throws -> CIImage {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let imagesDirectory = packageRoot.appendingPathComponent("images", isDirectory: true)
        let candidates = [
            imagesDirectory.appendingPathComponent("PHOTO-2026-03-18-22-18-19 2.jpg"),
            imagesDirectory.appendingPathComponent("PHOTO-2026-03-18-22-18-19 5.jpg")
        ]

        guard let inputURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let image = CIImage(contentsOf: inputURL, options: [.applyOrientationProperty: true]) else {
            throw XCTSkip("Portrait sample image not available in this environment")
        }

        return image
    }

    private func averageRGBA(for image: CIImage, crop: CGRect) throws -> (r: Double, g: Double, b: Double, a: Double) {
        let context = CIContext()
        let extent = crop.integral
        let filter = CIFilter.areaAverage()
        filter.inputImage = image.cropped(to: extent)
        filter.extent = extent

        guard let outputImage = filter.outputImage else {
            throw NSError(domain: "LocalPhotoPipelineTests", code: 1)
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
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
