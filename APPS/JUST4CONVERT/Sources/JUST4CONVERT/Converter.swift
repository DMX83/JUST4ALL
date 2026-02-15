import Foundation
@preconcurrency import AVFoundation
@preconcurrency import AppKit
import UniformTypeIdentifiers
import ImageIO

enum Converter {
    private final class NonSendableBox<T>: @unchecked Sendable {
        let value: T

        init(_ value: T) {
            self.value = value
        }
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    static func convert(
        from inputURL: URL,
        to outputDirectory: URL,
        type: ConversionType,
        format: ConversionFormat,
        settings: ConversionSettings,
        outputNameTemplate: String,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        let outputURL = makeOutputURL(
            inputURL: inputURL,
            outputDirectory: outputDirectory,
            format: format,
            template: outputNameTemplate
        )

        switch type {
        case .audio:
            switch format {
            case .m4a, .mp3:
                return try await exportAudio(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    format: format,
                    bitrate: settings.audioBitrate,
                    progressHandler: progressHandler
                )
            case .flac:
                throw ConvertError.unsupportedFormat
            default:
                throw ConvertError.unsupportedFormat
            }
        case .video:
            guard format == .mov || format == .mp4 || format == .mkv else { throw ConvertError.unsupportedFormat }
            if format == .mkv {
                return try await exportVideoWithFfmpeg(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    resolution: settings.videoResolution,
                    fps: settings.videoFps,
                    codec: settings.videoCodec,
                    bitrate: settings.videoBitrate,
                    progressHandler: progressHandler
                )
            }
            return try await exportVideo(
                inputURL: inputURL,
                outputURL: outputURL,
                resolution: settings.videoResolution,
                fps: settings.videoFps,
                outputFileType: format == .mp4 ? .mp4 : .mov,
                codec: settings.videoCodec,
                bitrate: settings.videoBitrate,
                progressHandler: progressHandler
            )
        case .image:
            guard format.isImageFormat else { throw ConvertError.unsupportedFormat }
            try exportImage(inputURL: inputURL, outputURL: outputURL, format: format, quality: settings.imageQuality)
            progressHandler(1.0)
            return outputURL
        }
    }

    private static func exportVideo(
        inputURL: URL,
        outputURL: URL,
        resolution: VideoResolutionOption,
        fps: VideoFpsOption,
        outputFileType: AVFileType,
        codec: VideoCodecOption,
        bitrate: VideoBitrateOption,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let preferredPreset = codec.exportPreset
        let exporter = AVAssetExportSession(asset: asset, presetName: preferredPreset)
            ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        guard let exporter else {
            throw ConvertError.exportFailed("No se pudo crear el exportador.")
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = outputFileType

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        if let videoTrack = videoTracks.first,
           resolution.size != nil || fps != .original {
            exporter.videoComposition = try await makeVideoComposition(
                track: videoTrack,
                targetSize: resolution.size,
                fps: fps
            )
        }

        _ = bitrate

        let exporterBox = NonSendableBox(exporter)
        progressHandler(0.0)

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler {
            progressHandler(min(Double(exporterBox.value.progress), 1.0))
        }
        timer.resume()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporterBox.value.exportAsynchronously {
                timer.cancel()
                progressHandler(1.0)

                switch exporterBox.value.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    let message = exporterBox.value.error?.localizedDescription ?? "Error desconocido."
                    continuation.resume(throwing: ConvertError.exportFailed(message))
                case .cancelled:
                    continuation.resume(throwing: ConvertError.exportFailed("Exportacion cancelada."))
                default:
                    let message = exporterBox.value.error?.localizedDescription ?? "Estado inesperado."
                    continuation.resume(throwing: ConvertError.exportFailed(message))
                }
            }
        }

        return outputURL
    }

    private static func exportVideoWithFfmpeg(
        inputURL: URL,
        outputURL: URL,
        resolution: VideoResolutionOption,
        fps: VideoFpsOption,
        codec: VideoCodecOption,
        bitrate: VideoBitrateOption,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        guard let ffmpegURL = ffmpegExecutableURL() else {
            throw ConvertError.exportFailed("FFmpeg no encontrado en el paquete.")
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // Get duration first for progress calculation
        let asset = AVAsset(url: inputURL)
        let durationSeconds = try await asset.load(.duration).seconds

        var arguments: [String] = ["-y", "-i", inputURL.path]
        if let size = resolution.size {
            let width = Int(size.width)
            let height = Int(size.height)
            arguments += ["-vf", "scale=\(width):\(height)"]
        }
        if fps != .original {
            arguments += ["-r", "\(fps.rawValue)"]
        }

        let videoCodec = codec == .hevc ? "libx265" : "libx264"
        arguments += ["-c:v", videoCodec]

        if bitrate != .auto {
            arguments += ["-b:v", "\(bitrate.rawValue)"]
        }

        arguments += ["-c:a", "aac", outputURL.path]

        progressHandler(0.0)
        
        let result = try await runProcess(
            executableURL: ffmpegURL, 
            arguments: arguments,
            duration: durationSeconds,
            progressHandler: progressHandler
        )
        
        if result.status != 0 {
            // Check if it was cancelled
            if Task.isCancelled {
                throw ConvertError.exportFailed("Cancelado por el usuario.")
            }
            let message = lastNonEmptyLine(in: result.output)
            throw ConvertError.exportFailed("FFmpeg fallo: \(message)")
        }

        progressHandler(1.0)
        return outputURL
    }

    private static func exportAudio(
        inputURL: URL,
        outputURL: URL,
        format: ConversionFormat,
        bitrate: AudioBitrateOption,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw ConvertError.invalidInput
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let reader = try AVAssetReader(asset: asset)
        let writerSettings = audioWriterSettings(for: format, bitrate: bitrate)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: writerSettings.fileType)

        let readerOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerOutputSettings)
        reader.add(readerOutput)

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings.settings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: .zero)

        let totalDuration = try await asset.load(.duration).seconds
        var processedDuration = 0.0

        let writerInputBox = NonSendableBox(writerInput)
        let readerOutputBox = NonSendableBox(readerOutput)
        let writerBox = NonSendableBox(writer)
        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "just4convert.audio.export")
            writerInputBox.value.requestMediaDataWhenReady(on: queue) {
                while writerInputBox.value.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutputBox.value.copyNextSampleBuffer() {
                        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                        processedDuration = currentTime
                        if totalDuration > 0 {
                            progressHandler(min(processedDuration / totalDuration, 1.0))
                        }

                        writerInputBox.value.append(sampleBuffer)
                    } else {
                        writerInputBox.value.markAsFinished()
                        writerBox.value.finishWriting {
                            progressHandler(1.0)
                            if writerBox.value.status == .completed {
                                continuation.resume(returning: outputURL)
                            } else {
                                let message = writerBox.value.error?.localizedDescription ?? "Error desconocido."
                                continuation.resume(throwing: ConvertError.exportFailed(message))
                            }
                        }
                        break
                    }
                }
            }
        }
    }

    private static func exportImage(
        inputURL: URL,
        outputURL: URL,
        format: ConversionFormat,
        quality: ImageQualityOption
    ) throws {
        guard let image = NSImage(contentsOf: inputURL) else {
            throw ConvertError.imageConversionFailed
        }

        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw ConvertError.imageConversionFailed
        }

        let uti: CFString
        switch format {
        case .jpg:
            uti = UTType.jpeg.identifier as CFString
        case .png:
            uti = UTType.png.identifier as CFString
        case .heic:
            uti = UTType.heic.identifier as CFString
        case .heif:
            uti = UTType.heif.identifier as CFString
        case .webp:
            uti = UTType.webP.identifier as CFString
        case .tiff:
            uti = UTType.tiff.identifier as CFString
        case .bmp:
            uti = UTType.bmp.identifier as CFString
        case .gif:
            uti = UTType.gif.identifier as CFString
        default:
            throw ConvertError.unsupportedFormat
        }

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, uti, 1, nil) else {
            throw ConvertError.imageConversionFailed
        }

        var properties: [CFString: Any] = [:]
        if format.supportsLossyQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = Double(quality.rawValue) / 100.0
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            throw ConvertError.imageConversionFailed
        }
    }

    private static func ffmpegExecutableURL() -> URL? {
        if let url = Bundle.module.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "ffmpeg") {
            return url
        }
        if let url = Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "ffmpeg") {
            return url
        }
        return nil
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        duration: Double? = nil,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        let errorPipe = Pipe()
        process.standardError = errorPipe

        return try await withCheckedThrowingContinuation { continuation in
            let outHandle = pipe.fileHandleForReading
            let errHandle = errorPipe.fileHandleForReading
            let outputBox = DataBox()
            let errorBox = DataBox()

            outHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    outputBox.data.append(data)
                }
            }
            
            errHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    errorBox.data.append(data)
                    
                    if let string = String(data: data, encoding: .utf8), 
                       let duration = duration, duration > 0 {
                        if let range = string.range(of: "time=\\d{2}:\\d{2}:\\d{2}\\.\\d{2}", options: .regularExpression) {
                             let timeString = string[range].dropFirst(5)
                             let components = timeString.split(separator: ":").compactMap { Double($0) }
                             if components.count >= 3 {
                                 let seconds = components[0] * 3600 + components[1] * 60 + components[2]
                                 progressHandler?(min(seconds / duration, 1.0))
                             }
                        }
                    }
                }
            }

            process.terminationHandler = { p in
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                
                let combinedOutput = String(data: errorBox.data + outputBox.data, encoding: .utf8) ?? ""
                continuation.resume(returning: (p.terminationStatus, combinedOutput))
            }

            do {
                try process.run()
                
                Task {
                    while process.isRunning {
                         if Task.isCancelled {
                            process.terminate()
                            return
                         }
                         try? await Task.sleep(nanoseconds: 250_000_000)
                    }
                }
            } catch {
                continuation.resume(throwing: ConvertError.exportFailed("No se pudo ejecutar FFmpeg: \(error.localizedDescription)"))
            }
        }
    }

    private static func lastNonEmptyLine(in output: String) -> String {
        let lines = output
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return lines.last ?? "Error desconocido."
    }

    private static func audioWriterSettings(
        for format: ConversionFormat,
        bitrate: AudioBitrateOption
    ) -> (fileType: AVFileType, settings: [String: Any]) {
        switch format {
        case .m4a:
            return (
                fileType: .m4a,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVEncoderBitRateKey: bitrate.rawValue,
                    AVNumberOfChannelsKey: 2,
                    AVSampleRateKey: 44100
                ]
            )
        case .mp3:
            return (
                fileType: .mp3,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEGLayer3,
                    AVEncoderBitRateKey: bitrate.rawValue,
                    AVNumberOfChannelsKey: 2,
                    AVSampleRateKey: 44100
                ]
            )
        default:
            return (
                fileType: .m4a,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVEncoderBitRateKey: bitrate.rawValue,
                    AVNumberOfChannelsKey: 2,
                    AVSampleRateKey: 44100
                ]
            )
        }
    }

    private static func makeOutputURL(
        inputURL: URL,
        outputDirectory: URL,
        format: ConversionFormat,
        template: String
    ) -> URL {
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let dateToken = Self.outputDateFormatter.string(from: Date())
        var name = template
            .replacingOccurrences(of: "{name}", with: baseName)
            .replacingOccurrences(of: "{format}", with: format.rawValue)
            .replacingOccurrences(of: "{date}", with: dateToken)

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = "\(baseName)_converted"
        }

        name = name.replacingOccurrences(of: "/", with: "-")
        name = name.replacingOccurrences(of: ":", with: "-")

        if !name.hasSuffix(".\(format.rawValue)") {
            name += ".\(format.rawValue)"
        }

        var candidate = outputDirectory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = outputDirectory.appendingPathComponent("\(base)_\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    private static let outputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    private static func makeVideoComposition(
        track: AVAssetTrack,
        targetSize: CGSize?,
        fps: VideoFpsOption
    ) async throws -> AVMutableVideoComposition {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let duration: CMTime
        if let asset = track.asset {
            duration = try await asset.load(.duration)
        } else {
            duration = .zero
        }
        let transformedSize = naturalSize.applying(preferredTransform)
        let videoSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        let renderSize = targetSize ?? videoSize

        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        if fps.rawValue > 0 {
            composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.rawValue))
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let scale = min(renderSize.width / videoSize.width, renderSize.height / videoSize.height)
        let scaledSize = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        let tx = (renderSize.width - scaledSize.width) / 2
        let ty = (renderSize.height - scaledSize.height) / 2
        let transform = preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
        layerInstruction.setTransform(transform, at: .zero)

        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]

        return composition
    }
}
