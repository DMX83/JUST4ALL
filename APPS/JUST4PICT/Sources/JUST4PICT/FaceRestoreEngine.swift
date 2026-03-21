import CoreImage
import CoreImage.CIFilterBuiltins

enum FaceRestoreEngine {
    static func applyIfNeeded(
        to image: CIImage,
        strength: Double?,
        faceMask: CIImage?
    ) -> CIImage {
        guard let strength, strength > 0, let faceMask else {
            return image
        }

        let normalizedStrength = min(max(strength, 0.0), 1.0)
        guard normalizedStrength > 0 else {
            return image
        }

        var restored = image

        let noiseReduction = CIFilter.noiseReduction()
        noiseReduction.inputImage = restored
        noiseReduction.noiseLevel = Float(0.002 + (normalizedStrength * 0.006))
        noiseReduction.sharpness = Float(0.10 + (normalizedStrength * 0.08))
        restored = noiseReduction.outputImage ?? restored

        let microDetail = CIFilter.unsharpMask()
        microDetail.inputImage = restored
        microDetail.radius = Float(0.35 + (normalizedStrength * 0.45))
        microDetail.intensity = Float(0.10 + (normalizedStrength * 0.18))
        restored = microDetail.outputImage ?? restored

        let tonalLift = CIFilter.colorControls()
        tonalLift.inputImage = restored
        tonalLift.brightness = Float(normalizedStrength * 0.006)
        tonalLift.contrast = Float(1.0 + (normalizedStrength * 0.015))
        tonalLift.saturation = Float(1.0 + (normalizedStrength * 0.018))
        restored = tonalLift.outputImage ?? restored

        let blend = CIFilter.blendWithMask()
        blend.inputImage = restored
        blend.backgroundImage = image
        blend.maskImage = faceMask.cropped(to: image.extent)
        return (blend.outputImage ?? image).cropped(to: image.extent)
    }
}
