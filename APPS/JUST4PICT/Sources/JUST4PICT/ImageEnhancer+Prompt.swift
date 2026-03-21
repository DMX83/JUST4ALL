// Prompt IA óptimo según tipo de imagen detectado
import Foundation

extension ImageEnhancer {
    public func promptForImageType(inputURL: URL) -> String {
        let scene = detectSceneType(inputURL: inputURL)
        switch scene {
        case .portrait:
            return """
Enhance this portrait into a professional editorial-quality photo.

Improve:
- facial detail, eyes, hair definition, and skin tone balance
- exposure, contrast, and white balance
- subtle skin cleanup while keeping pores and natural texture
- noise reduction and compression cleanup
- realistic color grading

Preserve exactly:
- identity, facial structure, expression, age appearance
- pose, wardrobe, background, and lighting direction

Avoid:
- changing features, beautifying excessively, plastic skin, fake makeup, artificial blur, or stylized effects

Result:
premium, realistic, polished portrait photography
"""
        case .document:
            return """
Enhance this document photo for maximum clarity and readability.

Improve:
- sharpness, contrast, and text legibility
- remove noise and compression artifacts
- correct perspective and lighting if needed

Preserve:
- all original content and layout

Avoid:
- inventing or altering text, adding artifacts, or changing document structure

Result:
clear, readable, realistic document scan
"""
        default:
            return """
Professionally enhance this image while keeping it fully realistic.

Adjust:
- exposure, white balance, highlight and shadow balance
- clarity, texture, and fine detail
- noise reduction and artifact cleanup
- natural color correction and tonal balance

Preserve:
- composition, subjects, scene structure, and realism

Do not:
- invent details, change identities, alter objects, or apply artistic styles

Result:
natural, premium, high-resolution photographic finish
"""
        }
    }
}
