import Foundation

/// Limitador de concurrencia (semáforo asíncrono): acota cuántas operaciones corren a la vez.
///
/// Se usa para que un backlog grande de ficheros no lance cientos de hash/OCR simultáneos
/// (thrash de disco). El resto de tareas esperan turno sin consumir CPU.
public actor ConcurrencyLimiter {
    public let limit: Int

    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// Estado actual (para tests/diagnóstico).
    public var activeCount: Int { active }
    public var waitingCount: Int { waiters.count }

    /// Ejecuta `operation` con un slot del limitador; espera si no hay hueco libre.
    public func withSlot<T>(_ operation: () async -> T) async -> T {
        await acquire()
        let result = await operation()
        release()
        return result
    }

    private func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            active -= 1
        } else {
            // Transferimos el slot al siguiente en cola (active no cambia).
            waiters.removeFirst().resume()
        }
    }
}

/// Cola de archivado con concurrencia acotada sobre un `FilingCoordinator`.
///
/// Contrato: `process(_:)` se puede invocar desde muchas tareas a la vez; el limiter garantiza
/// que solo `maxConcurrent` ficheros se analizan/mueven simultáneamente.
public actor FilingPipeline {
    public static let defaultMaxConcurrent = 4

    private let coordinator: FilingCoordinator
    private let limiter: ConcurrencyLimiter

    public init(coordinator: FilingCoordinator, maxConcurrent: Int = FilingPipeline.defaultMaxConcurrent) {
        self.coordinator = coordinator
        self.limiter = ConcurrencyLimiter(limit: maxConcurrent)
    }

    public var activeCount: Int {
        get async { await limiter.activeCount }
    }

    /// Procesa un fichero (hash → análisis → clasificación → archivado) con slot acotado.
    public func process(_ url: URL) async -> FilingCoordinator.Outcome {
        await limiter.withSlot { [coordinator] in
            await coordinator.processFile(at: url)
        }
    }

    /// Procesa una **unidad** de la carpeta de entrada (fichero suelto o carpeta completa)
    /// con slot acotado. Es la vía que usa la vigilancia de entrada.
    public func processItem(_ url: URL) async -> FilingCoordinator.Outcome {
        await limiter.withSlot { [coordinator] in
            await coordinator.processItem(at: url)
        }
    }
}
