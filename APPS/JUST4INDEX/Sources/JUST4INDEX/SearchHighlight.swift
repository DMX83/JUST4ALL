import SwiftUI

/// Utilidades de resaltado de coincidencias para la UI de búsqueda.
enum SearchHighlight {
    /// Rangos de `text` que coinciden con alguno de los términos (insensible a caso y diacríticos).
    static func ranges(in text: String, terms: [String]) -> [Range<String.Index>] {
        let cleaned = terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return [] }

        var found: [Range<String.Index>] = []
        for term in cleaned {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<text.endIndex
                  ) {
                found.append(range)
                searchStart = range.upperBound
            }
        }
        found.sort { $0.lowerBound < $1.lowerBound }

        var merged: [Range<String.Index>] = []
        for range in found {
            if let last = merged.last, range.lowerBound < last.upperBound {
                continue
            }
            merged.append(range)
        }
        return merged
    }

    /// Texto con los términos resaltados en negrita (concatenación de `Text`).
    static func highlightedText(_ text: String, terms: [String]) -> Text {
        let matches = ranges(in: text, terms: terms)
        guard !matches.isEmpty else { return Text(text) }

        var output = Text("")
        var cursor = text.startIndex
        for range in matches {
            if cursor < range.lowerBound {
                output = output + Text(String(text[cursor..<range.lowerBound]))
            }
            output = output + Text(String(text[range.lowerBound..<range.upperBound])).bold()
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            output = output + Text(String(text[cursor...]))
        }
        return output
    }
}
