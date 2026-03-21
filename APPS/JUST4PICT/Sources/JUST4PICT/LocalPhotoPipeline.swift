import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

final class LocalPhotoPipeline {
    private let context: CIContext

    init(context: CIContext) {
        self.context = context
    }

    func makePortraitImage(
        image: CIImage,
        tuning: AIEnhancementTuning?,
        analysis: PhotoAnalysis,
        faceMask: CIImage?,
        upscaleToLongSide: CGFloat?
    ) -> CIImage {
        var output = applyPortraitGuidedEnhancement(
            image: image,
            tuning: tuning,
            analysis: analysis,
            faceMask: faceMask
        )

        if let targetLongSide = upscaleToLongSide {
            let upscaleResult = applyUpscaleIfNeeded(image: output, targetLongSide: targetLongSide)
            output = upscaleResult.image

            if upscaleResult.upscaled {
                output = applyPortraitUpscaleFinish(image: output, scale: upscaleResult.scale)
            }
        }

        return output
    }

    func makePhotographImage(
        image: CIImage,
        scene: ImageEnhancer.SceneType?,
        tuning: AIEnhancementTuning?,
        analysis: PhotoAnalysis,
        upscaleToLongSide: CGFloat?
    ) -> CIImage {
        var output = applyAppleLikePhotoEnhancement(
            image: image,
            scene: scene,
            tuning: tuning,
            analysis: analysis
        )

        if let targetLongSide = upscaleToLongSide {
            let upscaleResult = applyUpscaleIfNeeded(image: output, targetLongSide: targetLongSide)
            output = upscaleResult.image

            if upscaleResult.upscaled {
                output = applyPhotoUpscaleFinish(image: output, scale: upscaleResult.scale)
            }
        }

        return output
    }

    func makeStandardImage(
        image: CIImage,
        preset: EnhancementPreset,
        detectedScene: ImageEnhancer.SceneType?,
        profile: RecoveryProfile,
        options: EnhancementOptions,
        upscaleToLongSide: CGFloat?
    ) -> CIImage {
        var output = image

        if options.enableAutoAdjust {
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

        output = applyColorControls(
            image: output,
            brightness: options.brightness,
            contrast: options.contrast,
            saturation: options.saturation
        )

        output = applyProfessionalToneBalance(
            image: output,
            preset: preset,
            detectedScene: detectedScene,
            profile: profile
        )

        if profile == .conservativePortrait || profile == .legacyConservativePortrait {
            output = applyPortraitSafetyFinish(image: output, profile: profile)
        }

        if options.noiseReduction > 0.0 {
            output = applyNoiseReduction(image: output, amount: options.noiseReduction)
        }

        if options.sharpness > 0.0 {
            output = applySharpen(image: output, amount: options.sharpness)
        }

        if let targetLongSide = upscaleToLongSide {
            let upscaleResult = applyUpscaleIfNeeded(image: output, targetLongSide: targetLongSide)
            output = upscaleResult.image

            if upscaleResult.upscaled {
                output = applyPostUpscaleDetailRecovery(image: output, scale: upscaleResult.scale, profile: profile)
            }
        }

        return output
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
        detectedScene: ImageEnhancer.SceneType?,
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
            case .darkPhoto, .generic, .none:
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
        case .auto where detectedScene == .darkPhoto:
            shadowAmount = 0.26
            highlightAmount = 0.14
            exposureEV = 0.10
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

    private func applyAppleLikePhotoEnhancement(
        image: CIImage,
        scene: ImageEnhancer.SceneType?,
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

    private func defaultAITuning(for scene: ImageEnhancer.SceneType?, analysis: PhotoAnalysis) -> AIEnhancementTuning {
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
        case .darkPhoto:
            return AIEnhancementTuning(
                shadowAmount: 0.30,
                highlightAmount: 0.82,
                vibrance: 0.04,
                sharpen: 0.12,
                sharpenRadius: 0.40,
                contrast: 0.99,
                saturation: 0.99,
                exposureEV: 0.08
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

    private func constrainAITuning(_ tuning: AIEnhancementTuning, for scene: ImageEnhancer.SceneType?) -> AIEnhancementTuning {
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
        case .darkPhoto:
            return AIEnhancementTuning(
                shadowAmount: min(max(base.shadowAmount, 0.24), 0.40),
                highlightAmount: min(max(base.highlightAmount, 0.76), 0.94),
                vibrance: min(max(base.vibrance, 0.02), 0.10),
                sharpen: min(max(base.sharpen, 0.08), 0.18),
                sharpenRadius: min(max(base.sharpenRadius, 0.30), 0.55),
                contrast: min(max(base.contrast, 0.97), 1.01),
                saturation: min(max(base.saturation, 0.98), 1.02),
                exposureEV: min(max(base.exposureEV, 0.03), 0.10)
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
