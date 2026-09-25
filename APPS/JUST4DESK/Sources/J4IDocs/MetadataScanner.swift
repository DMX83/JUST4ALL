import Foundation

/// Extracción determinista de metadatos (fechas, importes, identificadores) por regex.
public enum MetadataScanner {
    public struct Result: Sendable, Equatable {
        public var dates: [String]
        public var amounts: [String]
        public var identifiers: [String]

        public init(dates: [String] = [], amounts: [String] = [], identifiers: [String] = []) {
            self.dates = dates
            self.amounts = amounts
            self.identifiers = identifiers
        }
    }

    public static func scan(text: String, limit: Int = 20) -> Result {
        Result(
            dates: matches(pattern: datePattern, in: text, limit: limit),
            amounts: matches(pattern: amountPattern, in: text, limit: limit),
            identifiers: matches(pattern: identifierPattern, in: text, limit: limit)
        )
    }

    private static func matches(pattern: String, in text: String, limit: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var results: [String] = []
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, stop in
            guard let match, let matchRange = Range(match.range, in: text) else { return }
            let value = String(text[matchRange]).trimmingCharacters(in: .whitespaces)
            if seen.insert(value).inserted {
                results.append(value)
            }
            if results.count >= limit {
                stop.pointee = true
            }
        }
        return results
    }

    static let datePattern = #"\b\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}\b"#
    static let amountPattern = #"(?:\b\d{1,3}(?:[.\s]\d{3})*(?:,\d{2})\s?€)|(?:€\s?\d{1,3}(?:[.\s]\d{3})*(?:,\d{2}))"#
    static let identifierPattern = #"\b(?:[XYZ]\d{7}[A-Z]|\d{8}[A-Z]|[ABCDEFGHJNPQRSUVW]\d{7}[0-9A-J]|ES\d{2}(?:\s?\d{4}){5})\b"#
}
