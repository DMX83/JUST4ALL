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
            return EnhancementOptions(enableAutoAdjust: true, brightness: 0.0, contrast: 1.03, saturation: 1.0, sharpness: 0.16, noiseReduction: 0.012)
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

enum ExportProfile: String, CaseIterable, Identifiable {
    case original = "Original"
    case social = "Social"
    case web = "Web"
    case ecommerce = "Ecommerce"

    var id: String { rawValue }

    func targetLongSide(for preset: EnhancementPreset) -> CGFloat? {
        switch self {
        case .original:
            return nil
        case .social:
            return 2048
        case .web:
            return 1600
        case .ecommerce:
            return preset == .ecommerce ? 2200 : 2000
        }
    }
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

enum RecoveryProfile {
    case standard
    case conservativePortrait
}

struct CoreTuning {
    let exposureEV: Double
    let shadowAmount: Double
    let highlightAmount: Double
    let contrast: Double
    let saturation: Double
    let vibrance: Double
    let sharpen: Double
    let sharpenRadius: Double
}

final class ImageEnhancer {
    private static let sharedContext = ImageEnhancer.makeContext()
    private let context = ImageEnhancer.sharedContext
    private lazy var analyzer = ImageAnalyzer(context: context)
    private lazy var localPipeline = LocalPhotoPipeline(context: context)
    private lazy var productIsolationEngine = ProductIsolationEngine(context: context)
    private let defaultHDLongSide: CGFloat = 1600
    private let logger = Logger(subsystem: "com.dmx83.just4pict", category: "ImageEnhancer")

    private struct PipelineConfig {
        let options: EnhancementOptions
        let recoveryProfile: RecoveryProfile
        let scene: SceneType?
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
        exportProfile: ExportProfile = .original,
        upscaleTargetLongSide: CGFloat? = nil,
        faceRestoreStrength: Double? = nil,
        tuning: AIEnhancementTuning? = nil,
        sceneOverride: SceneType? = nil
    ) throws {
        var image = try makeEnhancedImage(
            inputURL: inputURL,
            preset: preset,
            upscaleToLongSide: resolvedUpscaleTargetLongSide(upscaleTargetLongSide),
            faceRestoreStrength: faceRestoreStrength,
            tuning: tuning,
            sceneOverride: sceneOverride
        )
        image = applyExportResizeIfNeeded(
            image: image,
            targetLongSide: exportProfile.targetLongSide(for: preset)
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

    func pixelSize(for inputURL: URL) -> CGSize? {
        analyzer.pixelSize(for: inputURL)
    }

    func enhancedPreviewImage(
        inputURL: URL,
        preset: EnhancementPreset,
        maxDimension: CGFloat = 1600,
        tuning: AIEnhancementTuning? = nil,
        faceRestoreStrength: Double? = nil,
        upscaleTargetLongSide: CGFloat? = nil,
        sceneOverride: SceneType? = nil
    ) throws -> NSImage {
        let image = try makeEnhancedImage(
            inputURL: inputURL,
            preset: preset,
            upscaleToLongSide: resolvedPreviewUpscaleTargetLongSide(upscaleTargetLongSide),
            faceRestoreStrength: faceRestoreStrength,
            tuning: tuning,
            sceneOverride: sceneOverride
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

    private func resolvedUpscaleTargetLongSide(_ recipeTarget: CGFloat?) -> CGFloat? {
        guard let recipeTarget else { return defaultHDLongSide }
        guard recipeTarget > 0 else { return nil }
        return recipeTarget
    }

    private func resolvedPreviewUpscaleTargetLongSide(_ recipeTarget: CGFloat?) -> CGFloat? {
        guard let recipeTarget, recipeTarget > 0 else { return nil }
        return recipeTarget
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

    private func makeEnhancedImage(
        inputURL: URL,
        preset: EnhancementPreset,
        upscaleToLongSide: CGFloat?,
        faceRestoreStrength: Double?,
        tuning: AIEnhancementTuning?,
        sceneOverride: SceneType?
    ) throws -> CIImage {
        guard var image = CIImage(contentsOf: inputURL, options: [.applyOrientationProperty: true]) else {
            throw ImageEnhancerError.cannotLoadImage(inputURL)
        }

        let faceObservations = analyzer.detectFaces(in: inputURL)
        let localDetectedScene = analyzer.detectSceneType(inputURL: inputURL, precomputedFaces: faceObservations)
        let detectedScene = sceneOverride ?? localDetectedScene
        let analysis = analyzer.analyzePhotograph(image)
        let faceMask = createFaceProtectionMask(faceObservations: faceObservations, extent: image.extent.integral)

        let pipeline = resolvePipelineConfig(for: preset, detectedScene: detectedScene)
        let options = pipeline.options
        let recoveryProfile = pipeline.recoveryProfile
        let effectivePreset = effectivePreset(for: preset, detectedScene: detectedScene)

        if recoveryProfile == .conservativePortrait {
            logger.notice(
                "Conservative portrait recovery activated | mode=\(self.recoveryProfileLabel(recoveryProfile), privacy: .public) file=\(inputURL.lastPathComponent, privacy: .public) preset=\(preset.rawValue, privacy: .public) scene=\(self.sceneLabel(detectedScene), privacy: .public) localScene=\(self.sceneLabel(localDetectedScene), privacy: .public)"
            )
        } else {
            logger.debug(
                "Standard recovery profile | file=\(inputURL.lastPathComponent, privacy: .public) preset=\(preset.rawValue, privacy: .public) scene=\(self.sceneLabel(detectedScene), privacy: .public) localScene=\(self.sceneLabel(localDetectedScene), privacy: .public)"
            )
        }

        if recoveryProfile == .conservativePortrait {
            image = localPipeline.makePortraitImage(
                image: image,
                tuning: tuning,
                analysis: analysis,
                faceMask: faceMask,
                upscaleToLongSide: upscaleToLongSide
            )
            image = productIsolationEngine.applyIfNeeded(
                to: image,
                sourceURL: inputURL,
                preset: effectivePreset,
                scene: detectedScene
            )

            return FaceRestoreEngine.applyIfNeeded(
                to: image,
                strength: faceRestoreStrength,
                faceMask: faceMask
            )
        }

        if isPhotographScene(detectedScene) {
            logger.notice(
                "Photo recipe activated | file=\(inputURL.lastPathComponent, privacy: .public) preset=\(preset.rawValue, privacy: .public) scene=\(self.sceneLabel(detectedScene), privacy: .public) localScene=\(self.sceneLabel(localDetectedScene), privacy: .public)"
            )
            image = localPipeline.makePhotographImage(
                image: image,
                scene: detectedScene,
                tuning: tuning,
                analysis: analysis,
                upscaleToLongSide: upscaleToLongSide
            )
            image = productIsolationEngine.applyIfNeeded(
                to: image,
                sourceURL: inputURL,
                preset: effectivePreset,
                scene: detectedScene
            )

            return FaceRestoreEngine.applyIfNeeded(
                to: image,
                strength: faceRestoreStrength,
                faceMask: faceMask
            )
        }

        image = localPipeline.makeStandardImage(
            image: image,
            preset: preset,
            detectedScene: detectedScene,
            profile: recoveryProfile,
            options: options,
            upscaleToLongSide: upscaleToLongSide
        )
        image = productIsolationEngine.applyIfNeeded(
            to: image,
            sourceURL: inputURL,
            preset: effectivePreset,
            scene: detectedScene
        )

        return FaceRestoreEngine.applyIfNeeded(
            to: image,
            strength: faceRestoreStrength,
            faceMask: faceMask
        )
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
        case .ecommerce:
            return .ecommerce
        case .darkPhoto, .generic, .none:
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
        case ecommerce
        case darkPhoto
        case generic
    }

    func detectSceneType(inputURL: URL) -> SceneType? {
        analyzer.detectSceneType(inputURL: inputURL)
    }

    private func isPhotographScene(_ scene: SceneType?) -> Bool {
        switch scene {
        case .portrait, .landscape, .ecommerce, .darkPhoto, .generic, .none:
            return true
        case .document:
            return false
        }
    }

    private func resolveRecoveryProfile(preset: EnhancementPreset, detectedScene: SceneType?) -> RecoveryProfile {
        if preset == .portrait {
            return .conservativePortrait
        }
        if preset == .auto, detectedScene == .portrait {
            return .conservativePortrait
        }
        return .standard
    }

    private func sceneLabel(_ scene: SceneType?) -> String {
        switch scene {
        case .portrait:
            return "portrait"
        case .document:
            return "document"
        case .landscape:
            return "landscape"
        case .ecommerce:
            return "ecommerce"
        case .darkPhoto:
            return "dark-photo"
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
        }
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
}
