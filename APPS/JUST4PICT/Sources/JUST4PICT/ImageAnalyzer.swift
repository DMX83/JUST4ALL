import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

struct PhotoAnalysis {
    let averageLuminance: Double
    let averageSaturation: Double
    let isLowKey: Bool
    let isHighKey: Bool
}

final class ImageAnalyzer {
    private let context: CIContext

    init(context: CIContext) {
        self.context = context
    }

    func detectSceneType(inputURL: URL) -> ImageEnhancer.SceneType? {
        detectSceneType(inputURL: inputURL, precomputedFaces: detectFaces(in: inputURL))
    }

    func detectSceneType(inputURL: URL, precomputedFaces: [VNFaceObservation]) -> ImageEnhancer.SceneType? {
        let pixelSize = imagePixelSize(from: inputURL)
        let textObservationCount = recognizedTextObservationCount(in: inputURL)
        let landscapeHint = looksLikeLandscapePhoto(inputURL: inputURL)
        let analysis: PhotoAnalysis?
        let ecommerceHint: Bool
        if let image = CIImage(contentsOf: inputURL, options: [.applyOrientationProperty: true]) {
            analysis = analyzePhotograph(image)
            ecommerceHint = looksLikeProductPhoto(image: image)
        } else {
            analysis = nil
            ecommerceHint = false
        }

        return Self.inferSceneType(
            hasFaces: !precomputedFaces.isEmpty,
            textObservationCount: textObservationCount,
            pixelSize: pixelSize,
            analysis: analysis,
            landscapeHint: landscapeHint,
            ecommerceHint: ecommerceHint
        )
    }

    static func inferSceneType(
        hasFaces: Bool,
        textObservationCount: Int,
        pixelSize: CGSize?,
        analysis: PhotoAnalysis?,
        landscapeHint: Bool,
        ecommerceHint: Bool
    ) -> ImageEnhancer.SceneType {
        if hasFaces {
            return .portrait
        }

        if textObservationCount >= 8 {
            return .document
        }

        if let analysis {
            if textObservationCount >= 4 && analysis.averageSaturation < 0.18 {
                return .document
            }

            if textObservationCount >= 3 && analysis.isHighKey && analysis.averageSaturation < 0.12 {
                return .document
            }

            if analysis.isLowKey && textObservationCount <= 1 && analysis.averageSaturation < 0.42 {
                return .darkPhoto
            }

            if ecommerceHint && textObservationCount <= 2 && analysis.isHighKey {
                return .ecommerce
            }
        }

        if let size = pixelSize, size.width > 0, size.height > 0 {
            let ratio = size.width / size.height
            if ratio >= 1.25 && textObservationCount <= 2 {
                return .landscape
            }
        }

        if landscapeHint && textObservationCount <= 3 {
            return .landscape
        }

        return .generic
    }

    func detectFaces(in inputURL: URL) -> [VNFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(url: inputURL, options: [:])
        do {
            try handler.perform([request])
            return request.results ?? []
        } catch {
            return []
        }
    }

    func analyzePhotograph(_ image: CIImage) -> PhotoAnalysis {
        let extent = image.extent.integral
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = extent

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            filter.outputImage ?? image,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        let luminance = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)

        return PhotoAnalysis(
            averageLuminance: luminance,
            averageSaturation: max(r, g, b) - min(r, g, b),
            isLowKey: luminance < 0.42,
            isHighKey: luminance > 0.68
        )
    }

    private func recognizedTextObservationCount(in inputURL: URL) -> Int {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.minimumTextHeight = 0.015
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["es", "en"]

        let handler = VNImageRequestHandler(url: inputURL, options: [:])
        do {
            try handler.perform([request])
            return request.results?.count ?? 0
        } catch {
            return 0
        }
    }

    private func imagePixelSize(from inputURL: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat
        else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private func looksLikeLandscapePhoto(inputURL: URL) -> Bool {
        guard let image = CIImage(contentsOf: inputURL, options: [.applyOrientationProperty: true]) else {
            return false
        }

        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else { return false }

        let topRect = CGRect(
            x: extent.minX,
            y: extent.midY,
            width: extent.width,
            height: extent.height / 2
        ).integral
        let bottomRect = CGRect(
            x: extent.minX,
            y: extent.minY,
            width: extent.width,
            height: extent.height / 2
        ).integral

        let top = averageRGB(in: image, extent: topRect)
        let bottom = averageRGB(in: image, extent: bottomRect)

        let topBlueDominant = top.b > top.r + 0.03 && top.b >= top.g - 0.01
        let topBrightEnough = top.luminance > 0.40
        let bottomNatureLike = (bottom.g > bottom.r && bottom.g > bottom.b - 0.02) || (bottom.b > bottom.r && bottom.b > bottom.g - 0.02)
        let bottomVisible = bottom.luminance > 0.18

        return topBlueDominant && topBrightEnough && bottomNatureLike && bottomVisible
    }

    private func looksLikeProductPhoto(image: CIImage) -> Bool {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else { return false }

        let borderThicknessX = max(extent.width * 0.12, 1)
        let borderThicknessY = max(extent.height * 0.12, 1)

        let topRect = CGRect(x: extent.minX, y: extent.maxY - borderThicknessY, width: extent.width, height: borderThicknessY).integral
        let bottomRect = CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: borderThicknessY).integral
        let leftRect = CGRect(x: extent.minX, y: extent.minY, width: borderThicknessX, height: extent.height).integral
        let rightRect = CGRect(x: extent.maxX - borderThicknessX, y: extent.minY, width: borderThicknessX, height: extent.height).integral
        let centerRect = CGRect(
            x: extent.minX + (extent.width * 0.22),
            y: extent.minY + (extent.height * 0.22),
            width: extent.width * 0.56,
            height: extent.height * 0.56
        ).integral

        let samples = [
            averageRGB(in: image, extent: topRect),
            averageRGB(in: image, extent: bottomRect),
            averageRGB(in: image, extent: leftRect),
            averageRGB(in: image, extent: rightRect)
        ]
        let center = averageRGB(in: image, extent: centerRect)

        let borderLuminances = samples.map(\.luminance)
        let borderSaturations = samples.map { max($0.r, $0.g, $0.b) - min($0.r, $0.g, $0.b) }

        guard let minBorderLuminance = borderLuminances.min(),
              let maxBorderLuminance = borderLuminances.max()
        else {
            return false
        }

        let averageBorderLuminance = borderLuminances.reduce(0, +) / Double(borderLuminances.count)
        let averageBorderSaturation = borderSaturations.reduce(0, +) / Double(borderSaturations.count)
        let centerSaturation = max(center.r, center.g, center.b) - min(center.r, center.g, center.b)

        let brightUniformBackground = averageBorderLuminance > 0.72 && (maxBorderLuminance - minBorderLuminance) < 0.10
        let neutralBorder = averageBorderSaturation < 0.12
        let centerSeparatedFromBackground = centerSaturation > averageBorderSaturation + 0.08 || center.luminance < averageBorderLuminance - 0.08

        return brightUniformBackground && neutralBorder && centerSeparatedFromBackground
    }

    private func averageRGB(in image: CIImage, extent: CGRect) -> (r: Double, g: Double, b: Double, luminance: Double) {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = extent

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            filter.outputImage ?? image,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        let luminance = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
        return (r, g, b, luminance)
    }
}
