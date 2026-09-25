import Foundation

/// Inventario de categorías disponible **en disco** (F14.0).
///
/// Petición del usuario (25-sep): «si hay alguna clasificación que no esté cuando busque una
/// categoría… debo poder crear esa categoría o darme la opción de crearla». El inventario combina
/// la **taxonomía por defecto** con las **carpetas que existan de verdad** en la raíz (creadas al
/// momento desde el buscador de destino, o a mano en el Finder) para que aparezcan en los
/// buscadores de destino, en la UI y en las categorías permitidas de la IA.
public enum TaxonomyInventory {
    /// Nodos de categoría (validación del planificador + categorías permitidas de la IA):
    /// taxonomía por defecto ∪ carpetas existentes hasta `maxDepth` niveles. La cuarentena se
    /// conserva tal cual (sin hijos: su contenido son unidades pendientes de revisar, no destinos).
    public static func categories(rootURL: URL, maxDepth: Int = 2, fileManager: FileManager = .default) -> [TaxonomyNode] {
        let defaults = DefaultTaxonomy.categories()
        var nodes: [TaxonomyNode] = []
        for node in defaults {
            if node.name == DefaultTaxonomy.quarantineRelativePath {
                nodes.append(node)
                continue
            }
            var children = node.children
            if maxDepth >= 2 {
                let extras = subdirectories(of: rootURL.appendingPathComponent(node.name, isDirectory: true), fileManager: fileManager)
                    .filter { name in !children.contains(where: { $0.name == name }) }
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                    .map { TaxonomyNode(name: $0) }
                children += extras
            }
            nodes.append(TaxonomyNode(name: node.name, children: children))
        }
        let known = Set(defaults.map(\.name))
        let customNames = subdirectories(of: rootURL, fileManager: fileManager)
            .filter { !known.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for name in customNames {
            var children: [TaxonomyNode] = []
            if maxDepth >= 2 {
                children = subdirectories(of: rootURL.appendingPathComponent(name, isDirectory: true), fileManager: fileManager)
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                    .map { TaxonomyNode(name: $0) }
            }
            nodes.append(TaxonomyNode(name: name, children: children))
        }
        return nodes
    }

    /// Rutas relativas para los buscadores de destino (sin cuarentena).
    public static func availableDestinations(rootURL: URL, maxDepth: Int = 2, fileManager: FileManager = .default) -> [String] {
        categories(rootURL: rootURL, maxDepth: maxDepth, fileManager: fileManager)
            .flatMap { $0.allRelativePaths }
            .filter { $0 != DefaultTaxonomy.quarantineRelativePath }
    }

    /// Nombres de subcarpetas visibles (solo directorios, sin ocultas).
    private static func subdirectories(of url: URL, fileManager: FileManager) -> [String] {
        guard let items = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.compactMap { item in
            (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true ? item.lastPathComponent : nil
        }
    }
}
