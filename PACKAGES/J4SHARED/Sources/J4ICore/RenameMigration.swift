import Foundation

/// Migración del renombrado JUST4INDEX → JUST4DESK (25-sep-2026).
///
/// El renombrado cambia el «vecindario» técnico de los datos:
/// - **Preferencias**: el binario pasa de llamarse `JUST4INDEX` a `JUST4DESK`, así que las claves
///   `just4index.*` se **copian** a `just4desk.*` conservando sus valores (cap de IA, contadores,
///   carpetas de entrada/salida, modo simulación, búsqueda en contenido…). El dominio antiguo no
///   se toca.
/// - **Datos locales** (`~/Library/Application Support/JUST4DESK`): se **copia** el contenido de la
///   carpeta antigua — `index.sqlite` (índice), `knowledge.json` (reglas aprendidas) y
///   `ai-suggestions.json` (caché de propuestas). El original se conserva como respaldo; puede
///   borrarse a mano cuando ya no haga falta.
/// - **Registro**: se estrena `~/Library/Logs/JUST4DESK`; el histórico de JUST4INDEX se conserva.
///
/// Garantías: se ejecuta **una sola vez** (marcador persistente), es **idempotente** (si el
/// destino ya existe no toca nada), **nunca corre durante los tests** y **no elimina nada**.
public enum RenameMigration {
    static let markerKey = "just4desk.migratedFromIndex.v1"
    static let legacyDomain = "JUST4INDEX"
    static let legacyFolderName = "JUST4INDEX"
    static let currentFolderName = "JUST4DESK"
    static let legacyKeyPrefix = "just4index."
    static let currentKeyPrefix = "just4desk."

    /// Ejecuta la migración si aún no se ha hecho. Devuelve `true` si hubo algo que migrar.
    @discardableResult
    public static func runIfNeeded(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> Bool {
        // Nunca en tests: evitaría tocar los datos reales del usuario.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return false }
        guard !defaults.bool(forKey: markerKey) else { return false }

        // Valores del dominio antiguo (dos vías por si una no estuviera disponible).
        var legacyValues: [String: Any] = [:]
        if let domain = defaults.persistentDomain(forName: legacyDomain) {
            legacyValues.merge(domain) { current, _ in current }
        }
        if let suite = UserDefaults(suiteName: legacyDomain) {
            for (key, value) in suite.dictionaryRepresentation() where legacyValues[key] == nil {
                legacyValues[key] = value
            }
        }

        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let result = migrate(
            defaults: defaults,
            legacyValues: legacyValues,
            legacyFolder: base?.appendingPathComponent(legacyFolderName, isDirectory: true),
            currentFolder: base?.appendingPathComponent(currentFolderName, isDirectory: true),
            fileManager: fileManager
        )

        // El marcador solo se sella si no quedó ninguna copia a medias.
        if !result.failed {
            defaults.set(true, forKey: markerKey)
        }
        return result.migrated
    }

    /// Núcleo de la migración (testeable): copia las claves `just4index.*` → `just4desk.*` y la
    /// carpeta de datos, sin pisar nada existente y sin borrar el original.
    /// Devuelve `(migrated, failed)`: si hubo algo que migrar y si alguna copia falló.
    @discardableResult
    static func migrate(
        defaults: UserDefaults,
        legacyValues: [String: Any],
        legacyFolder: URL?,
        currentFolder: URL?,
        fileManager: FileManager
    ) -> (migrated: Bool, failed: Bool) {
        var migrated = false
        var failed = false

        // 1) Preferencias.
        var copiedKeys = 0
        for (key, value) in legacyValues where key.hasPrefix(legacyKeyPrefix) {
            let newKey = currentKeyPrefix + String(key.dropFirst(legacyKeyPrefix.count))
            if defaults.object(forKey: newKey) == nil {
                defaults.set(value, forKey: newKey)
                copiedKeys += 1
            }
        }
        if copiedKeys > 0 {
            migrated = true
            J4Log.info(.app, "Migración JUST4INDEX → JUST4DESK: \(copiedKeys) preferencia(s) copiadas al dominio nuevo.")
        }

        // 2) Datos locales: copia (nunca mueve) la carpeta antigua a la nueva.
        if let legacyFolder, let currentFolder,
           fileManager.fileExists(atPath: legacyFolder.path),
           !fileManager.fileExists(atPath: currentFolder.path) {
            do {
                try fileManager.copyItem(at: legacyFolder, to: currentFolder)
                migrated = true
                J4Log.info(.app, "Migración JUST4INDEX → JUST4DESK: datos copiados a «\(currentFolder.path)» (el original se conserva como respaldo).")
            } catch {
                failed = true
                J4Log.warn(.app, "Migración JUST4INDEX → JUST4DESK: no se pudo copiar la carpeta de datos (\(error.localizedDescription)); se reintentará en el próximo arranque.")
            }
        }
        return (migrated, failed)
    }
}
