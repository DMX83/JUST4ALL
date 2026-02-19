import Foundation
import J4FOps

extension Notification.Name {
    static let j4fPreferencesChanged = Notification.Name("j4f.preferences.changed")
}

enum DeleteBehaviorPreference: String, CaseIterable, Identifiable {
    case trashIfPossible
    case permanent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trashIfPossible:
            return "Enviar a Papelera"
        case .permanent:
            return "Eliminar definitivamente"
        }
    }

    var deletePreference: DeletePreference {
        switch self {
        case .trashIfPossible:
            return .trashIfPossible
        case .permanent:
            return .permanent
        }
    }
}

struct J4FPreferences {
    struct Keys {
        static let deleteBehavior = "j4f.pref.deleteBehavior"
        static let showHiddenFiles = "j4f.pref.showHiddenFiles"
        static let preferredBigBufferMB = "j4f.pref.preferredBigBufferMB"
    }

    var deleteBehavior: DeleteBehaviorPreference
    var showHiddenFiles: Bool
    var preferredBigBufferMB: Int

    static func load(defaults: UserDefaults = .standard) -> J4FPreferences {
        let behaviorRaw = defaults.string(forKey: Keys.deleteBehavior) ?? DeleteBehaviorPreference.trashIfPossible.rawValue
        let behavior = DeleteBehaviorPreference(rawValue: behaviorRaw) ?? .trashIfPossible
        let showHidden = defaults.object(forKey: Keys.showHiddenFiles) as? Bool ?? false
        let buffer = defaults.object(forKey: Keys.preferredBigBufferMB) as? Int ?? 4
        return J4FPreferences(
            deleteBehavior: behavior,
            showHiddenFiles: showHidden,
            preferredBigBufferMB: max(1, min(8, buffer))
        )
    }
}
