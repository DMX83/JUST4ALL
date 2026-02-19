import CoreServices
import Foundation

public final class DirectoryWatchService {
    public typealias ChangeHandler = ([String]) -> Void

    private let streamLatency: CFTimeInterval
    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(label: "j4f.fs.watch", qos: .utility)

    private var stream: FSEventStreamRef?
    private var watchedPath: String?
    private var handler: ChangeHandler?
    private var paused = false
    private var pendingPaths: Set<String> = []
    private var debounceWorkItem: DispatchWorkItem?

    public init(streamLatency: CFTimeInterval = 0.2, debounceInterval: TimeInterval = 0.3) {
        self.streamLatency = max(0.05, streamLatency)
        self.debounceInterval = max(0.1, debounceInterval)
    }

    deinit {
        stop()
    }

    public func start(url: URL, handler: @escaping ChangeHandler) throws {
        stop()
        self.handler = handler

        let path = url.standardizedFileURL.path
        watchedPath = path

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagUseCFTypes
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, clientInfo, numEvents, eventPaths, _, _ in
                guard let clientInfo else { return }
                let watcher = Unmanaged<DirectoryWatchService>.fromOpaque(clientInfo).takeUnretainedValue()
                watcher.handleStreamEvents(count: numEvents, pathsPointer: eventPaths)
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            streamLatency,
            flags
        ) else {
            throw NSError(
                domain: "J4FFileSystem",
                code: 4101,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo crear stream de FSEvents."]
            )
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        if let work = debounceWorkItem {
            work.cancel()
            debounceWorkItem = nil
        }
        pendingPaths.removeAll()
        handler = nil
        watchedPath = nil
        paused = false

        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    public func setPaused(_ paused: Bool) {
        queue.async { [weak self] in
            self?.paused = paused
        }
    }

    private func handleStreamEvents(count: Int, pathsPointer: UnsafeMutableRawPointer?) {
        guard !paused else { return }
        guard count > 0 else { return }
        guard let pathsPointer else { return }
        guard let watchedPath else { return }

        let paths = Unmanaged<CFArray>.fromOpaque(pathsPointer).takeUnretainedValue() as NSArray
        for case let raw as String in paths {
            let std = URL(fileURLWithPath: raw).standardizedFileURL.path
            if std == watchedPath || std.hasPrefix(watchedPath + "/") {
                pendingPaths.insert(std)
            }
        }

        scheduleDebouncedEmit()
    }

    private func scheduleDebouncedEmit() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.paused else { return }
            let changes = Array(self.pendingPaths)
            self.pendingPaths.removeAll()
            guard !changes.isEmpty, let handler = self.handler else { return }
            DispatchQueue.main.async {
                handler(changes)
            }
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
