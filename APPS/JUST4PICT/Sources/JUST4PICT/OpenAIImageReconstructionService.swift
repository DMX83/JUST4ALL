import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum OpenAIImageReconstructionError: LocalizedError {
    case unavailable
    case invalidDownloadedImage
    case failedToWriteOutput

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Reconstrucción IA no disponible: falta configurar OPENAI_API_KEY"
        case .invalidDownloadedImage:
            return "La respuesta de reconstrucción IA no devolvió una imagen válida"
        case .failedToWriteOutput:
            return "No se pudo escribir la salida reconstruida"
        }
    }
}

final class OpenAIImageReconstructionService {
    private let client: OpenAIImageEditClient?

    init(client: OpenAIImageEditClient? = OpenAIImageEditClient(model: "gpt-image-1")) {
        self.client = client
    }

    var isAvailable: Bool {
        client != nil
    }

    static func defaultPrompt() -> String {
        """
        Restore and reconstruct this low-resolution or compressed image conservatively. Preserve identity, framing, lighting, colors and scene layout as much as possible. Remove heavy compression artifacts and rebuild plausible detail without changing the composition, adding objects, stylizing the image or over-smoothing faces.
        """
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
        quality: Double
    ) async throws {
        let downloadedImage = try await reconstructNSImage(inputURL: inputURL)
        try write(image: downloadedImage, to: outputURL, format: format, quality: quality)
    }

    func reconstructPreviewImage(inputURL: URL) async throws -> NSImage {
        try await reconstructNSImage(inputURL: inputURL)
    }

    private func reconstructNSImage(inputURL: URL) async throws -> NSImage {
        guard let client else { throw OpenAIImageReconstructionError.unavailable }

        let pixelSize = pixelSize(for: inputURL)
        let size = Self.recommendedCanvasSize(for: pixelSize)
        let urls = try await client.editImage(
            imageURL: inputURL,
            prompt: Self.defaultPrompt(),
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

    private func write(image: NSImage, to outputURL: URL, format: OutputFormat, quality: Double) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OpenAIImageReconstructionError.failedToWriteOutput
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            format.utTypeIdentifier,
            1,
            nil
        ) else {
            throw OpenAIImageReconstructionError.failedToWriteOutput
        }

        var options: [CFString: Any] = [:]
        if format.supportsLossyQuality {
            options[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0.1), 1.0)
        }

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw OpenAIImageReconstructionError.failedToWriteOutput
        }
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
