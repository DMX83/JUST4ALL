import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Vision

final class ProductIsolationEngine {
    private let context: CIContext

    init(context: CIContext) {
        self.context = context
    }

    func applyIfNeeded(
        to image: CIImage,
        sourceURL: URL,
        preset: EnhancementPreset,
        scene: ImageEnhancer.SceneType?
    ) -> CIImage {
        guard preset == .ecommerce || scene == .ecommerce else {
            return image
        }

        guard #available(macOS 14.0, *) else {
            return image
        }

        return isolateProductForegroundIfPossible(image: image, sourceURL: sourceURL)
    }

    @available(macOS 14.0, *)
    private func isolateProductForegroundIfPossible(image: CIImage, sourceURL: URL) -> CIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(url: sourceURL, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return image
        }

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty
        else {
            return image
        }

        let fullExtent = image.extent.integral
        if let isolatedImageBuffer = try? observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        ) {
            return centeredMaskedSubject(
                isolatedImage: CIImage(cvPixelBuffer: isolatedImageBuffer),
                canvasExtent: fullExtent
            )
        }

        guard let maskBuffer = try? observation.generateScaledMaskForImage(
            forInstances: observation.allInstances,
            from: handler
        )
        else {
            return image
        }

        let scaledMask = CIImage(cvPixelBuffer: maskBuffer).cropped(to: fullExtent)
        let softenedMask = softened(mask: scaledMask)

        guard let subjectBounds = subjectBounds(from: softenedMask) else {
            return compositedOnWhiteBackground(image: image, mask: softenedMask)
        }

        let paddedBounds = expandedBounds(subjectBounds, within: fullExtent)
        let centeredSubject = centeredSubjectImage(
            from: image,
            mask: softenedMask,
            subjectBounds: paddedBounds,
            canvasExtent: fullExtent
        )
        return centeredSubject
    }

    private func centeredMaskedSubject(isolatedImage: CIImage, canvasExtent: CGRect) -> CIImage {
        let subjectExtent = isolatedImage.extent.integral
        guard subjectExtent.width > 0, subjectExtent.height > 0 else {
            return isolatedImage
        }

        let availableWidth = canvasExtent.width * 0.82
        let availableHeight = canvasExtent.height * 0.82
        let widthScale = availableWidth / max(subjectExtent.width, 1)
        let heightScale = availableHeight / max(subjectExtent.height, 1)
        let scale = min(widthScale, heightScale, 1.0)

        let centeredTransform = CGAffineTransform(translationX: -subjectExtent.minX, y: -subjectExtent.minY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(
                x: ((canvasExtent.width - (subjectExtent.width * scale)) / 2.0) + canvasExtent.minX,
                y: ((canvasExtent.height - (subjectExtent.height * scale)) / 2.0) + canvasExtent.minY
            )

        let centeredCutout = isolatedImage.transformed(by: centeredTransform).cropped(to: canvasExtent)
        let background = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: canvasExtent)
        return centeredCutout.composited(over: background).cropped(to: canvasExtent)
    }

    private func softened(mask: CIImage) -> CIImage {
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = mask
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = clamp.outputImage ?? mask
        blur.radius = 2.2
        return (blur.outputImage ?? mask).cropped(to: mask.extent)
    }

    private func expandedBounds(_ bounds: CGRect, within extent: CGRect) -> CGRect {
        let expanded = bounds.insetBy(dx: -bounds.width * 0.08, dy: -bounds.height * 0.08)
        return expanded.intersection(extent).integral
    }

    private func centeredSubjectImage(
        from image: CIImage,
        mask: CIImage,
        subjectBounds: CGRect,
        canvasExtent: CGRect
    ) -> CIImage {
        let subjectImage = image.cropped(to: subjectBounds)
        let subjectMask = mask.cropped(to: subjectBounds)

        let availableWidth = canvasExtent.width * 0.82
        let availableHeight = canvasExtent.height * 0.82
        let widthScale = availableWidth / max(subjectBounds.width, 1)
        let heightScale = availableHeight / max(subjectBounds.height, 1)
        let scale = min(widthScale, heightScale, 1.0)

        let centeredTransform = CGAffineTransform(translationX: -subjectBounds.minX, y: -subjectBounds.minY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(
                x: ((canvasExtent.width - (subjectBounds.width * scale)) / 2.0) + canvasExtent.minX,
                y: ((canvasExtent.height - (subjectBounds.height * scale)) / 2.0) + canvasExtent.minY
            )

        let centeredImage = subjectImage.transformed(by: centeredTransform)
        let centeredMask = subjectMask.transformed(by: centeredTransform)
        return compositedOnWhiteBackground(image: centeredImage, mask: centeredMask, canvasExtent: canvasExtent)
    }

    private func compositedOnWhiteBackground(
        image: CIImage,
        mask: CIImage,
        canvasExtent: CGRect? = nil
    ) -> CIImage {
        let extent = canvasExtent ?? image.extent.integral
        let background = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = image.cropped(to: extent)
        blend.backgroundImage = background
        blend.maskImage = mask.cropped(to: extent)
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    private func subjectBounds(from mask: CIImage) -> CGRect? {
        let extent = mask.extent.integral
        guard extent.width > 0, extent.height > 0 else { return nil }

        let sampleLongSide: CGFloat = 192
        let scale = min(sampleLongSide / max(extent.width, extent.height), 1.0)
        let sampledMask: CIImage
        if scale < 1.0 {
            let downscale = CIFilter.lanczosScaleTransform()
            downscale.inputImage = mask
            downscale.scale = Float(scale)
            downscale.aspectRatio = 1.0
            sampledMask = (downscale.outputImage ?? mask).cropped(to: (downscale.outputImage ?? mask).extent.integral)
        } else {
            sampledMask = mask
        }

        let sampledExtent = sampledMask.extent.integral
        guard let cgImage = context.createCGImage(sampledMask, from: sampledExtent) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let bitmapContext = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let alpha = pixels[offset + 3]
                let luminance = max(pixels[offset], pixels[offset + 1], pixels[offset + 2])
                if alpha > 12 || luminance > 20 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        let sampledBounds = CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        )

        let scaleBackX = extent.width / sampledExtent.width
        let scaleBackY = extent.height / sampledExtent.height

        return CGRect(
            x: extent.minX + (sampledBounds.minX * scaleBackX),
            y: extent.minY + (sampledBounds.minY * scaleBackY),
            width: sampledBounds.width * scaleBackX,
            height: sampledBounds.height * scaleBackY
        ).integral
    }
}
