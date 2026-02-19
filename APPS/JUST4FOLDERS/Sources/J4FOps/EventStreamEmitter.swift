import Foundation

public final class EventStreamEmitter {
    public typealias EventHandler = (JobEvent) -> Void

    private let lock = NSLock()
    private var subscribers: [UUID: EventHandler] = [:]

    public init() {}

    @discardableResult
    public func subscribe(_ handler: @escaping EventHandler) -> UUID {
        let token = UUID()
        lock.lock()
        subscribers[token] = handler
        lock.unlock()
        return token
    }

    public func unsubscribe(_ token: UUID) {
        lock.lock()
        subscribers.removeValue(forKey: token)
        lock.unlock()
    }

    public func emit(_ event: JobEvent) {
        lock.lock()
        let handlers = subscribers.values
        lock.unlock()
        for handler in handlers {
            handler(event)
        }
    }
}
