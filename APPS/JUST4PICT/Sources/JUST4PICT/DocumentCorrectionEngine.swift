import Foundation
import CoreImage
import Vision
import OSLog

final class DocumentCorrectionEngine {
    private let context: CIContext
    private let logger = Logger(subsystem: "com.dmx83.just4pict", category: "DocumentCorrectionEngine")

    init(context: CIContext) {
        self.context = context
    }

    func applyIfNeeded(
        to image: CIImage,
        scene: ImageEnhancer.SceneType?,
        preset: EnhancementPreset
    ) -> CIImage {
        // Solo aplicar si la escena o el preset indican explícitamente "Documento"
        guard shouldApplyCorrection(scene: scene, preset: preset) else {
            return image
        }

        return correctPerspective(image)
    }

    private func shouldApplyCorrection(scene: ImageEnhancer.SceneType?, preset: EnhancementPreset) -> Bool {
        return scene == .document || preset == .document
    }

    private func correctPerspective(_ image: CIImage) -> CIImage {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.8  // Solo correcciones muy seguras
        request.minimumAspectRatio = 0.3
        request.quadratureTolerance = 45.0 // Permitir cierta distorsión
        request.maximumObservations = 1

        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                return image
            }

            // Vision devuelve coordenadas normalizadas (0..1) con origen abajo-izquierda (igual que Core Image)
            let imageSize = image.extent.size
            let topLeft = observation.topLeft.scaled(to: imageSize)
            let topRight = observation.topRight.scaled(to: imageSize)
            let bottomLeft = observation.bottomLeft.scaled(to: imageSize)
            let bottomRight = observation.bottomRight.scaled(to: imageSize)

            logger.notice("Applying perspective correction | confidence=\(observation.confidence) bounds=\(String(describing: observation.boundingBox))")

            let filter = CIFilter(name: "CIPerspectiveCorrection")!
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
            filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
            filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
            filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")

            return filter.outputImage ?? image

        } catch {
            logger.error("Vision rectangle detection failed: \(error.localizedDescription)")
            return image
        }
    }
}

private extension CGPoint {
    func scaled(to size: CGSize) -> CGPoint {
        return CGPoint(x: x * size.width, y: y * size.height)
    }
}