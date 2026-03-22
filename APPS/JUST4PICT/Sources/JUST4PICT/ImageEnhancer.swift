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
    case webLite = "Web <300KB"
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
        case .webLite:
            return 1280
        case .ecommerce:
            return preset == .ecommerce ? 2200 : 2000
        }
    }

    var targetByteBudget: Int? {
        switch self {
        case .webLite:
            return 300_000
        case .original, .social, .web, .ecommerce:
            return nil
        }
    }

    var minimumLossyQuality: Double? {
        switch self {
        case .webLite:
            return 0.58
        case .original, .social, .web, .ecommerce:
            return nil
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
    case cannotFitByteBudget(URL, Int)

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
        case .cannotFitByteBudget(let url, let budget):
            return "No se pudo ajustar \(url.lastPathComponent) al objetivo de \(budget / 1000)KB"
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
    private lazy var upscaleEngine = UpscaleEngine(context: context)
    private lazy var analyzer = ImageAnalyzer(context: context)
    private lazy var localPipeline = LocalPhotoPipeline(context: context, upscaleEngine: upscaleEngine)
    private lazy var productIsolationEngine = ProductIsolationEngine(context: context)
    private lazy var documentCorrectionEngine = DocumentCorrectionEngine(context: context)
    private lazy var exportWriter = ImageExportWriter(context: context)
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
        try autoreleasepool {
            let image = try makeEnhancedImage(
                inputURL: inputURL,
                preset: preset,
                upscaleToLongSide: resolvedUpscaleTargetLongSide(upscaleTargetLongSide),
                faceRestoreStrength: faceRestoreStrength,
                tuning: tuning,
                sceneOverride: sceneOverride
            )

            try exportWriter.write(
                image: image,
                sourceURL: inputURL,
                to: outputURL,
                format: format,
                quality: quality,
                exportProfile: exportProfile,
                preset: preset
            )
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
        try autoreleasepool {
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

        // Deteccion de escena base
        let faceObservations = analyzer.detectFaces(in: inputURL)
        let localDetectedScene = analyzer.detectSceneType(inputURL: inputURL, precomputedFaces: faceObservations)
        let detectedScene = sceneOverride ?? localDetectedScene

        // Correccion geometrica temprana (Documentos)
        // Se aplica antes del analisis tonal para que el histograma ignore el fondo recortado
        let effectivePreset = effectivePreset(for: preset, detectedScene: detectedScene)
        image = documentCorrectionEngine.applyIfNeeded(to: image, scene: detectedScene, preset: effectivePreset)

        // Analisis y mascaras sobre la imagen geometricamente final
        let analysis = analyzer.analyzePhotograph(image)
        // Nota: Si hubo recorte de documento, la mascara facial basada en coordenadas originales podria desviarse.
        // En documentos asumimos que la prioridad es el texto/papel y no la proteccion facial precisa.
        let faceMask = createFaceProtectionMask(faceObservations: faceObservations, extent: image.extent.integral)
        
        let pipeline = resolvePipelineConfig(for: preset, detectedScene: detectedScene)
        let options = pipeline.options
        let recoveryProfile = pipeline.recoveryProfile

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
            if detectedScene == .darkPhoto {
                // TODO: Move this specific pipeline logic to LocalPhotoPipeline for better separation of concerns.
                image = makeDarkPhotoRecoveryImage(
                    image: image,
                    analysis: analysis,
                    upscaleToLongSide: upscaleToLongSide
                )
            } else {
                image = localPipeline.makePhotographImage(
                    image: image,
                    scene: detectedScene,
                    tuning: tuning,
                    analysis: analysis,
                    upscaleToLongSide: upscaleToLongSide
                )
            }
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

    // CORRECCIÓN — makeDarkPhotoRecoveryImage
    // Archivo: APPS/JUST4PICT/Sources/JUST4PICT/ImageEnhancer.swift
    //
    // El parámetro `analysis` ya no es una firma mentirosa:
    // se usa para adaptar exposición, sombras y reducción de ruido
    // según la luminancia media y el perfil tonal real de la imagen.
    private func makeDarkPhotoRecoveryImage(
        image: CIImage,
        analysis: PhotoAnalysis,
        upscaleToLongSide: CGFloat?
    ) -> CIImage {
        var currentImage = image
        logger.notice(
            "Applying dark photo recovery pipeline | lum=\(String(format: \"%.3f\", analysis.averageLuminance)) lowKey=\(analysis.isLowKey)"
        )

        // ── 1. Exposición adaptativa ─────────────────────────────────────────────
        // Cuanto más oscura la imagen, más boost necesita.
        // Tres franjas calibradas sobre el rango esperado de darkPhoto
        // (isLowKey => luminance < 0.42, con el núcleo real entre 0.18 y 0.38).
        //   < 0.28  → imagen muy oscura, boost fuerte
        //   0.28–0.34 → oscura moderada, boost medio
        //   ≥ 0.34  → rozando el umbral, boost suave
        // Techo en 0.72 EV para no quemar altas luces en imágenes con zonas claras.
        let lum = analysis.averageLuminance
        let exposureEV: Float
        switch lum {
        case ..<0.28:
            exposureEV = 0.68
        case 0.28..<0.34:
            exposureEV = 0.50
        default:
            exposureEV = 0.34
        }

        // ── 2. Sombras adaptativas ───────────────────────────────────────────────
        // isLowKey indica imagen dominantemente oscura: abre sombras con más fuerza.
        // Si no es lowKey (imagen puntualmente subexpuesta pero con zonas medias),
        // un shadowAmount excesivo destruye el contraste percibido.
        let shadowAmount: Float = analysis.isLowKey ? 0.88 : 0.64
        let highlightAmount: Float = analysis.isLowKey ? 0.92 : 0.96

        let shadowsHighlights = CIFilter.highlightShadowAdjust()
        shadowsHighlights.inputImage = currentImage
        shadowsHighlights.shadowAmount = shadowAmount
        shadowsHighlights.highlightAmount = highlightAmount
        currentImage = shadowsHighlights.outputImage ?? currentImage

        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = currentImage
        exposure.ev = exposureEV
        currentImage = exposure.outputImage ?? currentImage

        // ── 3. Color y contraste ─────────────────────────────────────────────────
        // Sin cambio respecto a la versión anterior: vibrance moderado
        // y un toque de contraste/saturación para recuperar color sin saturar.
        if let vibrance = CIFilter(name: "CIVibrance") {
            vibrance.setValue(currentImage, forKey: kCIInputImageKey)
            vibrance.setValue(0.25, forKey: "inputAmount")
            currentImage = vibrance.outputImage ?? currentImage
        }

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = currentImage
        colorControls.saturation = 1.1
        colorControls.contrast = 1.08
        currentImage = colorControls.outputImage ?? currentImage

        // ── 4. Reducción de ruido adaptativa ────────────────────────────────────
        // Imágenes muy oscuras tienen más ruido digital: subir noiseLevel
        // cuando la luminancia es baja. Techo conservador para no
        // plastificar la imagen antes del sharpen final.
        let noiseLevel: Float = lum < 0.28 ? 0.10 : 0.08

        let noiseReduction = CIFilter.noiseReduction()
        noiseReduction.inputImage = currentImage
        noiseReduction.noiseLevel = noiseLevel
        noiseReduction.sharpness = 0.1
        currentImage = noiseReduction.outputImage ?? currentImage

        // ── 5. Upscale opcional ──────────────────────────────────────────────────
        if let upscaleToLongSide {
            let upscaleResult = upscaleEngine.upscaleIfNeeded(
                image: currentImage,
                targetLongSide: upscaleToLongSide,
                allowExternalBackend: true
            )
            currentImage = upscaleResult.image
        }

        // ── 6. Sharpen final ─────────────────────────────────────────────────────
        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = currentImage
        sharpen.radius = 1.8
        sharpen.intensity = 0.35
        currentImage = sharpen.outputImage ?? currentImage

        return currentImage.cropped(to: currentImage.extent)
    }
}
