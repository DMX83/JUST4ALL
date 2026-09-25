import Foundation

/// Control central de la IA de clasificación (N1): interruptor de usuario, cap diario y contadores.
///
/// Persistente en `UserDefaults` y seguro para uso concurrente (el pipeline archiva en paralelo).
/// Los contadores se reinician por día natural; el total es acumulado y no se pierde.
public final class AIControlCenter: @unchecked Sendable {
    public static let shared = AIControlCenter()

    enum Keys {
        static let enabled = "just4index.ai.enabled"
        static let dailyLimit = "just4index.ai.dailyLimit"
        static let callsDate = "just4index.ai.callsDate"
        static let callsToday = "just4index.ai.callsToday"
        static let callsTotal = "just4index.ai.callsTotal"
        static let tokensToday = "just4index.ai.tokensToday"
        static let tokensTotal = "just4index.ai.tokensTotal"
    }

    /// Límite diario por defecto de llamadas a la IA.
    public static let defaultDailyLimit = 200

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Configuración

    /// Interruptor «usar IA al clasificar» (no borra la clave; al apagarlo, solo reglas locales).
    public var isEnabled: Bool {
        get { lock.withLock { defaults.object(forKey: Keys.enabled) as? Bool ?? true } }
        set { lock.withLock { defaults.set(newValue, forKey: Keys.enabled) } }
    }

    /// Cap diario de llamadas (0 = ninguna; se aplica al alcanzarlo → solo reglas + aviso).
    public var dailyLimit: Int {
        get {
            lock.withLock {
                max(0, defaults.object(forKey: Keys.dailyLimit) as? Int ?? Self.defaultDailyLimit)
            }
        }
        set { lock.withLock { defaults.set(max(0, newValue), forKey: Keys.dailyLimit) } }
    }

    // MARK: - Uso

    public struct Usage: Sendable, Equatable {
        public let isEnabled: Bool
        public let dailyLimit: Int
        public let callsToday: Int
        public let callsTotal: Int
        public let tokensToday: Int
        public let tokensTotal: Int

        public var limitReached: Bool { callsToday >= dailyLimit }
    }

    public func usage() -> Usage {
        lock.withLock {
            rolloverIfNeededLocked()
            return currentUsageLocked()
        }
    }

    /// ¿Se puede hacer una llamada a la IA ahora mismo? (interruptor + cap diario).
    public func canUseAI() -> Bool {
        let usage = usage()
        return usage.isEnabled && usage.callsToday < usage.dailyLimit
    }

    /// Registra una llamada (reinicia el contador diario si cambió el día; suma al total).
    @discardableResult
    public func registerCall() -> Usage {
        lock.withLock {
            rolloverIfNeededLocked()
            defaults.set(defaults.integer(forKey: Keys.callsToday) + 1, forKey: Keys.callsToday)
            defaults.set(defaults.integer(forKey: Keys.callsTotal) + 1, forKey: Keys.callsTotal)
            return currentUsageLocked()
        }
    }

    /// Suma los tokens reales que devuelve la API (`usage`) a los contadores hoy/total.
    @discardableResult
    public func registerTokens(_ total: Int) -> Usage {
        guard total > 0 else { return usage() }
        return lock.withLock {
            rolloverIfNeededLocked()
            defaults.set(defaults.integer(forKey: Keys.tokensToday) + total, forKey: Keys.tokensToday)
            defaults.set(defaults.integer(forKey: Keys.tokensTotal) + total, forKey: Keys.tokensTotal)
            return currentUsageLocked()
        }
    }

    // MARK: - Privados

    private func currentUsageLocked() -> Usage {
        Usage(
            isEnabled: defaults.object(forKey: Keys.enabled) as? Bool ?? true,
            dailyLimit: max(0, defaults.object(forKey: Keys.dailyLimit) as? Int ?? Self.defaultDailyLimit),
            callsToday: defaults.integer(forKey: Keys.callsToday),
            callsTotal: defaults.integer(forKey: Keys.callsTotal),
            tokensToday: defaults.integer(forKey: Keys.tokensToday),
            tokensTotal: defaults.integer(forKey: Keys.tokensTotal)
        )
    }

    private func rolloverIfNeededLocked() {
        let today = Self.dayKey(for: Date())
        if defaults.string(forKey: Keys.callsDate) != today {
            defaults.set(today, forKey: Keys.callsDate)
            defaults.set(0, forKey: Keys.callsToday)
            defaults.set(0, forKey: Keys.tokensToday)
        }
    }

    /// Clave de día (`yyyy-MM-dd`, zona local) para el reinicio diario.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
