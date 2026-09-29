import Foundation

/// CLI de JUST4PICT (`just4pict-cli`): ejecución de lote SIN UI usando el MISMO pipeline
/// local (PRO) que la app.
///
/// Vive dentro del binario de JUST4PICT: si el primer argumento es un comando conocido se
/// ejecuta la CLI y se sale; sin argumentos, arranca la app normal (ver `Just4PictApp.init()`).
///
/// Convenciones (espejo del CLI de JUST4PDF, para el puente de FOLDERS):
/// - **stdout**: una ruta por fichero creado (o JSON compacto con `--json`).
/// - **stderr**: progreso y errores legibles.
/// - **Códigos**: `0` ok · `2` uso inválido · `3` fallo total · `4` fallo parcial.
enum Just4PictCLI {

    // MARK: - Modelo

    enum Command: Equatable {
        case enhance(EnhanceOptions)
        case listPresets
        case version
        case help
    }

    struct EnhanceOptions: Equatable {
        var inputs: [String] = []
        var preset: EnhancementPreset = .auto
        var format: OutputFormat = .png
        var quality: Double = OutputFormat.preferredQualityDefault
        var outputDirectory: String?
        var exportProfile: ExportProfile = .original
        var sceneOverride: ImageEnhancer.SceneType?
        var json: Bool = false
    }

    enum CLIError: Error, Equatable, CustomStringConvertible {
        case unknownCommand(String)
        case missingValue(String)
        case invalidValue(flag: String, value: String, expected: String)
        case missingInputs

        var description: String {
            switch self {
            case .unknownCommand(let command):
                return "comando desconocido: «\(command)»"
            case .missingValue(let flag):
                return "falta el valor de \(flag)"
            case .invalidValue(let flag, let value, let expected):
                return "valor inválido para \(flag): «\(value)» (esperado: \(expected))"
            case .missingInputs:
                return "no se indicó ninguna imagen de entrada"
            }
        }
    }

    // MARK: - Invocación

    private static let commandNames: Set<String> = ["enhance", "presets", "version", "help", "--help", "-h"]

    /// ¿Los argumentos piden el modo CLI? (sin argumentos, o con algo que no es un comando,
    /// el binario arranca la app normal).
    static func isCLIInvocation(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        return commandNames.contains(first)
    }

    // MARK: - Parseo (puro y testeable)

    static func parse(_ arguments: [String]) throws -> Command {
        guard let first = arguments.first else { throw CLIError.missingInputs }
        let rest = Array(arguments.dropFirst())

        switch first {
        case "version":
            return .version
        case "help", "--help", "-h":
            return .help
        case "presets":
            return .listPresets
        case "enhance":
            break
        default:
            throw CLIError.unknownCommand(first)
        }

        var options = EnhanceOptions()
        var index = 0
        while index < rest.count {
            let argument = rest[index]
            func nextValue() throws -> String {
                guard index + 1 < rest.count else { throw CLIError.missingValue(argument) }
                index += 1
                return rest[index]
            }

            switch argument {
            case "-p", "--preset":
                let value = try nextValue()
                guard let preset = preset(from: value) else {
                    throw CLIError.invalidValue(flag: argument, value: value, expected: "auto|retrato|paisaje|documento|ecommerce")
                }
                options.preset = preset
            case "-f", "--format":
                let value = try nextValue()
                guard let format = format(from: value) else {
                    throw CLIError.invalidValue(flag: argument, value: value, expected: "png|jpg|heic|webp|tiff")
                }
                options.format = format
            case "-q", "--quality":
                let value = try nextValue()
                guard let quality = Double(value), (0.1...1.0).contains(quality) else {
                    throw CLIError.invalidValue(flag: argument, value: value, expected: "0.1…1.0")
                }
                options.quality = quality
            case "-o", "--output":
                options.outputDirectory = try nextValue()
            case "--profile":
                let value = try nextValue()
                guard let profile = profile(from: value) else {
                    throw CLIError.invalidValue(flag: argument, value: value, expected: "original|social|web|weblite|ecommerce")
                }
                options.exportProfile = profile
            case "--scene":
                let value = try nextValue()
                guard let scene = scene(from: value) else {
                    throw CLIError.invalidValue(flag: argument, value: value, expected: "retrato|paisaje|documento|ecommerce|oscura|generica")
                }
                options.sceneOverride = scene
            case "--json":
                options.json = true
            case "-h", "--help":
                return .help
            default:
                guard !argument.hasPrefix("-") else {
                    throw CLIError.unknownCommand(argument)
                }
                options.inputs.append(argument)
            }
            index += 1
        }

        guard !options.inputs.isEmpty else { throw CLIError.missingInputs }
        return .enhance(options)
    }

    // MARK: - Traducción de valores

    static func preset(from value: String) -> EnhancementPreset? {
        switch value.lowercased() {
        case "auto": return .auto
        case "retrato", "portrait": return .portrait
        case "paisaje", "landscape": return .landscape
        case "documento", "document": return .document
        case "ecommerce", "e-commerce": return .ecommerce
        default: return nil
        }
    }

    static func format(from value: String) -> OutputFormat? {
        switch value.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpg
        case "heic": return .heic
        case "webp": return .webp
        case "tiff", "tif": return .tiff
        default: return nil
        }
    }

    static func profile(from value: String) -> ExportProfile? {
        switch value.lowercased() {
        case "original": return .original
        case "social": return .social
        case "web": return .web
        case "weblite", "web-lite", "web<300kb": return .webLite
        case "ecommerce": return .ecommerce
        default: return nil
        }
    }

    static func scene(from value: String) -> ImageEnhancer.SceneType? {
        switch value.lowercased() {
        case "retrato", "portrait": return .portrait
        case "documento", "document": return .document
        case "paisaje", "landscape": return .landscape
        case "ecommerce", "e-commerce": return .ecommerce
        case "oscura", "dark", "darkphoto": return .darkPhoto
        case "generica", "genérica", "generic": return .generic
        default: return nil
        }
    }

    // MARK: - Ejecución

    static func run(arguments: [String]) -> Int32 {
        let command: Command
        do {
            command = try parse(arguments)
        } catch let error as CLIError {
            fail("error: \(error.description)")
            fail("Prueba `just4pict-cli help` para ver el uso.")
            return 2
        } catch {
            fail("error: \(error.localizedDescription)")
            return 2
        }

        switch command {
        case .help:
            print(helpText)
            return 0
        case .version:
            print(BuildInfo.displayLabel)
            return 0
        case .listPresets:
            for preset in EnhancementPreset.allCases {
                print("\(presetLabel(preset))\t\(preset.rawValue)")
            }
            return 0
        case .enhance(let options):
            return runEnhance(options)
        }
    }

    /// Etiqueta CLI de un preset (clave en minúsculas, estable para scripts).
    static func presetLabel(_ preset: EnhancementPreset) -> String {
        switch preset {
        case .auto: return "auto"
        case .portrait: return "retrato"
        case .landscape: return "paisaje"
        case .document: return "documento"
        case .ecommerce: return "ecommerce"
        }
    }

    static func runEnhance(_ options: EnhanceOptions) -> Int32 {
        var created: [String] = []
        var failures = 0
        let fileManager = FileManager.default

        for path in options.inputs {
            let inputURL = URL(fileURLWithPath: path).standardizedFileURL
            guard fileManager.fileExists(atPath: inputURL.path) else {
                failures += 1
                fail("error: no existe «\(inputURL.path)»")
                continue
            }

            let directory = options.outputDirectory
                .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
                ?? inputURL.deletingLastPathComponent()

            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                let outputURL = OutputPathResolver.uniqueOutputURL(
                    for: inputURL,
                    in: directory,
                    format: options.format,
                    mode: .local
                )
                try autoreleasepool {
                    let enhancer = ImageEnhancer()
                    try enhancer.enhance(
                        inputURL: inputURL,
                        outputURL: outputURL,
                        preset: options.preset,
                        quality: options.quality,
                        format: options.format,
                        exportProfile: options.exportProfile,
                        sceneOverride: options.sceneOverride
                    )
                }
                created.append(outputURL.path)
                fail("ok: \(inputURL.lastPathComponent) → \(outputURL.path)")
            } catch {
                failures += 1
                fail("error: \(inputURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if options.json {
            print(jsonSummary(created: created, failed: failures))
        } else {
            for path in created {
                print(path)
            }
        }

        if failures == 0 { return 0 }
        return created.isEmpty ? 3 : 4
    }

    /// JSON compacto para consumidores (FOLDERS): `{"created":[…],"failed":N}`.
    static func jsonSummary(created: [String], failed: Int) -> String {
        let escaped = created.map { path in
            path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        let list = escaped.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"created\":[\(list)],\"failed\":\(failed)}"
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
    }

    // MARK: - Ayuda

    static let helpText = """
    just4pict-cli — JUST4PICT por línea de comandos (mismo pipeline local que la app, sin IA)

    USO
      just4pict-cli enhance [opciones] <imagen>...
      just4pict-cli presets
      just4pict-cli version | help

    OPCIONES DE enhance
      -p, --preset <auto|retrato|paisaje|documento|ecommerce>   preset (def: auto)
      -f, --format <png|jpg|heic|webp|tiff>                     formato de salida (def: png)
      -q, --quality <0.1…1.0>                                   calidad con pérdida (def: 1.0)
      -o, --output <dir>                                        carpeta de salida (def: junto al original)
          --profile <original|social|web|weblite|ecommerce>     perfil de exportación (def: original)
          --scene <retrato|paisaje|documento|ecommerce|oscura|generica>   forzar escena (opcional)
          --json                                                salida JSON: {"created":[…],"failed":N}
      -h, --help                                                esta ayuda

    SALIDA
      stdout: una ruta por fichero creado (ficheros NUEVOS con sufijo, nunca sobrescribe)
      stderr: progreso y errores
      Códigos: 0 ok · 2 uso inválido · 3 fallo total · 4 fallo parcial

    EJEMPLOS
      just4pict-cli enhance ~/fotos/*.jpg -p documento -f png -o ~/salida
      just4pict-cli enhance foto.jpg -p auto --profile web --json
    """
}
