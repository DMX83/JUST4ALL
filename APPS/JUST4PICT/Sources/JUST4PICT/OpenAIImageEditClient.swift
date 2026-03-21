import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum OpenAIImageEditError: LocalizedError {
    case missingAPIKey
    case apiError(String)
    case invalidResponse
    case failedToLoadImage

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No se encontró OPENAI_API_KEY en variables de entorno o .env.secrets"
        case .apiError(let msg):
            return "OpenAI API error: \(msg)"
        case .invalidResponse:
            return "Respuesta inválida de la API de imagen"
        case .failedToLoadImage:
            return "No se pudo cargar la imagen para enviar a la API"
        }
    }
}

final class OpenAIImageEditClient {
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/images/edits"
    private let model: String

    init?(model: String = "dall-e-2") {
        guard let key = OpenAIImageAdvisor.resolveAPIKey(), !key.isEmpty else { return nil }
        self.apiKey = key
        self.model = model
    }

    func editImage(
        imageURL: URL,
        prompt: String,
        n: Int = 1,
        size: String = "1024x1024",
        responseFormat: String = "url"
    ) async throws -> [URL] {
        guard let imageData = makeRGBAImageData(from: imageURL) else {
            throw OpenAIImageEditError.failedToLoadImage
        }

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // Image file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"input.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        // Prompt
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append(prompt.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        // model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append(model.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        // n
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"n\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(n)\r\n".data(using: .utf8)!)
        // size
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"size\"\r\n\r\n".data(using: .utf8)!)
        body.append(size.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        // response_format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append(responseFormat.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        // End
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP error"
            throw OpenAIImageEditError.apiError(msg)
        }
        guard let result = try? JSONDecoder().decode(OpenAIImageEditResponse.self, from: data) else {
            throw OpenAIImageEditError.invalidResponse
        }
        let urls = result.data.compactMap { URL(string: $0.url) }
        if urls.isEmpty { throw OpenAIImageEditError.invalidResponse }
        return urls
    }

    private func makeRGBAImageData(from imageURL: URL) -> Data? {
        guard let image = NSImage(contentsOf: imageURL) else {
            return nil
        }

        let proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: proposedRect)
        guard let rgbaImage = context.makeImage() else {
            return nil
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, rgbaImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }
}

private struct OpenAIImageEditResponse: Decodable {
    struct ImageData: Decodable {
        let url: String
    }
    let data: [ImageData]
}

// Data extension for multipart
private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
