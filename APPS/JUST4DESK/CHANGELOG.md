# Changelog — JUST4DESK

Convención por version + build stamp:

- Version: `CFBundleShortVersionString` · Build: `CFBundleVersion`
- Build stamp: `J4ABuildStamp` (`YYYYMMDDHHMMSS-<commit-corto>`)
- Artefacto: `JUST4DESK-<version>+<buildStamp>.dmg`

## [Unreleased] — 2026-09-24

### Added

- Scaffold inicial: paquete SPM con módulos `J4ICore`, `J4IIndex`, `J4IDocs`, `J4IAI`, `J4IFiling`
  y ejecutable `JUST4INDEX`.
- App shell SwiftUI placeholder (ventana + estado de módulos + versión/build stamp).
- `scripts/build_dmg.sh` con versionado y `J4ABuildStamp`; entitlements sandbox en `packaging/macos/`.
- Library products nuevos en `APPS/JUST4FOLDERS/Package.swift` (`J4FCore`, `J4FFileSystem`, `J4FOps`, `J4FUI`)
  para consumir el motor de operaciones vía `.package(path:)`.
- Documentación base: `README.md`, `TODO.md`, `CHANGELOG.md`, `MEMORY.md`, `ARCHITECTURE.md`, `PRIVACY.md`.
- Skill de agente `.github/skills/just4index/SKILL.md` (ciclo obligatorio de trabajo + guardrails).

### Added — F1 (motor de índice)

- `J4IIndex`: `SearchIndex` — actor SQLite FTS5 (esquema v1: `roots`, `entries`, `entries_fts`,
  `doc_text`, `doc_text_fts`; WAL; upserts por lotes; filtros y ranking bm25; `optimize`).
- `J4IIndex`: `IndexCrawler` cooperativo (cancelable, completitud por root, `reindex`).
- `J4IIndex`: `IndexWatchService` — ingesta incremental FSEvents con `eventId` persistido,
  debounce, mapeo `/private` y reconciliación vía `onNeedsRescan`.
- Suite `J4IIndexTests`: 20 tests (búsqueda con diacríticos/prefix/filtros, contenido, crawler,
  watcher FSEvents end-to-end).
- Benchmark opt-in 100k (`J4I_RUN_100K_PERF=1`): crawl 6.92 s; queries típicas 0.3–38 ms;
  peor caso (match global) 193 ms.

### Added — F2 (UI buscador)

- `SearchViewModel`: búsqueda con debounce (120 ms) y cancelación de queries obsoletas, polling de
  estado (1 s), gestión de raíces (añadir/reindexar/quitar), arranque de watchers y acciones sobre
  resultados (abrir/revelar/copiar ruta).
- `ContentView`: ventana keyboard-first (campo con foco al arrancar, Enter abre, flechas en lista),
  chips de tipo, scope por carpeta, toggle "solo carpetas", estados vacíos y barra de estado con
  progreso de indexación.
- `SearchResultRow` + `SearchHighlight`: resaltado de coincidencias (insensible a acentos) e iconos
  por tipo con cache; badge "contenido" para matches en texto.
- Tests `JUST4INDEXTests`: 6 tests de resaltado y filtros de tipo (total del proyecto: 26).

### Added — F3.0/F3/F4/F5 (configuración inicial, ingesta, clasificación y archivado)

- Configuración inicial: onboarding de carpeta raíz (sugerencia `~/JUST4INDEX`) + carpeta de entrada
  (sugerencia `~/Descargas`), generación del esqueleto de taxonomía (idempotente) y persistencia.
- `J4ICore`: `FilingProposal`, `FileNameFactory`, `RulesFilingClassifier`, `FilingPlanner`.
- `J4IDocs`: `SourceFolderWatcher` (estabilidad + ignore-list + backlog), `TextExtractor`
  (PDFKit/Vision OCR/txt/rtf/docx), `MetadataScanner` (fechas/NIF/IBAN/importes), `DocumentAnalyzer` (hash+perfil).
- `J4IAI`: `DeepSeekClient` (JSON mode, retry, timeout), `DeepSeekFilingAdvisor` (prompt + parseo),
  `DeepSeekKeyResolver` (entorno/`.env.secrets`).
- `J4IFiling`: `FilingExecutor` (mkdirs+move, colisiones `-1`, undo), `FilingCoordinator`
  (pipeline completo con cache por hash, detección de duplicados y journal).
- `J4IIndex`: schema v2 (`analysis_cache`, `ops_journal`) + APIs de cache/journal/entryID.
- UI: panel de Actividad (undo por item y del último, estados simulado/deshecho), pausar/reanudar
  organización, modo simulación y "Abrir cuarentena".

### Added — F6 (hub + release + QA)

- Hub JUST4ALL: entrada `JUST4INDEX` en `SubAppsCatalog` + carpeta de assets.
- `release.sh`, `sync_local_dmgs.sh` y `clean_artifacts.sh` actualizados (también FOLDERS/PICT en limpieza).
- Workspace Xcode con FOLDERS/PICT/INDEX; README/agent.md/MODULOS_A_CREAR actualizados.
- `APPS/JUST4INDEX/scripts/qa_smoke.sh` (build + test + checklist manual).

### Added — F6.1 (observabilidad: registro en vivo)

- `J4ICore.J4Log`: registro con niveles (DEBUG/INFO/AVISO/ERROR) y 8 categorías; buffer en memoria
  (5 000), stream en vivo (`AsyncStream`), archivo rotativo en `~/Library/Logs/JUST4INDEX/just4index.log`
  y registro unificado de macOS (subsystem `com.dmx83.just4index`).
- Pipeline instrumentado: indexación (crawler/watcher), carpeta de entrada (detección/estabilidad),
  extracción, clasificación (IA/reglas), plan, ejecución, cuarentena, duplicados, undo y búsquedas.
- Visor «Registro» en la app (menú Carpetas → Ver registro…, ⌘L): filtros por nivel/categoría/texto,
  auto-scroll, copiar, limpiar y revelar el archivo; botón «Registro» en la barra de estado.
- `scripts/log_watch.sh` (registro unificado o archivo); tests `J4LogTests` (7).

### Added — F7 (reconocimiento por nombre/extensión, explorador y concurrencia acotada)

- Análisis «lite»: si no hay texto extraíble (instaladores, vídeo, comprimidos…), se genera el perfil
  con hash+nombre+extensión y se clasifica por nombre/extensión en vez de dejar el fichero sin tocar.
- Taxonomía ampliada: `12_Software/{Instaladores,Herramientas,Desarrollo}`, `13_Multimedia/{Fotos,Videos,Audio}`
  y `14_Comprimidos`; se sincroniza de forma idempotente al arrancar (también en instalaciones existentes).
- `RulesFilingClassifier`: reglas nuevas por nombre (dotnet/sdk/docker/ctrader/cleaner/setup…) y
  `classifyByExtension` (exe/msi→Software/Instaladores, mp4→Vídeos, jpg→Fotos, rar/zip→Comprimidos…).
- IA por nombre: el prompt de DeepSeek indica «sin texto extraíble: clasifica por nombre/extensión/metadatos».
- Explorador integrado (⌘E): ventana que navega la carpeta de organización con datos del índice
  (breadcrumb, carpetas/ficheros, abrir/revelar/copiar, refresco automático) y
  `SearchIndex.children(ofDirectory:)` (orden carpetas→ficheros).
- Concurrencia acotada: `FilingPipeline` + `ConcurrencyLimiter` (4 por defecto) y hash/extracción a
  prioridad `utility`; evita el thrash de disco con backlogs de 100+ archivos.
- Tests nuevos: +4 clasificador, +2 explorador, +2 pipeline, +1 análisis lite (total 78; 1 skip opt-in).

### Added — F7.1 (Ajustes, menú Ver y explorador con propiedades)

- Ventana de Ajustes (⌘,): Organización (carpetas raíz/entrada, modo simulación, pausa persistente),
  Indexado (raíces con reindexar/quitar/añadir) y Acerca de/Diagnóstico (estado IA, registro, explorador).
- Comandos de menú estándar visibles: menú Ver → «Abrir explorador» (⌘E) y «Ver registro» (⌘L);
  `SettingsLink` («Ajustes…») también en el menú Carpetas.
- Explorador: selección marcada de carpetas/ficheros y panel de **propiedades** a la derecha (nº de
  ficheros, subcarpetas y tamaño del subárbol); las carpetas se muestran todas y los archivos
  ocultos no se indexan.
- `SearchIndex.subtreeStats(forDirectory:)`; el watcher ya no indexa ocultos (limpia `.DS_Store`).
- Pausa de organización persistente entre arranques.
- Tests: +1 estadísticas de subárbol (total 79; 1 skip opt-in).

### Fixed — F7.2 (atajos de teclado fiables)

- Atajos: ⌘E (explorador), ⌘L (registro) y ⌘A (ajustes; ⌘, también) se capturan con un monitor
  local de `NSEvent` (`J4IAppDelegate`): funcionan también ejecutando el binario directamente sin
  bundle `.app`. ⌘A abre Ajustes siempre (también con el buscador enfocado); la apertura tiene
  respaldos (selectores de SwiftUI y, en último caso, el ítem ⌘, del menú de la app) y deja aviso en
  el registro si fallara. Los menús Ver y Carpetas muestran los atajos, hay botones
  Explorador/Registro/Ajustes en la barra de estado.

### Fixed — F7.3 (explorador: selección visible y mensaje de subcarpetas)

- Las filas de Carpetas/Ficheros del explorador se marcan con **resaltado propio** al seleccionarlas
  (el `List(selection:)` no lo pintaba con los gestos de doble clic): un clic selecciona, doble clic
  entra en la carpeta o abre el fichero.
- Si una carpeta no tiene ficheros directos pero sí subcarpetas con contenido, el panel central ahora
  lo explica («los ficheros están dentro de las subcarpetas (N en total)») en vez de decir que no hay
  ficheros. La estructura de carpetas se mantiene tal cual (decisión del usuario).

### Added — F7.4 (mover a la Papelera desde el explorador)

- Menú contextual de cada fichero y botón en el panel de propiedades: **Mover a la papelera**
  (acción manual y reversible desde el Finder; el motor automático de archivado sigue sin borrar
  nunca). El índice se actualiza al momento y la acción queda registrada en el log.

### Added — F7.5 (búsqueda por contenido)

- Toggle **«En contenido»** en la barra de filtros de búsqueda (persistente en `UserDefaults`):
  activa `includeContent` en las queries contra `doc_text_fts`.
- Los resultados con coincidencia en el texto muestran un **fragmento destacado** del acierto
  (además del chip «contenido»); el registro anota «(con contenido)».
- Test de índice ampliado (fragmento presente y coincidencia real).

### Added — F7.6 (revisión asistida de cuarentena)

- Ventana **«Por revisar»** (⌘R): lista los ficheros de `99_SinClasificar` con **sugerencia de
  destino** (reglas locales: nombre → extensión), destino editable y mover a su categoría en un clic.
- La operación pasa por el **journal** (deshacer desde Actividad) con las mismas garantías del
  archivado (colisión `-1`, nunca sobrescribe); el índice se actualiza al momento y el texto
  extraído viaja al nuevo registro (sin re-OCR).
- `FilingExecutor.move` (movimiento manual) + `FilingCoordinator.reclassify` + `suggestDestination`;
  tests nuevos (reclasificación con journal/undo y colisión resuelta).

### Added — F7.7 (orden y selección múltiple en «Por revisar»)

- **Orden** de la lista por **Extensión** (por defecto, con secciones por tipo y «sin extensión» al
  final), Nombre, Fecha (recientes primero) o Tamaño (mayores primero).
- **Selección múltiple** (clic, ⌘-clic y mayús-clic) con barra de acciones: destino común para toda
  la selección y **«Mover seleccionados»** (cada uno a su destino; los que no tengan destino se
  omiten con aviso). Botones «Seleccionar todo» y «Quitar selección».
- Tests de ordenación (extensión —con las sin-extensión al final—, nombre, fecha y tamaño).

### Added — F7.8 (papelera en «Por revisar»)

- **Mover a la papelera** para la selección (barra de acciones) y por fila (menú contextual): acción
  manual y reversible desde el Finder; el índice se actualiza al momento y queda traza en el registro.
  Sin journal (no es un archivado): se restaura desde la Papelera de macOS.

### Added — F8.0 (Explorador 2.0)

- **Selección múltiple** (clic, ⌘-clic, mayús-clic) con acciones en lote: **«Mover a…»** (a cualquier
  categoría de la taxonomía, con journal/undo) y **«Mover a la papelera»**; también desde el menú
  contextual (actúa en lote si la fila está seleccionada).
- **Orden** (nombre/tamaño/fecha) y **filtro por nombre** dentro de cada carpeta.
- **Duplicados visibles**: en propiedades, «Duplicado de …» (hash → caché de archivado) con botón
  «Revelar duplicado».
- **Vista previa con la barra espaciadora** (QuickLook) sobre los ficheros seleccionados, con
  navegación entre ellos; se cierra con espacio/ESC.
- Tests de orden/filtro del explorador (3).

### Changed — F8.1 (interfaz más agradable)

- Buscador con **anillo de foco** (acento), sombra sutil y lupa que se tiñe de acento al escribir.
- **Chips de tipo con iconos** (cuadrícula, doc, foto, música, vídeo, comprimidos) y selección en
  acento sólido con texto blanco.
- **Estado inicial rediseñado**: icono en degradado, tipografía redondeada y **tarjetas de atajos**
  (⌘E explorador · ⌘R por revisar · ⌘L registro).
- **Barra de estado más limpia**: acciones (copiar/revelar/abrir) y accesos (explorador/registro/
  ajustes) como iconos con tooltip, menú «Carpetas» sin borde y separadores.
- **Hover suave** en todas las listas (resultados, explorador y «Por revisar»); encabezados de panel
  con iconos; filas de resultados más aireadas (icono 22 px, chip «contenido» con icono).
- Ventana principal con tamaño por defecto mayor (1020×680).

### Changed — F8.2 (explorador con árbol de carpetas)

- El panel izquierdo del explorador pasa de lista plana a **árbol de carpetas**: expandir/contraer
  con chevron, indentación por nivel, resaltado de la carpeta actual y contador de ficheros.
- **Navegación de un clic**: al hacer clic en una carpeta se navega a ella (se expande y se ven sus
  subcarpetas; sus ficheros aparecen en la columna central). Botones **Expandir todo / Contraer todo**.
- El árbol se reconstruye desde el índice cada ~8 s (y al instante tras mover/papelera o «Actualizar»).
- Test de filas visibles del árbol (expansión con profundidades).

### Added — F8.3 (ingesta por unidades: carpetas completas + permisos)

- **La carpeta de entrada se procesa por UNIDADES**: cada hijo directo (fichero suelto **o carpeta**)
  se perfila, clasifica y archiva. Antes el backlog solo miraba el primer nivel y **descartaba las
  carpetas** — caso real: los 63 subdirectorios de `~/Descargas` quedaban invisibles.
- **Carpeta = unidad completa**: se mueve ENTERA (nombre y estructura intactos: apps portables,
  subtítulos…) y se clasifica con un perfil de contenido (`FolderProfiler`: extensión dominante +
  muestras de nombres y hasta 2 documentos de texto truncados). Sin señal → cuarentena, también
  como carpeta completa (journal + undo igual que los ficheros).
- Vigilancia en vivo también por unidades: hijos directos nuevos (ficheros o carpetas) con
  estabilidad; lo que ocurre dentro de una carpeta no genera trabajo por separado.
- Reglas nuevas: `audiolibro`, `documental/película/serie/temporada`, `curso/tutorial`, `portable`.
- **Permisos (macOS)**: sonda de acceso en `SourceFolderWatcher.start` con error accionable; la app
  muestra aviso con **«Abrir Ajustes del Sistema…»** (panel de Privacidad adecuado) y **«Reintentar»**;
  `scripts/build_dmg.sh` añade descripciones de uso TCC (`NSDownloadsFolderUsageDescription`, …).
- Tests: el watcher emite carpetas del backlog como unidades (`J4IDocsTests`) y el archivo de carpeta
  completa + cuarentena con journal/undo (`J4IFilingTests`, 2). Suite: 93 (92 ✅ + 1 skip opt-in).

### Added — F9.0 (skill interna del clasificador: casos curados + regresión)

- `J4ICore.FilingSkill`: **skill versionada** (`version=1`, `assistantInstructions`) con **12 casos
  curados** reales (nombre, tipo, pista, destino esperado o `nil` = cuarentena): audiolibros→Audio,
  documental/serie→Vídeos, portable→Herramientas, setup→Instaladores, cajones sin señal→99.
- El prompt del asesor (`DeepSeekFilingAdvisor`) se compone desde la skill + contrato JSON + few-shot
  de los casos curados; distingue carpeta («unidad completa») de fichero.
- Arranque: «Skill de clasificación v1 — 12 caso(s) curado(s)» en el registro.
- Tests `FilingSkillCasesTests` (3): cada caso curado queda verde para siempre — cada mala
  clasificación futura entra como caso nuevo en rojo. Sin editor de usuario: la skill viaja con la app.

### Added — F7.9 (búsqueda por subcadena estilo «Everything»)

- Nueva columna `entries.name_norm` (nombre en minúsculas y sin diacríticos): migración v3 con
  rellenado único y normalización al indexar.
- `search()` añade una **pasada «contiene»** tras el MATCH por prefijos de FTS5: «net» ya encuentra
  `dotnet-sdk…`, `Internet.Download.Manager…` o `Makefile.NetBSD` (los prefijos siguen rankeando
  primero; insensible a acentos: «seno» encuentra «Diseño-final.pdf»).
- Test de índice con subcadena, acentos y orden prefijo-primero. Suite: 99 (98 ✅ + 1 skip).

### Added — F9.2 (taxonomía fina: Peliculas, Series, Documentales, Audiolibros, Musica, Libros, Cursos)

- `13_Multimedia` gana `Peliculas`, `Series`, `Documentales`, `Audiolibros` y `Musica` (conserva
  `Videos`/`Audio` como catch-all para lo dudoso); `06_Educacion` gana `Cursos`; nueva top-level
  `15_Libros` (epub/mobi/azw3/fb2 por extensión). El instalador idempotente creó las 7 carpetas al
  arrancar («Taxonomía actualizada: 7 carpeta(s) nueva(s)»).
- Reglas locales afinadas: documental→Documentales; serie/temporada→Series; película→Peliculas;
  audiolibro→Audiolibros; música→Musica; curso/tutorial→06_Educacion/Cursos; libro/ebook→15_Libros.
- Cotejo de reglas insensible a diacríticos (los nombres pueden llegar en NFD desde el FS).
- Skill v2: instrucciones y casos curados actualizados — 14 casos (nuevos: serie de episodios, película).
- Casos reales reclasificados a mano: el documental → Documentales; dos audiolibros → Audiolibros.
- Tests: 100 ejecutados (99 ✅ + 1 skip); nuevo test de reglas finas.

### Added — IA de clasificación EN VIVO (clave DeepSeek) + skill v3

- `DEEPSEEK_API_KEY` en `.env.secrets` del repo: al arrancar se detecta («Clave de DeepSeek
  detectada») y el asesor clasifica ficheros y carpetas con la skill; sin red o sin coincidencia
  siguen las reglas locales (la IA nunca bloquea); los duplicados por hash se siguen saltando.
- Validación end-to-end en la carpeta de entrada (artefactos sintéticos, retirados tras probar):
  · `Dune.Part.Two.2024.1080p.AAC.mkv` → IA «nombre de película conocida (Dune Part Two, 2024)»
    (0,95) → `13_Multimedia/Peliculas/Dune-Parte-Dos-2024.mkv` — el ejemplo exacto del objetivo.
  · Presupuesto interno de empresa (0,25) → cuarentena: red de seguridad del umbral funcionando.
- Skill **v3**: documentos internos de empresa/trabajo sin categoría específica → `05_Trabajo`.
  Re-validado: «Acta-reunion-comercial-Q4-2026.txt» → IA «acta de reunión interna de empresa»
  (0,82) → `05_Trabajo/`. Ciclo afinar→probar→verificar cerrado.

### Added — N1 (control de la IA: cap diario, contadores e interruptor)

- `J4IAI.AIControlCenter`: interruptor «usar IA» (sin borrar la clave), **cap diario configurable**
  (por defecto 200) y contadores (hoy con reinicio por día natural + total acumulado); persistente
  en `UserDefaults` y seguro en concurrencia.
- El archivado (ficheros y carpetas) y las sugerencias respetan el control: al alcanzar el cap o
  apagar la IA, todo sigue por reglas locales con aviso en el registro.
- Ajustes → pestaña **«IA»**: interruptor, límite diario (stepper), uso (hoy/total) y versión de la
  skill; puente por `NotificationCenter` (`j4iSetAIEnabled`, `j4iSetAIDailyLimit`).
- Al arrancar se registra «Control IA: activada/desactivada · llamadas hoy N/M · total T».
- Atajo **⌘I** (menú «Ajustes de IA») abre Ajustes directamente en la pestaña «IA»; funciona también
  si la ventana aún no existe (router `SettingsTabRouter` + notificación `j4iOpenAISettings`).
  La apertura de la ventana usa la API moderna `openSettings` de SwiftUI vía notificación
  `j4iRequestOpenSettings` (los selectores clásicos fallaban en silencio en Sonoma con binario
  directo); los selectores quedan de respaldo y cada ruta deja traza en el registro.
- Tests `AIControlCenterTests` (3): cap, interruptor y reinicio diario.

### Added — N2 (F9.3: reevaluar la cuarentena con la IA)

- «Por revisar» (⌘R): botón **«Reevaluar con IA»** para la selección (o todo): consulta fresca con
  la skill actual y deja la propuesta como destino sugerido (icono ✨ + «IA → categoría (conf.)»);
  el movimiento sigue siendo explícito («Mover» / «Mover seleccionados»).
- La cuarentena ahora incluye también **carpetas** (antes solo ficheros) con sugerencia por nombre.
- `FilingCoordinator.proposeDestination(for:)`: propuesta sin mover (mismo criterio y salvaguardas
  que el archivado; sin caché; respeta el control de IA). Tests `FilingSuggestTests` (3).
- Ajuste posterior (24-sep, tras la primera prueba real del usuario): la propuesta de la IA **se
  conserva** como destino preseleccionado al recargar la cola tras cada movimiento (antes el
  desplegable volvía a las reglas y había que rebuscarla); botón **«Mover sugeridos (N)»** con
  confirmación (aplica de una vez todas las propuestas; los «sin destino claro» se quedan); y
  **caché persistente** (`AISuggestionStore`: JSON en Application Support con huella tamaño+fecha y
  versión de skill) — «Reevaluar con IA» reutiliza lo ya consultado (sin gastar tokens ni cap) y
  «Olvidar propuesta de la IA» (menú contextual de la fila) fuerza una consulta nueva.

### Added — N3 («Sugerir destino (IA)» en el Explorador)

- Botón «Sugerir con IA» (con selección) y menú contextual **«Sugerir destino (IA)»**: hoja con
  nombre → categoría propuesta · fuente · confianza; «Aplicar sugerencias» mueve cada elemento a su
  destino (journal/undo/colisiones vía `reclassify`); los que apuntan a cuarentena se omiten.

### Added — F9.4 (catálogo de extensiones técnicas: Redes + scripts)

- Nueva subcategoría `12_Software/Redes`: `.rsc` (scripts RouterOS de MikroTik), `.ovpn`, `.pcap`,
  `.backup` (RouterOS) y configuraciones de dispositivo (`.conf`/`.cfg`) dejan de caer en cuarentena.
- Scripts de código (`.py`, `.sh`, `.ps1`, `.sql`, `.js`, `.rb`, `.go`…) → `12_Software/Desarrollo`;
  `.ts` excluido (colisiona con vídeo MPEG-TS).
- Skill **v4** (17 casos): familias de extensión en las instrucciones de la IA y cita de la señal
  decisiva en el motivo; espejo en las reglas locales (`classifyByExtension`), activas sin IA.
- Privacidad: NO se extrae texto de scripts/configuraciones (pueden contener credenciales).
- Validación: los 4 `.rsc` reales de `99_SinClasificar` («Sin coincidencias…») son reevaluables con
  ⌘R → `12_Software/Redes`; +1 test (extensiones técnicas); suite 107 (106 en verde + 1 skip).

### Fixed — carpetas en la cuarentena y «Por revisar» (24-sep)

- Carpetas-cáscara (sin ficheros en todo el árbol, aunque contengan subcarpetas vacías — p. ej.
  «AnyUkit» con music/video vacíos) ya no van a cuarentena: `FolderProfiler.isEmpty` = sin ficheros
  y el pipeline las deja en origen («skipped-empty»; registro: «Carpeta sin ficheros «X» (2
  subcarpeta(s) sin ficheros): se deja en origen»).
- «Por revisar»: las carpetas ahora tienen su propia sección **CARPETAS (N)** (antes caían en
  «SIN EXTENSIÓN») y muestran su resumen de contenido («16 fichero(s) · dominante .pdf» /
  «sin ficheros (cáscara vacía)»); al sugerir se usa también la extensión dominante perfilada sin
  leer texto (`FolderProfiler.summarize(includeText: false)`).
- Tests: `FolderProfilerTests` (2), cáscara vía coordinador (1), agrupación por carpetas (1);
  suite 117 (116 en verde + 1 skip).

### Added — F10.0 (desglose de carpetas-cajón: la IA decide entera o por ficheros)

- El asesor responde un campo **`mode`** («folder» | «split») para carpetas: «folder» = mover la
  carpeta entera (por defecto; también si los elementos guardan relación entre sí: mismo prefijo o
  producto, curso, serie, álbum, app portable con sus ficheros); «split» = cajón heterogéneo → los
  ficheros se archivan por separado. Skill **v5** con la instrucción de estrategia; el resumen de
  carpeta incluye más nombres de ejemplo (12) para juzgar la coherencia.
- Archivado automático: si la IA decide `split` (confianza ≥ 0,6, ≤ 500 ficheros, profundidad ≤ 4),
  la carpeta se **desglosa**: cada hijo directo se procesa como unidad (ficheros por separado,
  subcarpetas con su lógica completa) y la cáscara vacía queda en origen (nunca se borra); todo va
  al journal con un **mismo lote** de undo.
- «Por revisar»: acción de fila **«Desglosar y organizar por ficheros…»** (menú contextual, con
  confirmación) para cajones atascados (p. ej. «Documents»); la sugerencia de desglose de la IA se
  muestra como «IA: cajón heterogéneo → desglosar» y la estrategia se persiste en la caché
  (`AISuggestionStore`). Los elementos con estrategia `split` no entran en «Mover sugeridos».
- Tests: parseo de `mode` (2), desglose E2E con lote único (1), estrategia persistida (1);
  suite 121 (120 en verde + 1 skip).

### Added — F11.0 (N4: múltiples carpetas de entrada)

- La configuración admite **varias carpetas de entrada** (`just4index.filing.sourcePaths`; la clave
  antigua de una sola carpeta se migra al leer). El watcher arranca una vigilancia **por carpeta**
  (idempotente, con sonda de permisos por carpeta) y el pipeline es compartido: todas las entradas
  se archivan igual.
- Ajustes → Organización: lista de carpetas de entrada con **Quitar** por fila y altas
  («Añadir…», «Usar ~/Descargas», «Usar ~/Downloads»).
- Activación real en el equipo del usuario: entradas **«~/Descargas» + «~/Downloads»** (28 GB,
  385 unidades iniciales). Registro: «Organización: entradas «~/Descargas» + «~/Downloads» → …».
  Sin problemas de TCC en `~/Downloads`; los duplicados detectados por hash se dejan en origen.
- Tests: `FilingConfigurationTests` (2: alta estandarizada/sin duplicados y baja); suite 123
  (122 en verde + 1 skip).

### Added — F12.0 (tokens reales + conocimiento local aprendido)

- **Tokens**: el cliente de DeepSeek lee el `usage` de la API y suma **tokens reales** (hoy/total,
  con reinicio diario) en `AIControlCenter`; Ajustes → IA muestra «llamadas · tokens» hoy y totales;
  el registro de arranque incluye «tokens hoy/total».
- **Conocimiento local** (`LocalKnowledgeStore`, JSON en Application Support): cada decisión de la IA
  y cada corrección manual se resumen en observaciones por **extensión de fichero** o **palabra del
  nombre de carpeta**; con **≥ 3 observaciones, ≥ 75 % de acuerdo y confianza media ≥ 0,7** se
  promueve a regla local y las próximas unidades así se clasifican **sin llamar a la IA** (fuente
  `knowledge`; el ahorro queda trazado en el registro y contado en Ajustes → IA). Una corrección del
  usuario **reescribe la regla al momento**. Los cajones con `mode: split` no enseñan categoría.
- Tests: tokens (1) + `LocalKnowledgeStoreTests` (6) + `KnowledgeFilingTests` (2: regla promovida
  evita la IA; corrección del usuario alimenta la base); suite 132 (131 en verde + 1 skip).

### Docs — PITCH.md (25-sep)

- `PITCH.md`: pitch comercial (qué es, para quién, ventajas con evidencia real, limitaciones
  honestas, comparativa y cierre de demo) + **versión corta** para el catálogo del hub JUST4ALL.
- Hub: título, descripción y changelog de JUST4INDEX actualizados en `SubAppsCatalog`.

### Added — F13.0 (buscador de destino con autocompletado)

- «Mover a…» ahora abre un **buscador de destino** (en el Explorador: toolbar, menú contextual y
  panel de selección; en «Por revisar»: cada fila y la selección múltiple): escribir filtra la
  taxonomía al momento — «trabajo» muestra `05_Trabajo` **y sus subcarpetas** — sin acentos ni
  mayúsculas, todos los términos deben aparecer, **Enter** elige el primero y **Esc** cancela.
  Sustituye los menús/dropdowns planos de ~52 categorías.
- Tests: `DestinationSearchTests` (5); suite 137 (136 en verde + 1 skip).

### Added — F14.0 (categorías al vuelo desde el buscador de destino)

- Si escribes un destino que no existe (p. ej. «trading»), el buscador ofrece **«Crear categoría
  “Trading”»** (botón y Enter): la carpeta se crea dentro de JUST4INDEX al mover (el executor hace
  `mkdir` del destino). Nombre saneado (sin barras/dos puntos, espacios colapsados, máx. 60 chars).
- **Inventario en disco** (`TaxonomyInventory`): la UI y la IA usan la taxonomía de fábrica ∪ las
  carpetas existentes en la raíz (creadas al momento o a mano; hasta 2 niveles; la cuarentena y su
  contenido quedan fuera de los destinos) — el planificador y las **categorías permitidas de la
  IA** incluyen las nuevas, así que la IA también podrá proponerlas en adelante.
- Tests: `TaxonomyInventoryTests` (3) + saneado del nombre (1); suite 141 (140 en verde + 1 skip).
- Ajuste (25-sep): en Ajustes → IA el **cap diario se puede escribir a mano** (TextField 0–5000
  con saneado) además del stepper ±50.
- Fix (25-sep, tarde): el cap diario se edita en un campo de **solo dígitos** que aplica **al
  momento** (Enter o al salir del campo); antes el valor se revertía al escribir (carrera con el
  puente de notificaciones) y el interruptor de IA podía quedar desincronizado — ambos aplican
  ahora de forma síncrona.

### Added — F15.0 (sistema de diseño + rediseño de la interfaz)

- `DesignKit.swift`: sistema de diseño J4I — **marca** índigo/violeta (glifo documento + lupa),
  **tokens** (espaciado 4–24, radios 6/10/14, semánticos éxito/aviso/peligro/superficie/hairline),
  títulos en redondeada y componentes propios: `BrandMark`, `Chip`/`ToggleChip`, `J4ICard`,
  `SectionHeader`, `PropertyRow`, `StatusPill`, `J4IEmptyState`, `GhostIconButton`, `ToolbarSeparator`.
- **Buscador**: cabecera con marca + campo con anillo de foco de marca; chips **sin cortes**
  (carrusel horizontal con fundido en el borde; toggles «Solo carpetas»/«En contenido» como chips
  con check); menú de carpeta indexada con el mismo lenguaje visual; estado inicial con marca,
  atajos y píldoras de datos; barra de estado segmentada (contadores tabulares, píldora de
  organización, acciones agrupadas).
- **Explorador**: cabeceras de panel en versalitas, **selección visible** (índigo suave + borde),
  campo de filtro integrado, propiedades como **tarjeta** con jerarquía y toolbar con acción
  primaria («Mover a…»); se elimina la ruta duplicada de la cabecera.
- **Por revisar**: toolbar **sin truncados** (orden + «Reevaluar con IA» + «Mover sugeridos (N)»
  prominente + menú «⋯» con selección/Finder/actualizar); vacío con placa de éxito; barra de
  selección en índigo suave; cabecera con contador en cápsula.
- **Ajustes**: de cajas de sistema a **tarjetas J4I** en las cuatro pestañas (Organización con
  carpetas de entrada como filas; IA con reglas/uso/skill/conocimiento; Indexado; Acerca de con
  marca, atajos y diagnóstico); cap diario con botones **− / +50** además del campo escribible.
- Títulos de ventana **limpios** («JUST4INDEX», «Explorador», «Por revisar»); la etiqueta dev
  (v/build/stamp) queda solo en «Acerca de» y en el registro; `tint` de marca en todas las ventanas.
- QA visual en **claro y oscuro** de las cuatro ventanas (capturas antes/después); suite en verde.

### Fix (25-sep) — conocimiento local: tests aislados y extensiones sin señal

- Los tests de archivado (`FilingCoordinatorTests`, `FilingPipelineTests`, `FilingSuggestTests`,
  `FolderSplitTests`, `FolderUnitFilingTests`) no inyectaban `knowledge` y **leían/escribían el
  almacén real** de conocimiento local. Ahora todos usan un `LocalKnowledgeStore` temporal.
- `LocalKnowledgeStore.noSignalExtensions` (`txt`, `dat`, `log`, `tmp`, `bak`, `old`, `md`): no se
  aprende una regla de extensión a partir de datos automáticos (IA/reglas) — una **corrección
  explícita del usuario** siempre se aprende. Retirada del almacén real la regla contaminada
  «txt → 09_Identidad/Documentos» (copia de seguridad `knowledge.json.bak-…`).
- Suite: **141 (140 en verde + 1 skip)**.

### Changed — Renombrado a JUST4DESK (25-sep, tarde)

- La app pasa de llamarse **JUST4INDEX** a **JUST4DESK** — «tu escritorio inteligente»: el nombre
  cuenta la evolución (organizar, recordar y proteger), no solo el índice. **J4DESK** queda como
  marca corta informal (coherente con el sello `J4` interno: `J4Log`, `J4I*`). Dominios comprobados
  por RDAP: `just4desk.com` y `j4desk.com` están **libres**.
- Renombrado en sitio (Plan A): carpeta `APPS/JUST4DESK`, target/binario `JUST4DESK`, hub (nombre,
  subtítulo «escritorio inteligente», icono `desktopcomputer`, acento índigo), scripts de build/DMG,
  skill `.github/skills/just4desk` y documentación. Los módulos internos `J4I*` se mantienen
  (invisibles al usuario; su renombrado, si se quiere, irá en una fase aparte).
- **Migración de datos automática y no destructiva** (`RenameMigration`, J4ICore): copia las claves
  `just4index.*` → `just4desk.*` al nuevo dominio de UserDefaults y **copia** (no mueve) la carpeta
  `~/Library/Application Support/JUST4DESK` (índice, conocimiento local y caché de sugerencias);
  el original queda como respaldo. El registro estrena `~/Library/Logs/JUST4DESK`. La carpeta de
  documentos `~/JUST4INDEX` no se toca (sigue siendo el destino; se puede cambiar en Ajustes).
- Incidencia del despliegue: la primera ejecución mostró el asistente de primer arranque (la
  configuración se cachea al crear el modelo, antes de migrar) y se completó por error, creando
  un esqueleto **vacío** en `~/JUST4DESK` — **0 ficheros afectados**; esqueleto movido a la
  Papelera, configuración restaurada y arranque corregido (relectura tras migrar).
- Tests: `RenameMigrationTests` (3: copia de claves sin pisar, copia de carpeta conservando el
  original, idempotencia); suite **144 (143 en verde + 1 skip)**.

### Added — G1 (pantalla «Inicio»: centro de control + omnibox ⌘K)

- **«Inicio» es ahora la pantalla principal**: bandeja de decisiones (cuarentena con contador y
  «Revisar», deshacer el último archivado con su nombre, avisos de organización sin
  configurar/pausada), actividad de hoy (archivados + últimos movimientos con hora y categoría,
  «Ver todo»), estado (destino, entradas indexadas, carpetas de entrada, uso de IA y reglas
  aprendidas) y accesos rápidos con sus atajos. El buscador deja de ser la identidad de arranque.
- **Omnibox ⌘K**: busca al instante desde Inicio (resultados inmediatos bajo el campo con iconos
  reales; Enter abre el primero; «Ver todos los resultados (N)» → ventana «Buscar»).
- **Ventana «Buscar» (⌘F)**: la búsqueda completa (filtros por tipo, scope por carpeta, búsqueda
  en contenido) pasa a ser su propia ventana y comparte el mismo `SearchViewModel` (arranque
  idempotente: una sola vigilancia y un solo pipeline aunque haya dos ventanas abiertas).
- Detalles: rejilla adaptativa 2×2, ventana principal 1120×720, pie con píldora de organización y
  última operación; «Inicio» aloja el asistente inicial, la actividad y el visor de registro.
- Validación: capturas de Inicio, omnibox con resultados y ventana «Buscar»; suite 144 (143 + 1).

### Changed — Terminología: «cuarentena» → «por revisar» / «sin clasificar» (25-sep)

- La palabra «cuarentena» desaparece de **toda la interfaz** (petición del usuario: «me suena a
  virus») y se sustituye por **«por revisar»** (la cola/acción; coincide con la ventana ⌘R) y
  **«sin clasificar»** (estado/carpeta; coincide con `99_SinClasificar`). Incluye Inicio, ventana
  «Buscar», «Por revisar», menús (⌘R), avisos de error, registro en vivo y documentación de
  producto (PITCH/README/SKILL_IA/skill del agente).
- Sin migración de datos: la carpeta `99_SinClasificar` y los identificadores internos
  (`quarantine*`) se conservan. Las entradas históricas de CHANGELOG/MEMORY/TODO mantienen el
  término antiguo a propósito.

### Fixed — «Inicio» contaba un `.DS_Store` como elemento «por revisar» (25-sep, noche)

- La bandeja contaba cualquier entrada de `99_SinClasificar`, incluido el `.DS_Store` invisible que
  Finder crea al abrir la carpeta → «1 elemento(s) por revisar» mientras la ventana «Por revisar»
  estaba vacía. Ahora ambos usan el mismo criterio (`QuarantineListing`, J4ICore): ocultos omitidos
  y solo ficheros/carpetas (3 tests nuevos).

### Changed — Carpeta de datos renombrada a `~/JUST4DESK` + limpieza de restos (25-sep, noche)

- `~/JUST4INDEX` → `~/JUST4DESK` (mv en sitio, sin copia de 32 GB): preferencias
  (`just4desk.filing.rootPath`), índice (`roots`/`entries`/`entries_fts`), journal y caché de
  análisis migrados con reemplazo de prefijo; caché de sugerencias de la IA actualizada.
- Eliminado un **root fantasma** `~/JUST4DESK` del índice (57 entradas del esqueleto accidental
  del renombrado): «Entradas indexadas» deja de sumarlas y no hay resultados a rutas muertas.
- `packaging/macos/JUST4INDEX.entitlements` → `JUST4DESK.entitlements` (el script de DMG ya
  esperaba el nombre nuevo).
- Hub JUST4ALL: textos de la tarjeta reescritos (sin «cuarentena», sin «(antes JUST4INDEX)»).
- Log rotado a `just4desk.log.pre-rename-20260925` para arrancar con trazas limpias (el histórico
  se conserva en disco).
