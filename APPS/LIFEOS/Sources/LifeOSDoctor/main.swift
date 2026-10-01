import Foundation

import LifeOSAPI
import LifeOSCore

// Diagnóstico del servidor de LifeOS desde la terminal.
//
// Sirve para comprobar una instalación sin abrir la app y, sobre todo, para ver
// **por qué** una pantalla no funciona contra un servidor que no es el de
// desarrollo: versión antigua (falta el endpoint), sesión de otro servidor, o un
// contrato que no encaja con lo que la app espera.
//
//   lifeos-doctor                                  # el servidor configurado
//   lifeos-doctor https://lifeos.perlatec.net      # otro servidor
//   lifeos-doctor --server https://… --token-env LIFEOS_TOKEN
//
// Sale con 0 si todo va bien, 1 si hay avisos y 2 si hay algo roto.

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    Uso: lifeos-doctor [servidor] [--token-env NOMBRE] [--token TOKEN] [--keychain] [--quiet]

      servidor        Dirección de LifeOS (por defecto, la configurada en la app).
      --token-env     Lee la sesión de esa variable de entorno.
      --token         Sesión literal (queda en el historial del shell: mejor --token-env).
      --keychain      Lee la sesión del llavero de la app (macOS pedirá permiso).
      --quiet         Solo imprime los problemas.

    Sin sesión se comprueba el servidor y qué endpoints tiene (un 401 quiere decir
    «existe, pide entrar» y un 404 «esa versión no lo tiene»), así que sirve para
    mirar un servidor nuevo sin credenciales.
    """)
    exit(0)
}

let quiet = arguments.contains("--quiet")

func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else { return nil }
    return arguments[index + 1]
}

let serverArgument = arguments.first { !$0.hasPrefix("-") && $0 != value(after: "--token-env") && $0 != value(after: "--token") }

let baseURL: URL
if let serverArgument, let url = SettingsStore.normalize(serverArgument) {
    baseURL = url
} else if serverArgument != nil {
    print("✗ Dirección no válida: \(serverArgument ?? "")")
    exit(2)
} else {
    baseURL = SettingsStore().baseURL
}

let token: String?
if let name = value(after: "--token-env") {
    token = ProcessInfo.processInfo.environment[name]
    if token == nil {
        print("• No hay ningún valor en la variable \(name); se comprobará sin sesión.")
    }
} else if let literal = value(after: "--token") {
    token = literal
} else if arguments.contains("--keychain") {
    // A propósito **no** se lee el llavero por defecto: este es otro binario y
    // macOS pediría permiso (con ventana y todo) antes de dejar leer la sesión de
    // la app. Con --keychain se asume que se quiere eso.
    token = try? CredentialsStore().token()
} else {
    token = nil
}

print("Diagnóstico de LifeOS — \(baseURL.absoluteString)")
print("Sesión: \(token != nil ? "con token" : "sin token (solo servidor y endpoints)")")
print(String(repeating: "─", count: 68))

let checks = await ServerDoctor.run(baseURL: baseURL, token: token)

for check in checks where !quiet || check.level != .ok {
    print("\(check.level.symbol) \(check.title)")
    print("   \(check.detail)")
}
print(String(repeating: "─", count: 68))
print("Resumen: \(ServerDoctor.summary(checks))")

let failures = checks.filter { $0.level == .failure }.count
let warnings = checks.filter { $0.level == .warning }.count
exit(failures > 0 ? 2 : (warnings > 0 ? 1 : 0))
