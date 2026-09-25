import Foundation

/// Punto de entrada de metadatos del módulo J4IFiling.
/// J4IFiling alberga la ejecución del archivado (mkdirs + move sobre el motor J4FOps),
/// el journal de operaciones con undo, la cuarentena y el modo simulación.
/// Regla dura: nunca se borra un archivo; solo se mueve (con undo disponible).
public enum J4IFilingBootstrap {
    public static let moduleName = "J4IFiling"
    public static let version = "0.1.0"
}
