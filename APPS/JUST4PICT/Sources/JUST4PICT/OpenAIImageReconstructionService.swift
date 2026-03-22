import Foundation
import AppKit
import ImageIO

enum ReconstructionIntent: Equatable {
    case general
    case ecommerceCleanup
}

enum OpenAIImageReconstructionError: LocalizedError {
    case unavailable
    case invalidDownloadedImage

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Reconstrucción IA no disponible: falta configurar OPENAI_API_KEY"
        case .invalidDownloadedImage:
            return "La respuesta de reconstrucción IA no devolvió una imagen válida"
        }
    }
}

final class OpenAIImageReconstructionService {
    private let client: OpenAIImageEditClient?
    private let exportWriter: ImageExportWriter

    init(
        client: OpenAIImageEditClient? = OpenAIImageEditClient(model: "gpt-image-1"),
        exportWriter: ImageExportWriter = ImageExportWriter(context: ImageEnhancer.sharedContext)
    ) {
        self.client = client
        self.exportWriter = exportWriter
    }

    var isAvailable: Bool {
        client != nil
    }

    static func defaultPrompt(for intent: ReconstructionIntent = .general) -> String {
        switch intent {
        case .general:
            return """
            Restore and reconstruct this low-resolution or compressed image conservatively. Preserve identity, framing, lighting, colors and scene layout as much as possible. Remove heavy compression artifacts and rebuild plausible detail without changing the composition, adding objects, stylizing the image or over-smoothing faces.
            """
        case .ecommerceCleanup:
            return """
            Restore this product image conservatively for ecommerce. Preserve the product identity, branding, label text, shape and colors. Clean up compression artifacts, improve edge definition, isolate the main product cleanly, and place it centered on a plain white background without adding props, shadows, reflections or changing the product geometry.
            """
        }
    }

    static func recommendedIntent(
        preset: EnhancementPreset,
        scene: ImageEnhancer.SceneType?
    ) -> ReconstructionIntent {
        if preset == .ecommerce || scene == .ecommerce {
            return .ecommerceCleanup
        }
        return .general
    }

    static func recommendedCanvasSize(for pixelSize: CGSize) -> String {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return "1024x1024" }
        if pixelSize.width > pixelSize.height * 1.15 {
            return "1536x1024"
        }
        if pixelSize.height > pixelSize.width * 1.15 {
            return "1024x1536"
        }
        return "1024x1024"
    }

    func reconstructImage(
        inputURL: URL,
        outputURL: URL,
        format: OutputFormat,
        quality: Double,
        exportProfile: ExportProfile,
        preset: EnhancementPreset,
        intent: ReconstructionIntent
    ) async throws {
        let downloadedImage = try await reconstructNSImage(inputURL: inputURL, intent: intent)
        try exportWriter.write(
            image: downloadedImage,
            sourceURL: inputURL,
            to: outputURL,
            format: format,
            quality: quality,
            exportProfile: exportProfile,
            preset: preset
        )
    }

    func reconstructPreviewImage(
        inputURL: URL,
        intent: ReconstructionIntent
    ) async throws -> NSImage {
        try await reconstructNSImage(inputURL: inputURL, intent: intent)
    }

    private func reconstructNSImage(
        inputURL: URL,
        intent: ReconstructionIntent
    ) async throws -> NSImage {
        guard let client else { throw OpenAIImageReconstructionError.unavailable }

        let pixelSize = pixelSize(for: inputURL)
        let size = Self.recommendedCanvasSize(for: pixelSize)
        let urls = try await client.editImage(
            imageURL: inputURL,
            prompt: Self.defaultPrompt(for: intent),
            n: 1,
            size: size,
            responseFormat: "url"
        )

        guard let firstURL = urls.first else {
            throw OpenAIImageReconstructionError.invalidDownloadedImage
        }

        let (data, _) = try await URLSession.shared.data(from: firstURL)
        guard let image = NSImage(data: data) else {
            throw OpenAIImageReconstructionError.invalidDownloadedImage
        }

        return image
    }

    private func pixelSize(for inputURL: URL) -> CGSize {
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return .zero
        }

        return CGSize(width: width, height: height)
    }
}
