import Foundation
import J4IFiling

/// G2 — silencios de las sugerencias proactivas: «Ahora no» (7 días) y «Nunca más» (siempre).
///
/// Se guardan en `UserDefaults` (dominio `just4desk.suggestions.*`). El motor de escaneo sigue
/// siendo puro: esta pieza solo filtra lo que la tarjeta de «Inicio» muestra.
struct SuggestionDismissals {
    /// «Ahora no» pospone la sugerencia una semana.
    static let snoozeInterval: TimeInterval = 7 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let snoozePrefix = "just4desk.suggestions.snooze."
    private let neverPrefix = "just4desk.suggestions.never."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isDismissed(_ kind: ProactiveSuggestionKind, now: Date = Date()) -> Bool {
        if defaults.bool(forKey: neverPrefix + kind.rawValue) {
            return true
        }
        let until = defaults.double(forKey: snoozePrefix + kind.rawValue)
        return until > now.timeIntervalSince1970
    }

    func snooze(_ kind: ProactiveSuggestionKind, forever: Bool, now: Date = Date()) {
        if forever {
            defaults.set(true, forKey: neverPrefix + kind.rawValue)
            defaults.removeObject(forKey: snoozePrefix + kind.rawValue)
        } else {
            defaults.set(
                now.addingTimeInterval(Self.snoozeInterval).timeIntervalSince1970,
                forKey: snoozePrefix + kind.rawValue
            )
        }
    }
}
