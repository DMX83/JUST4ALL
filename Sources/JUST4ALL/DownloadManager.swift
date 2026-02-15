import Foundation

@MainActor
final class DownloadManager: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(appName: String, progress: Double?)
        case finished(fileURL: URL)
        case failed(message: String)
    }

    @Published private(set) var state: State = .idle

    func downloadToDownloadsFolder(from url: URL, fileName: String, appName: String) async -> URL? {
        state = .downloading(appName: appName, progress: nil)

        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let downloadsDir else {
            state = .failed(message: "No se pudo encontrar la carpeta Descargas.")
            return nil
        }

        let destination = downloadsDir.appendingPathComponent(fileName)
        let tmp = destination.appendingPathExtension("download")

        do {
            // If already downloaded, reuse it.
            if FileManager.default.fileExists(atPath: destination.path) {
                state = .finished(fileURL: destination)
                return destination
            }

            var request = URLRequest(url: url)
            request.setValue("JUST4ALL", forHTTPHeaderField: "User-Agent")

            let (downloadedTmpURL, response) = try await URLSession.shared.download(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                state = .failed(message: "HTTP \(http.statusCode) al descargar.")
                return nil
            }

            // Replace destination atomically.
            _ = try? FileManager.default.removeItem(at: destination)
            _ = try? FileManager.default.removeItem(at: tmp)
            try FileManager.default.moveItem(at: downloadedTmpURL, to: tmp)
            try FileManager.default.moveItem(at: tmp, to: destination)

            state = .finished(fileURL: destination)
            return destination
        } catch {
            _ = try? FileManager.default.removeItem(at: tmp)
            state = .failed(message: error.localizedDescription)
            return nil
        }
    }
}
