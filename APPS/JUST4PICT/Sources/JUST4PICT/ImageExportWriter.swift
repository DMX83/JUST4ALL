import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit
import ImageIO

final class ImageExportWriter {
    private let context: CIContext

    init(context: CIContext = CIContext(options: [.cacheIntermediates: false])) {
        self.context = context
    }

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

        try write(
            cgImage: cgImage,
            to: outputURL,
            format: format,
            quality: quality,
            exportProfile: exportProfile,
            preset: preset
        )
    }

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

        try write(
            cgImage: cgImage,
            to: outputURL,
            format: format,
            quality: quality,
            exportProfile: exportProfile,
            preset: preset
        )
    }

    private func write(
        cgImage: CGImage,
        to outputURL: URL,
        format: OutputFormat,
        quality: Double,
        exportProfile: ExportProfile,
        preset: EnhancementPreset
    ) throws {
        let finalCGImage = try resizedCGImageIfNeeded(
            cgImage,
            sourceURL: outputURL,
            targetLongSide: exportProfile.targetLongSide(for: preset)
        )

        if let byteBudget = exportProfile.targetByteBudget,
           format.supportsLossyQuality {
            let minimumQuality = exportProfile.minimumLossyQuality ?? 0.58
            let requestedQuality = min(max(quality, 0.1), 1.0)
            let qualityCandidates = lossyQualityCandidates(
                startingAt: requestedQuality,
                minimum: minimumQuality
            )

            for candidateQuality in qualityCandidates {
                try writeCGImage(
                    finalCGImage,
                    to: outputURL,
                    format: format,
                    quality: candidateQuality
                )

                let fileSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
                if fileSize <= byteBudget {
                    return
                }
            }

            let finalSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
            if finalSize <= byteBudget {
                return
            }
            throw ImageEnhancerError.cannotFitByteBudget(outputURL, byteBudget)
        }

        try writeCGImage(finalCGImage, to: outputURL, format: format, quality: quality)
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

    private func writeCGImage(
        _ cgImage: CGImage,
        to outputURL: URL,
        format: OutputFormat,
        quality: Double
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, format.utTypeIdentifier, 1, nil) else {
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
