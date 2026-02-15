import Foundation
import UniformTypeIdentifiers
import AVFoundation

enum ConversionType: String, CaseIterable, Identifiable {
    case audio = "Audio"
    case video = "Video"
    case image = "Imagen"

    var id: String { rawValue }

    var allowedContentTypes: [UTType] {
        switch self {
        case .audio:
            return [.audio]
        case .video:
            return [.movie, .video]
        case .image:
            return [.image]
        }
    }
}

enum ConversionFormat: String, CaseIterable, Identifiable, Codable {
    case m4a = "m4a"
    case mp3 = "mp3"
    case flac = "flac"
    case mov = "mov"
    case mp4 = "mp4"
    case mkv = "mkv"
    case jpg = "jpg"
    case png = "png"
    case heic = "heic"
    case heif = "heif"
    case webp = "webp"
    case tiff = "tiff"
    case bmp = "bmp"
    case gif = "gif"

    var id: String { rawValue }

    static func supportedFormats(for type: ConversionType) -> [ConversionFormat] {
        switch type {
        case .audio:
            return [.m4a, .mp3, .flac]
        case .video:
            return [.mov, .mp4, .mkv]
        case .image:
            return [.jpg, .png, .heic, .heif, .webp, .tiff, .bmp, .gif]
        }
    }

    static func defaultFormat(for type: ConversionType) -> ConversionFormat {
        supportedFormats(for: type).first ?? .m4a
    }

    var displayLabel: String {
        switch self {
        case .flac:
            return "FLAC (pendiente)"
        default:
            return rawValue.uppercased()
        }
    }

    var isSelectableOutput: Bool {
        switch self {
        case .flac:
            return false
        default:
            return true
        }
    }

    var isImageFormat: Bool {
        switch self {
        case .jpg, .png, .heic, .heif, .webp, .tiff, .bmp, .gif:
            return true
        case .m4a, .mp3, .flac, .mov, .mp4, .mkv:
            return false
        }
    }

    var supportsLossyQuality: Bool {
        switch self {
        case .jpg, .heic, .heif, .webp:
            return true
        case .png, .tiff, .bmp, .gif, .m4a, .mp3, .flac, .mov, .mp4, .mkv:
            return false
        }
    }
}

enum AudioBitrateOption: Int, CaseIterable, Identifiable {
    case bps128 = 128000
    case bps192 = 192000
    case bps256 = 256000

    var id: Int { rawValue }

    var label: String {
        "\(rawValue / 1000) kbps"
    }
}

enum VideoResolutionOption: String, CaseIterable, Identifiable {
    case original = "Original"
    case p720 = "1280x720"
    case p1080 = "1920x1080"

    var id: String { rawValue }

    var size: CGSize? {
        switch self {
        case .original:
            return nil
        case .p720:
            return CGSize(width: 1280, height: 720)
        case .p1080:
            return CGSize(width: 1920, height: 1080)
        }
    }
}

enum VideoFpsOption: Int, CaseIterable, Identifiable {
    case original = 0
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }

    var label: String {
        rawValue == 0 ? "Original" : "\(rawValue) fps"
    }
}

enum VideoCodecOption: String, CaseIterable, Identifiable {
    case h264 = "H.264"
    case hevc = "HEVC"

    var id: String { rawValue }

    var fileType: AVFileType {
        .mp4
    }

    var exportPreset: String {
        switch self {
        case .h264:
            return AVAssetExportPresetHighestQuality
        case .hevc:
            return AVAssetExportPresetHEVCHighestQuality
        }
    }

    var compressionType: AVVideoCodecType {
        switch self {
        case .h264:
            return .h264
        case .hevc:
            return .hevc
        }
    }
}

enum VideoBitrateOption: Int, CaseIterable, Identifiable {
    case auto = 0
    case bps2m = 2_000_000
    case bps4m = 4_000_000
    case bps8m = 8_000_000

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .auto:
            return "Auto"
        default:
            return "\(rawValue / 1_000_000) Mbps"
        }
    }
}

enum ImageQualityOption: Int, CaseIterable, Identifiable {
    case q70 = 70
    case q85 = 85
    case q95 = 95

    var id: Int { rawValue }

    var label: String {
        "\(rawValue)%"
    }
}

struct ConversionSettings {
    var audioBitrate: AudioBitrateOption
    var videoResolution: VideoResolutionOption
    var videoFps: VideoFpsOption
    var videoCodec: VideoCodecOption
    var videoBitrate: VideoBitrateOption
    var imageQuality: ImageQualityOption
}

enum ConvertError: LocalizedError {
    case invalidInput
    case unsupportedFormat
    case exportFailed(String)
    case imageConversionFailed

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Archivo de entrada invalido."
        case .unsupportedFormat:
            return "Formato no soportado para este tipo."
        case .exportFailed(let message):
            return "Fallo la exportacion: \(message)"
        case .imageConversionFailed:
            return "No se pudo convertir la imagen."
        }
    }
}
