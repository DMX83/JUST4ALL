import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Vision
import OSLog
import Metal

enum EnhancementPreset: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case portrait = "Retrato"
    case landscape = "Paisaje"
    case document = "Documento"
    case ecommerce = "Ecommerce"

    var id: String { rawValue }

    var options: EnhancementOptions {
        switch self {
        case .auto:
            return EnhancementOptions(enableAutoAdjust: true, brightness: 0.0, contrast: 1.01, saturation: 1.0, sharpness: 0.1, noiseReduction: 0.008)
        case .portrait:
            return EnhancementOptions(enableAutoAdjust: false, brightness: 0.0, contrast: 1.0, saturation: 0.98, sharpness: 0.035, noiseReduction: 0.006)
        case .landscape:
            return EnhancementOptions(enableAutoAdjust: true, brightness: 0.0, contrast: 1.08, saturation: 1.08, sharpness: 0.24, noiseReduction: 0.012)
        case .document:
            return EnhancementOptions(enableAutoAdjust: false, brightness: 0.03, contrast: 1.14, saturation: 0.0, sharpness: 0.28, noiseReduction: 0.02)
        case .ecommerce:
            return EnhancementOptions(enableAutoAdjust: true, brightness: 0.02, contrast: 1.06, saturation: 1.05, sharpness: 0.2, noiseReduction: 0.01)
        }
    }
}

struct EnhancementOptions {
    let enableAutoAdjust: Bool
    let brightness: Double
    let contrast: Double
    let saturation: Double
    let sharpness: Double
    let noiseReduction: Double
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpg = "JPG"
    case heic = "HEIC"
    case webp = "WEBP"
    case tiff = "TIFF"

    var id: String { rawValue }

    static let preferredDefault: OutputFormat = .png
    static let preferredQualityDefault: Double = 1.0

    static var pickerOrder: [OutputFormat] {
        [.png, .jpg, .heic, .webp, .tiff]
    }

    var fileExtension: String {
        switch self {
        case .jpg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .webp: return "webp"
        case .tiff: return "tiff"
        }
    }

    var utTypeIdentifier: CFString {
        switch self {
        case .jpg: return UTType.jpeg.identifier as CFString
        case .png: return UTType.png.identifier as CFString
        case .heic: return UTType.heic.identifier as CFString
        case .webp:
            if let webp = UTType("org.webmproject.webp") {
                return webp.identifier as CFString
            }
            return UTType.png.identifier as CFString
        case .tiff: return UTType.tiff.identifier as CFString
        }
    }

    var supportsLossyQuality: Bool {
        switch self {
        case .jpg, .heic, .webp:
            return true
        case .png, .tiff:
            return false
        }
    }
}

enum ImageEnhancerError: LocalizedError {
    case cannotLoadImage(URL)
    case cannotRenderImage(URL)
    case cannotCreateDestination(URL)
    case cannotFinalizeWrite(URL)

    var errorDescription: String? {
        switch self {
        case .cannotLoadImage(let url):
            return "No se pudo cargar la imagen: \(url.lastPathComponent)"
        case .cannotRenderImage(let url):
            return "No se pudo renderizar la imagen: \(url.lastPathComponent)"
        case .cannotCreateDestination(let url):
            return "No se pudo crear el archivo de salida: \(url.lastPathComponent)"
        case .cannotFinalizeWrite(let url):
            return "No se pudo finalizar la escritura: \(url.lastPathComponent)"
        }
    }
}

final class ImageEnhancer {
    private static let sharedContext = ImageEnhancer.makeContext()
    private let context = ImageEnhancer.sharedContext
    private let defaultHDLongSide: CGFloat = 1600
    private let logger = Logger(subsystem: "com.dmx83.just4pict", category: "ImageEnhancer")

    private enum RecoveryProfile {
        case standard
        case conservativePortrait
        case legacyConservativePortrait
    }

    private struct PhotoAnalysis {
        let averageLuminance: Double
        let isLowKey: Bool
        let isHighKey: Bool
    }

    private struct PipelineConfig {
        let options: EnhancementOptions
        let recoveryProfile: RecoveryProfile
        let scene: SceneType?
    }

    private struct CoreTuning {
        let exposureEV: Double
        let shadowAmount: Double
        let highlightAmount: Double
        let contrast: Double
        let saturation: Double
        let vibrance: Double
        let sharpen: Double
        let sharpenRadius: Double
    }

    private static func makeContext() -> CIContext {
        let workingColorSpace = CGColorSpace(name: CGColorSpace.extendedSRGB) ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        let options: [CIContextOption: Any] = [
            .workingColorSpace: workingColorSpace,
            .outputColorSpace: outputColorSpace,
            .cacheIntermediates: true,
            .priorityRequestLow: false
        ]

        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: options)
        }

        return CIContext(options: options)
    }

    func enhance(
        inputURL: URL,
        outputURL: URL,
        preset: EnhancementPreset,
        quality: Double,
        format: OutputFormat,
        tuning: AIEnhancementTuning? = nil
    ) throws {
        let image = try makeEnhancedImage(
            inputURL: inputURL,
            preset: preset,
            upscaleToLongSide: defaultHDLongSide,
            tuning: tuning
        )

        let extent = image.extent.integral
        guard let cgImage = context.createCGImage(image, from: extent) else {
            throw ImageEnhancerError.cannotRenderImage(inputURL)
        }

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

    func enhancedPreviewImage(
        inputURL: URL,
        preset: EnhancementPreset,
        maxDimension: CGFloat = 1600,
        tuning: AIEnhancementTuning? = nil
    ) throws -> NSImage {
        let image = try makeEnhancedImage(
            inputURL: inputURL,
            preset: preset,
            upscaleToLongSide: nil,
            tuning: tuning
        )
        let extent = image.extent.integral
        guard let cgImage = context.createCGImage(image, from: extent) else {
            throw ImageEnhancerError.cannotRenderImage(inputURL)
        }

        let originalWidth = CGFloat(cgImage.width)
        let originalHeight = CGFloat(cgImage.height)
        let maxSide = max(originalWidth, originalHeight)
        let scale = maxSide > maxDimension ? (maxDimension / maxSide) : 1.0
        let size = NSSize(width: originalWidth * scale, height: originalHeight * scale)
        return NSImage(cgImage: cgImage, size: size)
    }

    private func makeEnhancedImage(
        inputURL: URL,
        preset: EnhancementPreset,
        upscaleToLongSide: CGFloat?,
        tuning: AIEnhancementTuning?
    ) throws -> CIImage {
        guard var image = CIImage(contentsOf: inputURL, options: [.applyOrientationProperty: true]) else {
            throw ImageEnhancerError.cannotLoadImage(inputURL)
        }

        let faceObservations = detectFaces(in: inputURL)
        let detectedScene = detectSceneType(inputURL: inputURL, precomputedFaces: faceObservations)
        let analysis = analyzePhotograph(image)
        let faceMask = createFaceProtectionMask(faceObservations: faceObservations, extent: image.extent.integral)

        let pipeline = resolvePipelineConfig(for: preset, detectedScene: detectedScene)
        let options = pipeline.options
        let recoveryProfile = pipeline.recoveryProfile

        if recoveryProfile == .conservativePortrait || recoveryProfile == .legacyConservativePortrait {
            logger.notice(
                "Conservative portrait recovery activated | mode=\(self.recoveryProfileLabel(recoveryProfile), privacy: .public) file=\(inputURL.lastPathComponent, privacy: .public) preset=\(preset.rawValue, privacy: .public) scene=\(self.sceneLabel(detectedScene), privacy: .public)"
            )
        } else {
            logger.debug(
                "Standard recovery profile | file=\(inputURL.lastPathComponent, privacy: .public) preset=\(preset.rawValue, privacy: .public) scene=\(self.sceneLabel(detectedScene), privacy: .public)"
            )
        }

        if recoveryProfile == .conservativePortrait {
            image = applyPortraitGuidedEnhancement(
                image: image,
                tuning: tuning,
                analysis: analysis,
                faceMask: faceMask
            )

            if let targetLongSide = upscaleToLongSide {
                let upscaleResult = applyUpscaleIfNeeded(image: image, targetLongSide: targetLongSide)
                image = upscaleResult.image

                if upscaleResult.upscaled {
                    logger.debug(
                        "Upscale applied | file=\(inputURL.lastPathComponent, privacy: .public) scale=\(upscaleResult.scale, privacy: .public)"
                    )
                    image = applyPortraitUpscaleFinish(image: image, scale: upscaleResult.scale)
                }
            }

            return image
        }

        if isPhotographScene(detectedScene) {
            logger.notice(
                "Photo recipe activated | file=\(inputURL.lastPathComponent, privacy: .public) preset=\(preset.rawValue, privacy: .public) scene=\(self.sceneLabel(detectedScene), privacy: .public)"
            )
            image = applyAppleLikePhotoEnhancement(
                image: image,
                scene: detectedScene,
                tuning: tuning,
                analysis: analysis
            )

            if let targetLongSide = upscaleToLongSide {
                let upscaleResult = applyUpscaleIfNeeded(image: image, targetLongSide: targetLongSide)
                image = upscaleResult.image

                if upscaleResult.upscaled {
                    logger.debug(
                        "Upscale applied | file=\(inputURL.lastPathComponent, privacy: .public) scale=\(upscaleResult.scale, privacy: .public)"
                    )
                    image = applyPhotoUpscaleFinish(image: image, scale: upscaleResult.scale)
                }
            }

            return image
        }

        if options.enableAutoAdjust {
            let autoFilters = image.autoAdjustmentFilters(options: [
                .enhance: true,
                .redEye: true,
                .crop: false,
                .level: true
            ])
            for filter in autoFilters {
                filter.setValue(image, forKey: kCIInputImageKey)
                if let adjusted = filter.outputImage {
                    image = adjusted
                }
            }
        }

        image = applyColorControls(
            image: image,
            brightness: options.brightness,
            contrast: options.contrast,
            saturation: options.saturation
        )

        image = applyProfessionalToneBalance(
            image: image,
            preset: preset,
            detectedScene: detectedScene,
            profile: recoveryProfile
        )

        if recoveryProfile == .conservativePortrait || recoveryProfile == .legacyConservativePortrait {
            image = applyPortraitSafetyFinish(image: image, profile: recoveryProfile)
        }

        if options.noiseReduction > 0.0 {
            image = applyNoiseReduction(image: image, amount: options.noiseReduction)
        }

        if options.sharpness > 0.0 {
            image = applySharpen(image: image, amount: options.sharpness)
        }

        if let targetLongSide = upscaleToLongSide {
            let upscaleResult = applyUpscaleIfNeeded(image: image, targetLongSide: targetLongSide)
            image = upscaleResult.image

            if upscaleResult.upscaled {
                logger.debug(
                    "Upscale applied | file=\(inputURL.lastPathComponent, privacy: .public) scale=\(upscaleResult.scale, privacy: .public)"
                )
                image = applyPostUpscaleDetailRecovery(image: image, scale: upscaleResult.scale, profile: recoveryProfile)
            }
        }

        return image
    }

    private func resolvedOptions(for preset: EnhancementPreset, detectedScene: SceneType?) -> EnhancementOptions {
        effectivePreset(for: preset, detectedScene: detectedScene).options
    }

    func effectivePreset(for preset: EnhancementPreset, inputURL: URL) -> EnhancementPreset {
        let detectedScene = detectSceneType(inputURL: inputURL)
        return effectivePreset(for: preset, detectedScene: detectedScene)
    }

    private func effectivePreset(for preset: EnhancementPreset, detectedScene: SceneType?) -> EnhancementPreset {
        guard preset == .auto else {
            return preset
        }

        switch detectedScene {
        case .portrait:
            return .portrait
        case .document:
            return .document
        case .landscape:
            return .landscape
        case .generic, .none:
            return .auto
        }
    }

    private func resolvePipelineConfig(for preset: EnhancementPreset, detectedScene: SceneType?) -> PipelineConfig {
        PipelineConfig(
            options: resolvedOptions(for: preset, detectedScene: detectedScene),
            recoveryProfile: resolveRecoveryProfile(preset: preset, detectedScene: detectedScene),
            scene: detectedScene
        )
    }

    enum SceneType {
        case portrait
        case document
        case landscape
        case generic
    }

    func detectSceneType(inputURL: URL) -> SceneType? {
        detectSceneType(inputURL: inputURL, precomputedFaces: detectFaces(in: inputURL))
    }

    private func detectSceneType(inputURL: URL, precomputedFaces: [VNFaceObservation]) -> SceneType? {
        if !precomputedFaces.isEmpty {
            return .portrait
        }

        if hasDenseText(in: inputURL) {
            return .document
        }

        if let size = imagePixelSize(from: inputURL), size.width > 0, size.height > 0 {
            let ratio = size.width / size.height
            if ratio >= 1.25 {
                return .landscape
            }
        }

        if looksLikeLandscapePhoto(inputURL: inputURL) {
            return .landscape
        }

        return .generic
    }

    private func hasFaces(in inputURL: URL) -> Bool {
        !detectFaces(in: inputURL).isEmpty
    }

    private func detectFaces(in inputURL: URL) -> [VNFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(url: inputURL, options: [:])
        do {
            try handler.perform([request])
            return request.results ?? []
        } catch {
            return []
        }
    }

    private func hasDenseText(in inputURL: URL) -> Bool {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.minimumTextHeight = 0.015
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["es", "en"]

        let handler = VNImageRequestHandler(url: inputURL, options: [:])
        do {
            try handler.perform([request])
            let count = request.results?.count ?? 0
            return count >= 8
        } catch {
            return false
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

    private func isPhotographScene(_ scene: SceneType?) -> Bool {
        switch scene {
        case .portrait, .landscape, .generic, .none:
            return true
        case .document:
            return false
        }
    }

    private func resolveRecoveryProfile(preset: EnhancementPreset, detectedScene: SceneType?) -> RecoveryProfile {
        let useLegacy = portraitRecoveryMode() == "legacy"

        if preset == .portrait {
            return useLegacy ? .legacyConservativePortrait : .conservativePortrait
        }
        if preset == .auto, detectedScene == .portrait {
            return useLegacy ? .legacyConservativePortrait : .conservativePortrait
        }
        return .standard
    }

    private func portraitRecoveryMode() -> String {
        let raw = ProcessInfo.processInfo.environment["JUST4PICT_PORTRAIT_PROFILE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return raw == "legacy" ? "legacy" : "pro"
    }

    private func sceneLabel(_ scene: SceneType?) -> String {
        switch scene {
        case .portrait:
            return "portrait"
        case .document:
            return "document"
        case .landscape:
            return "landscape"
        case .generic:
            return "generic"
        case .none:
            return "unknown"
        }
    }

    private func recoveryProfileLabel(_ profile: RecoveryProfile) -> String {
        switch profile {
        case .standard:
            return "standard"
        case .conservativePortrait:
            return "portrait-pro"
        case .legacyConservativePortrait:
            return "portrait-legacy"
        }
    }

    private func applyUpscaleIfNeeded(image: CIImage, targetLongSide: CGFloat) -> (image: CIImage, upscaled: Bool, scale: CGFloat) {
        let extent = image.extent.integral
        let currentLongSide = max(extent.width, extent.height)
        guard currentLongSide > 0, currentLongSide < targetLongSide else {
            return (image, false, 1.0)
        }

        let scale = targetLongSide / currentLongSide
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1.0
        return (filter.outputImage ?? image, true, scale)
    }

    private func applyPostUpscaleDetailRecovery(image: CIImage, scale: CGFloat, profile: RecoveryProfile) -> CIImage {
        var output = image

        let adaptiveNoiseLevel: CGFloat
        switch profile {
        case .legacyConservativePortrait:
            adaptiveNoiseLevel = min(max(0.006 + (scale - 1.0) * 0.004, 0.006), 0.018)
        case .conservativePortrait:
            adaptiveNoiseLevel = min(max(0.003 + (scale - 1.0) * 0.002, 0.003), 0.007)
        case .standard:
            adaptiveNoiseLevel = min(max(0.006 + (scale - 1.0) * 0.004, 0.006), 0.02)
        }
        output = applyNoiseReduction(image: output, amount: adaptiveNoiseLevel)

        let sharpenUpperBound: CGFloat
        switch profile {
        case .legacyConservativePortrait:
            sharpenUpperBound = 0.18
        case .conservativePortrait:
            sharpenUpperBound = 0.045
        case .standard:
            sharpenUpperBound = 0.22
        }
        let adaptiveSharpen = min(max(0.02 + (scale - 1.0) * 0.02, 0.02), sharpenUpperBound)
        output = applySharpen(image: output, amount: adaptiveSharpen)

        let microContrast = CIFilter.unsharpMask()
        microContrast.inputImage = output
        let radiusUpperBound: CGFloat
        let intensityUpperBound: CGFloat
        switch profile {
        case .legacyConservativePortrait:
            radiusUpperBound = 1.1
            intensityUpperBound = 0.14
        case .conservativePortrait:
            radiusUpperBound = 0.7
            intensityUpperBound = 0.04
        case .standard:
            radiusUpperBound = 1.2
            intensityUpperBound = 0.18
        }
        microContrast.radius = Float(min(max(0.32 + (scale - 1.0) * 0.12, 0.32), radiusUpperBound))
        microContrast.intensity = Float(min(max(0.015 + (scale - 1.0) * 0.015, 0.015), intensityUpperBound))

        if profile == .conservativePortrait {
            let colorLift = CIFilter.colorControls()
            colorLift.inputImage = microContrast.outputImage ?? output
            colorLift.brightness = 0.0
            colorLift.contrast = 0.995
            colorLift.saturation = 0.975
            return applyPortraitHighlightCompression(image: colorLift.outputImage ?? (microContrast.outputImage ?? output))
        }

        return microContrast.outputImage ?? output
    }

    private func applyColorControls(image: CIImage, brightness: Double, contrast: Double, saturation: Double) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.brightness = Float(brightness)
        filter.contrast = Float(contrast)
        filter.saturation = Float(saturation)
        return filter.outputImage ?? image
    }

    private func applyProfessionalToneBalance(
        image: CIImage,
        preset: EnhancementPreset,
        detectedScene: SceneType?,
        profile: RecoveryProfile
    ) -> CIImage {
        let effectivePreset: EnhancementPreset
        if preset == .auto {
            switch detectedScene {
            case .portrait:
                effectivePreset = .portrait
            case .document:
                effectivePreset = .document
            case .landscape:
                effectivePreset = .landscape
            case .generic, .none:
                effectivePreset = .auto
            }
        } else {
            effectivePreset = preset
        }

        let shadowAmount: Float
        let highlightAmount: Float
        let exposureEV: Float

        switch effectivePreset {
        case .portrait:
            if profile == .legacyConservativePortrait {
                shadowAmount = 0.18
                highlightAmount = 0.04
                exposureEV = 0.05
            } else {
                shadowAmount = 0.08
                highlightAmount = 0.035
                exposureEV = -0.01
            }
        case .landscape:
            shadowAmount = 0.18
            highlightAmount = 0.08
            exposureEV = 0.05
        case .ecommerce:
            shadowAmount = 0.18
            highlightAmount = 0.06
            exposureEV = 0.06
        case .document:
            shadowAmount = 0.08
            highlightAmount = 0.03
            exposureEV = 0.03
        case .auto:
            shadowAmount = 0.14
            highlightAmount = 0.05
            exposureEV = 0.04
        }

        let highlightShadow = CIFilter.highlightShadowAdjust()
        highlightShadow.inputImage = image
        highlightShadow.shadowAmount = shadowAmount
        highlightShadow.highlightAmount = highlightAmount

        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = highlightShadow.outputImage ?? image
        exposure.ev = exposureEV

        return exposure.outputImage ?? (highlightShadow.outputImage ?? image)
    }

    private func applyPortraitGuidedEnhancement(
        image: CIImage,
        tuning: AIEnhancementTuning?,
        analysis: PhotoAnalysis,
        faceMask: CIImage?
    ) -> CIImage {
        let resolvedTuning = constrainAITuning(
            tuning ?? defaultAITuning(for: .portrait, analysis: analysis),
            for: .portrait
        )
        let baseExposure: Double
        if analysis.isLowKey {
            baseExposure = 0.05
        } else if analysis.isHighKey {
            baseExposure = 0.01
        } else {
            baseExposure = 0.02
        }

        let portraitTuning = CoreTuning(
            exposureEV: min(max(max(resolvedTuning.exposureEV, baseExposure), 0.0), 0.05),
            shadowAmount: 0.0,
            highlightAmount: 0.0,
            contrast: 1.004,
            saturation: min(max(resolvedTuning.saturation, 0.995), 1.0),
            vibrance: min(max(resolvedTuning.vibrance, 0.0), 0.015),
            sharpen: min(max(resolvedTuning.sharpen, 0.024), 0.040),
            sharpenRadius: min(max(resolvedTuning.sharpenRadius, 0.26), 0.33)
        )

        let output = applyCoreTuning(
            image: image,
            tuning: portraitTuning,
            faceMask: faceMask
        )

        return applyProtectedPortraitDetail(image: output, faceMask: faceMask)
    }

    private func analyzePhotograph(_ image: CIImage) -> PhotoAnalysis {
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
            isLowKey: luminance < 0.42,
            isHighKey: luminance > 0.68
        )
    }

    private func applyPortraitToneCurve(image: CIImage, analysis: PhotoAnalysis) -> CIImage {
        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        curve.point0 = CGPoint(x: 0.0, y: 0.02)
        curve.point1 = CGPoint(x: 0.25, y: analysis.isLowKey ? 0.31 : 0.28)
        curve.point2 = CGPoint(x: 0.5, y: analysis.isLowKey ? 0.54 : 0.52)
        curve.point3 = CGPoint(x: 0.75, y: analysis.isHighKey ? 0.79 : 0.82)
        curve.point4 = CGPoint(x: 1.0, y: analysis.isHighKey ? 0.97 : 0.985)
        return curve.outputImage ?? image
    }

    private func applyCoreTuning(
        image: CIImage,
        tuning: CoreTuning,
        faceMask: CIImage? = nil
    ) -> CIImage {
        var output = image

        if abs(tuning.exposureEV) > 0.0001 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = output
            exposure.ev = Float(tuning.exposureEV)
            output = exposure.outputImage ?? output
        }

        if tuning.shadowAmount > 0.0 || tuning.highlightAmount > 0.0 {
            let highlightShadow = CIFilter.highlightShadowAdjust()
            highlightShadow.inputImage = output
            highlightShadow.shadowAmount = Float(tuning.shadowAmount)
            highlightShadow.highlightAmount = Float(tuning.highlightAmount)
            output = highlightShadow.outputImage ?? output
        }

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = output
        colorControls.brightness = 0.0
        colorControls.contrast = Float(tuning.contrast)
        colorControls.saturation = Float(tuning.saturation)
        output = colorControls.outputImage ?? output

        if abs(tuning.vibrance) > 0.0001 {
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = output
            vibrance.amount = Float(tuning.vibrance)
            output = vibrance.outputImage ?? output
        }

        if tuning.sharpen > 0.0 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = output
            sharpen.sharpness = Float(tuning.sharpen)
            sharpen.radius = Float(tuning.sharpenRadius)
            let sharpened = sharpen.outputImage ?? output

            if let faceMask {
                let protectFaces = CIFilter.blendWithMask()
                protectFaces.inputImage = output
                protectFaces.backgroundImage = sharpened
                protectFaces.maskImage = faceMask
                output = protectFaces.outputImage ?? sharpened
            } else {
                output = sharpened
            }
        }

        return output
    }

    private func applyProtectedPortraitDetail(image: CIImage, faceMask: CIImage?) -> CIImage {
        let microDetail = CIFilter.unsharpMask()
        microDetail.inputImage = image
        microDetail.radius = 0.50
        microDetail.intensity = 0.026
        let detailed = microDetail.outputImage ?? image

        guard let faceMask else {
            return detailed
        }

        let protectFaces = CIFilter.blendWithMask()
        protectFaces.inputImage = image
        protectFaces.backgroundImage = detailed
        protectFaces.maskImage = faceMask
        return protectFaces.outputImage ?? detailed
    }

    private func makeEdgeMask(for image: CIImage) -> CIImage {
        let edges = CIFilter.edges()
        edges.inputImage = image
        edges.intensity = 1.5

        let mono = CIFilter.colorControls()
        mono.inputImage = edges.outputImage ?? image
        mono.saturation = 0.0
        mono.contrast = 1.8

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = mono.outputImage ?? image
        blur.radius = 1.2

        return (blur.outputImage ?? mono.outputImage ?? image).cropped(to: image.extent)
    }

    private func createFaceProtectionMask(faceObservations: [VNFaceObservation], extent: CGRect) -> CIImage? {
        guard !faceObservations.isEmpty else { return nil }

        let width = max(Int(extent.width.rounded()), 1)
        let height = max(Int(extent.height.rounded()), 1)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.setFillColor(gray: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 1.0, alpha: 1.0)

        for observation in faceObservations {
            let box = observation.boundingBox
            let rect = CGRect(
                x: box.minX * extent.width,
                y: box.minY * extent.height,
                width: box.width * extent.width,
                height: box.height * extent.height
            )
            let expanded = rect.insetBy(dx: -rect.width * 0.35, dy: -rect.height * 0.25)
            context.fillEllipse(in: expanded)
        }

        guard let cgImage = context.makeImage() else { return nil }

        let mask = CIImage(cgImage: cgImage).cropped(to: CGRect(x: 0, y: 0, width: extent.width, height: extent.height))
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = mask
        blur.radius = 10.0
        return (blur.outputImage ?? mask).cropped(to: mask.extent)
    }

    private func applyAppleLikePhotoEnhancement(
        image: CIImage,
        scene: SceneType?,
        tuning: AIEnhancementTuning?,
        analysis: PhotoAnalysis
    ) -> CIImage {
        var output = image

        if scene != .portrait {
            let autoFilters = output.autoAdjustmentFilters(options: [
                .enhance: true,
                .redEye: true,
                .crop: false,
                .level: true
            ])
            for filter in autoFilters {
                filter.setValue(output, forKey: kCIInputImageKey)
                if let adjusted = filter.outputImage {
                    output = adjusted
                }
            }
        }

        let resolvedTuning = constrainAITuning(
            tuning ?? defaultAITuning(for: scene, analysis: analysis),
            for: scene
        )

        let highlightShadow = CIFilter.highlightShadowAdjust()
        highlightShadow.inputImage = output
        highlightShadow.shadowAmount = Float(resolvedTuning.shadowAmount)
        highlightShadow.highlightAmount = Float(resolvedTuning.highlightAmount)
        output = highlightShadow.outputImage ?? output

        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = output
        exposure.ev = Float(resolvedTuning.exposureEV)
        output = exposure.outputImage ?? output

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = output
        colorControls.brightness = 0.0
        colorControls.contrast = Float(resolvedTuning.contrast)
        colorControls.saturation = Float(resolvedTuning.saturation)
        output = colorControls.outputImage ?? output

        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = output
        vibrance.amount = Float(resolvedTuning.vibrance)
        output = vibrance.outputImage ?? output

        if scene == .portrait {
            output = applyPortraitAISafetyFinish(image: output)
        }

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = output
        sharpen.sharpness = Float(resolvedTuning.sharpen)
        sharpen.radius = Float(resolvedTuning.sharpenRadius)
        output = sharpen.outputImage ?? output

        return output
    }

    private func defaultAITuning(for scene: SceneType?, analysis: PhotoAnalysis) -> AIEnhancementTuning {
        switch scene {
        case .portrait:
            return AIEnhancementTuning(
                shadowAmount: 0.08,
                highlightAmount: 0.06,
                vibrance: 0.03,
                sharpen: 0.06,
                sharpenRadius: 0.30,
                contrast: 0.995,
                saturation: 0.995,
                exposureEV: 0.03
            )
        case .landscape:
            return AIEnhancementTuning(
                shadowAmount: 0.34,
                highlightAmount: 0.82,
                vibrance: 0.14,
                sharpen: 0.22,
                sharpenRadius: 0.58,
                contrast: 1.005,
                saturation: 1.02,
                exposureEV: 0.0
            )
        case .document:
            return AIEnhancementTuning(
                shadowAmount: 0.22,
                highlightAmount: 0.76,
                vibrance: 0.05,
                sharpen: 0.30,
                sharpenRadius: 0.45,
                contrast: 1.03,
                saturation: 0.98,
                exposureEV: 0.02
            )
        case .generic, .none:
            if analysis.isLowKey {
                return AIEnhancementTuning(
                    shadowAmount: 0.22,
                    highlightAmount: 0.78,
                    vibrance: 0.05,
                    sharpen: 0.14,
                    sharpenRadius: 0.42,
                    contrast: 0.992,
                    saturation: 0.995,
                    exposureEV: -0.04
                )
            }
            return AIEnhancementTuning(
                shadowAmount: 0.35,
                highlightAmount: 0.86,
                vibrance: 0.15,
                sharpen: 0.24,
                sharpenRadius: 0.60,
                contrast: 1.0,
                saturation: 1.01,
                exposureEV: -0.01
            )
        }
    }

    private func constrainAITuning(_ tuning: AIEnhancementTuning, for scene: SceneType?) -> AIEnhancementTuning {
        let base = tuning.clamped()

        switch scene {
        case .portrait:
            return AIEnhancementTuning(
                shadowAmount: min(max(base.shadowAmount, 0.04), 0.14),
                highlightAmount: min(max(base.highlightAmount, 0.02), 0.10),
                vibrance: min(max(base.vibrance, 0.00), 0.08),
                sharpen: min(max(base.sharpen, 0.02), 0.10),
                sharpenRadius: min(max(base.sharpenRadius, 0.20), 0.36),
                contrast: min(max(base.contrast, 0.985), 1.00),
                saturation: min(max(base.saturation, 0.99), 1.00),
                exposureEV: min(max(base.exposureEV, 0.00), 0.05)
            )
        case .landscape:
            return AIEnhancementTuning(
                shadowAmount: min(max(base.shadowAmount, 0.24), 0.46),
                highlightAmount: min(max(base.highlightAmount, 0.78), 1.00),
                vibrance: min(max(base.vibrance, 0.08), 0.22),
                sharpen: min(max(base.sharpen, 0.12), 0.34),
                sharpenRadius: min(max(base.sharpenRadius, 0.35), 0.80),
                contrast: min(max(base.contrast, 0.96), 1.04),
                saturation: min(max(base.saturation, 0.97), 1.06),
                exposureEV: min(max(base.exposureEV, -0.10), 0.08)
            )
        case .document:
            return AIEnhancementTuning(
                shadowAmount: min(max(base.shadowAmount, 0.20), 0.32),
                highlightAmount: min(max(base.highlightAmount, 0.72), 0.90),
                vibrance: min(max(base.vibrance, 0.00), 0.08),
                sharpen: min(max(base.sharpen, 0.14), 0.30),
                sharpenRadius: min(max(base.sharpenRadius, 0.25), 0.50),
                contrast: min(max(base.contrast, 0.98), 1.05),
                saturation: min(max(base.saturation, 0.95), 1.00),
                exposureEV: min(max(base.exposureEV, -0.04), 0.06)
            )
        case .generic, .none:
            return base
        }
    }

    private func applyPortraitAISafetyFinish(image: CIImage) -> CIImage {
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.brightness = 0.0
        colorControls.contrast = 0.998
        colorControls.saturation = 0.995
        return colorControls.outputImage ?? image
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

    private func applyPortraitUpscaleFinish(image: CIImage, scale: CGFloat) -> CIImage {
        var output = image
        let adaptiveSharpen = min(max(0.002 + (scale - 1.0) * 0.004, 0.002), 0.008)
        output = applySharpen(image: output, amount: adaptiveSharpen)

        let microContrast = CIFilter.unsharpMask()
        microContrast.inputImage = output
        microContrast.radius = Float(min(max(0.14 + (scale - 1.0) * 0.04, 0.14), 0.2))
        microContrast.intensity = Float(min(max(0.002 + (scale - 1.0) * 0.003, 0.002), 0.006))
        return microContrast.outputImage ?? output
    }

    private func applyPhotoUpscaleFinish(image: CIImage, scale: CGFloat) -> CIImage {
        var output = image
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = output
        sharpen.sharpness = Float(min(max(0.02 + (scale - 1.0) * 0.02, 0.02), 0.05))
        sharpen.radius = 0.22
        output = sharpen.outputImage ?? output

        let definition = CIFilter.unsharpMask()
        definition.inputImage = output
        definition.radius = Float(min(max(0.25 + (scale - 1.0) * 0.08, 0.25), 0.4))
        definition.intensity = Float(min(max(0.015 + (scale - 1.0) * 0.015, 0.015), 0.03))
        return definition.outputImage ?? output
    }

    private func applyPortraitSafetyFinish(image: CIImage, profile: RecoveryProfile) -> CIImage {
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.brightness = 0.0
        colorControls.contrast = profile == .legacyConservativePortrait ? 1.0 : 0.985
        colorControls.saturation = profile == .legacyConservativePortrait ? 0.99 : 0.96

        let baseImage = colorControls.outputImage ?? image
        return applyPortraitHighlightCompression(image: baseImage)
    }

    private func applyPortraitHighlightCompression(image: CIImage) -> CIImage {
        let highlightShadow = CIFilter.highlightShadowAdjust()
        highlightShadow.inputImage = image
        highlightShadow.shadowAmount = 0.0
        highlightShadow.highlightAmount = 0.08
        return highlightShadow.outputImage ?? image
    }

    private func applyNoiseReduction(image: CIImage, amount: Double) -> CIImage {
        let filter = CIFilter.noiseReduction()
        filter.inputImage = image
        filter.noiseLevel = Float(amount)
        filter.sharpness = 0.06
        return filter.outputImage ?? image
    }

    private func applySharpen(image: CIImage, amount: Double) -> CIImage {
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = image
        filter.sharpness = Float(amount)
        filter.radius = 0.25
        return filter.outputImage ?? image
    }
}
