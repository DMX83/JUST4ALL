import Foundation

// Presentación y edición de los tokens del diario.
//
// El texto guardado **no se toca nunca**: el servidor sólo interpreta la
// cabecera `@hora:`/`@fecha:` al principio, y las referencias (`@tarea:`,
// `@evento:`) no se deducen del texto — hay que declararlas aparte para que el
// vínculo exista de verdad.
//
// Todo lo de aquí es el espejo en Swift de `web/lib/journal-text.ts` y de las
// funciones sueltas de `web/components/journal-view.tsx` (`tokenFor`,
// `unlinkedMentions`). Si la web cambia, esto cambia: son las mismas reglas.

/// Una referencia ya vinculada a una entidad: la etiqueta es el texto que se
/// escribió en la entrada (`@tarea:Enviar el informe` → `Enviar el informe`).
public struct JournalMention: Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let text: String

    public init(id: String, kind: String, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }

    /// Lo que va escrito en el texto.
    public var token: String { JournalText.token(kind: kind, text: text) }

    /// Lo que se manda al servidor al guardar. La etiqueta se recorta a 240
    /// caracteres porque el esquema del servidor rechaza más con un 422 (una
    /// acción con un nombre larguísimo no debe romper el guardado del diario).
    public var input: JournalReferenceInput {
        JournalReferenceInput(targetId: id, text: String(text.prefix(240)))
    }
}

public enum JournalText {
    /// Cómo se llaman las referencias al escribirlas.
    public static let kindTokens: [String: String] = ["task": "tarea", "event": "evento"]
    /// Prefijos que son la cabecera de hora/fecha, no una referencia.
    static let leadPrefixes: Set<String> = ["time", "date", "hora", "fecha"]
    static let kindPrefixes: [String: String] = ["tarea": "task", "task": "task", "evento": "event", "event": "event"]

    public static func prefix(forKind kind: String) -> String {
        kindTokens[kind] ?? kind
    }

    public static func token(kind: String, text: String) -> String {
        "@\(prefix(forKind: kind)):\(text)"
    }

    public static func token(for candidate: JournalReferenceCandidate) -> String {
        token(kind: candidate.kind, text: candidate.label)
    }

    // MARK: - Lectura

    public enum Segment: Hashable, Sendable {
        case text(String)
        case reference(kind: String, label: String, trailing: String)
    }

    /// Parte una línea en texto y referencias, para poder pintar cada referencia
    /// como una etiqueta en lugar de enseñar el código `@tarea:…`.
    ///
    /// La sintaxis no tiene cierre: `@tarea:` se come el resto de la línea menos
    /// la puntuación final (igual que en la web). Por eso, si se pasan las
    /// referencias **declaradas**, se usan como frontera y el chip es justo lo
    /// que se escribió; si no, se aplica la regla general.
    public static func segments(in line: String, known: [JournalMention] = []) -> [Segment] {
        let characters = Array(line)
        var segments: [Segment] = []
        var position = 0
        var index = 0
        while index < characters.count {
            guard let match = referenceMatch(characters, from: index) else {
                index += 1
                continue
            }
            // La coincidencia incluye el espacio anterior; se cuenta una sola vez.
            let leadingStart = match.at > 0 ? match.at - 1 : 0
            let before = String(characters[position..<leadingStart])
            let leading = match.at == 0 ? "" : String(characters[match.at - 1])
            if !before.isEmpty || !leading.isEmpty {
                segments.append(.text(before + leading))
            }
            if let declared = declaredToken(in: characters, at: match.at, known: known) {
                segments.append(.reference(kind: declared.kind, label: declared.text, trailing: ""))
                position = match.at + declared.token.count
                index = position
                continue
            }
            var label = match.label.trimmingCharacters(in: .whitespaces)
            var trailing = ""
            while let last = label.last, ".,;:!?".contains(last) {
                trailing = String(last) + trailing
                label.removeLast()
            }
            segments.append(.reference(kind: match.kind, label: label, trailing: trailing))
            position = match.end
            index = match.end
        }
        let rest = String(characters[position...])
        if !rest.isEmpty || segments.isEmpty {
            segments.append(.text(rest))
        }
        return segments
    }

    /// La referencia declarada que empieza justo en esa posición, si la hay. Gana
    /// la etiqueta más larga, para que una que sea prefijo de otra no se adelante.
    private static func declaredToken(
        in characters: [Character],
        at index: Int,
        known: [JournalMention]
    ) -> JournalMention? {
        let rest = String(characters[index...]).lowercased()
        return known
            .filter { rest.hasPrefix($0.token.lowercased()) }
            .max { $0.token.count < $1.token.count }
    }

    /// El texto como se lee: sin la cabecera y con las referencias por su nombre.
    public static func plainText(_ content: String, known: [JournalMention] = []) -> String {
        body(content)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                segments(in: String(line), known: known)
                    .map { segment in
                        switch segment {
                        case .text(let text): return text
                        case .reference(_, let label, let trailing): return label + trailing
                        }
                    }
                    .joined()
            }
            .joined(separator: "\n")
    }

    /// El texto sin la cabecera de hora/fecha (que ya vive en la ficha).
    public static func body(_ content: String) -> String {
        JournalLeadHeader.parse(content).remainder
    }

    /// Primera línea con contenido, lista para la lista de entradas.
    public static func previewLine(_ content: String) -> String {
        plainText(content)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }

    // MARK: - Menciones escritas

    /// Todas las menciones escritas a mano, vinculadas o no.
    public static func writtenMentions(in content: String) -> [String] {
        mentionLabels(in: content, skipping: [])
    }

    /// Menciones que se quedaron en texto: se quitan primero las ya vinculadas
    /// para no volver a leerlas ni arrastrar texto de la vecina.
    public static func unlinkedMentions(in content: String, linked: [JournalMention]) -> [String] {
        mentionLabels(in: content, skipping: linked.map(\.token))
    }

    /// Sólo se envían las referencias cuyo token sigue escrito: si se borró la
    /// mención, el vínculo deja de existir.
    public static func activeMentions(_ mentions: [JournalMention], in content: String) -> [JournalMention] {
        let searched = content.lowercased()
        return mentions.filter { searched.contains($0.token.lowercased()) }
    }

    private static func mentionLabels(in content: String, skipping tokens: [String]) -> [String] {
        var remaining = content
        for token in tokens {
            remaining = remaining.replacingOccurrences(of: token, with: " ")
        }
        var found: [String] = []
        for line in remaining.split(separator: "\n", omittingEmptySubsequences: false) {
            let characters = Array(line)
            var index = 0
            while index < characters.count {
                guard let match = referenceMatch(characters, from: index) else {
                    index += 1
                    continue
                }
                var label = match.label.trimmingCharacters(in: .whitespaces)
                while let last = label.last, ".,;:!?".contains(last) { label.removeLast() }
                if !label.isEmpty, !found.contains(label) { found.append(label) }
                index = match.end
            }
        }
        return found
    }

    private struct ReferenceMatch {
        let at: Int
        let end: Int
        let kind: String
        let label: String
    }

    /// `(?:^|\s)@(tarea|task|evento|event):([^\n@]+)`
    private static func referenceMatch(_ characters: [Character], from index: Int) -> ReferenceMatch? {
        if index > 0, !characters[index - 1].isWhitespace { return nil }
        guard characters[index] == "@" else { return nil }
        var cursor = index + 1
        let kindStart = cursor
        while cursor < characters.count, characters[cursor].isLetter { cursor += 1 }
        let kind = kindPrefixes[String(characters[kindStart..<cursor]).lowercased()]
        guard let kind, cursor < characters.count, characters[cursor] == ":" else { return nil }
        cursor += 1
        guard cursor < characters.count, characters[cursor] != "\n", characters[cursor] != "@" else { return nil }
        let labelStart = cursor
        while cursor < characters.count, characters[cursor] != "\n", characters[cursor] != "@" { cursor += 1 }
        return ReferenceMatch(
            at: index,
            end: cursor,
            kind: kind,
            label: String(characters[labelStart..<cursor])
        )
    }

    // MARK: - Escritura

    /// Mientras se escribe una mención al final del texto, el selector se abre
    /// solo (igual que en la web). `start` es la posición del `@`.
    public struct MentionQuery: Hashable, Sendable {
        public let start: Int
        public let query: String
        public let kind: String?

        public init(start: Int, query: String, kind: String?) {
            self.start = start
            self.query = query
            self.kind = kind
        }
    }

    /// ¿El texto que se está escribiendo termina en una mención a medias?
    ///
    /// Se devuelve `nil` cuando lo que hay delante es la cabecera (`@hora:`,
    /// `@fecha:`, `@time:`, `@date:`) o cuando aún se está escribiendo esa
    /// palabra: en esos casos un selector de tareas estorbaría.
    public static func editingMention(in text: String) -> MentionQuery? {
        let characters = Array(text)
        var index = characters.count
        while index > 0, characters[index - 1] != "@", characters[index - 1] != "\n" { index -= 1 }
        guard index > 0, characters[index - 1] == "@" else { return nil }
        let start = index - 1
        let raw = String(characters[index...])
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        let prefix = parts.first.map { String($0).lowercased() } ?? ""
        if leadPrefixes.contains(prefix) { return nil }
        if !raw.contains(":"), leadPrefixes.contains(where: { $0.hasPrefix(prefix) && !prefix.isEmpty }) {
            return nil
        }
        if let kind = kindPrefixes[prefix] {
            return MentionQuery(start: start, query: parts.dropFirst().joined(separator: ":"), kind: kind)
        }
        return MentionQuery(start: start, query: raw, kind: nil)
    }

    /// Mete la referencia en el texto: sustituye la mención a medias si la hay y,
    /// si no, la añade al final (que es donde queda el cursor al escribir).
    public static func inserting(_ token: String, into text: String, replacing mention: MentionQuery?) -> String {
        let characters = Array(text)
        if let mention, mention.start <= characters.count {
            let head = String(characters[0..<mention.start])
            return head + token + " "
        }
        guard !text.isEmpty else { return token + " " }
        guard let last = text.last, !last.isWhitespace else { return text + token + " " }
        return text + " " + token + " "
    }
}
