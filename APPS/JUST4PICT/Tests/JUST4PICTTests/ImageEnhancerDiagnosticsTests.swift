import XCTest
import CoreImage
import AppKit
@testable import JUST4PICT

final class ImageEnhancerDiagnosticsTests: XCTestCase {
    private let longBenchmarkEnvironmentKey = "JUST4PICT_RUN_LONG_BENCHMARKS"

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

    func testPortraitProBaselineStaysWithinCurrentReferenceWindow() throws {
        let inputURL = try primarySampleImageURL()
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw XCTSkip("Sample image not available in this environment")
        }

        let enhancer = ImageEnhancer()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        try enhancer.enhance(
            inputURL: inputURL,
            outputURL: outputURL,
            preset: .portrait,
            quality: 1.0,
            format: .png
        )

        defer { try? FileManager.default.removeItem(at: outputURL) }

        let outputStats = try averageRGBA(for: outputURL)
        let faceStats = try averageRGBA(for: outputURL, normalizedCrop: CGRect(x: 0.28, y: 0.32, width: 0.44, height: 0.44))

        XCTAssertGreaterThan(outputStats.r, 0.57)
        XCTAssertLessThan(outputStats.r, 0.64)
        XCTAssertGreaterThan(outputStats.g, 0.54)
        XCTAssertLessThan(outputStats.g, 0.60)
        XCTAssertGreaterThan(outputStats.b, 0.51)
        XCTAssertLessThan(outputStats.b, 0.57)

        XCTAssertGreaterThan(faceStats.r, 0.56)
        XCTAssertLessThan(faceStats.r, 0.70)
        XCTAssertGreaterThan(faceStats.g, 0.46)
        XCTAssertLessThan(faceStats.g, 0.62)
        XCTAssertGreaterThan(faceStats.b, 0.38)
        XCTAssertLessThan(faceStats.b, 0.56)
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

    func testProcessesHundredImageLocalBatchUsingRealRepoSamples() throws {
        let sourceSamples = try sampleImageURLs()
        guard !sourceSamples.isEmpty else {
            throw XCTSkip("No sample images available in this environment")
        }

        let repeatedInputs = (0..<100).map { sourceSamples[$0 % sourceSamples.count] }
        let enhancer = ImageEnhancer()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("just4pict-batch-100-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let startedAt = Date()
        var outputs: [URL] = []

        defer {
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        for (index, inputURL) in repeatedInputs.enumerated() {
            let outputURL = outputDirectory.appendingPathComponent(String(format: "%03d-%@.png", index, inputURL.deletingPathExtension().lastPathComponent))
            try enhancer.enhance(
                inputURL: inputURL,
                outputURL: outputURL,
                preset: .auto,
                quality: 1.0,
                format: .png
            )
            outputs.append(outputURL)
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        XCTAssertEqual(outputs.count, 100)
        XCTAssertTrue(outputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        print(String(format: "QA_BATCH_100 duration=%.2fs outputs=%d", elapsed, outputs.count))
    }

    func testProcessesThousandImageLocalBatchUsingRealRepoSamples() throws {
        try requireLongBenchmarksEnabled()

        let sourceSamples = try sampleImageURLs()
        guard !sourceSamples.isEmpty else {
            throw XCTSkip("No sample images available in this environment")
        }

        let repeatedInputs = (0..<1000).map { sourceSamples[$0 % sourceSamples.count] }
        let enhancer = ImageEnhancer()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("just4pict-batch-1000-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let startedAt = Date()
        var outputs: [URL] = []

        defer {
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        for (index, inputURL) in repeatedInputs.enumerated() {
            let outputURL = outputDirectory.appendingPathComponent(String(format: "%04d-%@.png", index, inputURL.deletingPathExtension().lastPathComponent))
            try enhancer.enhance(
                inputURL: inputURL,
                outputURL: outputURL,
                preset: .auto,
                quality: 1.0,
                format: .png
            )
            outputs.append(outputURL)
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        XCTAssertEqual(outputs.count, 1000)
        XCTAssertTrue(outputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        print(String(format: "QA_BATCH_1000 duration=%.2fs outputs=%d", elapsed, outputs.count))
    }

    func testMeasuresPresetLatencyAcrossRealRepoSamples() throws {
        try requireLongBenchmarksEnabled()

        let sourceSamples = try sampleImageURLs()
        guard !sourceSamples.isEmpty else {
            throw XCTSkip("No sample images available in this environment")
        }

        let enhancer = ImageEnhancer()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("just4pict-preset-bench-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        for preset in EnhancementPreset.allCases {
            var totalDuration: TimeInterval = 0
            var processedCount = 0

            for inputURL in sourceSamples {
                let baseName = inputURL.deletingPathExtension().lastPathComponent
                let outputURL = outputDirectory.appendingPathComponent("\(preset.rawValue.lowercased())-\(baseName).png")
                try? FileManager.default.removeItem(at: outputURL)

                let startedAt = Date()
                try enhancer.enhance(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    preset: preset,
                    quality: 1.0,
                    format: .png
                )
                totalDuration += Date().timeIntervalSince(startedAt)
                processedCount += 1
                XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
            }

            let averageDuration = totalDuration / Double(processedCount)
            print(String(format: "BENCH_PRESET preset=%@ samples=%d total=%.2fs avg=%.3fs", preset.rawValue, processedCount, totalDuration, averageDuration))
        }

        let sizeBuckets = sizeBucketsForSamples(sourceSamples, enhancer: enhancer)
        for bucket in sizeBuckets.sorted(by: { $0.key < $1.key }) {
            let durations = try bucket.value.map { inputURL -> TimeInterval in
                let baseName = inputURL.deletingPathExtension().lastPathComponent
                let outputURL = outputDirectory.appendingPathComponent("auto-\(bucket.key)-\(baseName).png")
                try? FileManager.default.removeItem(at: outputURL)

                let startedAt = Date()
                try enhancer.enhance(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    preset: .auto,
                    quality: 1.0,
                    format: .png
                )
                XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
                return Date().timeIntervalSince(startedAt)
            }

            let totalDuration = durations.reduce(0, +)
            let averageDuration = totalDuration / Double(durations.count)
            print(String(format: "BENCH_SIZE bucket=%@ samples=%d total=%.2fs avg=%.3fs", bucket.key, durations.count, totalDuration, averageDuration))
        }
    }

    func testWritesPortraitFaceRestoreSampleForQuickQA() throws {
        let inputURL = try primarySampleImageURL()
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw XCTSkip("Sample image not available in this environment")
        }

        let enhancer = ImageEnhancer()
        let outputDirectory = try sampleOutputDirectory()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let outputURL = outputDirectory.appendingPathComponent("\(baseName)-portrait-face-restore-sample.png")
        try? FileManager.default.removeItem(at: outputURL)

        try enhancer.enhance(
            inputURL: inputURL,
            outputURL: outputURL,
            preset: .portrait,
            quality: 1.0,
            format: .png,
            faceRestoreStrength: 0.65
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        print("QA_OUTPUT \(outputURL.path)")
    }

    func testDetectsDocumentSceneFromRealRepoSample() throws {
        let inputURL = try sampleImageURL(named: "image_doc_orig.jpeg")
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw XCTSkip("Document sample image not available in this environment")
        }

        let enhancer = ImageEnhancer()
        let detectedScene = enhancer.detectSceneType(inputURL: inputURL)
        XCTAssertEqual(detectedScene, .document)
    }

    func testDocumentAutoKeepsBrightBackgroundOnRealRepoSample() throws {
        let inputURL = try sampleImageURL(named: "image_doc_orig.jpeg")
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw XCTSkip("Document sample image not available in this environment")
        }

        let enhancer = ImageEnhancer()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        try enhancer.enhance(
            inputURL: inputURL,
            outputURL: outputURL,
            preset: .auto,
            quality: 1.0,
            format: .png
        )

        defer { try? FileManager.default.removeItem(at: outputURL) }

        let topLeft = try averageRGBA(for: outputURL, normalizedCrop: CGRect(x: 0.0, y: 0.82, width: 0.18, height: 0.18))
        XCTAssertGreaterThan(topLeft.r, 0.82)
        XCTAssertGreaterThan(topLeft.g, 0.82)
        XCTAssertGreaterThan(topLeft.b, 0.82)
    }

    func testDetectsEcommerceSceneFromRealRepoSample() throws {
        let inputURL = try sampleImageURL(named: "image_product_orig.jpeg")
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw XCTSkip("Ecommerce sample image not available in this environment")
        }

        let enhancer = ImageEnhancer()
        let detectedScene = enhancer.detectSceneType(inputURL: inputURL)
        XCTAssertEqual(detectedScene, .ecommerce)
    }

    func testWritesDocumentAndEcommerceSamplesForQuickQA() throws {
        let sampleNames = ["image_doc_orig.jpeg", "image_product_orig.jpeg"]
        let enhancer = ImageEnhancer()
        let outputDirectory = try sampleOutputDirectory()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for sampleName in sampleNames {
            let inputURL = try sampleImageURL(named: sampleName)
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                throw XCTSkip("Sample image \(sampleName) not available in this environment")
            }

            let baseName = inputURL.deletingPathExtension().lastPathComponent
            let outputURL = outputDirectory.appendingPathComponent("\(baseName)-auto-sample.png")
            try? FileManager.default.removeItem(at: outputURL)

            try enhancer.enhance(
                inputURL: inputURL,
                outputURL: outputURL,
                preset: .auto,
                quality: 1.0,
                format: .png
            )

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
            print("QA_OUTPUT \(outputURL.path)")
        }
    }

    func testEcommerceAutoPlacesDetectedProductOnWhiteBackground() throws {
        let inputURL = try sampleImageURL(named: "image_product_orig.jpeg")
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw XCTSkip("Ecommerce sample image not available in this environment")
        }

        let enhancer = ImageEnhancer()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        try enhancer.enhance(
            inputURL: inputURL,
            outputURL: outputURL,
            preset: .auto,
            quality: 1.0,
            format: .png
        )

        defer { try? FileManager.default.removeItem(at: outputURL) }

        let topLeft = try averageRGBA(for: outputURL, normalizedCrop: CGRect(x: 0.0, y: 0.82, width: 0.18, height: 0.18))
        let topRight = try averageRGBA(for: outputURL, normalizedCrop: CGRect(x: 0.82, y: 0.82, width: 0.18, height: 0.18))
        let bottomLeft = try averageRGBA(for: outputURL, normalizedCrop: CGRect(x: 0.0, y: 0.0, width: 0.18, height: 0.18))
        let bottomRight = try averageRGBA(for: outputURL, normalizedCrop: CGRect(x: 0.82, y: 0.0, width: 0.18, height: 0.18))

        for sample in [topLeft, topRight, bottomLeft, bottomRight] {
            XCTAssertGreaterThan(sample.r, 0.90)
            XCTAssertGreaterThan(sample.g, 0.90)
            XCTAssertGreaterThan(sample.b, 0.90)
        }
    }

    func testPreviewAndExportStayMeasurablyAlignedForSameRecipeInputs() throws {
        let inputURL = try primarySampleImageURL()
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw XCTSkip("Sample image not available in this environment")
        }

        let enhancer = ImageEnhancer()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        let tuning = AIEnhancementTuning(
            shadowAmount: 0.30,
            highlightAmount: 0.85,
            vibrance: 0.12,
            sharpen: 0.18,
            sharpenRadius: 0.45,
            contrast: 1.01,
            saturation: 1.02,
            exposureEV: 0.02
        )

        let preview = try enhancer.enhancedPreviewImage(
            inputURL: inputURL,
            preset: .portrait,
            tuning: tuning,
            upscaleTargetLongSide: 2200
        )

        try enhancer.enhance(
            inputURL: inputURL,
            outputURL: outputURL,
            preset: .portrait,
            quality: 1.0,
            format: .png,
            upscaleTargetLongSide: 2200,
            tuning: tuning
        )

        defer { try? FileManager.default.removeItem(at: outputURL) }

        guard let previewCG = preview.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            XCTFail("Preview image should provide a CGImage")
            return
        }

        let previewRep = NSBitmapImageRep(cgImage: previewCG)
        guard let previewPNG = previewRep.representation(using: .png, properties: [:]) else {
            XCTFail("Preview should be encodable as PNG")
            return
        }

        let previewTempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try previewPNG.write(to: previewTempURL)
        defer { try? FileManager.default.removeItem(at: previewTempURL) }

        let previewStats = try averageRGBA(for: previewTempURL)
        let exportStats = try averageRGBA(for: outputURL)

        let delta = abs(previewStats.r - exportStats.r)
            + abs(previewStats.g - exportStats.g)
            + abs(previewStats.b - exportStats.b)
            + abs(previewStats.a - exportStats.a)

        XCTAssertLessThan(delta, 0.08, "Preview and export should stay visually aligned for the same recipe inputs")
    }

    func testFaceRestoreAddsContainedChangeOnPortraitSample() throws {
        let inputURL = try primarySampleImageURL()
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw XCTSkip("Sample image not available in this environment")
        }

        let enhancer = ImageEnhancer()
        let baselineURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let restoredURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        try enhancer.enhance(
            inputURL: inputURL,
            outputURL: baselineURL,
            preset: .portrait,
            quality: 1.0,
            format: .png
        )

        try enhancer.enhance(
            inputURL: inputURL,
            outputURL: restoredURL,
            preset: .portrait,
            quality: 1.0,
            format: .png,
            faceRestoreStrength: 0.65
        )

        defer {
            try? FileManager.default.removeItem(at: baselineURL)
            try? FileManager.default.removeItem(at: restoredURL)
        }

        let faceRegion = CGRect(x: 0.28, y: 0.32, width: 0.44, height: 0.44)
        let baselineStats = try averageRGBA(for: baselineURL, normalizedCrop: faceRegion)
        let restoredStats = try averageRGBA(for: restoredURL, normalizedCrop: faceRegion)
        let delta = abs(baselineStats.r - restoredStats.r)
            + abs(baselineStats.g - restoredStats.g)
            + abs(baselineStats.b - restoredStats.b)
            + abs(baselineStats.a - restoredStats.a)

        XCTAssertGreaterThan(delta, 0.001, "Face restore should produce some measurable facial adjustment")
        XCTAssertLessThan(delta, 0.05, "Face restore should remain conservative against the current PRO baseline")
    }

    func testExportProfileWebResizesLargeImageOnWrite() throws {
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        try makeSolidImage(width: 2400, height: 1200).pngWrite(to: inputURL)
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let enhancer = ImageEnhancer()
        try enhancer.enhance(
            inputURL: inputURL,
            outputURL: outputURL,
            preset: .auto,
            quality: 0.9,
            format: .jpg,
            exportProfile: .web
        )

        let writtenSize = try pixelSize(for: outputURL)
        XCTAssertEqual(writtenSize.width, 1600)
        XCTAssertEqual(writtenSize.height, 800)
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

    private func sampleImageURL(named fileName: String) throws -> URL {
        let imagesDirectory = try imagesDirectoryURL()
        return imagesDirectory.appendingPathComponent(fileName)
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

    private func requireLongBenchmarksEnabled() throws {
        let value = ProcessInfo.processInfo.environment[longBenchmarkEnvironmentKey]
        guard value == "1" else {
            throw XCTSkip("Set \(longBenchmarkEnvironmentKey)=1 to run long local benchmarks")
        }
    }

    private func sizeBucketsForSamples(_ inputURLs: [URL], enhancer: ImageEnhancer) -> [String: [URL]] {
        var buckets: [String: [URL]] = [:]
        for inputURL in inputURLs {
            let pixelSize = enhancer.pixelSize(for: inputURL) ?? .zero
            let bucket = sizeBucketLabel(for: pixelSize)
            buckets[bucket, default: []].append(inputURL)
        }
        return buckets
    }

    private func sizeBucketLabel(for size: CGSize) -> String {
        let longSide = max(size.width, size.height)
        switch longSide {
        case ..<1200:
            return "small"
        case ..<2500:
            return "medium"
        default:
            return "large"
        }
    }

    private func averageRGBA(
        for url: URL,
        normalizedCrop: CGRect? = nil
    ) throws -> (r: Double, g: Double, b: Double, a: Double) {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw XCTSkip("Could not load image at \(url.path)")
        }

        let extent = image.extent.integral
        let sampleExtent: CGRect
        if let normalizedCrop {
            let cropped = CGRect(
                x: extent.minX + (extent.width * normalizedCrop.minX),
                y: extent.minY + (extent.height * normalizedCrop.minY),
                width: extent.width * normalizedCrop.width,
                height: extent.height * normalizedCrop.height
            ).integral
            sampleExtent = cropped.intersection(extent)
        } else {
            sampleExtent = extent
        }
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = sampleExtent

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

    private func pixelSize(for url: URL) throws -> (width: Int, height: Int) {
        guard let image = NSImage(contentsOf: url) else {
            throw XCTSkip("Could not load image at \(url.path)")
        }
        guard let rep = image.representations.first else {
            throw XCTSkip("No bitmap representation available for \(url.path)")
        }
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    private func makeSolidImage(width: Int, height: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor(calibratedRed: 0.85, green: 0.86, blue: 0.88, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        image.unlockFocus()
        return image
    }
}

private extension NSImage {
    func pngWrite(to url: URL) throws {
        guard let tiffData = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "JUST4PICTTests", code: 1)
        }
        try pngData.write(to: url)
    }
}
