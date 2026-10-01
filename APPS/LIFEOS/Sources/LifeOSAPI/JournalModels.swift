import Foundation

// Diario personal.
//
// Dos cosas del contrato que conviene no olvidar:
//   · `entry_date` es un **día**, no un instante (llega como "2026-09-30").
//   · **El texto manda**: si la entrada empieza por `@hora:22:30` o
//     `@fecha:20-09-2026`, el servidor deriva de ahí la hora y el día, aunque el
//     cliente diga otra cosa. Por eso no se reescribe el texto nunca.
//   · Las referencias (`@tarea:`/`@evento:`) no se deducen del texto: hay que
//     declararlas aparte para que exista un vínculo real.

/// Referencia declarada al escribir, ya resuelta contra el dominio.
public struct JournalReference: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let text: String
    /// `ok`, `renamed` o `missing` (el destino se renombró o ya no está).
    public let status: String

    public var isMissing: Bool { status == "missing" }
    public var wasRenamed: Bool { status == "renamed" }
}
public struct JournalEntry: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let entryDate: String
    public let title: String
    public let contentMarkdown: String
    public let mood: Int?
    public let energy: Int?
    public let occurredAt: Date?
    public let sensitivity: String
    public let version: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let references: [JournalReference]
    /// Menciones escritas a mano que no pasaron por el selector: el servidor
    /// avisa pero no inventa el vínculo.
    public let unresolvedReferences: [String]

    public var isPrivate: Bool { sensitivity == "sensitive" }

    /// El servidor titula solo cuando no hay título: «Entrada del 30 de septiembre».
    /// Eso no es un título del usuario y no debe tapar el texto en la lista.
    public var hasUserTitle: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.hasPrefix("Entrada del ") else { return true }
        let rest = trimmed.dropFirst("Entrada del ".count)
        let parts = rest.components(separatedBy: " de ")
        guard parts.count == 2, Int(parts[0]) != nil, !parts[1].isEmpty else { return true }
        return false
    }

    /// La cabecera del texto (`@hora:22:30`, `@fecha:20-09-2026`…) tal cual se
    /// escribió. Se muestra aparte porque ya es la hora y el día de la entrada.
    public var leadTokens: [String] {
        JournalLeadHeader.parse(contentMarkdown).tokens
    }

    /// El texto sin la cabecera: lo que se lee.
    public var body: String {
        JournalText.body(contentMarkdown)
    }

    /// Primera línea con texto del cuerpo, para la lista. Las menciones se leen
    /// por su nombre (`@tarea:Enviar el informe` → «Enviar el informe»), igual
    /// que en la web.
    public var excerpt: String {
        let first = JournalText.previewLine(contentMarkdown)
        if !first.isEmpty { return first }
        return hasUserTitle ? title : "(sin texto)"
    }

    public var heading: String {
        if hasUserTitle { return title }
        return String(excerpt.prefix(80))
    }

    /// Las referencias vinculadas, con la etiqueta tal como se escribió (la del
    /// servidor puede venir vacía si la relación es antigua).
    public var mentions: [JournalMention] {
        references.map { JournalMention(id: $0.id, kind: $0.kind, text: $0.text.isEmpty ? $0.title : $0.text) }
    }

    /// El texto tal como se lee: sin la cabecera y con las referencias por su
    /// nombre. Las declaradas hacen de frontera, así que el vínculo no se come la
    /// frase que venga detrás.
    public var readingText: String {
        JournalText.plainText(contentMarkdown, known: mentions)
    }
}

/// La cabecera de una entrada: los tokens del principio que dicen cuándo ocurrió.
///
/// Es un espejo de `journal_strip_lead_tokens` del servidor, y copia también su
/// regla fina: se consume mientras el valor sea una hora o una fecha **válida** y
/// se para en el primer token inválido. Lo que no se entendió como hora ni fecha
/// es prosa, y no se oculta.
public enum JournalLeadHeader {
    /// Qué es el valor de un token: una hora, un día o nada.
    public enum Value: Equatable, Sendable {
        case time(hour: Int, minute: Int)
        case date(year: Int, month: Int, day: Int)
        case invalid
    }

    /// Lo que la cabecera manda, **en números** (el texto y el idioma son de la interfaz).
    ///
    /// Existe para poder avisar **mientras se escribe** de qué hará el `@hora:`/`@fecha:` al
    /// guardar y de si algo no se entendió. Un token mal escrito no cambia la hora, se queda
    /// en el texto y no pasa nada visible: sin este aviso, parece que el diario «ignore» lo
    /// que escribes.
    public struct Schedule: Equatable, Sendable {
        public var hour: Int?
        public var minute: Int?
        public var year: Int?
        public var month: Int?
        public var day: Int?
        /// El primer valor que no se entendió como hora ni como fecha.
        public var invalid: String?

        /// Hay algo que sí se entendió (hora o día).
        public var hasValue: Bool { hour != nil || year != nil }
    }

    public struct Parsed {
        public let tokens: [String]
        public let remainder: String
        public let schedule: Schedule
    }

    /// Prefijos que dicen una **hora** (los otros dos dicen un día).
    static let timePrefixes: Set<String> = ["hora", "time"]

    /// Lo que la cabecera hará al guardar, sin tocar el texto.
    public static func schedule(in text: String) -> Schedule {
        scan(text).schedule
    }

    public static func parse(_ text: String) -> Parsed {
        let result = scan(text)
        let characters = Array(text)
        guard result.stripEnd > 0, result.stripEnd <= characters.count else {
            return Parsed(tokens: [], remainder: text, schedule: result.schedule)
        }
        let rest = String(characters[result.stripEnd...]).drop(while: { $0.isWhitespace })
        return Parsed(tokens: result.tokens, remainder: String(rest), schedule: result.schedule)
    }

    /// Recorre la cadena de tokens del principio, que es lo único que mira el servidor.
    ///
    /// Devuelve las dos cosas a la vez, porque las reglas del servidor no son idénticas:
    /// · `tokens`/`stripEnd` paran en el primer token inválido (eso es `journal_strip_lead_tokens`,
    ///   lo que se oculta al presentar),
    /// · `schedule` mira **todos** los tokens del principio aunque uno sea inválido (eso es
    ///   `journal_lead_schedule`, lo que de verdad se aplica al guardar).
    private static func scan(_ text: String) -> (tokens: [String], stripEnd: Int, schedule: Schedule) {
        let characters = Array(text)
        var tokens: [String] = []
        var schedule = Schedule()
        var stripEnd = 0
        var stillValid = true
        var index = 0
        while index < characters.count, let match = matchToken(characters, from: index) {
            switch classify(match.value, kind: match.kind) {
            case .time(let hour, let minute):
                if schedule.hour == nil {
                    schedule.hour = hour
                    schedule.minute = minute
                }
            case .date(let year, let month, let day):
                if schedule.year == nil {
                    schedule.year = year
                    schedule.month = month
                    schedule.day = day
                }
            case .invalid:
                if schedule.invalid == nil { schedule.invalid = match.value }
                stillValid = false
            }
            if stillValid {
                tokens.append(String(characters[match.start..<match.end]))
                stripEnd = match.end
            }
            index = match.end
        }
        return (tokens, stripEnd, schedule)
    }

    /// `\s*@(hora|time|fecha|date)\s*:\s*([0-9]{1,4}([:/.\-][0-9]{1,4})*)`
    private static func matchToken(
        _ characters: [Character],
        from start: Int
    ) -> (start: Int, end: Int, kind: String, value: String)? {
        var index = start
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count, characters[index] == "@" else { return nil }
        let tokenStart = index
        index += 1

        let kindStart = index
        while index < characters.count, characters[index].isLetter { index += 1 }
        let kind = String(characters[kindStart..<index]).lowercased()
        guard ["hora", "time", "fecha", "date"].contains(kind) else { return nil }

        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count, characters[index] == ":" else { return nil }
        index += 1
        while index < characters.count, characters[index].isWhitespace { index += 1 }

        let valueStart = index
        guard consumeDigits(characters, &index, max: 4) > 0 else { return nil }
        while index < characters.count, [":", "/", ".", "-"].contains(characters[index]) {
            let separator = index
            index += 1
            if consumeDigits(characters, &index, max: 4) == 0 {
                index = separator  // el separador no cerraba un número: no era un token
                break
            }
        }
        return (tokenStart, index, kind, String(characters[valueStart..<index]))
    }

    @discardableResult
    private static func consumeDigits(_ characters: [Character], _ index: inout Int, max: Int) -> Int {
        var count = 0
        while index < characters.count, characters[index].isNumber, count < max {
            index += 1
            count += 1
        }
        return count
    }

    /// ¿El valor es una hora o una fecha de verdad? Si no, era prosa.
    static func classify(_ value: String, kind: String) -> Value {
        if value.contains(":") {
            let parts = value.split(separator: ":").compactMap { Int($0) }
            guard !parts.isEmpty, parts.count <= 3 else { return .invalid }
            let hour = parts[0]
            let minute = parts.count > 1 ? parts[1] : 0
            let second = parts.count > 2 ? parts[2] : 0
            guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
                return .invalid
            }
            return .time(hour: hour, minute: minute)
        }
        if value.contains("-") || value.contains("/") {
            let raw = value.split(whereSeparator: { $0 == "-" || $0 == "/" }).map(String.init)
            guard raw.count == 3, let first = Int(raw[0]), let second = Int(raw[1]),
                  let third = Int(raw[2]) else { return .invalid }
            // El año es el número de cuatro cifras, esté donde esté (2026-09-30
            // y 30-09-2026 valen igual). El mes es siempre el del medio.
            let year = raw[0].count == 4 ? first : third
            let month = second
            let day = raw[0].count == 4 ? third : first
            guard (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day) else {
                return .invalid
            }
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            guard let date = calendar.date(from: components) else { return .invalid }
            let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
            guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
                return .invalid
            }
            return .date(year: year, month: month, day: day)
        }
        if value.count <= 2, let hour = Int(value), (0...23).contains(hour) {
            return .time(hour: hour, minute: 0)
        }
        // `@hora:1100` son las 11:00 y `@hora:830` las 8:30: la hora escrita a mano sin el «:»
        // (30-sep-2026, el dueño escribió `@Time:1100` y no pasaba nada). Sólo vale con prefijo
        // de **hora**: `@fecha:1100` no es una hora, así que se sigue ignorando. El prefijo se
        // compara en minúsculas, como hace el servidor (`kind.lower()`).
        if (3...4).contains(value.count), timePrefixes.contains(kind.lowercased()),
           let number = Int(value) {
            let hour = number / 100
            let minute = number % 100
            if (0...23).contains(hour), (0...59).contains(minute) {
                return .time(hour: hour, minute: minute)
            }
        }
        return .invalid
    }
}

/// Candidato para el selector de referencias.
public struct JournalReferenceCandidate: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let label: String
    public let detail: String
}

// MARK: - Peticiones

public struct JournalReferenceInput: Encodable, Sendable {
    public let targetId: String
    public let text: String

    public init(targetId: String, text: String) {
        self.targetId = targetId
        self.text = text
    }
}

/// Alta de una entrada. Los campos opcionales que van a `nil` **no se envían**:
/// el servidor pone el día de hoy y su sensibilidad por defecto (privada).
///
/// `tz` es la zona del dispositivo que escribe (nombre IANA, p. ej. «Europe/Madrid»): con
/// ella el servidor lee la cabecera `@hora:` del texto, para que 11:00 sea **la hora de
/// quien escribe** y no la del espacio de trabajo (1-oct-2026, petición del dueño). Va por
/// defecto la del Mac; los servidores viejos la ignoran (no rompe nada).
public struct JournalEntryRequest: Encodable, Sendable {
    public let entryDate: String?
    public let title: String
    public let contentMarkdown: String
    public let mood: Int?
    public let energy: Int?
    public let tz: String?
    public let sensitivity: String
    public let references: [JournalReferenceInput]

    public init(
        entryDate: String? = nil,
        title: String = "",
        contentMarkdown: String,
        mood: Int? = nil,
        energy: Int? = nil,
        tz: String? = TimeZone.current.identifier,
        sensitivity: String = "sensitive",
        references: [JournalReferenceInput] = []
    ) {
        self.entryDate = entryDate
        self.title = title
        self.contentMarkdown = contentMarkdown
        self.mood = mood
        self.energy = energy
        self.tz = tz
        self.sensitivity = sensitivity
        self.references = references
    }
}

/// Edición de una entrada.
///
/// `expectedVersion` es control optimista: si la entrada cambió desde que se
/// abrió, el servidor responde 409 en vez de pisar cambios ajenos.
///
/// Y ojo con el PATCH: **omitir un campo significa «no lo toques»**, así que
/// para poder *quitar* el ánimo o la energía hay que mandarlos como `null`
/// explícito. `explicitNulls` (activado por defecto) hace justo eso, que es lo
/// que quiere el compositor: lo que ves en pantalla es lo que queda.
public struct JournalUpdateRequest: Encodable, Sendable {
    public let title: String?
    public let contentMarkdown: String?
    public let mood: Int?
    public let energy: Int?
    /// Zona del dispositivo que edita: el servidor lee con ella la cabecera `@hora:` (ver
    /// `JournalEntryRequest`).
    public let tz: String?
    public let sensitivity: String?
    public let references: [JournalReferenceInput]?
    public let expectedVersion: Int?
    public let explicitNulls: Bool

    private enum CodingKeys: String, CodingKey {
        case title
        case contentMarkdown = "content_markdown"
        case mood
        case energy
        case tz
        case sensitivity
        case references
        case expectedVersion = "expected_version"
    }

    public init(
        title: String? = nil,
        contentMarkdown: String? = nil,
        mood: Int? = nil,
        energy: Int? = nil,
        tz: String? = TimeZone.current.identifier,
        sensitivity: String? = nil,
        references: [JournalReferenceInput]? = nil,
        expectedVersion: Int? = nil,
        explicitNulls: Bool = true
    ) {
        self.title = title
        self.contentMarkdown = contentMarkdown
        self.mood = mood
        self.energy = energy
        self.tz = tz
        self.sensitivity = sensitivity
        self.references = references
        self.expectedVersion = expectedVersion
        self.explicitNulls = explicitNulls
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(contentMarkdown, forKey: .contentMarkdown)
        try container.encodeIfPresent(tz, forKey: .tz)
        try container.encodeIfPresent(sensitivity, forKey: .sensitivity)
        try container.encodeIfPresent(references, forKey: .references)
        try container.encodeIfPresent(expectedVersion, forKey: .expectedVersion)
        if explicitNulls {
            try container.encode(mood, forKey: .mood)
            try container.encode(energy, forKey: .energy)
        } else {
            try container.encodeIfPresent(mood, forKey: .mood)
            try container.encodeIfPresent(energy, forKey: .energy)
        }
    }
}
