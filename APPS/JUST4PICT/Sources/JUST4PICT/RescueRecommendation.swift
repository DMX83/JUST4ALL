import Foundation
import CoreGraphics

enum RescueRecommendation: Equatable {
    case pro
    case realESRGAN
    case reconstructAI

    var title: String {
        switch self {
        case .pro:
            return "PRO"
        case .realESRGAN:
            return "Real-ESRGAN"
        case .reconstructAI:
            return "Reconstruir IA"
        }
    }

    var summary: String {
        switch self {
        case .pro:
            return "La imagen ya está en una zona segura para el pipeline local."
        case .realESRGAN:
            return "Mejor opción para imagen pequeña no facial cuando hace falta recuperar detalle aparente."
        case .reconstructAI:
            return "Mejor opción para miniaturas extremas o retratos muy degradados donde hace falta reconstrucción, no solo upscale."
        }
    }
}

enum RescueRecommendationEngine {
    static func recommend(
        pixelSize: CGSize?,
        scene: ImageEnhancer.SceneType?,
        fileSizeBytes: Int64?
    ) -> RescueRecommendation {
        let width = max(pixelSize?.width ?? 0, 0)
        let height = max(pixelSize?.height ?? 0, 0)
        let longSide = max(width, height)
        let shortSide = min(width, height)
        let fileSize = max(fileSizeBytes ?? 0, 0)

        let isExtremeMiniature = longSide > 0 && (longSide <= 700 || shortSide <= 420)
        let isVeryCompressed = fileSize > 0 && fileSize <= 45_000
        let isModeratelySmall = longSide > 0 && longSide <= 1400

        if scene == .portrait {
            if isExtremeMiniature || isVeryCompressed {
                return .reconstructAI
            }
            return .pro
        }

        if isExtremeMiniature || isVeryCompressed {
            return .reconstructAI
        }

        if isModeratelySmall {
            return .realESRGAN
        }

        return .pro
    }
}
