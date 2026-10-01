import Foundation

extension String {
    /// «miércoles, 30 de septiembre» → «Miércoles, 30 de septiembre». Se usa para
    /// títulos (en español el día va en minúscula dentro de la frase).
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
