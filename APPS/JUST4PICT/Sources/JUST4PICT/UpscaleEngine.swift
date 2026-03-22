import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

struct UpscaleResult {
    let image: CIImage
    let upscaled: Bool
    let scale: CGFloat
    let backend: UpscaleBackendKind
}

enum UpscaleBackendKind: String {
    case localLanczos = "local_lanczos"
    case realESRGAN = "real_esrgan"
}

struct UpscaleBackendResolution: Equatable {
    let backend: UpscaleBackendKind
    let scaleFactor: Int?
}

final class UpscaleEngine {
    private let context: CIContext
    private let fileManager: FileManager
    private struct RealESRGANInstallation {
        let binaryURL: URL
        let modelDirectoryURL: URL
        let modelName: String
    }

    init(context: CIContext, fileManager: FileManager = .default) {
        self.context = context
        self.fileManager = fileManager
    }

    func upscaleIfNeeded(image: CIImage, targetLongSide: CGFloat) -> UpscaleResult {
        let extent = image.extent.integral
        let currentLongSide = max(extent.width, extent.height)
        guard currentLongSide > 0, currentLongSide < targetLongSide else {
            return UpscaleResult(image: image, upscaled: false, scale: 1.0, backend: .localLanczos)
        }

        let resolution = Self.resolveBackend(
            environment: ProcessInfo.processInfo.environment,
            currentLongSide: currentLongSide,
            targetLongSide: targetLongSide
        )

        if resolution.backend == .realESRGAN,
           let scaleFactor = resolution.scaleFactor,
           let installation = Self.findRealESRGANInstallation(environment: ProcessInfo.processInfo.environment),
           let upscaledImage = try? upscaleWithRealESRGAN(
                image: image,
                installation: installation,
                scaleFactor: scaleFactor,
                targetLongSide: targetLongSide
           ) {
            return UpscaleResult(
                image: upscaledImage,
                upscaled: true,
                scale: targetLongSide / currentLongSide,
                backend: .realESRGAN
            )
        }

        return localLanczosUpscale(image: image, targetLongSide: targetLongSide)
    }

    static func resolveBackend(
        environment: [String: String],
        currentLongSide: CGFloat,
        targetLongSide: CGFloat
    ) -> UpscaleBackendResolution {
        guard currentLongSide > 0, targetLongSide > currentLongSide else {
            return UpscaleBackendResolution(backend: .localLanczos, scaleFactor: nil)
        }

        guard findRealESRGANInstallation(environment: environment) != nil else {
            return UpscaleBackendResolution(backend: .localLanczos, scaleFactor: nil)
        }

        let requestedScale = targetLongSide / currentLongSide
        guard currentLongSide <= 1600, requestedScale >= 1.35 else {
            return UpscaleBackendResolution(backend: .localLanczos, scaleFactor: nil)
        }

        let scaleFactor = requestedScale > 2.25 ? 4 : 2
        return UpscaleBackendResolution(backend: .realESRGAN, scaleFactor: scaleFactor)
    }

    static func findRealESRGANBinary(environment: [String: String]) -> URL? {
        findRealESRGANInstallation(environment: environment)?.binaryURL
    }

    private static func findRealESRGANInstallation(environment: [String: String]) -> RealESRGANInstallation? {
        let modelName = "realesrgan-x4plus"

        if let explicit = environment["JUST4PICT_REAL_ESRGAN_BIN"], !explicit.isEmpty {
            let url = URL(fileURLWithPath: explicit)
            if FileManager.default.isExecutableFile(atPath: url.path),
               let modelDirectoryURL = resolveModelDirectory(
                    environment: environment,
                    binaryURL: url,
                    modelName: modelName
               ) {
                return RealESRGANInstallation(
                    binaryURL: url,
                    modelDirectoryURL: modelDirectoryURL,
                    modelName: modelName
                )
            }
        }

        let pathValue = environment["PATH"] ?? ""
        for component in pathValue.split(separator: ":") {
            let url = URL(fileURLWithPath: String(component))
                .appendingPathComponent("realesrgan-ncnn-vulkan")
            if FileManager.default.isExecutableFile(atPath: url.path),
               let modelDirectoryURL = resolveModelDirectory(
                    environment: environment,
                    binaryURL: url,
                    modelName: modelName
               ) {
                return RealESRGANInstallation(
                    binaryURL: url,
                    modelDirectoryURL: modelDirectoryURL,
                    modelName: modelName
                )
            }
        }

        return nil
    }

    private static func resolveModelDirectory(
        environment: [String: String],
        binaryURL: URL,
        modelName: String
    ) -> URL? {
        let fm = FileManager.default
        let candidateURLs: [URL]

        if let explicit = environment["JUST4PICT_REAL_ESRGAN_MODELS"], !explicit.isEmpty {
            candidateURLs = [URL(fileURLWithPath: explicit)]
        } else {
            candidateURLs = [binaryURL.deletingLastPathComponent().appendingPathComponent("models", isDirectory: true)]
        }

        for candidate in candidateURLs {
            let paramURL = candidate.appendingPathComponent("\(modelName).param")
            let binURL = candidate.appendingPathComponent("\(modelName).bin")
            if fm.fileExists(atPath: paramURL.path), fm.fileExists(atPath: binURL.path) {
                return candidate
            }
        }

        return nil
    }

    private func localLanczosUpscale(image: CIImage, targetLongSide: CGFloat) -> UpscaleResult {
        let extent = image.extent.integral
        let currentLongSide = max(extent.width, extent.height)
        guard currentLongSide > 0, currentLongSide < targetLongSide else {
            return UpscaleResult(image: image, upscaled: false, scale: 1.0, backend: .localLanczos)
        }

        let scale = targetLongSide / currentLongSide
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1.0
        let output = (filter.outputImage ?? image).cropped(to: (filter.outputImage ?? image).extent.integral)
        return UpscaleResult(image: output, upscaled: true, scale: scale, backend: .localLanczos)
    }

    private func upscaleWithRealESRGAN(
        image: CIImage,
        installation: RealESRGANInstallation,
        scaleFactor: Int,
        targetLongSide: CGFloat
    ) throws -> CIImage {
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("just4pict-realesrgan-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let inputURL = tempDirectory.appendingPathComponent("input.png")
        let outputURL = tempDirectory.appendingPathComponent("output.png")
        try writePNG(image: image, to: inputURL)

        let process = Process()
        process.executableURL = installation.binaryURL
        process.arguments = [
            "-i", inputURL.path,
            "-o", outputURL.path,
            "-s", String(scaleFactor),
            "-m", installation.modelDirectoryURL.path,
            "-n", installation.modelName
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              fileManager.fileExists(atPath: outputURL.path),
              let outputImage = CIImage(contentsOf: outputURL, options: [.applyOrientationProperty: true]) else {
            throw NSError(domain: "UpscaleEngine", code: 1)
        }

        return resizeIfNeeded(image: outputImage, targetLongSide: targetLongSide)
    }

    private func resizeIfNeeded(image: CIImage, targetLongSide: CGFloat) -> CIImage {
        let extent = image.extent.integral
        let currentLongSide = max(extent.width, extent.height)
        guard currentLongSide > 0 else { return image }
        guard currentLongSide != targetLongSide else { return image }

        let scale = targetLongSide / currentLongSide
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1.0
        return (filter.outputImage ?? image).cropped(to: (filter.outputImage ?? image).extent.integral)
    }

    private func writePNG(image: CIImage, to url: URL) throws {
        let extent = image.extent.integral
        guard let cgImage = context.createCGImage(image, from: extent) else {
            throw NSError(domain: "UpscaleEngine", code: 2)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "UpscaleEngine", code: 3)
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "UpscaleEngine", code: 4)
        }
    }
}
