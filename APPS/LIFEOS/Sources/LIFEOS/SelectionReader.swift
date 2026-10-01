import AppKit

/// Lee lo que el menú **Servicios** deja en el portapapeles.
///
/// Vive aparte para poder probarlo: la parte difícil de un servicio no es
/// registrarlo, es que el texto llegue entero y en el tipo correcto. Cada app
/// pone lo que quiere (texto, RTF, una URL, un fichero), así que aquí se prueban
/// en orden y se para en el primero que traiga algo con sentido.
enum SelectionReader {
    /// El texto de la selección, o `nil` si no había nada que enviar.
    static func text(from pboard: NSPasteboard) -> String? {
        if let plain = pboard.string(forType: .string), !isBlank(plain) {
            return plain
        }
        // Apps como Safari o Preview a veces ofrecen solo RTF.
        if let rtf = pboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil),
           !isBlank(attributed.string) {
            return attributed.string
        }
        // Un fichero seleccionado en el Finder: se manda su ruta, que sigue
        // siendo información útil (y la app puede subirlo desde ahí).
        if let paths = pboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String],
           let first = paths.first {
            return paths.count == 1
                ? "Fichero: \(first)"
                : "Ficheros:\n" + paths.joined(separator: "\n")
        }
        if let url = pboard.string(forType: .fileURL) ?? pboard.string(forType: .URL), !isBlank(url) {
            return url
        }
        return nil
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
