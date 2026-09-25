import Foundation

/// Clasificador determinista por palabras clave (funciona sin red; es el fallback de la IA).
public enum RulesFilingClassifier {
    struct Rule {
        let keywords: [String]
        let category: String
        let confidence: Double
    }

    /// Normaliza texto para el cotejo de reglas: minúsculas y sin diacríticos (los nombres que llegan
    /// del sistema de ficheros pueden venir en NFD: «película» con acento combinante).
    static func fold(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
    }

    /// Clasifica según el nombre del archivo (prioritario) y, si no hay coincidencia, el texto.
    public static func classify(fileName: String, textSample: String) -> FilingProposal? {
        let nameFolded = Self.fold(fileName)
        for rule in rules {
            if let keyword = rule.keywords.first(where: { nameFolded.contains(Self.fold($0)) }) {
                return proposal(rule: rule, keyword: keyword, matchedInName: true)
            }
        }
        let textFolded = Self.fold(textSample)
        for rule in rules {
            if let keyword = rule.keywords.first(where: { textFolded.contains(Self.fold($0)) }) {
                return proposal(rule: rule, keyword: keyword, matchedInName: false)
            }
        }
        return nil
    }

    /// Clasificación de último recurso por extensión (instaladores, multimedia, comprimidos,
    /// scripts y configuraciones técnicas…).
    ///
    /// Se usa cuando ni la IA ni las reglas por nombre/texto han propuesto nada: garantiza que
    /// un `.exe`, un `.mp4` o un `.rar` acaben en una categoría razonable en vez de cuarentena.
    public static func classifyByExtension(fileName: String) -> FilingProposal? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        guard let rule = extensionRules.first(where: { $0.extensions.contains(ext) }) else { return nil }
        return FilingProposal(
            categoryPath: rule.category,
            suggestedTitle: nil,
            confidence: rule.confidence,
            reason: "regla local: extensión «.\(ext)»",
            issuer: nil,
            documentDate: nil,
            source: .rules
        )
    }

    /// Sugerencia de destino para la cola de revisión de cuarentena (solo reglas locales:
    /// nombre → extensión; sin IA ni redes).
    public static func suggestDestination(fileName: String) -> FilingProposal? {
        classify(fileName: fileName, textSample: "") ?? classifyByExtension(fileName: fileName)
    }

    /// Clasificación de una **carpeta-unidad**: nombre (con prioridad) → extensión dominante.
    ///
    /// A diferencia de los ficheros, NO se usan reglas por texto: el texto de un documento suelto
    /// dentro de una carpeta no debe decidir por todo el lote (evita falsos positivos como un vídeo
    /// sobre ERP cayendo en «Facturas» por una mención en su descripción). El texto queda como
    /// contexto para la IA cuando esté activa.
    public static func classifyFolder(name: String, dominantExtension: String?) -> FilingProposal? {
        if let byName = classify(fileName: name, textSample: "") {
            return byName
        }
        if let dominantExtension, !dominantExtension.isEmpty,
           let byExtension = classifyByExtension(fileName: "\(name).\(dominantExtension)") {
            return byExtension
        }
        return nil
    }

    struct ExtensionRule {
        let extensions: Set<String>
        let category: String
        let confidence: Double
    }

    private static func proposal(rule: Rule, keyword: String, matchedInName: Bool) -> FilingProposal {
        let confidence = min(0.95, rule.confidence + (matchedInName ? 0.15 : 0))
        return FilingProposal(
            categoryPath: rule.category,
            suggestedTitle: nil,
            confidence: confidence,
            reason: "regla local: «\(keyword)» \(matchedInName ? "en el nombre" : "en el contenido")",
            issuer: nil,
            documentDate: nil,
            source: .rules
        )
    }

    private static let rules: [Rule] = [
        Rule(keywords: ["iberdrola", "endesa", "naturgy", "electricidad", "gas natural", "factura de luz", "recibo de luz", "suministro"], category: "07_Vivienda/Suministros", confidence: 0.7),
        Rule(keywords: ["nómina", "nomina", "payroll"], category: "01_Fiscal/Nominas", confidence: 0.75),
        Rule(keywords: ["irpf", "aeat", "declaración", "declaracion", "modelo 100", "modelo 130", "impuesto"], category: "01_Fiscal/Impuestos", confidence: 0.75),
        Rule(keywords: ["factura", "invoice"], category: "01_Fiscal/Facturas", confidence: 0.7),
        Rule(keywords: ["extracto", "movimientos", "cuenta corriente"], category: "02_Banca/Extractos", confidence: 0.7),
        Rule(keywords: ["préstamo", "prestamo", "hipoteca", "crédito", "credito"], category: "02_Banca/Prestamos", confidence: 0.7),
        Rule(keywords: ["póliza", "poliza", "seguro", "siniestro"], category: "03_Seguros/Polizas", confidence: 0.65),
        Rule(keywords: ["receta"], category: "04_Salud/Recetas", confidence: 0.75),
        Rule(keywords: ["analítica", "analitica", "informe médico", "informe medico"], category: "04_Salud/Informes", confidence: 0.7),
        Rule(keywords: ["alquiler", "arrendamiento"], category: "07_Vivienda/Contratos", confidence: 0.7),
        Rule(keywords: ["contrato de trabajo", "contrato laboral"], category: "05_Trabajo/Contratos", confidence: 0.75),
        Rule(keywords: ["certificado"], category: "09_Identidad/Certificados", confidence: 0.6),
        Rule(keywords: ["pasaporte", "nie", "dni"], category: "09_Identidad/Documentos", confidence: 0.7),
        Rule(keywords: ["billete", "boarding", "tarjeta de embarque", "reserva", "vuelo"], category: "10_Viajes/Reservas", confidence: 0.65),
        Rule(keywords: ["manual de", "manual usuario", "manual del"], category: "11_Hogar/Manuales", confidence: 0.6),
        Rule(keywords: ["garantía", "garantia"], category: "11_Hogar/Garantias", confidence: 0.65),
        Rule(keywords: ["comunidad de propietarios", "cuota de comunidad"], category: "07_Vivienda/Comunidad", confidence: 0.7),
        Rule(keywords: ["audiolibro", "audio libro", "audiobook"], category: "13_Multimedia/Audiolibros", confidence: 0.75),
        Rule(keywords: ["documental"], category: "13_Multimedia/Documentales", confidence: 0.75),
        Rule(keywords: ["serie", "temporada"], category: "13_Multimedia/Series", confidence: 0.75),
        Rule(keywords: ["película", "pelicula"], category: "13_Multimedia/Peliculas", confidence: 0.75),
        Rule(keywords: ["música", "musica", "music"], category: "13_Multimedia/Musica", confidence: 0.65),
        Rule(keywords: ["curso", "tutorial", "clase "], category: "06_Educacion/Cursos", confidence: 0.65),
        Rule(keywords: ["libro", "ebook"], category: "15_Libros", confidence: 0.65),
        Rule(keywords: ["portable"], category: "12_Software/Herramientas", confidence: 0.6),
        Rule(keywords: ["itv", "permiso de circulación", "permiso de circulacion", "vehículo", "vehiculo"], category: "08_Vehiculos/Documentacion", confidence: 0.6),
        Rule(keywords: ["dotnet", ".net sdk", "sdk", "visual studio", "vscode", "xcode", "docker", "python", "nodejs", "node-v", "jdk", "openjdk", "intellij", "pycharm", "android studio", "flutter", "unity", "github desktop", "postman"], category: "12_Software/Desarrollo", confidence: 0.7),
        Rule(keywords: ["ctrader", "metatrader", "trading", "broker", "backtest"], category: "02_Banca/Inversiones", confidence: 0.65),
        Rule(keywords: ["driver booster", "drivers", "driver"], category: "12_Software/Herramientas", confidence: 0.6),
        Rule(keywords: ["cleaner", "antivirus"], category: "12_Software/Herramientas", confidence: 0.6),
        Rule(keywords: ["instalador", "installer", "setup"], category: "12_Software/Instaladores", confidence: 0.6)
    ]

    /// Reglas de último recurso por extensión (se aplican tras nombre y texto).
    static let extensionRules: [ExtensionRule] = [
        ExtensionRule(extensions: ["exe", "msi", "msix", "appx", "dmg", "pkg", "app"], category: "12_Software/Instaladores", confidence: 0.6),
        ExtensionRule(extensions: ["rsc", "ovpn", "pcap", "backup", "conf", "cfg"], category: "12_Software/Redes", confidence: 0.65),
        ExtensionRule(extensions: ["py", "sh", "zsh", "bash", "ps1", "bat", "cmd", "sql", "js", "rb", "pl", "go", "rs"], category: "12_Software/Desarrollo", confidence: 0.6),
        ExtensionRule(extensions: ["mp4", "mov", "mkv", "avi", "webm", "m4v", "mpg", "mpeg", "wmv"], category: "13_Multimedia/Videos", confidence: 0.6),
        ExtensionRule(extensions: ["mp3", "m4a", "aac", "wav", "aiff", "flac", "alac", "ogg"], category: "13_Multimedia/Audio", confidence: 0.6),
        ExtensionRule(extensions: ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp", "svg", "raw", "cr2", "nef"], category: "13_Multimedia/Fotos", confidence: 0.6),
        ExtensionRule(extensions: ["epub", "mobi", "azw3", "fb2"], category: "15_Libros", confidence: 0.6),
        ExtensionRule(extensions: ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "iso", "tgz"], category: "14_Comprimidos", confidence: 0.6)
    ]
}
