import Foundation

/// «Skill» del agente de clasificación de JUST4INDEX.
///
/// Es un **artefacto interno de la app** (decisión del usuario, 2026-09-24): no se edita desde la
/// UI ni por configuración de usuario. La afinamos **nosotros en el repositorio**: se versiona con
/// el binario y cada mala clasificación real se convierte en un caso curado con su prueba de
/// regresión — «un caso nuevo en rojo obliga a arreglar antes de mezclar».
///
/// - `version`: sube al tocar instrucciones o casos. Se registra en el log al arrancar
///   («Skill de clasificación vN») para poder auditar cada decisión.
/// - `assistantInstructions`: criterio curado (base del prompt del asesor IA).
/// - `curatedCases`: casos reales con destino esperado; a la vez few-shot para la IA y suite de
///   regresión (`FilingSkillCasesTests`).
public enum FilingSkill {
    /// Versión de la skill (incrementar SIEMPRE que cambien instrucciones, casos o criterio).
    public static let version = 5

    /// Criterio curado del archivador (base del prompt de sistema de la IA).
    public static let assistantInstructions: String = """
    Eres el archivador personal de JUST4INDEX. Clasificas documentos y carpetas (facturas, nóminas, seguros, banca, salud, identidad, viajes, software, multimedia…) en una taxonomía fija en español.

    Criterio obligatorio (aprendido de casos reales):
    - Una CARPETA se archiva EN BLOQUE: pesa su nombre y el tipo dominante de su contenido (p. ej. carpeta con .mkv de un documental → 13_Multimedia/Documentales; carpeta de audiolibro con .m4a/.mp3 → 13_Multimedia/Audiolibros). El texto de un documento suelto dentro NO decide por todo el lote; solo desempata si es inequívoco.
    - Un FICHERO se decide por nombre → contenido → tipo (extensión).
    - Vocabulario del usuario: «audiolibro» → 13_Multimedia/Audiolibros; «documental» → 13_Multimedia/Documentales; «serie»/«temporada» → 13_Multimedia/Series; «película» → 13_Multimedia/Peliculas; «música» → 13_Multimedia/Musica; «curso»/«tutorial» → 06_Educacion/Cursos; «libro»/ebook → 15_Libros; «portable» → 12_Software/Herramientas; «setup»/«installer»/«instalador» → 12_Software/Instaladores.
    - Instaladores y portables de Windows (.exe/.msi/.dmg/.pkg) → 12_Software; comprimidos → 14_Comprimidos.
    - Extensiones técnicas (señal fuerte cuando el nombre no dice nada): .rsc (RouterOS/MikroTik), .ovpn, .pcap, .backup (RouterOS) y configuraciones de dispositivo (.conf/.cfg) → 12_Software/Redes; scripts de programación (.py, .sh, .ps1, .sql, .js…) → 12_Software/Desarrollo.
    - Estrategia de carpetas (campo «mode»): «folder» = mover la carpeta ENTERA (por defecto; también si los elementos guardan relación entre sí: mismo prefijo o producto, curso, serie, álbum, app portable con sus ficheros). «split» = cajón heterogéneo (nombre sin señal y elementos dispares) → los ficheros se archivan por separado; entonces category_path se ignora (usa 99_SinClasificar).
    - En «reason», cita la señal decisiva: «script RouterOS (.rsc)», «extensión dominante .mkv», «cajón de sastre»…
    - Un cajón de sastre (p. ej. «Documents» con documentos variados) NO se fuerza a una categoría concreta: va a 99_SinClasificar.
    - Documentos internos de empresa o trabajo sin categoría específica (actas, presupuestos, planificación, propuestas, informes internos) → «05_Trabajo». No los envíes a 99 solo por no encajar en Facturas/Nóminas/Contratos.
    - Un nombre solo con fechas o códigos («alexis 25-09-06») sin contenido claro → 99_SinClasificar.
    - Ante duda real, elige 99_SinClasificar con confianza baja: preferimos revisar a archivar mal.
    """

    /// Caso real curado: entrada + destino esperado (nil = sin propuesta local → cuarentena).
    public struct CuratedCase: Sendable, Equatable {
        public enum Kind: String, Sendable {
            case file
            case folder
        }

        public let name: String
        public let kind: Kind
        /// Extensión dominante (carpetas) o pista adicional (ficheros).
        public let hint: String
        /// Categoría esperada; `nil` = cuarentena («sin propuesta de clasificación local»).
        public let expected: String?
        /// Por qué este caso existe (contexto del hallazgo).
        public let note: String

        public init(name: String, kind: Kind, hint: String, expected: String?, note: String) {
            self.name = name
            self.kind = kind
            self.hint = hint
            self.expected = expected
            self.note = note
        }
    }

    /// Casos reales curados por el equipo (few-shot + regresión). Añadir uno NUEVO por cada
    /// mala clasificación real; nunca se borran.
    public static let curatedCases: [CuratedCase] = [
        CuratedCase(
            name: "Above Majestic Documental Completo Subtitulado En Español 2018",
            kind: .folder,
            hint: "mkv",
            expected: "13_Multimedia/Documentales",
            note: "documental en carpeta: nombre + extensión dominante (taxonomía fina F9.2)"
        ),
        CuratedCase(
            name: "8 Programas ERP 100% Gratis y Muy SIMPLES para Empresas PYMEs, que NO Conoces",
            kind: .folder,
            hint: "mkv",
            expected: "13_Multimedia/Videos",
            note: "regresión 2026-09-24: es un vídeo; una mención de «factura» en su .txt interno NO debe llevarlo a 01_Fiscal/Facturas"
        ),
        CuratedCase(
            name: "'Tu MENTE al máximo' FOCUS Aprende a conseguir lo que quieres UN GRAN PODER William Walker Atkinson",
            kind: .folder,
            hint: "m4a",
            expected: "13_Multimedia/Audio",
            note: "audiolibro: extensión dominante .m4a"
        ),
        CuratedCase(
            name: "El Poder de Confiar en Ti Audiolibro 🌟 ¦ Despierta tu Fuerza Interior",
            kind: .folder,
            hint: "mp3",
            expected: "13_Multimedia/Audiolibros",
            note: "«audiolibro» en el nombre (taxonomía fina F9.2)"
        ),
        CuratedCase(
            name: "Curso de Desarrollo con IA Gratis - Clase 1",
            kind: .folder,
            hint: "mp4",
            expected: "06_Educacion/Cursos",
            note: "«curso» en el nombre (taxonomía fina F9.2)"
        ),
        CuratedCase(
            name: "Advanced SystemCare Pro Portable",
            kind: .folder,
            hint: "exe",
            expected: "12_Software/Herramientas",
            note: "«portable» en el nombre"
        ),
        CuratedCase(
            name: "mt5setup",
            kind: .folder,
            hint: "exe",
            expected: "12_Software/Instaladores",
            note: "«setup» en el nombre"
        ),
        CuratedCase(
            name: "Documents",
            kind: .folder,
            hint: "pdf",
            expected: nil,
            note: "regresión 2026-09-24: cajón de sastre con PDFs variados → cuarentena (una «nómina» interna no decide el lote)"
        ),
        CuratedCase(
            name: "alexis 25-09-06",
            kind: .folder,
            hint: "pdf",
            expected: nil,
            note: "nombre con fecha/código sin señal clara → cuarentena (revisable con ⌘R)"
        ),
        CuratedCase(
            name: "Factura-Luz-Marzo.txt",
            kind: .file,
            hint: "txt",
            expected: "01_Fiscal/Facturas",
            note: "regla por nombre"
        ),
        CuratedCase(
            name: "backup_2024.zip",
            kind: .file,
            hint: "zip",
            expected: "14_Comprimidos",
            note: "regla por extensión (sin señal en el nombre)"
        ),
        CuratedCase(
            name: "AnyDesk.exe",
            kind: .file,
            hint: "exe",
            expected: "12_Software/Instaladores",
            note: "regla por extensión (.exe)"
        ),
        CuratedCase(
            name: "Index of ⁄Series⁄Ingles⁄The Terminal List Dark Wolf",
            kind: .folder,
            hint: "mkv",
            expected: "13_Multimedia/Series",
            note: "«series» en el nombre: carpeta de episodios (F9.2)"
        ),
        CuratedCase(
            name: "Pelicula Dune Parte Dos (2024).mkv",
            kind: .file,
            hint: "mkv",
            expected: "13_Multimedia/Peliculas",
            note: "«película» en el nombre (F9.2)"
        ),
        CuratedCase(
            name: "111.rsc",
            kind: .file,
            hint: "rsc",
            expected: "12_Software/Redes",
            note: "regresión 2026-09-24: script RouterOS de MikroTik; antes del catálogo de extensiones técnicas acabó en cuarentena"
        ),
        CuratedCase(
            name: "Scripts MikroTik RouterOS",
            kind: .folder,
            hint: "rsc",
            expected: "12_Software/Redes",
            note: "carpeta-unidad de scripts de red: extensión dominante .rsc (F9.4)"
        ),
        CuratedCase(
            name: "deploy-prod.sh",
            kind: .file,
            hint: "sh",
            expected: "12_Software/Desarrollo",
            note: "script de programación sin señal en el nombre → extensión .sh (F9.4)"
        )
    ]

    /// Líneas de few-shot para el prompt del asesor IA (criterio ya validado).
    public static func fewShotLines(limit: Int = 8) -> [String] {
        curatedCases.prefix(max(0, limit)).map { curated in
            let kind = curated.kind == .folder ? "carpeta" : "fichero"
            let destination = curated.expected ?? DefaultTaxonomy.quarantineRelativePath
            let hint = curated.hint.isEmpty ? "" : ", \(curated.hint)"
            return "- «\(curated.name)» (\(kind)\(hint)) → \(destination)"
        }
    }
}
