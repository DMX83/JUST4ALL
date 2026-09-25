import Foundation

/// Punto de entrada de metadatos del módulo J4IAI.
/// J4IAI alberga el cliente de DeepSeek (chat/completions, JSON mode), el asesor de
/// clasificación documental y la cache por hash. Privacidad: solo se envía texto
/// truncado; los archivos nunca salen del equipo.
public enum J4IAIBootstrap {
    public static let moduleName = "J4IAI"
    public static let version = "0.1.0"
}
