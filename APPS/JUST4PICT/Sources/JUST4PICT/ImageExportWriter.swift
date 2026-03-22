import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit
import ImageIO

// CORRECCIÓN — ImageExportWriter
//
// Problema original:
//   write(image: CIImage) aplicaba applyExportResizeIfNeeded sobre la CIImage
//   y luego llamaba a write(cgImage:) que volvía a llamar resizedCGImageIfNeeded
//   sobre el CGImage resultante. El guard de resizedCGImageIfNeeded normalmente
//   lo evitaba, pero el redondeo de .integral podía hacer que currentLongSide
//   fuera targetLongSide+1, disparando un segundo resize real.
//
// Corrección:
//   Se extrae commitCGImage como método privado que solo gestiona
//   el presupuesto de bytes y la escritura final, sin ninguna lógica de resize.
//
//   - write(image: CIImage)  → resize en espacio CIImage → render → commitCGImage
//   - write(image: NSImage)  → get CGImage → resize en espacio CGImage → commitCGImage
//
//   El resize ocurre exactamente una vez por path. No hay doble comprobación.

final class ImageExportWriter {
    private let context: CIContext

    init(context: CIContext = CIContext(options: [.cacheIntermediates: false])) {
        self.context = context
    }

    // ── CIImage path ──────────────────────────────────────────────────────────
    // Resize en espacio CIImage (eficiente, evita renderizar píxeles innecesarios)
    // y luego commit sin segundo intento de resize.

    func write(
        image: CIImage,
        sourceURL: URL? = nil,
        to outputURL: URL,
        format: OutputFormat,
        quality: Double,
        exportProfile: ExportProfile,
        preset: EnhancementPreset
    ) throws {
        let resizedImage = applyExportResizeIfNeeded(
            image: image,
            targetLongSide: exportProfile.targetLongSide(for: preset)
        )
        let extent = resizedImage.extent.integral
        guard let cgImage = context.createCGImage(resizedImage, from: extent) else {
            throw ImageEnhancerError.cannotRenderImage(sourceURL ?? outputURL)
        }
        try commitCGImage(cgImage, to: outputURL, format: format, quality: quality, exportProfile: exportProfile)
    }

    // ── NSImage path ──────────────────────────────────────────────────────────
    // Resize en espacio CGImage y luego commit.

    func write(
        image: NSImage,
        sourceURL: URL? = nil,
        to outputURL: URL,
        format: OutputFormat,
        quality: Double,
        exportProfile: ExportProfile,
        preset: EnhancementPreset
    ) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageEnhancerError.cannotRenderImage(sourceURL ?? outputURL)
        }
        let finalCGImage = try resizedCGImageIfNeeded(
            cgImage,
            sourceURL: sourceURL ?? outputURL,
            targetLongSide: exportProfile.targetLongSide(for: preset)
        )
        try commitCGImage(finalCGImage, to: outputURL, format: format, quality: quality, exportProfile: exportProfile)
    }

    // ── Commit (sin resize) ───────────────────────────────────────────────────
    // Recibe un CGImage ya en las dimensiones finales correctas.
    // Solo gestiona el presupuesto de bytes y la escritura.

    private func commitCGImage(
        _ cgImage: CGImage,
        to outputURL: URL,
        format: OutputFormat,
        quality: Double,
        exportProfile: ExportProfile
    ) throws {
        if let byteBudget = exportProfile.targetByteBudget,
           format.supportsLossyQuality {
            let minimumQuality = exportProfile.minimumLossyQuality ?? 0.58
            let requestedQuality = min(max(quality, 0.1), 1.0)
            let qualityCandidates = lossyQualityCandidates(
                startingAt: requestedQuality,
                minimum: minimumQuality
            )

            for candidateQuality in qualityCandidates {
                try writeCGImage(cgImage, to: outputURL, format: format, quality: candidateQuality)
                let fileSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
                if fileSize <= byteBudget { return }
            }

            let finalSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
            if finalSize <= byteBudget { return }
            throw ImageEnhancerError.cannotFitByteBudget(outputURL, byteBudget)
        }

        try writeCGImage(cgImage, to: outputURL, format: format, quality: quality)
    }

    // ── Resize helpers ────────────────────────────────────────────────────────

    private func applyExportResizeIfNeeded(image: CIImage, targetLongSide: CGFloat?) -> CIImage {
        guard let targetLongSide, targetLongSide > 0 else {
            return image
        }

        let extent = image.extent.integral
        let currentLongSide = max(extent.width, extent.height)
        guard currentLongSide > targetLongSide else {
            return image
        }

        let scale = targetLongSide / currentLongSide
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1.0
        return (filter.outputImage ?? image).cropped(to: (filter.outputImage ?? image).extent.integral)
    }

    private func resizedCGImageIfNeeded(
        _ cgImage: CGImage,
        sourceURL: URL,
        targetLongSide: CGFloat?
    ) throws -> CGImage {
        guard let targetLongSide, targetLongSide > 0 else {
            return cgImage
        }

        let currentLongSide = CGFloat(max(cgImage.width, cgImage.height))
        guard currentLongSide > targetLongSide else {
            return cgImage
        }

        let ciImage = CIImage(cgImage: cgImage)
        let resizedImage = applyExportResizeIfNeeded(image: ciImage, targetLongSide: targetLongSide)
        let extent = resizedImage.extent.integral
        guard let resizedCGImage = context.createCGImage(resizedImage, from: extent) else {
            throw ImageEnhancerError.cannotRenderImage(sourceURL)
        }
        return resizedCGImage
    }

    // ── Write primitivo ───────────────────────────────────────────────────────

    private func writeCGImage(
        _ cgImage: CGImage,
        to outputURL: URL,
        format: OutputFormat,
        quality: Double
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            format.utTypeIdentifier,
            1,
            nil
        ) else {
            throw ImageEnhancerError.cannotCreateDestination(outputURL)
        }

        var destinationOptions: [CFString: Any] = [:]
        if format.supportsLossyQuality {
            destinationOptions[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0.1), 1.0)
        }

        CGImageDestinationAddImage(destination, cgImage, destinationOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageEnhancerError.cannotFinalizeWrite(outputURL)
        }
    }

    // ── Calidad iterativa para byte budget ────────────────────────────────────

    private func lossyQualityCandidates(startingAt start: Double, minimum: Double) -> [Double] {
        let baseSteps: [Double] = [start, 0.90, 0.84, 0.78, 0.72, 0.66, 0.62, minimum]
        var values: [Double] = []
        for step in baseSteps {
            let clamped = min(max(step, minimum), 1.0)
            if !values.contains(where: { abs($0 - clamped) < 0.0001 }) {
                values.append(clamped)
            }
        }
        return values
    }
}