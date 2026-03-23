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

    func testSelectiveSharpenLandscapeHazeIncreasesEdgeEnergy() throws {
        let pipeline = makePipeline()
        let image = makeSyntheticHazyLandscapeImage()
        let selective = pipeline.diagnosticSelectiveSharpen(
            image: image,
            amount: 0.14,
            radius: 0.48,
            edgeBlurRadius: 3.2
        )
        let legacy = pipeline.diagnosticLegacySharpen(image: image, amount: 0.14)

        let before = try edgeEnergy(for: image, crop: image.extent)
        let after = try edgeEnergy(for: selective, crop: image.extent)
        let selectiveDelta = try differenceMagnitude(selective, image, crop: image.extent)
        let legacyDelta = try differenceMagnitude(legacy, image, crop: image.extent)

        XCTAssertGreaterThanOrEqual(after, before * 0.95)
        XCTAssertLessThanOrEqual(selectiveDelta, legacyDelta * 1.05)
    }

    func testSelectiveSharpenLandscapeVegetationDetailIncreasesHighFrequencyContent() throws {
        let pipeline = makePipeline()
        let image = makeSyntheticVegetationLandscapeImage()
        let selective = pipeline.diagnosticSelectiveSharpen(
            image: image,
            amount: 0.18,
            radius: 0.50,
            edgeBlurRadius: 3.2
        )
        let legacy = pipeline.diagnosticLegacySharpen(image: image, amount: 0.18)

        let before = try edgeEnergy(for: image, crop: image.extent)
        let after = try edgeEnergy(for: selective, crop: image.extent)
        let selectiveDelta = try differenceMagnitude(selective, image, crop: image.extent)
        let legacyDelta = try differenceMagnitude(legacy, image, crop: image.extent)

        XCTAssertGreaterThanOrEqual(after, before * 0.95)
        XCTAssertGreaterThan(selectiveDelta, 0.002)
        XCTAssertGreaterThan(selectiveDelta, legacyDelta * 0.60)
    }

    func testSelectiveSharpenDenseTextProtectsFlatAreasBetterThanLegacy() throws {
        let pipeline = makePipeline()
        let image = makeSyntheticDenseTextLandscapeImage()
        let selective = pipeline.diagnosticSelectiveSharpen(
            image: image,
            amount: 0.22,
            radius: 0.50,
            edgeBlurRadius: 3.2
        )
        let legacy = pipeline.diagnosticLegacySharpen(image: image, amount: 0.22)

        let flatCrop = CGRect(x: 0, y: 210, width: image.extent.width, height: 46)
        let textCrop = CGRect(x: 0, y: 0, width: image.extent.width, height: 150)

        let selectiveFlatDelta = try differenceMagnitude(selective, image, crop: flatCrop)
        let legacyFlatDelta = try differenceMagnitude(legacy, image, crop: flatCrop)
        let selectiveTextDelta = try differenceMagnitude(selective, image, crop: textCrop)

        XCTAssertLessThanOrEqual(selectiveFlatDelta, legacyFlatDelta)
        XCTAssertGreaterThan(selectiveTextDelta, selectiveFlatDelta * 2.0)
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

    private func edgeEnergy(for image: CIImage, crop: CGRect) throws -> Double {
        let edges = image
            .cropped(to: crop.integral)
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.2])
        let stats = try averageRGBA(for: edges, crop: crop)
        return stats.r + stats.g + stats.b
    }

    private func differenceMagnitude(_ lhs: CIImage, _ rhs: CIImage, crop: CGRect) throws -> Double {
        let diff = lhs.applyingFilter(
            "CIDifferenceBlendMode",
            parameters: [kCIInputBackgroundImageKey: rhs]
        )
        let stats = try averageRGBA(for: diff, crop: crop)
        return stats.r + stats.g + stats.b
    }

    private func makeSyntheticHazyLandscapeImage() -> CIImage {
        let extent = CGRect(x: 0, y: 0, width: 512, height: 320)

        let softBase = CIImage(color: CIColor(red: 0.62, green: 0.71, blue: 0.76, alpha: 1.0))
            .cropped(to: extent)

        let bands = CIImage(
            color: .init(red: 0.58, green: 0.66, blue: 0.70, alpha: 1.0)
        )
        let horizontalBand = bands
            .cropped(to: CGRect(x: 0, y: 130, width: 512, height: 26))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 10.0)
            .cropped(to: extent)

        let hazeNoise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 0.20,
                kCIInputBrightnessKey: 0.50
            ])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.08)
            ])

        return horizontalBand
            .composited(over: softBase)
            .composited(over: hazeNoise)
            .cropped(to: extent)
    }

    private func makeSyntheticVegetationLandscapeImage() -> CIImage {
        let extent = CGRect(x: 0, y: 0, width: 512, height: 320)

        let sky = CIImage(color: CIColor(red: 0.72, green: 0.82, blue: 0.92, alpha: 1.0))
            .cropped(to: CGRect(x: 0, y: 180, width: 512, height: 140))
        let ground = CIImage(color: CIColor(red: 0.26, green: 0.43, blue: 0.21, alpha: 1.0))
            .cropped(to: CGRect(x: 0, y: 0, width: 512, height: 180))

        let base = sky.composited(over: ground).cropped(to: extent)

        let leafNoise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .cropped(to: CGRect(x: 0, y: 0, width: 512, height: 170))
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 1.15
            ])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.08, y: 0.02, z: 0.01, w: 0.0),
                "inputGVector": CIVector(x: 0.18, y: 0.34, z: 0.10, w: 0.0),
                "inputBVector": CIVector(x: 0.04, y: 0.10, z: 0.03, w: 0.0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.45)
            ])

        let trunkLines = CIFilter(
            name: "CICheckerboardGenerator",
            parameters: [
                "inputCenter": CIVector(x: 0, y: 0),
                "inputColor0": CIColor(red: 0.16, green: 0.11, blue: 0.08, alpha: 1.0),
                "inputColor1": CIColor(red: 0.25, green: 0.17, blue: 0.13, alpha: 1.0),
                "inputWidth": 5.0,
                "inputSharpness": 1.0
            ]
        )!.outputImage!
            .cropped(to: CGRect(x: 0, y: 0, width: 512, height: 170))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.22, y: 0.0, z: 0.0, w: 0.0),
                "inputGVector": CIVector(x: 0.14, y: 0.0, z: 0.0, w: 0.0),
                "inputBVector": CIVector(x: 0.10, y: 0.0, z: 0.0, w: 0.0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.30)
            ])

        return leafNoise
            .composited(over: trunkLines)
            .composited(over: base)
            .cropped(to: extent)
    }

    private func makeSyntheticDenseTextLandscapeImage() -> CIImage {
        let extent = CGRect(x: 0, y: 0, width: 512, height: 320)
        let whiteBase = CIImage(color: CIColor(red: 0.97, green: 0.97, blue: 0.96, alpha: 1.0))
            .cropped(to: extent)

        let subtleNoise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 0.20,
                kCIInputBrightnessKey: 0.50
            ])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.02, y: 0.0, z: 0.0, w: 0.0),
                "inputGVector": CIVector(x: 0.02, y: 0.0, z: 0.0, w: 0.0),
                "inputBVector": CIVector(x: 0.02, y: 0.0, z: 0.0, w: 0.0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.18)
            ])

        let textBlock = CIFilter(
            name: "CICheckerboardGenerator",
            parameters: [
                "inputCenter": CIVector(x: 0, y: 0),
                "inputColor0": CIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1.0),
                "inputColor1": CIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0),
                "inputWidth": 3.0,
                "inputSharpness": 1.0
            ]
        )!.outputImage!
            .cropped(to: CGRect(x: 0, y: 0, width: 512, height: 150))
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 1.0,
                kCIInputBrightnessKey: -0.48
            ])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.65)
            ])

        return textBlock
            .composited(over: subtleNoise.composited(over: whiteBase))
            .cropped(to: extent)
    }
}
