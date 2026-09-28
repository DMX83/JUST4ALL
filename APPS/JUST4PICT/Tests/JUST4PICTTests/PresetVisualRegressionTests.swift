import XCTest
import CoreImage
@testable import JUST4PICT

/// Métrica de regresión visual por preset clave: mide el resultado real del pipeline local
/// (luminancia, cambio de color, energía de bordes y luminancia del borde) contra ventanas
/// calibradas para detectar regresiones gruesas (salida negra, no-op, bordes colapsados…).
final class PresetVisualRegressionTests: XCTestCase {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    private struct Metrics {
        let luma: Double
        let edgeEnergy: Double
    }

    private struct MetricsComparison {
        let input: Metrics
        let output: Metrics
        let deltaRGB: Double
        let edgeRatio: Double
        let borderLuma: Double
    }

    private struct Windows {
        let luma: ClosedRange<Double>
        let deltaRGB: ClosedRange<Double>
        let edgeRatio: ClosedRange<Double>
        let borderLuma: ClosedRange<Double>?
    }

    // Ventanas calibradas contra el pipeline actual (28-sep). Tolerancias amplias: el objetivo
    // es cazar regresiones gruesas (salida negra, no-op, bordes colapsados), no bloquear
    // mejoras visuales legítimas.
    private static let windows: [EnhancementPreset: Windows] = [
        // base: outLuma 0.628 · delta 0.034 · edge 0.975
        .portrait: Windows(
            luma: 0.35...0.80,
            deltaRGB: 0.005...0.20,
            edgeRatio: 0.60...2.50,
            borderLuma: nil
        ),
        // base: outLuma 0.647 · delta 0.009 · edge 0.533
        .landscape: Windows(
            luma: 0.35...0.80,
            deltaRGB: 0.002...0.20,
            edgeRatio: 0.30...1.60,
            borderLuma: nil
        ),
        // base: outLuma 0.941 · delta 0.255 · edge 0.182 · borde 0.890
        .document: Windows(
            luma: 0.70...1.00,
            deltaRGB: 0.05...0.50,
            edgeRatio: 0.05...0.80,
            borderLuma: 0.60...1.00
        ),
        // base: outLuma 0.937 · delta 0.335 · edge 0.667 · borde 1.000
        .ecommerce: Windows(
            luma: 0.70...1.00,
            deltaRGB: 0.10...0.60,
            edgeRatio: 0.30...1.60,
            borderLuma: 0.80...1.00
        )
    ]

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sampleURL(for candidates: [String]) throws -> URL {
        let root = packageRoot()
        for candidate in candidates {
            let url = root.appendingPathComponent("images/\(candidate)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        throw XCTSkip("Muestra no disponible para \(candidates.first ?? "?")")
    }

    private func metrics(for url: URL) throws -> Metrics {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw XCTSkip("No se pudo cargar \(url.lastPathComponent)")
        }
        let extent = image.extent.integral
        let average = try areaAverage(of: image, extent: extent)
        let luma = 0.2126 * average.r + 0.7152 * average.g + 0.0722 * average.b

        let edges = image.applyingFilter("CIEdges", parameters: ["inputIntensity": 1.0])
        let edgeAverage = try areaAverage(of: edges, extent: edges.extent.integral)
        let edgeEnergy = (edgeAverage.r + edgeAverage.g + edgeAverage.b) / 3.0

        return Metrics(luma: luma, edgeEnergy: edgeEnergy)
    }

    private func borderLuma(for url: URL) throws -> Double {
        let image = try XCTUnwrap(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
        let extent = image.extent.integral
        let strip = max(extent.height * 0.06, 4)
        let topStrip = CGRect(x: extent.minX, y: extent.maxY - strip, width: extent.width, height: strip)
        let average = try areaAverage(of: image, extent: topStrip)
        return 0.2126 * average.r + 0.7152 * average.g + 0.0722 * average.b
    }

    private func areaAverage(of image: CIImage, extent: CGRect) throws -> (r: Double, g: Double, b: Double, a: Double) {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = extent
        var bitmap = [UInt8](repeating: 0, count: 4)
        Self.context.render(
            filter.outputImage ?? image,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (Double(bitmap[0]) / 255.0, Double(bitmap[1]) / 255.0, Double(bitmap[2]) / 255.0, Double(bitmap[3]) / 255.0)
    }

    private func average(for url: URL) throws -> (r: Double, g: Double, b: Double, a: Double) {
        let image = try XCTUnwrap(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
        return try areaAverage(of: image, extent: image.extent.integral)
    }

    private func compare(input: URL, output: URL) throws -> MetricsComparison {
        let inputMetrics = try metrics(for: input)
        let outputMetrics = try metrics(for: output)

        let inputAverage = try average(for: input)
        let outputAverage = try average(for: output)

        let deltaRGB = (abs(outputAverage.r - inputAverage.r)
            + abs(outputAverage.g - inputAverage.g)
            + abs(outputAverage.b - inputAverage.b)) / 3.0
        let edgeRatio = outputMetrics.edgeEnergy / max(inputMetrics.edgeEnergy, 0.000_001)

        return MetricsComparison(
            input: inputMetrics,
            output: outputMetrics,
            deltaRGB: deltaRGB,
            edgeRatio: edgeRatio,
            borderLuma: try borderLuma(for: output)
        )
    }

    private func runRegression(
        preset: EnhancementPreset,
        candidates: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let input = try sampleURL(for: candidates)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("j4pict-regression-\(preset.rawValue)-\(UUID().uuidString)")
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: output) }

        let enhancer = ImageEnhancer()
        try enhancer.enhance(
            inputURL: input,
            outputURL: output,
            preset: preset,
            quality: 1.0,
            format: .png
        )

        let comparison = try compare(input: input, output: output)
        let window = try XCTUnwrap(Self.windows[preset], file: file, line: line)

        print("REGRESSION preset=\(preset.rawValue) inputLuma=\(comparison.input.luma) outputLuma=\(comparison.output.luma) deltaRGB=\(comparison.deltaRGB) edgeRatio=\(comparison.edgeRatio) borderLuma=\(comparison.borderLuma)")

        XCTAssertTrue(window.luma.contains(comparison.output.luma), "[\(preset.rawValue)] luma fuera de ventana: \(comparison.output.luma)", file: file, line: line)
        XCTAssertTrue(window.deltaRGB.contains(comparison.deltaRGB), "[\(preset.rawValue)] deltaRGB fuera de ventana: \(comparison.deltaRGB)", file: file, line: line)
        XCTAssertTrue(window.edgeRatio.contains(comparison.edgeRatio), "[\(preset.rawValue)] edgeRatio fuera de ventana: \(comparison.edgeRatio)", file: file, line: line)
        if let borderWindow = window.borderLuma {
            XCTAssertTrue(borderWindow.contains(comparison.borderLuma), "[\(preset.rawValue)] borderLuma fuera de ventana: \(comparison.borderLuma)", file: file, line: line)
        }
    }

    func testPortraitRegressionWindow() throws {
        try runRegression(
            preset: .portrait,
            candidates: ["PHOTO-2026-03-18-22-18-19 2.jpg", "PHOTO-2026-03-18-22-18-19 5.jpg"]
        )
    }

    func testLandscapeRegressionWindow() throws {
        try runRegression(preset: .landscape, candidates: ["image_paisaje_orig.jpeg"])
    }

    func testDocumentRegressionWindow() throws {
        try runRegression(preset: .document, candidates: ["images_document_orig.jpeg"])
    }

    func testEcommerceRegressionWindow() throws {
        try runRegression(preset: .ecommerce, candidates: ["image_commerce_orig.jpeg"])
    }
}
