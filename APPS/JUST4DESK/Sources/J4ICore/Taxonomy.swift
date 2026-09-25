import Foundation

/// Nodo de la taxonomía documental (nombre relativo + hijos).
public struct TaxonomyNode: Sendable, Equatable {
    public let name: String
    public let children: [TaxonomyNode]

    public init(name: String, children: [TaxonomyNode] = []) {
        self.name = name
        self.children = children
    }

    /// Paths relativos de este nodo y sus descendientes (p. ej. "01_Fiscal", "01_Fiscal/Facturas").
    public var allRelativePaths: [String] {
        if children.isEmpty {
            return [name]
        }
        return [name] + children.flatMap { child in
            child.allRelativePaths.map { "\(name)/\($0)" }
        }
    }
}

/// Taxonomía por defecto de JUST4DESK (categorías en español).
public enum DefaultTaxonomy {
    public static let quarantineRelativePath = "99_SinClasificar"
    /// G6 — archivo en frío: lo grande y olvidado se conserva aquí, con su ruta relativa intacta.
    public static let coldArchiveRelativePath = "90_Archivo"

    public static func categories() -> [TaxonomyNode] {
        [
            TaxonomyNode(name: "01_Fiscal", children: [
                TaxonomyNode(name: "Facturas"),
                TaxonomyNode(name: "Nominas"),
                TaxonomyNode(name: "Impuestos"),
                TaxonomyNode(name: "Recibos")
            ]),
            TaxonomyNode(name: "02_Banca", children: [
                TaxonomyNode(name: "Extractos"),
                TaxonomyNode(name: "Inversiones"),
                TaxonomyNode(name: "Prestamos")
            ]),
            TaxonomyNode(name: "03_Seguros", children: [
                TaxonomyNode(name: "Polizas"),
                TaxonomyNode(name: "Recibos"),
                TaxonomyNode(name: "Siniestros")
            ]),
            TaxonomyNode(name: "04_Salud", children: [
                TaxonomyNode(name: "Informes"),
                TaxonomyNode(name: "Recetas")
            ]),
            TaxonomyNode(name: "05_Trabajo", children: [
                TaxonomyNode(name: "Contratos"),
                TaxonomyNode(name: "Nominas"),
                TaxonomyNode(name: "Formacion")
            ]),
            TaxonomyNode(name: "06_Educacion", children: [
                TaxonomyNode(name: "Cursos")
            ]),
            TaxonomyNode(name: "07_Vivienda", children: [
                TaxonomyNode(name: "Contratos"),
                TaxonomyNode(name: "Suministros"),
                TaxonomyNode(name: "Comunidad")
            ]),
            TaxonomyNode(name: "08_Vehiculos", children: [
                TaxonomyNode(name: "Documentacion"),
                TaxonomyNode(name: "Seguros"),
                TaxonomyNode(name: "Mantenimiento")
            ]),
            TaxonomyNode(name: "09_Identidad", children: [
                TaxonomyNode(name: "Documentos"),
                TaxonomyNode(name: "Certificados")
            ]),
            TaxonomyNode(name: "10_Viajes", children: [
                TaxonomyNode(name: "Reservas"),
                TaxonomyNode(name: "Billetes")
            ]),
            TaxonomyNode(name: "11_Hogar", children: [
                TaxonomyNode(name: "Manuales"),
                TaxonomyNode(name: "Garantias")
            ]),
            TaxonomyNode(name: "12_Software", children: [
                TaxonomyNode(name: "Instaladores"),
                TaxonomyNode(name: "Herramientas"),
                TaxonomyNode(name: "Desarrollo"),
                TaxonomyNode(name: "Redes")
            ]),
            TaxonomyNode(name: "13_Multimedia", children: [
                TaxonomyNode(name: "Fotos"),
                TaxonomyNode(name: "Capturas"),
                TaxonomyNode(name: "Videos"),
                TaxonomyNode(name: "Peliculas"),
                TaxonomyNode(name: "Series"),
                TaxonomyNode(name: "Documentales"),
                TaxonomyNode(name: "Audio"),
                TaxonomyNode(name: "Audiolibros"),
                TaxonomyNode(name: "Musica")
            ]),
            TaxonomyNode(name: "14_Comprimidos"),
            TaxonomyNode(name: "15_Libros"),
            TaxonomyNode(name: coldArchiveRelativePath),
            TaxonomyNode(name: quarantineRelativePath)
        ]
    }

    /// Todos los paths relativos del árbol por defecto (categorías y subcategorías).
    public static var allRelativePaths: [String] {
        categories().flatMap { $0.allRelativePaths }
    }
}

/// Resultado de instalar el esqueleto de taxonomía en disco.
public struct TaxonomyInstallReport: Sendable, Equatable {
    public let rootPath: String
    public let created: [String]
    public let existing: [String]
    public let conflicts: [String]
}

/// Crea en disco el esqueleto de carpetas de la taxonomía.
/// Es idempotente: repetir la instalación no falla y reporta lo ya existente.
public enum TaxonomyInstaller {
    @discardableResult
    public static func install(
        at rootURL: URL,
        categories: [TaxonomyNode] = DefaultTaxonomy.categories(),
        fileManager: FileManager = .default
    ) -> TaxonomyInstallReport {
        let root = rootURL.standardizedFileURL
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        var created: [String] = []
        var existing: [String] = []
        var conflicts: [String] = []

        for relativePath in categories.flatMap({ $0.allRelativePaths }) {
            let directoryURL = root.appendingPathComponent(relativePath, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    existing.append(relativePath)
                } else {
                    conflicts.append(relativePath)
                }
            } else {
                do {
                    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                    created.append(relativePath)
                } catch {
                    conflicts.append(relativePath)
                }
            }
        }

        return TaxonomyInstallReport(
            rootPath: root.path,
            created: created,
            existing: existing,
            conflicts: conflicts
        )
    }
}
