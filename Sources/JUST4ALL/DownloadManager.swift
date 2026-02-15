import Foundation

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(appName: String, progress: Double?)
        case finished(fileURL: URL)
        case failed(message: String)
    }

    @Published private(set) var state: State = .idle

    private struct Context {
        let appName: String
        let destination: URL
        let tmp: URL
        let continuation: CheckedContinuation<URL?, Never>
        var finished: Bool
    }

    private var contextsByTaskId: [Int: Context] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func downloadToDownloadsFolder(from url: URL, fileName: String, appName: String) async -> URL? {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let downloadsDir else {
            state = .failed(message: "No se pudo encontrar la carpeta Descargas.")
            return nil
        }

        let destination = downloadsDir.appendingPathComponent(fileName)
        let tmp = destination.appendingPathExtension("download")

        // If already downloaded, reuse it.
        if FileManager.default.fileExists(atPath: destination.path) {
            state = .finished(fileURL: destination)
            return destination
        }

        state = .downloading(appName: appName, progress: nil)

        var request = URLRequest(url: url)
        request.setValue("JUST4ALL", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60

        return await withCheckedContinuation { continuation in
            let task = session.downloadTask(with: request)
            contextsByTaskId[task.taskIdentifier] = Context(
                appName: appName,
                destination: destination,
                tmp: tmp,
                continuation: continuation,
                finished: false
            )
            task.resume()
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            guard let ctx = contextsByTaskId[downloadTask.taskIdentifier] else { return }
            if totalBytesExpectedToWrite > 0 {
                let p = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0.0), 1.0)
                state = .downloading(appName: ctx.appName, progress: p)
            } else {
                state = .downloading(appName: ctx.appName, progress: nil)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { @MainActor in
            guard var ctx = contextsByTaskId[downloadTask.taskIdentifier], ctx.finished == false else { return }
            ctx.finished = true
            contextsByTaskId[downloadTask.taskIdentifier] = ctx

            do {
                // Replace destination atomically.
                _ = try? FileManager.default.removeItem(at: ctx.destination)
                _ = try? FileManager.default.removeItem(at: ctx.tmp)
                try FileManager.default.moveItem(at: location, to: ctx.tmp)
                try FileManager.default.moveItem(at: ctx.tmp, to: ctx.destination)

                state = .finished(fileURL: ctx.destination)
                ctx.continuation.resume(returning: ctx.destination)
            } catch {
                _ = try? FileManager.default.removeItem(at: ctx.tmp)
                state = .failed(message: error.localizedDescription)
                ctx.continuation.resume(returning: nil)
            }

            contextsByTaskId.removeValue(forKey: downloadTask.taskIdentifier)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            guard var ctx = contextsByTaskId[task.taskIdentifier], ctx.finished == false else { return }
            ctx.finished = true
            contextsByTaskId[task.taskIdentifier] = ctx

            state = .failed(message: error.localizedDescription)
            ctx.continuation.resume(returning: nil)
            contextsByTaskId.removeValue(forKey: task.taskIdentifier)
        }
    }
}

