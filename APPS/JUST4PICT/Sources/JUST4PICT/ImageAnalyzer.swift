import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

struct PhotoAnalysis {
    let averageRed: Double
    let averageGreen: Double
    let averageBlue: Double
    let highlightRed: Double
    let highlightGreen: Double
    let highlightBlue: Double
    let highlightCoverage: Double
    let averageLuminance: Double
    let averageSaturation: Double
    let isLowKey: Bool
    let isHighKey: Bool

    init(
        averageRed: Double = 0.5,
        averageGreen: Double = 0.5,
        averageBlue: Double = 0.5,
        highlightRed: Double = 0.5,
        highlightGreen: Double = 0.5,
        highlightBlue: Double = 0.5,
        highlightCoverage: Double = 0.0,
        averageLuminance: Double,
        averageSaturation: Double,
        isLowKey: Bool,
        isHighKey: Bool
    ) {
        self.averageRed = averageRed
        self.averageGreen = averageGreen
        self.averageBlue = averageBlue
        self.highlightRed = highlightRed
        self.highlightGreen = highlightGreen
        self.highlightBlue = highlightBlue
        self.highlightCoverage = highlightCoverage
        self.averageLuminance = averageLuminance
        self.averageSaturation = averageSaturation
        self.isLowKey = isLowKey
        self.isHighKey = isHighKey
    }
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

        if let analysis,
           ecommerceHint && textObservationCount <= 5 &&
            (analysis.isHighKey || analysis.averageLuminance > 0.48) {
            return .ecommerce
        }

        if let analysis,
           !landscapeHint,
           textObservationCount == 0,
           let size = pixelSize,
           size.width > 0,
           size.height > 0 {
            let ratio = size.width / size.height
            if ratio > 0.55 &&
                ratio < 1.15 &&
                analysis.averageLuminance > 0.50 &&
                analysis.averageSaturation > 0.32 {
                return .ecommerce
            }
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

    func pixelSize(for inputURL: URL) -> CGSize? {
        imagePixelSize(from: inputURL)
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
        let highlightReference = highlightReferenceRGB(in: image)

        return PhotoAnalysis(
            averageRed: r,
            averageGreen: g,
            averageBlue: b,
            highlightRed: highlightReference.r,
            highlightGreen: highlightReference.g,
            highlightBlue: highlightReference.b,
            highlightCoverage: highlightReference.coverage,
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

        let cornerWidth = max(extent.width * 0.16, 1)
        let cornerHeight = max(extent.height * 0.16, 1)

        let topLeftRect = CGRect(x: extent.minX, y: extent.maxY - cornerHeight, width: cornerWidth, height: cornerHeight).integral
        let topRightRect = CGRect(x: extent.maxX - cornerWidth, y: extent.maxY - cornerHeight, width: cornerWidth, height: cornerHeight).integral
        let bottomLeftRect = CGRect(x: extent.minX, y: extent.minY, width: cornerWidth, height: cornerHeight).integral
        let bottomRightRect = CGRect(x: extent.maxX - cornerWidth, y: extent.minY, width: cornerWidth, height: cornerHeight).integral
        let centerRect = CGRect(
            x: extent.minX + (extent.width * 0.22),
            y: extent.minY + (extent.height * 0.22),
            width: extent.width * 0.56,
            height: extent.height * 0.56
        ).integral

        let samples = [
            averageRGB(in: image, extent: topLeftRect),
            averageRGB(in: image, extent: topRightRect),
            averageRGB(in: image, extent: bottomLeftRect),
            averageRGB(in: image, extent: bottomRightRect)
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

        let brightEnoughBackground = averageBorderLuminance > 0.50
        let reasonablyUniformCorners = (maxBorderLuminance - minBorderLuminance) < 0.50
        let neutralEnoughBorder = averageBorderSaturation <= 0.28
        let centerSeparatedFromBackground = centerSaturation > averageBorderSaturation + 0.08 || center.luminance < averageBorderLuminance - 0.04
        let aspectRatio = extent.width / extent.height
        let catalogStyleProduct = aspectRatio > 0.55 &&
            aspectRatio < 1.15 &&
            averageBorderLuminance > 0.38 &&
            neutralEnoughBorder &&
            centerSaturation > averageBorderSaturation + 0.20

        return (brightEnoughBackground && reasonablyUniformCorners && neutralEnoughBorder && centerSeparatedFromBackground)
            || catalogStyleProduct
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

    private func highlightReferenceRGB(in image: CIImage) -> (r: Double, g: Double, b: Double, coverage: Double) {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else {
            return (0.5, 0.5, 0.5, 0.0)
        }

        let maxSampleSide = 160.0
        let longSide = max(extent.width, extent.height)
        let scale = min(1.0, maxSampleSide / longSide)
        let sampledImage: CIImage
        if scale < 1.0 {
            let resize = CIFilter.lanczosScaleTransform()
            resize.inputImage = image
            resize.scale = Float(scale)
            resize.aspectRatio = 1.0
            sampledImage = (resize.outputImage ?? image).cropped(to: (resize.outputImage ?? image).extent.integral)
        } else {
            sampledImage = image
        }

        let sampledExtent = sampledImage.extent.integral
        let width = Int(sampledExtent.width)
        let height = Int(sampledExtent.height)
        guard width > 0, height > 0 else {
            return (0.5, 0.5, 0.5, 0.0)
        }

        let rowBytes = width * 4
        var bitmap = [UInt8](repeating: 0, count: rowBytes * height)
        context.render(
            sampledImage,
            toBitmap: &bitmap,
            rowBytes: rowBytes,
            bounds: sampledExtent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        var highlightPixelCount = 0
        var redTotal = 0.0
        var greenTotal = 0.0
        var blueTotal = 0.0
        let threshold = 0.72

        for index in stride(from: 0, to: bitmap.count, by: 4) {
            let r = Double(bitmap[index]) / 255.0
            let g = Double(bitmap[index + 1]) / 255.0
            let b = Double(bitmap[index + 2]) / 255.0
            let luminance = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)

            if luminance > threshold {
                highlightPixelCount += 1
                redTotal += r
                greenTotal += g
                blueTotal += b
            }
        }

        let totalPixels = width * height
        guard highlightPixelCount > 0, totalPixels > 0 else {
            return (0.5, 0.5, 0.5, 0.0)
        }

        let coverage = Double(highlightPixelCount) / Double(totalPixels)
        return (
            redTotal / Double(highlightPixelCount),
            greenTotal / Double(highlightPixelCount),
            blueTotal / Double(highlightPixelCount),
            coverage
        )
    }
}
