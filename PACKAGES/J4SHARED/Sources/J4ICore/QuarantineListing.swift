import Foundation

/// Listado compartido de la carpeta «sin clasificar» (`99_SinClasificar`).
///
/// La bandeja de «Inicio» (contador) y la ventana «Por revisar» deben mostrar SIEMPRE lo mismo:
/// - se omiten los archivos ocultos (Finder crea `.DS_Store` al abrir la carpeta y llegó a
///   contarse como «1 elemento por revisar»);
/// - solo cuentan ficheros regulares y carpetas (ni enlaces raros ni otros tipos).
public enum QuarantineListing {
    /// URLs de los elementos revisables de `99_SinClasificar` bajo `rootURL`.
    /// Devuelve `[]` si la carpeta no existe o no se puede leer.
    public static func itemURLs(rootURL: URL, fileManager: FileManager = .default) -> [URL] {
        let directory = rootURL.appendingPathComponent(DefaultTaxonomy.quarantineRelativePath, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey]
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return false }
            return values.isRegularFile == true || values.isDirectory == true
        }
    }
}
