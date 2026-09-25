import Foundation

/// Punto de entrada de metadatos del módulo J4IIndex.
/// J4IIndex alberga el índice local SQLite FTS5, el crawler cooperativo y la ingesta
/// incremental por FSEvents de JUST4INDEX. Nunca recorre el árbol en tiempo de query.
public enum J4IIndexBootstrap {
    public static let moduleName = "J4IIndex"
    public static let version = "0.1.0"
}
