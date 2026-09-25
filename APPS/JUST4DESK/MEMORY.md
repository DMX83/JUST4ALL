# MEMORY — JUST4DESK (memoria maestra)

> Archivo maestro de memoria del proyecto. **Regla dura:** toda sesión de trabajo termina con
> una entrada nueva aquí (estado, cambios, validación, siguiente paso). No se borran entradas;
> lo obsoleto se mueve a una sección "Histórico" al final.

## Cómo se usa

- Leer al inicio de cualquier sesión (humana o agente) antes de tocar código.
- Actualizar al cerrar cada tarea: (1) "Estado actual", (2) hito en "Historial de hitos",
  (3) decisiones nuevas en la tabla, (4) deuda/pendientes.
- Complementa a: `TODO.md` (qué falta), `CHANGELOG.md` (qué cambió), `ARCHITECTURE.md` (cómo está hecho).
- El skill `.github/skills/just4desk/SKILL.md` obliga a este ciclo.

## Estado actual

- Fecha: 2026-09-25
- Fase: **F7.1 completada** — sobre F3–F6, F6.1 y F7 (registro en vivo, análisis «lite» por
  nombre/extensión, taxonomía ampliada, cola acotada): + ventana de **Ajustes (⌘,)** con
  organización/indexado/diagnóstico, comandos en el menú **Ver** con atajos visibles (⌘E explorador,
  ⌘L registro), explorador con **panel de propiedades** y selección marcada (las carpetas se
  muestran todas — decisión del usuario —; los ocultos se limpian del índice).
- F7.2: atajos garantizados con monitor local de `NSEvent` (`J4IAppDelegate`), con traza en el
  registro: ⌘E explorador, ⌘L registro, ⌘A ajustes (⌘, también; **siempre**, sin passthrough de
  «Seleccionar todo» — el foco automático del buscador lo interceptaba); apertura de Ajustes con
  respaldos; botones Explorador/Registro/Ajustes en la barra de estado.
- F7.5: **búsqueda por contenido activada** — toggle «En contenido» (persistente) en la barra de
  filtros, `includeContent` en las queries y fragmento resaltado en los resultados; traza en el
  registro («(con contenido)»).
- F7.6: **revisión asistida de cuarentena** — ventana «Por revisar» (⌘R) con sugerencia por reglas,
  mover en un clic (journal + undo + índice al momento, texto reutilizado sin re-OCR).
- F7.7: «Por revisar» con **orden por extensión** (secciones; también nombre/fecha/tamaño) y
  **selección múltiple** (destino común o por fila + «Mover seleccionados»).
- F7.8: **papelera para la selección** en «Por revisar» (barra de acciones + menú contextual por
  fila; índice al momento; restauración desde el Finder — sin journal, no es un archivado).
- F8.0: **Explorador 2.0** — multiselección (⌘/mayús-clic) con «Mover a…» (journal/undo) y papelera
  en lote; orden/filtro por carpeta; duplicados visibles; QuickLook con la barra espaciadora.
- F8.1: **interfaz más agradable** — buscador con foco/sombra, chips con iconos y acento, estado
  inicial con degradado y tarjetas de atajos, barra de estado con iconos, hover en listas y ventana
  principal 1020×680 (`StyleKit.swift` con `hoverHighlight`/`KeycapBadge`).
- F8.2: **explorador con árbol de carpetas** — panel izquierdo jerárquico (chevrons, indentación,
  expandir/contraer todo), navegación de un clic y carpeta actual resaltada; el árbol se reconstruye
  desde el índice con caché de ~8 s.
- F8.3: **ingesta por unidades** — la carpeta de entrada procesa cada hijo directo como unidad
  (fichero suelto o **carpeta completa**): perfil de contenido (`FolderProfiler`: extensión dominante
  + muestras de nombres/texto), clasificación IA→reglas→extensión dominante y archivado de la
  carpeta entera con nombre/estructura intactos (antes los 63 subdirectorios de `~/Descargas` se
  ignoraban). Permisos: sonda de acceso con aviso en la app («Abrir Ajustes del Sistema…" +
  «Reintentar»).
- Suite total: **132 tests ejecutados** (131 en verde + 1 skip = benchmark opt-in; 0 fallos) y hub
  JUST4ALL compila.
- F9.0: **skill interna del clasificador** — `FilingSkill` (J4ICore) versiona instrucciones curadas
  + 12 casos reales (`curatedCases`) que sirven de few-shot para la IA y de tests de regresión; el
  prompt del asesor se compone desde la skill y al arrancar se registra «Skill de clasificación v1».
  Decisión del usuario: la skill es de la app y **no se edita** — la afinamos nosotros (repo + versión).
- F7.9: **búsqueda por subcadena** — columna `name_norm` (migración v3): «net» ya encuentra
  `dotnet-sdk` e `Internet.Download.Manager`; los prefijos siguen primero; insensible a acentos.
- F9.2: **taxonomía fina** — `13_Multimedia` → Peliculas/Series/Documentales/Audiolibros/Musica
  (Videos/Audio siguen de catch-all), `06_Educacion/Cursos`, nueva `15_Libros` (epub/mobi); reglas
  por vocabulario con cotejo sin diacríticos; skill v2 (14 casos). El instalador creó las 7 carpetas
  al arrancar; el documental y 2 audiolibros reales quedaron reclasificados a mano.
- IA **en vivo** (clave DeepSeek en `.env.secrets` del repo, detectada al arrancar): skill v3 —
  validada end-to-end con artefactos sintéticos (retirados tras probar): «Dune.…mkv» →
  `13_Multimedia/Peliculas` (0,95); acta interna de empresa → `05_Trabajo` (0,82) tras afinar la
  skill con la instrucción de empresa/trabajo.
- N1–N3 (control y ciclo cerrado): **AIControlCenter** (interruptor + cap diario 200 + contadores
  hoy/total con reinicio diario; pestaña «IA» en Ajustes); **«Reevaluar con IA»** en «Por revisar»
  (⌘R, ahora con carpetas incluidas) que propone destinos con la skill y los aplica con «Mover»;
  y **«Sugerir destino (IA)»** en el Explorador (botón + menú contextual) con hoja de confirmación
  y «Aplicar sugerencias» (reclassify con journal/undo). `proposeDestination(for:)` nuevo: propone
  sin mover (tests propios). Atajo **⌘I** → Ajustes en la pestaña IA (decisión del usuario).
- N4 (25-sep): **segunda carpeta de entrada** — varias entradas por configuración (`sourcePaths`)
  con watchers independientes (sonda TCC por carpeta); activadas «~/Descargas» + «~/Downloads»
  (28 GB, 385 unidades) con el pipeline compartido.
- F12.0 (25-sep): **tokens reales** (usage de la API sumado en `AIControlCenter`; visibles en
  Ajustes → IA y en el registro) y **conocimiento local** que aprende de la IA y de las
  correcciones del usuario (extensiones y palabras de carpeta; promoción ≥3 observaciones + ≥75 %
  + conf≥0,7; clasifica sin IA con fuente «knowledge»; `LocalKnowledgeStore` persistente).
- F13.0 (25-sep): **buscador de destino con autocompletado** (`DestinationChooser`) en «Mover a…»
  (Explorador y ⌘R): escribe «trabajo» → `05_Trabajo` + subcarpetas; sin acentos, todos los
  términos deben aparecer, Enter elige el primero.
- F14.0 (25-sep): **categorías al vuelo** — el buscador ofrece «Crear categoría “X”» si no existe
  (se crea al mover) e `TaxonomyInventory` (taxonomía ∪ carpetas reales ≤2 niveles, sin cuarentena)
  alimenta destinos de UI, validación del planificador y categorías permitidas de la IA; el cap
  diario de Ajustes → IA se puede escribir a mano (0–5000).
- F9.4: **catálogo de extensiones técnicas** (pregunta del usuario: «.rsc son scripts de MikroTik…
  ¿puede la IA clasificar por extensión?») — la IA ya veía la extensión (ficheros) y los tipos
  (carpetas), pero nada explicaba su significado; skill v4 con familias de extensión (red →
  `12_Software/Redes`, nueva; código → `12_Software/Desarrollo`) + reglas locales espejo +
  3 casos curados. Los 4 `.rsc` reales (`111/222/a2/cake`) son reevaluables con ⌘R. Privacidad:
  sin extraer texto de scripts (posibles credenciales).
- Registro en vivo (F6.1): `J4Log` en `J4ICore` (buffer + stream + archivo + `os.Logger`) con el pipeline
  completo instrumentado; visor en la app (Carpetas → Ver registro…, ⌘L) y `scripts/log_watch.sh`.
- Configuración inicial: onboarding pide carpeta raíz (sugerencia `~/JUST4INDEX`) y carpeta de entrada
  (sugerencia `~/Descargas`); genera el esqueleto de taxonomía y lo indexa para búsqueda.
- F1/F2 completadas: motor de índice (bench 100k: crawl 6.92 s; queries 0.3–38 ms) y UI buscador.
- Pendiente: **QA manual del usuario** (DMG real + flujo end-to-end con documentos reales).

## Decisiones clave

| Fecha | Decisión | Motivo | Alternativas descartadas |
|---|---|---|---|
| 2026-09-24 | Nombre **JUST4INDEX** | Elección del usuario; convención JUST4* | JUST4DOCS, JUST4SORT, JUST4FILES |
| 2026-09-24 | MVP único con ambos pilares (buscador + organizador) | Elección del usuario | Fases separadas |
| 2026-09-24 | IA local-first; DeepSeek solo con texto truncado | Privacidad + coste mínimo | DeepSeek Vision; solo local; todo nube |
| 2026-09-24 | Archivado **automático total** | Elección del usuario | Cola de revisión; auto alta confianza |
| 2026-09-24 | Redes de seguridad obligatorias del modo automático: journal+undo, cuarentena `99_SinClasificar`, never-delete (solo mover), modo simulación disponible | Hacer seguro el automatismo | Solo undo; solo revisión |
| 2026-09-24 | Destino por defecto `~/JUST4INDEX` (configurable) | Interpretación de "/dmx83" = home del usuario | `~/Documentos/JUST4INDEX` |
| 2026-09-24 | **Configuración inicial en primer arranque**: la app pide carpeta raíz (sugerencia `~/JUST4INDEX`), carpeta de entrada (sugerencia `~/Descargas`), genera taxonomía y persiste | Feedback del usuario: "la app debería pedir crear un directorio... donde desee el usuario" | Destino fijo hardcodeado |
| 2026-09-24 | Clasificación: IA (si hay key) → fallback reglas locales → cuarentena si duda (<0.5) | La IA no bloquea; reglas siempre disponibles | Solo reglas |
| 2026-09-24 | Ejecución de archivado con executor propio (move + colisiones + undo) en `J4IFiling` | Simplicidad y control del journal; `J4FOps` queda para operaciones masivas | Encolar cada fichero en JobQueueService |
| 2026-09-24 | Duplicados (hash ya archivado y presente) → se dejan en origen (`skipped-duplicate`) | Nunca destruir; el usuario decide | Mover a cuarentena / borrar |
| 2026-09-24 | docx vía `unzip` del sistema; xlsx pendiente | Coste/beneficio MVP; nota: posible limitación en sandbox | Lector ZIP propio (descartado por ahora) |
| 2026-09-24 | Análisis «lite» (hash+nombre+ext) cuando no hay texto, en vez de abortar | Instaladores/vídeo/comprimidos quedaban sin procesar e invisibles; el usuario pidió clasificarlos por nombre (IA incluida) | Dejarlos en origen |
| 2026-09-24 | Taxonomía `12_Software` / `13_Multimedia` / `14_Comprimidos` | Un `.exe`/`.mp4`/`.rar` no encaja en ninguna categoría documental; evita cuarentena masiva | Volcarlos en `99_SinClasificar` |
| 2026-09-24 | Reglas por extensión como último recurso (tras nombre y texto) | Destino razonable sin IA; el nombre/texto (y la IA) siempre tienen prioridad | Solo IA por nombre |
| 2026-09-24 | Explorador lee del índice (`children(ofDirectory:)` sobre `parent_path`) | Instantáneo y coherente con el guardrail de no recorrer disco en query | Enumerar con FileManager |
| 2026-09-24 | Cola de archivado con concurrencia acotada (4) + hash/OCR a prioridad `utility` | Con 100+ archivos, tareas ilimitadas saturaban el disco; ahora el flujo es ordenado | Tareas sin límite |
| 2026-09-24 | Explorador: las carpetas se muestran **todas** (sin filtrar vacías); selección marcada + panel de propiedades; ocultos fuera del índice | Primero se pidió ocultar vacías; el usuario después dijo «dejarla así» y las propiedades (nº de ficheros del subárbol) clarifican cada carpeta | Filtrar carpetas vacías (descartado) |
| 2026-09-24 | Pausa de organización persistente entre arranques | Ajustes debe reflejar el estado real y sobrevivir reinicios | Solo en memoria |
| 2026-09-24 | Ajustes con puente por `NotificationCenter` hacia `SearchViewModel` | Las escenas SwiftUI no comparten el viewmodel; el puente mantiene una única fuente de verdad | Estado global duplicado |
| 2026-09-24 | Comandos estándar en menú Ver (⌘E/⌘L) + `SettingsLink` en menú Carpetas | El usuario no debe adivinar atajos; deben verse en la barra de menús | Solo botones contextuales |
| 2026-09-24 | Atajos globales con monitor local de `NSEvent` (además del menú Ver) | Sin bundle `.app`, los key equivalents del menú no respondían; el monitor funciona en ejecución directa | Solo comandos de menú |
| 2026-09-24 | «Abrir explorador» pasa a **⌘A** (⌘E queda como alternativo) con passthrough en campos de texto | Petición del usuario («mejor Cmd+A»); el monitor respeta «Seleccionar todo» al editar | Solo ⌘E |
| 2026-09-24 | **⌘A = Ajustes siempre** (⌘, también); sin passthrough de «Seleccionar todo»; apertura con respaldos (selectores + ítem de menú) | El foco automático del buscador hacía que el passthrough interceptara ⌘A casi siempre (el usuario confirmó que ⌘E/⌘L sí funcionaban); ⌘A debe abrir Ajustes | Passthrough por campo de texto (descartado) |
| 2026-09-24 | Selección del explorador con resaltado manual (fondo accent + negrita), sin `List(selection:)` | El binding de selección no se marcaba con los gestos de doble clic; ahora un clic marca y dos entran/abren | `List(selection:)` (no visible) |
| 2026-09-24 | «Mover a la papelera» **manual** desde el explorador (menú contextual + propiedades) | Petición del usuario; es reversible desde el Finder y no contradice el guardrail (el motor automático nunca borra) | Borrado permanente (descartado) |
| 2026-09-24 | Target **macOS 14+** (no 13) | Dependencia local de JUST4FOLDERS (sus módulos son `.macOS(.v14)`) | Copiar módulos y bajar a 13 (duplicaría código) |
| 2026-09-24 | Reuso vía **library products nuevos** en `APPS/JUST4FOLDERS/Package.swift` + `.package(path:)` | Monorepo; evita duplicar el motor J4FOps | Copiar fuentes |
| 2026-09-24 | Módulos `J4ICore` / `J4IIndex` / `J4IDocs` / `J4IAI` / `J4IFiling` + app | Espejo del patrón modular que funcionó en JUST4FOLDERS | Target único |
| 2026-09-24 | Índice propio en `J4IIndex`; **no** reusar `PathSearchIndex` | Corregir antipatrones (LIKE por subárbol, indexado cancelado al buscar, completitud falsa) | Reusar tal cual |
| 2026-09-24 | DeepSeek: modelo `deepseek-flash`, JSON mode, off-peak | Docs verificadas 2026-09: base `https://api.deepseek.com`, `response_format=json_object` + "json" en prompt | `deepseek-v4-pro` (sin visión; más caro) |
| 2026-09-24 | Búsqueda por contenido **opt-in** (toggle «En contenido», persistente) | Cubre solo lo archivado (donde ya se guarda texto); el usuario decide cuándo usarla (coste/latencia) sin cambiar el comportamiento por defecto | Activarla siempre / dejarla apagada sin control |
| 2026-09-24 | Revisión de cuarentena **manual** («Por revisar», ⌘R): sugerencia por reglas + mover con journal | Cierra el eslabón débil del automatismo sin tocar el guardrail (sigue sin borrar; decide el usuario); las reglas F7 reevalúan ítems antiguos | Reclasificación IA automática / barrido masivo sin revisión |
| 2026-09-24 | «Por revisar»: orden por **Extensión** por defecto (con secciones) + **multiselección** con destino común | Agrupar por tipo es lo natural para decidir en lote (p. ej. todos los `.exe`); la selección múltiple evita ir clic a clic y el orden es conmutable | Solo orden por nombre / sin selección |
| 2026-09-24 | Explorador 2.0 (F8.0): multiselección + «Mover a…»/papelera en lote, orden/filtro, duplicados y QuickLook (espacio) | Cierra los pendientes de uso diario del explorador (mapa `MEJORAS.md` #4); el movimiento reutiliza `reclassify` (journal/undo) y los duplicados salen de la caché por hash | Solo selección simple / sin vista previa |

| 2026-09-24 | Explorador: panel izquierdo como **árbol de carpetas** (un clic navega) en vez de lista plana | Petición del usuario («o me haces un árbol…»): ver la jerarquía completa de un vistazo y navegar sin ir nivel a nivel con doble clic; el árbol se reconstruye del índice (caché ~8 s) | Lista plana con selección separada (descartado) |
| 2026-09-24 | Ingesta por **unidades**: cada hijo directo de la carpeta de entrada (fichero o carpeta) es una unidad; la carpeta se archiva ENTERA, sin descomponer ni renombrar | Los 63 subdirectorios de `~/Descargas` del usuario quedaban ignorados (backlog solo primer nivel y solo ficheros); mover ficheros sueltos rompería apps portables y dejaría árboles huérfanos | Recursión a fichero suelto (rompe portables) / mover carpetas sin perfil (sin criterio) |
| 2026-09-24 | Permisos macOS: fallo de lectura → aviso en la app con «Abrir Ajustes del Sistema…» + «Reintentar» (deep-link `Privacy_*`), en vez de silencio | El usuario pidió que la app «pida permisos y haga su trabajo» si el bloqueo fuera TCC; en el caso real no era TCC (era el filtro de carpetas), pero la sonda + aviso cubren ambos casos | Fallar en silencio / solo log |
| 2026-09-24 | La **skill del clasificador es interna y versionada** (sin editor de usuario): se afina en el repo con casos curados + tests de regresión | Decisión explícita del usuario («no debe modificarse, solo debemos afinarla nosotros para que haga lo que queremos bien siempre»); evita configuraciones divergentes | `policy.json` editable + editor en Ajustes (propuesta inicial, descartada) |
| 2026-09-24 | Búsqueda: tras el MATCH por **prefijos** (FTS5) se añade una pasada «contiene» sobre `name_norm` | «net» devolvía solo `Makefile.NetBSD` (prefijo) y el usuario esperaba `dotnet-sdk`/`Internet…` (comportamiento «Everything»); los prefijos siguen rankeando primero | Solo prefijos (descartado por el usuario) / trigram FTS (coste de índice innecesario a esta escala) |
| 2026-09-24 | Taxonomía fina (F9.2): `Peliculas`/`Series`/`Documentales`/`Audiolibros`/`Musica` en 13_Multimedia; `06_Educacion/Cursos`; `15_Libros` (epub/mobi) | Objetivo del usuario: una película NO va a «multimedia varios»; `Videos`/`Audio` quedan de catch-all para lo dudoso; los contextos trabajo/empresa/ocio exigen la capa IA | Todo en Videos/Audio (descartado) / inventar categorías sin señal |
| 2026-09-24 | Extensiones técnicas (F9.4): `.rsc` (RouterOS/MikroTik), `.ovpn`, `.pcap`, `.backup`, `.conf/.cfg` → nueva `12_Software/Redes`; código (`.py`/`.sh`/`.ps1`/`.sql`/`.js`…) → `12_Software/Desarrollo`; catálogo en skill v4 + espejo en reglas locales | Detonante: 4 `.rsc` reales en cuarentena y pregunta del usuario («¿puede la IA clasificar por extensión?»); red separada del código según opción recomendada (usuario no disponible; revisable en un paso) | Meter red y código juntos en Desarrollo / extraer texto de scripts (credenciales) / `.ts` como código (colisiona con vídeo MPEG-TS) |
| 2026-09-24 | Sugerencias IA **persistentes** (`AISuggestionStore`): JSON en Application Support con huella (tamaño+fecha) y `skillVersion`; «Reevaluar» reutiliza sin coste; «Olvidar propuesta de la IA» fuerza consulta nueva | Petición del usuario («que haya lugar para guardar las sugerencias… si no hay que gastar tokens de nuevo haciendo la misma pregunta»); la huella invalida si el archivo cambia y la versión de skill al mejorar el criterio | Solo memoria de sesión (descartado) / preguntar siempre (coste) |
| 2026-09-24 | Carpetas: **la IA decide entera vs desglosada** (campo `mode` de la respuesta; skill v5). `split` solo con evidencia (cajón heterogéneo: nombre sin señal y elementos dispares); seguridad: confianza ≥0,6, ≤500 ficheros, profundidad ≤4, **lote único de undo**, cáscara queda en origen | Petición del usuario: «los nombres de los subitems tienen que ver entre sí → entera; eso solo lo puede detectar la IA… una app portable con sus ficheros dentro va entera»; resuelve el caso «Documents» atascado | Desglosar siempre los cajones / desglose solo manual sin decisión IA |
| 2026-09-25 | **Segunda carpeta de entrada activada** (N4): `~/Descargas` + `~/Downloads` vía lista `sourcePaths`; un watcher por carpeta; pipeline compartido | El usuario preguntó por qué JUST4INDEX no tenía el tamaño de sus descargas: los ~28 GB estaban en `~/Downloads`, que nunca fue entrada; activada con salvaguardas (journal/undo, cuarentena, duplicados en origen) — decisión autónoma con usuario ausente (opción recomendada) | Mover los 28 GB a mano / dejarlo sin organizar |
| 2026-09-25 | **Conocimiento local** (`LocalKnowledgeStore`): aprender de la IA y de las correcciones del usuario (observaciones por extensión/palabra de carpeta; promoción ≥3 · ≥75 % · conf media ≥0,7) y clasificar sin IA | Petición del usuario («generar una inteligencia que sea de la app… para hacer menos preguntas»); ahorra tokens y la decisión queda trazada como `knowledge`; la corrección del usuario reescribe la regla | Solo caché por ruta (ya existe) / mantener reglas estáticas a mano |
| 2026-09-25 | **Tokens reales** en contadores (`usage` de DeepSeek por llamada/reintento; hoy+total con reinicio diario) visibles en Ajustes → IA | Petición del usuario («hacer el cálculo en tokens»); el cap es por llamadas y los tokens muestran el coste real | Estimación local por longitud del prompt |
| 2026-09-25 | «Mover a…» con **buscador de destino**: escribir filtra la taxonomía (padre + subitems; sin acentos; varios términos; Enter elige, Esc cancela) en Explorador y «Por revisar» | El usuario: «la lista de carpetas es muy grande y me es pesado buscar… debería ser más práctica, a lo mejor autocompletamiento» | Menús/dropdowns planos de ~52 categorías (descartado) |
| 2026-09-25 | **Categorías al vuelo** (F14.0): crear la categoría escrita desde el buscador si no existe; inventario en disco (taxonomía ∪ carpetas reales, ≤2 niveles; cuarentena fuera) usado por UI, planificador y categorías permitidas de la IA | Petición del usuario («si hay alguna clasificación que no esté… debo poder crear esa categoría o darme la opción de crearla»); las carpetas de trading estaban en cuarentena porque el cap (200) se agotó en el gran run | Solo taxonomía fija por código |

## Historial de hitos

### 2026-09-24 — F0 Fundaciones

- Qué: scaffold completo de `APPS/JUST4INDEX` (SPM con 5 módulos + ejecutable, app shell placeholder),
  `scripts/build_dmg.sh` con `J4ABuildStamp`, entitlements sandbox, docs base (README/TODO/CHANGELOG/
  MEMORY/ARCHITECTURE/PRIVACY), skill `.github/skills/just4index/SKILL.md`, y library products en
  `APPS/JUST4FOLDERS/Package.swift` para el reuso del motor.
- Cómo: patrones copiados de JUST4PICT (packaging, app shell, BuildInfo) y JUST4FOLDERS (módulos, entitlements).
- Validación: `swift build` verde (toolchain CLT vía `DEVELOPER_DIR=/Library/Developer/CommandLineTools`;
  build cruzado de `J4FFileSystem`/`J4FOps` de JUST4FOLDERS OK).
  `swift test` quedó pendiente de la licencia de Xcode en ese momento; **cerrado el 2026-09-24**
  tras aceptarse la licencia (suite verde).
- Siguiente: F1 — motor de índice.

### 2026-09-24 — F1 Motor de índice

- Qué: `J4IIndex` completo — `SearchIndex` (actor SQLite: esquema v1 con `roots`/`entries`/`entries_fts`/
  `doc_text`/`doc_text_fts`, WAL, upserts por lotes, query con filtros y ranking bm25), `IndexCrawler`
  (cooperativo, cancelable, estado por root), `IndexWatchService` (FSEvents con `eventId` persistido,
  debounce y reconciliación vía `onNeedsRescan`). Suite `J4IIndexTests` (20 tests) + benchmark 100k opt-in.
- Cómo: TDD ligero — suite escrita junto al motor y usada para cazar 3 bugs reales (ver Lecciones).
- Validación: `swift test` verde (20 tests, 0 fallos). Benchmark: crawl 6.92 s / queries media 50 ms
  (peor caso 193 ms con match global de 100k).
- Siguiente: F2 — UI buscador.

### 2026-09-24 — F2 UI Buscador

- Qué: UI completa del buscador — `SearchViewModel` (debounce 120 ms, cancelación de queries
  obsoletas, polling de estado 1 s, gestión de raíces y arranque de watchers, acciones de resultado),
  `ContentView` (campo keyboard-first, chips de filtro, scope, lista con selección y Enter,
  estados vacíos, barra de estado), `SearchResultRow` + `SearchHighlight` (resaltado insensible a
  acentos) y `ResultIconCache`. Tests `JUST4INDEXTests` (6).
- Validación: `swift test` (26 en verde) + smoke de arranque (la app abre sin crash).
- Pendiente: validación visual manual del usuario (`swift run` → añadir carpeta → buscar).
- Siguiente: F3 — ingesta y análisis.

### 2026-09-24 — F3.0/F3/F4/F5 (configuración inicial, ingesta, clasificación, archivado)

- Qué: onboarding de carpeta raíz + entrada con esqueleto de taxonomía; `J4IDocs` (`SourceFolderWatcher`
  con estabilidad/ignore-list/backlog, `TextExtractor` PDFKit+Vision OCR+txt/rtf/docx, `MetadataScanner`,
  `DocumentAnalyzer` con hash); `J4IAI` (`DeepSeekClient` JSON mode + `DeepSeekFilingAdvisor` + resolver de key);
  `J4ICore` (`FilingProposal`, `FileNameFactory`, `RulesFilingClassifier`, `FilingPlanner`); `J4IFiling`
  (`FilingExecutor` con colisiones/undo, `FilingCoordinator` con cache por hash, duplicados y journal);
  índice schema v2 (`analysis_cache` + `ops_journal`); UI de Actividad (undo/pausa/simulación/cuarentena).
- Validación: suite completa en verde (62 tests; 1 skip opt-in) y smoke de arranque.
- Siguiente: F6 — hub + release.

### 2026-09-24 — F6 (hub + release + QA)

- Qué: catálogo hub (`SubAppsCatalog` + assets), `release.sh`/`sync_local_dmgs.sh`/`clean_artifacts.sh`,
  workspace (FOLDERS/PICT/INDEX), docs raíz (README/agent.md/MODULOS_A_CREAR), `scripts/qa_smoke.sh`.
- Validación: hub compila (`swift build` raíz OK); suite de la app en verde.
- Pendiente: QA manual del usuario (DMG real + documentos reales).

### 2026-09-24 — F6.1 (observabilidad: registro en vivo)

- Qué: `J4Log` en `J4ICore` — niveles DEBUG/INFO/AVISO/ERROR, 8 categorías (app/búsqueda/índice/vigilancia/
  ingesta/extracción/IA/archivado), buffer 5 000 + `AsyncStream`, archivo rotativo
  `~/Library/Logs/JUST4INDEX/just4index.log` y `os.Logger` (subsystem `com.dmx83.just4index`).
  Pipeline instrumentado (crawler, watcher de índice, watcher de entrada, extracción, IA, coordinador de
  archivado, búsquedas, undo); visor «Registro» en la app (filtros nivel/categoría/texto, auto-scroll,
  copiar/revelar/limpiar); `scripts/log_watch.sh`; suite `J4LogTests` (7).
- Validación: suite completa en verde (69 tests; 1 skip opt-in).
- Siguiente: QA manual del usuario (ahora con registro en vivo para diagnosticar).

### 2026-09-24 — F7 (reconocimiento por nombre/extensión + explorador + concurrencia)

- Qué: análisis «lite» (perfil con hash+nombre cuando no hay texto extraíble) → ningún fichero queda
  sin procesar; taxonomía `12_Software/{Instaladores,Herramientas,Desarrollo}`,
  `13_Multimedia/{Fotos,Videos,Audio}` y `14_Comprimidos` (instalación idempotente al arrancar, también
  en instalaciones existentes); reglas nuevas por nombre (dotnet/sdk/docker/ctrader/cleaner/setup…) y
  `classifyByExtension` como último recurso; IA por nombre (prompt «sin texto extraíble…»); explorador
  (⌘E) con `SearchIndex.children(ofDirectory:)`; `FilingPipeline` (concurrencia 4) + `utility` para
  hash/OCR; tests +9.
- Validación: suite completa en verde (78 tests; 1 skip opt-in), build sin avisos.
- Siguiente: QA manual del usuario (DMG + flujo real + registro en vivo).

### 2026-09-24 — F7.1 (Ajustes, menú Ver, explorador con propiedades)

- Qué: ventana de **Ajustes** (⌘,): Organización (carpetas raíz/entrada, simulación, pausa persistente),
  Indexado (raíces con reindexar/quitar/añadir) y Acerca de/Diagnóstico (estado IA, log, explorador);
  puente por `NotificationCenter` (`AppNotifications.swift`); comandos en **menú Ver** («Abrir
  explorador» ⌘E, «Ver registro» ⌘L) + `SettingsLink`; explorador con selección, **panel de
  propiedades** (`SearchIndex.subtreeStats`), filtro de carpetas sin contenido y archivos ocultos;
  el watcher ya no indexa ocultos y limpia los existentes (`.DS_Store`).
- Validación: build sin avisos; suite completa en verde (79 tests; 1 skip opt-in).
- Contexto: el usuario reportó «faltan ficheros por organizar» → medición real: solo quedaban 2
  `.exe` en `~/Descargas` y ambos eran **duplicados** de archivos ya archivados (dejados en origen
  por diseño: nunca borrar).

### 2026-09-24 — F7.2 (atajos de teclado fiables)

- Qué: `J4IAppDelegate` (`@NSApplicationDelegateAdaptor`) con `NSEvent.addLocalMonitorForEvents`
  para ⌘E (explorador), ⌘L (registro) y ⌘, (ajustes, vía `showSettingsWindow:`); cada atajo deja
  traza debug en el registro; el menú Ver conserva los atajos visibles.
- Motivo: el usuario reportó que el atajo no funcionaba; la ejecución directa del binario (sin
  bundle `.app`) no despacha fiablemente los key equivalents del menú.
- Validación: build + suite en verde; prueba manual del usuario con trazas en el registro.
- Ajuste posterior (misma fecha): **⌘A = Ajustes** (⌘, también) y se elimina el passthrough de
  «Seleccionar todo» (el buscador autoenfocado lo interceptaba); apertura de Ajustes con respaldos
  (`showSettingsWindow:` → `showPreferencesWindow:` → ítem ⌘, del menú); ⌘E explorador y ⌘L registro
  confirmados funcionando por el usuario.

### 2026-09-24 — F7.3 (explorador: selección visible + mensaje claro)

- Qué: resaltado propio (fondo accent + negrita) al seleccionar carpetas/ficheros en el explorador
  — un clic selecciona, doble clic entra/abre — (el `List(selection:)` no pintaba la selección con
  los gestos); mensaje del panel de ficheros explicando que están en subcarpetas («N en total»)
  cuando no hay ficheros directos. Las carpetas se muestran todas, tal cual (petición del usuario:
  «vamos a dejarla así»).
- Corrección: las mejoras del explorador anunciadas en F7.1 (selección/panel de propiedades) no
  estaban realmente aplicadas en el código — las ediciones no llegaron al archivo; esta fase las
  implementa por primera vez.
- Validación: build + suite en verde.

### 2026-09-24 — F7.4 (Papelera desde el explorador)

- Qué: acción «Mover a la papelera» en el menú contextual de los ficheros y botón en el panel de
  propiedades; el índice se actualiza al instante (borrado manual de la entrada) y queda traza info
  en el registro. No hay borrado permanente: la restauración es desde el Finder (Papelera). El motor
  automático mantiene el guardrail de nunca borrar.
- Validación: build + suite en verde.

### 2026-09-24 — F7.5 (búsqueda por contenido)

- Qué: toggle «En contenido» en la barra de filtros (persistente, `just4index.search.inContent`);
  las queries pasan `includeContent` y el índice devuelve un fragmento (`snippet()` de FTS5) que se
  pinta resaltado en la fila (2 líneas); el registro anota «(con contenido)». Primer punto del
  mapa `MEJORAS.md` en ejecutarse.
- Cómo: `IndexSearchHit.contentSnippet` + `queryContent` con `snippet()` (J4IIndex); estado y
  preferencia en `SearchViewModel.searchInContent`; toggle en `ContentView.filterBar`.
- Validación: build + suite en verde (79 ejecutados: 78 en verde, 1 skip opt-in; test de contenido
  ampliado con aserciones del fragmento).

### 2026-09-24 — F7.6 (revisión asistida de cuarentena)

- Qué: ventana «Por revisar» (⌘R) — lista los ficheros de `99_SinClasificar` con sugerencia de
  destino (reglas locales), `Picker` de cualquier carpeta de la taxonomía y botón «Mover». Acción
  manual: no pasa por simulación; escribe journal (`move`, deshacer desde Actividad) y actualiza el
  índice al momento (entrada antigua fuera, nueva dentro, texto reutilizado sin re-OCR). Colisiones
  `-1` como el archivado; nunca sobrescribe.
- Cómo: `FilingExecutor.move(sourceURL:to:)` + `FilingCoordinator.reclassify(fileAt:to:)` +
  `RulesFilingClassifier.suggestDestination(fileName:)`; UI en `ReviewView` (escena «review»),
  atajo ⌘R (monitor `NSEvent` + menú Ver + menú Carpetas + fila de atajos en Ajustes).
- Validación: build + suite en verde (82 ejecutados: 81 en verde, 1 skip opt-in; tests nuevos de
  reclasificación con journal/undo y colisión resuelta).

### 2026-09-24 — F7.7 (orden y selección múltiple en «Por revisar»)

- Qué: la cola de revisión permite **ordenar** por Extensión (por defecto; secciones por tipo, «sin
  extensión» al final), Nombre, Fecha o Tamaño, y **seleccionar varios** ficheros (clic, ⌘-clic,
  mayús-clic) para moverlos en lote: destino común para la selección o el de cada fila; «Mover
  seleccionados» omite con aviso los que no tengan destino y resume el resultado.
- Cómo: `ReviewViewModel.SortKey` + `sorted(_:by:)` (puro y testeado), `selection: Set<String>` con
  `List(selection:)` y binding por id para los pickers, `performMove` compartido (individual/lote).
  El test de orden cazó un fallo real (las sin-extensión quedaban primero) y se corrigió.
- Validación: build + suite en verde (86 ejecutados: 85 en verde, 1 skip opt-in; 4 tests de orden).

### 2026-09-24 — F7.8 (papelera en «Por revisar»)

- Qué: «Mover a la papelera» para la selección (barra de acciones) y por fila (menú contextual):
  acción manual y reversible desde el Finder; el índice se actualiza al momento y queda traza en el
  registro. Sin journal (no es un archivado): se restaura desde la Papelera de macOS.
- Validación: build + suite en verde (86 ejecutados: 85 en verde, 1 skip opt-in; sin tests nuevos —
  la acción usa la Papelera real del sistema).

### 2026-09-24 — F8.0 (Explorador 2.0)

- Qué: el explorador gana **selección múltiple** (clic/⌘-clic/mayús-clic con ancla) y **acciones en
  lote**: «Mover a…» a cualquier categoría (usa `FilingCoordinator.reclassify`: journal/undo,
  colisión `-1`, índice al momento) y papelera; desde barra, propiedades y menú contextual (que actúa
  en lote si la fila está seleccionada). Además: **orden** (nombre/tamaño/fecha) + **filtro** por
  carpeta; **duplicados visibles** en propiedades («Duplicado de …», hash → caché; botón revelar); y
  **QuickLook con la barra espaciadora** (`QuickLookController` + monitor local por ventana; el app
  delegate acepta el control del panel como último eslabón de la cadena de respondedores).
- Cómo: `ExplorerViewModel.selectedFileIDs`/`handleFileClick` + `visibleFiles(_:filter:sort:)` puro
  (testeado); `WindowAccessor` + `ExplorerSpaceMonitor` (puente no aislado para `NSEvent`).
- Validación: build + suite en verde (89 ejecutados: 88 en verde, 1 skip opt-in; 3 tests de orden).
  Nota: el panel de QuickLook no se puede probar sin UI — pendiente de la prueba del usuario.

### 2026-09-24 — F8.1 (interfaz más agradable)

- Qué: pulido visual de las tres ventanas — buscador con anillo de foco/sombra y lupa en acento;
  chips de tipo con iconos y selección en acento sólido; estado inicial con degradado, tipografía
  redondeada y tarjetas de atajos; barra de estado con acciones como iconos + tooltips y menú sin
  borde; hover suave en todas las listas; encabezados de panel con iconos; ventana 1020×680. Nuevo
  `StyleKit.swift` (`hoverHighlight`, `KeycapBadge`).
- Validación: build + suite en verde (89 ejecutados: 88 en verde, 1 skip opt-in). Captura visual
  propia no disponible en este Mac (sin permiso de grabación de pantalla para el terminal) —
  pendiente de la valoración del usuario.

### 2026-09-24 — F8.2 (explorador con árbol de carpetas)

- Qué: el panel izquierdo del explorador es ahora un **árbol** de la taxonomía: chevrons para
  expandir/contraer, indentación, **navegación de un clic** (la carpeta clicada pasa a ser la actual:
  se expande, sus subcarpetas se ven en el árbol y sus ficheros en la columna central), resaltado de
  la carpeta actual, contador de ficheros por nodo y botones Expandir/Contraer todo. Se elimina el
  modelo de «selección de carpeta» (clic = navegar); las propiedades muestran la carpeta actual.
- Cómo: `FolderNode`/`TreeRow` + `visibleRows(of:expanded:)` y `folderTree(at:index:depth:)`
  (recursivo sobre el índice, puro/testeado); reconstrucción con caché de ~8 s y forzada tras
  mover/papelera/«Actualizar» (`refreshNow()`/`forceTreeRebuild()`).
- Validación: build + suite en verde (90 ejecutados: 89 en verde, 1 skip opt-in; test nuevo de filas
  visibles con expansión).

### 2026-09-24 — F8.3 (ingesta por unidades + permisos)

- Qué: la entrada archiva por unidades — ficheros sueltos y **carpetas completas** (el caso real
  `~/Descargas`: 63 subdirectorios + 2 ficheros, todos ya procesables). `FolderProfiler` resume
  contenido (extensión dominante, muestras de nombres, hasta 2 documentos de texto truncados);
  clasificación IA → reglas → extensión dominante; la carpeta viaja entera (sin rename ni
  descomposición; cuarentena incluida) con journal/undo e índice (entrada + texto-resumen; el árbol
  lo indexa el watcher del root destino). Reglas nuevas de vocabulario: audiolibro,
  documental/película/serie/temporada, curso/tutorial, portable. Permisos: sonda de acceso en
  `SourceFolderWatcher.start` (error accionable), aviso en la app con deep-link a Privacidad +
  «Reintentar»; descripciones TCC en `scripts/build_dmg.sh`.
- Cómo: unidades = hijos directos (backlog y FSEvents con filtro de profundidad); perfil sintético
  `DocumentProfile` (hash `folder:…` — las carpetas no usan caché por hash);
  `FilingCoordinator.processItem/processFolder` + `FilingPipeline.processItem`.
- Validación: build + suite en verde (93 ejecutados: 92 en verde, 1 skip opt-in; 3 tests nuevos).
  Pendiente: valoración del usuario sobre los destinos reales y la taxonomía fina (ver `MEJORAS.md`).

### 2026-09-24 — F9.0 (skill interna) + F7.9 (búsqueda por subcadena)

- Qué F9.0: `FilingSkill` (J4ICore) — `version=1`, `assistantInstructions` (criterio curado con los
  casos reales: carpeta≠documento, vocabulario audiolibro/documental/curso/portable, dudas→99) y 12
  `curatedCases` (destino esperado; `nil` = cuarentena) que valen como few-shot y como regresión.
  Prompt del asesor compuesto desde la skill + contrato JSON + few-shot; al arrancar se registra
  «Skill de clasificación v1 — 12 caso(s) curado(s)». Sin UI de edición (decisión del usuario).
- Qué F7.9: columna `entries.name_norm` (migración v3 con rellenado único) + pasada «contiene» en
  `search()`: «net» ya devuelve `Makefile.NetBSD` (1º, prefijo), `dotnet-sdk…` e `Internet…`;
  insensible a acentos («seno» → «Diseño-final.pdf»). Detonante: el usuario buscó «net» y solo salía 1.
- Cómo: `FilingSkill.fewShotLines` + `DeepSeekFilingAdvisor.systemPrompt/userPrompt`;
  `queryNameContains` + `foldForContains` en `SearchIndex`.
- Validación: build + suite en verde (99 ejecutados: 98 en verde, 1 skip opt-in; 4 tests nuevos:
  3 de skill + 1 de subcadena).

### 2026-09-24 — F9.2 (taxonomía fina)

- Qué: `13_Multimedia` → `Peliculas`, `Series`, `Documentales`, `Audiolibros`, `Musica` (Videos/Audio
  catch-all); `06_Educacion/Cursos`; `15_Libros` (epub/mobi/azw3/fb2). Vocabulario de reglas afinado
  y cotejo insensible a diacríticos (NFD); skill v2 con 14 casos curados. Al arrancar, el instalador
  creó las 7 carpetas («Taxonomía actualizada: 7 carpeta(s) nueva(s)»).
- Cómo: `DefaultTaxonomy` + `RulesFilingClassifier` (fold) + `FilingSkill` v2; tests: 16 top-level,
  paths finos, reglas finas (nuevo), casos curados actualizados.
- Validación: build + suite en verde (100 ejecutados: 99 en verde, 1 skip opt-in; +1 test). Casos
  reales reclasificados a mano (watcher reindexa): documental → Documentales; 2 audiolibros → Audiolibros.

### 2026-09-24 — IA en vivo (clave DeepSeek) + skill v3

- Qué: con `DEEPSEEK_API_KEY` presente, el asesor clasifica en producción con la skill. Ciclo de
  afinado cerrado sobre casos reales: (1) «Dune.…mkv» → «película conocida» (0,95) → Peliculas;
  (2) presupuesto interno de empresa → cuarentena (0,25) por hueco en las instrucciones → se añadió
  «empresa/trabajo sin categoría → 05_Trabajo» (skill v3) → re-test: acta interna → 05_Trabajo (0,82).
- Validación: build + suite en verde (100 ejecutados: 99+1 skip); artefactos sintéticos retirados
  tras la prueba (registro conserva las decisiones «IA → …»). Duplicados por hash confirmados.

### 2026-09-24 — N1–N3 (control de IA · reevaluar cuarentena · sugerir en Explorador)

- Qué N1: control de la IA — interruptor persistente, cap diario (200 por defecto, stepper en
  Ajustes → IA) y contadores hoy (reinicio por día) + total; el pipeline omite la IA (con aviso)
  al alcanzar el cap; línea «Control IA:…» al arrancar.
- Qué N2: «Reevaluar con IA» en ⌘R (selección o todo) — propuesta fresca por elemento con la skill;
  la cuarentena ya lista también **carpetas**; las filas muestran ✨ con «IA → categoría (conf.)».
- Qué N3: «Sugerir destino (IA)» en el Explorador (botón con selección + menú contextual) → hoja
  con propuestas y «Aplicar sugerencias» (mueve cada uno a su categoría con journal/undo).
- Cómo: `AIControlCenter` (J4IAI) + gates en `FilingCoordinator`; `proposeDestination(for:)`
  (J4IFiling, sin mover); UI en `SettingsView`/`ReviewView`/`ExplorerView` con advisor de DeepSeek.
- Validación: build limpio + suite en verde (106 ejecutados: 105 en verde, 1 skip opt-in; +6 tests:
  3 de control IA + 3 de propuesta).
- Ajuste posterior (24-sep, feedback directo del usuario en la primera sesión de uso real): en
  «Por revisar» la propuesta de la IA **se conserva** como destino preseleccionado aunque se recargue
  tras mover (bug: se perdía del desplegable y había que rebuscarla); **«Mover sugeridos (N)»**
  (con confirmación) aplica en lote todas las propuestas; `AISuggestionStore` = **caché persistente**
  (JSON Application Support; huella tamaño+fecha + `skillVersion` invalidan; reutilizar NO gasta
  tokens ni cap; «Olvidar propuesta de la IA» para forzar consulta nueva). +6 tests
  (`ReviewSuggestionsTests` 3, `AISuggestionStoreTests` 3); suite 113 (112 en verde + 1 skip).

### 2026-09-24 — F9.4 (catálogo de extensiones técnicas: Redes + Desarrollo)

- Qué: pregunta del usuario («.rsc son scripts de MikroTik… ¿puede la IA clasificar por extensión?»).
  La IA ya recibía la extensión (ficheros) y el desglose de tipos (carpetas), pero nada explicaba su
  significado: los 4 `.rsc` reales cayeron a `99_SinClasificar` («Sin coincidencias para «222.rsc»»).
  Añadido: `12_Software/Redes` (nueva); skill **v4** con familias de extensión (red y código) y cita
  de la señal en «reason»; reglas locales espejo (`.rsc/.ovpn/.pcap/.backup/.conf/.cfg` → Redes;
  `.py/.sh/.ps1/.sql/.js…` → `Desarrollo`); 3 casos curados (`.rsc` fichero y carpeta, `.sh`).
- Cómo: `DefaultTaxonomy` (subcarpeta Redes) + `FilingSkill` (v4, 17 casos) + `classifyByExtension`;
  el instalador creó `12_Software/Redes` al arrancar («Taxonomía actualizada: 1 carpeta(s) nueva(s)»).
- Validación: build + suite en verde (107 ejecutados: 106 en verde, 1 skip; +1 test). Destino elegido
  por opción recomendada (usuario no disponible); reevaluación de los 4 `.rsc` en ⌘R pendiente de un
  clic del usuario. Nota de privacidad: NO se extrae texto de scripts (posibles credenciales).

### 2026-09-24 — Carpetas en la cuarentena («AnyUkit») + sección CARPETAS

- Qué: caso real — `AnyUkit` (cáscara con subcarpetas music/video VACÍAS, 0 ficheros) acabó en
  `99_SinClasificar` porque `isEmpty` exigía también 0 subcarpetas; al reevaluar, la IA respondía
  «carpeta vacía» (0,20) y no había nada más que hacer. En «Por revisar» además caía bajo
  «SIN EXTENSIÓN», sin diferenciarse de un fichero sin extensión.
- Cómo: `FolderProfiler.isEmpty` = **sin ficheros en todo el árbol** (cáscaras incluidas) → el
  pipeline las deja en origen (`skipped-empty`); `summarize(includeText: false)` para listados
  rápidos (sin leer PDFs); «Por revisar» agrupa las carpetas en **CARPETAS (N)** con resumen de
  contenido y usa la extensión dominante perfilada al sugerir.
- Validación: build + suite en verde (117 ejecutados: 116 + 1 skip; +4 tests). `Documents` (cajón
  heterogéneo, IA 0,95 → cuarentena) queda como decisión manual del usuario (destino a mano o
  papelera); el desglose por ficheros llegó después (F10.0).

### 2026-09-24 — F10.0 (desglose de carpetas-cajón: la IA decide entera o desglosada)

- Qué: petición del usuario — «desglosa por ficheros… los nombres de los subitems tienen que ver
  entre sí → la carpeta entera; eso solo lo puede detectar la IA (una app portable con sus ficheros
  va entera)». El advisor responde `mode`; skill v5; el pipeline desglosa cuando la IA lo decide
  (con barandillas) y «Por revisar» gana la acción manual «Desglosar y organizar por ficheros…» con
  confirmación; la estrategia se persiste en la caché de sugerencias.
- Cómo: `FilingProposal.folderStrategy` (J4ICore) + `DeepSeekFilingAdvisor` (parseo de `mode` +
  instrucciones de coherencia) + `FilingCoordinator.processFolderSplit/splitFolder` (hijos como
  unidades, mismo `batchID`, `maxSplitElements=500`, `maxSplitDepth=4`, symlinks como ficheros,
  cáscara en origen) + `Suggestion.folderStrategy` + UI (subtítulo «IA: cajón heterogéneo → desglosar»).
- Validación: build + suite en verde (121 ejecutados: 120 + 1 skip; +4 tests: mode 2, desglose E2E 1,
  estrategia en caché 1). E2E real pendiente del usuario: ⌘R → «Documents» → menú contextual
  «Desglosar y organizar por ficheros…», o «Reevaluar con IA» y atender el hint.

### 2026-09-25 — N4 (segunda carpeta de entrada: `~/Downloads`)

- Qué: pregunta del usuario «~/Descargas tiene ~30 GB y no veo JUST4INDEX con ese tamaño». Diagnóstico:
  `~/Descargas` ya estaba organizada (17 MB: cáscaras vacías + 2 duplicados que por diseño se quedan);
  los 28 GB estaban en **`~/Downloads` (sistema), que nunca fue entrada**. Implementado N4:
  `FilingConfiguration.sourcePaths` (migración de la clave antigua), watchers múltiples por carpeta
  (idempotentes, sonda TCC por carpeta), Ajustes con lista/alta/baja («Usar ~/Downloads»).
- Activación: `sourcePaths = [~/Descargas, ~/Downloads]` (simulación off, pausa off) y relanzado:
  registro «Organización: entradas «~/Descargas» + «~/Downloads» → …»; escaneo inicial de Downloads
  = 385 unidades; archivado con IA en marcha (0,60–0,93 en las primeras decisiones) sin errores TCC;
  duplicados por hash dejados en origen.
- Validación: build + suite en verde (123: 122 + 1 skip; +2 tests de configuración).

### 2026-09-25 — F12.0 (tokens reales + conocimiento local aprendido)

- Qué: (a) contador de **tokens reales** por llamada a partir del `usage` de la API (hoy/total con
  reinicio diario; Ajustes → IA muestra llamadas · tokens; el registro de arranque los incluye);
  (b) **base de conocimiento local** que resume cada respuesta de la IA y cada corrección del
  usuario en observaciones por característica (extensión de fichero; palabras del nombre de
  carpeta — sin números puros ni relleno), promoviendo a regla local con ≥3 coincidencias · ≥75 %
  de acuerdo · conf media ≥0,7; las promovidas clasifican **sin IA** (fuente `knowledge`).
- Cómo: `AIControlCenter.registerTokens` + parseo del `usage` en `DeepSeekClient`;
  `LocalKnowledgeStore` (JSON) + `KnowledgeFeatures`; consulta antes de la IA en
  `processFile`/`processFolder`; aprendizaje tras la respuesta de la IA (los `split` no enseñan
  categoría) y en `reclassify` (corrección del usuario = promoción inmediata).
- Validación: build + suite en verde (132: 131 + 1 skip; +9 tests). E2E real: las promociones
  aparecerán en el registro («Conocimiento local: regla promovida…») y en Ajustes → IA.

### 2026-09-25 — F13.0 (buscador de destino con autocompletado)

- Qué: petición del usuario sobre el Explorador («escribir "trabajo" y que salgan opciones de
  subitems además de "trabajo"»). `DestinationChooser` reemplaza los menús de ~52 categorías en
  «Mover a…»: búsqueda al momento (fold sin acentos, TODOS los términos, orden padre→hijos),
  Enter elige el primero, Esc cancela; aplicado también a las filas y a la selección de ⌘R.
- Validación: build sin avisos + suite en verde (137: 136 + 1 skip; +5 tests `DestinationSearchTests`).

### 2026-09-25 — F14.0 (categorías al vuelo) + cap escribible

- Qué: (a) el buscador de destino ofrece **crear la categoría escrita** cuando no existe (p. ej.
  «Trading»); se crea al mover y las próximas veces aparece en la lista; (b) `TaxonomyInventory`
  (taxonomía ∪ carpetas reales en disco, ≤2 niveles, sin cuarentena) alimenta destinos de UI,
  validación del planificador y **categorías permitidas de la IA** — las categorías nuevas también
  se propondrán por IA en adelante; (c) en Ajustes → IA el cap diario se puede **escribir a mano**
  (0–5000 con saneado) además del stepper.
- Contexto: las carpetas de trading del usuario quedaron en cuarentena porque el cap (200) se agotó
  durante el gran run de `~/Downloads`; con el día repuesto, «Reevaluar con IA» las analiza y
  «Trading» ya es una categoría válida como destino.
- Validación: build + suite en verde (141: 140 + 1 skip; +4 tests: inventario 3 + saneado 1).
- Fix (25-sep, tarde): el cap diario (Ajustes → IA) es un campo de **solo dígitos** aplicado al
  momento (Enter o al salir); antes se revertía al escribir por la carrera con el puente de
  notificaciones (`refresh()` leía el valor viejo); el interruptor de IA aplica ahora síncrono.
- F15.0 (25-sep): **sistema de diseño + rediseño vendible de la interfaz** — `DesignKit.swift`
  (marca índigo/violeta `BrandMark`, tokens de espaciado/radios/colores y componentes: chips,
  toggles-chip, tarjetas, cabeceras en versalitas, píldoras de estado, estados vacíos, botones
  fantasma). Rediseño de las 4 ventanas: buscador con marca + barra de estado segmentada +
  carrusel de chips con fundido; explorador con selección visible y propiedades en tarjeta;
  «Por revisar» sin truncados (menú «⋯» para acciones secundarias); ajustes en tarjetas y cap
  con −/+50. Títulos de ventana limpios (la etiqueta dev queda en «Acerca de» y el registro) y
  `tint` de marca. Decisión autónoma por ausencia del usuario: acento índigo, estilo «nativo
  refinado». QA visual en claro y oscuro de las 4 ventanas con capturas.
- R1 (25-sep, tarde): **renombrado a JUST4DESK** («tu escritorio inteligente»; marca corta J4DESK;
  dominios `just4desk.com`/`j4desk.com` libres). Plan A en sitio: carpeta `APPS/JUST4DESK`,
  binario/dominio/App Support/Logs `JUST4DESK`, hub con subtítulo e icono nuevos, skill
  `just4desk`, docs. **Migración no destructiva** (`RenameMigration`: copia claves
  `just4index.*`→`just4desk.*` y **copia** la carpeta de datos; el original queda de respaldo).
  **Lección clave**: la configuración se cachea en propiedades `@Published` al crear el modelo
  (antes de que corra la migración) → hay que **releerla** tras migrar, o la app arranca como
  instalación nueva y aparece el asistente de primer arranque (pasó en la 1ª ejecución y se creó
  un esqueleto vacío en `~/JUST4DESK`; **0 ficheros afectados**; esqueleto a la Papelera,
  config restaurada, relectura implementada). Suite 144 (143 + 1 skip). Pendiente de decisión del
  usuario: renombrar también la carpeta de datos `~/JUST4INDEX` (~32 GB).
- G1 (25-sep): **pantalla «Inicio» — centro de control + omnibox ⌘K** (`HomeView`): bandeja
  (cuarentena con contador + «Revisar», deshacer con nombre del último archivado, avisos de
  configuración/pausa), actividad (N archivados hoy + últimos movimientos), estado (destino,
  entradas, carpetas de entrada, uso de IA, reglas aprendidas) y accesos con atajos. El buscador
  completo pasa a la ventana **«Buscar» (⌘F)**; el omnibox busca desde Inicio (Enter abre el
  primero, «Ver todos» → Buscar). **Motor compartido**: `SearchViewModel` se crea una vez en
  `Just4DeskApp` y se inyecta por `environmentObject`; `start()` es idempotente (`hasStarted`)
  para que Inicio y Buscar convivan sin duplicar vigilancia/pipeline. Cuarentena contada con
  listado plano barato (`refreshQuarantineCount`, refresco junto a `refreshActivity`). Atajos
  nuevos: ⌘F Buscar y ⌘K omnibox (comandos + notificaciones `j4iOpenSearch`/`j4iFocusOmnibox`).
  Suite 144 (143 + 1 skip); capturas validadas (Inicio/omnibox/Buscar).
- Terminología (25-sep, petición del usuario): **«cuarentena» fuera de la interfaz** («me suena a
  virus») → **«por revisar»** (cola/acción, coincide con la ventana ⌘R) y **«sin clasificar»**
  (estado/carpeta, coincide con `99_SinClasificar`). Cambiado en Inicio/Buscar/Por revisar/
  menús/avisos/log y docs de producto; identificadores internos `quarantine*` y carpeta intactos
  (sin migración de datos). Las entradas históricas conservan el término antiguo.
- Fix F12.0 (25-sep): **aislamiento del conocimiento local en tests** (los de archivado no
  inyectaban `knowledge` y contaminaban el almacén real) + `noSignalExtensions` (txt/dat/log/
  tmp/bak/old/md: no se aprende regla de extensión desde datos automáticos; las correcciones
  del usuario sí). Retirada del almacén real la regla «txt → 09_Identidad/Documentos» (copia
  `knowledge.json.bak-20260925-125023`). Suite 141 (140 + 1 skip) — el fallo detectado en esta
  sesión lo destapó precisamente esa contaminación.
- Limpieza JUST4INDEX (25-sep, noche, petición del usuario: «veo vinculos aun a just4index… no hay
  ningun elemento por revisar y sale en el main»): (a) el «1 elemento por revisar» era un
  `.DS_Store` invisible — el contador de Inicio listaba ocultos y «Por revisar» no → criterio
  compartido `QuarantineListing` (J4ICore: omite ocultos, solo ficheros/carpetas) + 3 tests;
  (b) carpeta de datos renombrada `~/JUST4INDEX` → `~/JUST4DESK` en sitio (mv instantáneo, sin
  copiar 32 GB) con reemplazo de prefijo en preferencias (`just4desk.filing.rootPath`),
  `roots`/`entries`/`entries_fts`, `ops_journal` y `analysis_cache` + caché de sugerencias;
  (c) eliminado un **root fantasma** `~/JUST4DESK` del índice (57 entradas del esqueleto
  accidental) — «Entradas indexadas» ya no lo suma; (d) `JUST4INDEX.entitlements` →
  `JUST4DESK.entitlements` (el script de DMG ya esperaba el nombre nuevo); (e) hub JUST4ALL sin
  «cuarentena» y sin «(antes JUST4INDEX)»; (f) log rotado (`just4desk.log.pre-rename-20260925`).
- G2 (25-sep, noche): **sugerencias proactivas v1** — tarjeta «Sugerencias» a ancho completo en
  «Inicio» con tres detectores baratos (re-escaneo ≤1/min; nada se ejecuta sin confirmar):
  (a) **duplicados** que siguen en las entradas por coincidencia de tamaño
  (`SearchIndex.indexedFileSizes`) + verificación por hash al aplicar → Papelera (reversible;
  **validado por el usuario en vivo: 4 duplicados, 25,1 MB**);
  (b) **capturas sueltas** (entradas + Escritorio) → [Archivar] vía pipeline real con journal/undo
  (sin simulación: acción manual) + destino nuevo `13_Multimedia/Capturas` (taxonomía + regla);
  (c) **grandes y olvidados** (≥1 GB, 180 días, `SearchIndex.largeFiles`) → [Revelar] (archivo en
  frío = G6). Silencios: «Ahora no» (7 d) / «Nunca más» persistentes (`SuggestionDismissals`,
  `just4desk.suggestions.*`). Motor `ProactiveSuggestionScanner` (J4IFiling). Suite 157 (156 + 1
  skip; +10 tests). Capturas en `docs/design/G2/`.
- G3 (25-sep, noche): **pantalla «Reglas» (⌘G)** — el conocimiento local a la vista: lista las 27
  reglas reales (promovidas) + características en observación con confianza/muestras; destino
  editable con el buscador de categorías (reescribe y promueve al momento), borrado, reglas
  manuales y **export/import JSON portable v1 con fusión por muestras** (gana quien tenga más
  observaciones; lo local nunca se pierde). API nueva en `LocalKnowledgeStore` (`rules()`,
  `setDestination`, `removeRule`, `addManualRule`, `exportData`/`importData`, `Stats` con init
  público). Validado con captura (27 reglas · aplicadas hoy 10). Suite 164 (163 + 1 skip; +7
  tests). Siguiente: G4 (menú de barra + atajo global + Quick Action de Finder).

## Lecciones y trampas

- (heredadas de JUST4FOLDERS; aplican aquí)
  - No enumerar el árbol en tiempo de query: siempre índice precomputado.
  - No usar `path LIKE 'root/%'` para filtrar subárboles: usar columna `root_id`.
  - Completitud de indexado por root; nunca dar por indexado un root con datos parciales.
  - Evitar `resourceValues` con muchos keys por item en caliente; usar caches (extensión→UTType, LRU de metadata).
  - Antes de mover un fichero recién descargado: esperar estabilidad (size+mtime) e ignorar
    `.part`, `.crdownload`, `.download`, `.tmp` y ocultos.
- DeepSeek: el JSON mode puede devolver contenido vacío ocasionalmente → retry corto + fallback a reglas.
- Scripts y configuraciones (`.rsc`, `.py`, `.sh`…): **no** se extrae su texto para la IA (pueden
  contener credenciales); se deciden por nombre + extensión con el catálogo de familias (skill v4).
- Extensiones que colisionan: `.ts` (TypeScript vs vídeo MPEG-TS) — el catálogo de código lo excluye.
- Carpetas-cáscara: «vacía» debe significar **sin ficheros en todo el árbol** — una carpeta con
  subcarpetas vacías (p. ej. music/video) es cáscara: no se archiva ni va a cuarentena.
- La estrategia de una carpeta (entera vs desglosada) es una decisión de CONTEXTO (nombres
  relacionados vs cajón): la responde la IA (`mode`); el desglose hereda todas las salvaguardas
  (lote único de undo, cáscara en origen, sin borrar) y los hijos siguen la lógica completa de unidad.
- Toolchain (este Mac, 2026-09): Xcode instalado pero con licencia sin aceptar; el CLT no trae XCTest
  ni Swift Testing → `swift test` requiere el toolchain de Xcode (con licencia aceptada).
- FTS5: `-` y otros separadores en la query pueden romper el MATCH (p. ej. `informe-2026*` no matchea).
  Solución adoptada: trocear la query en sub-tokens alfanuméricos (mismo criterio que unicode61) y
  construir `token* AND token*`; así ningún carácter sintáctico de FTS5 llega a la expresión MATCH.
- FSEvents + `/private`: los eventos pueden llegar con prefijo `/private` añadido (`/private/var/…`)
  aunque el root sea `/var/…`. `resolvingSymlinksInPath()` **no es fiable** para normalizar (con rutas
  existentes normaliza `/private/X` → `/X`; con inexistentes devuelve tal cual). Solución:
  `StreamContextBox.mapEventPath` compara contra ambas formas conocidas y alterna el prefijo `/private`.
- Ingesta FSEvents: al borrar un fichero el lote suele incluir también evento de la carpeta padre;
  el descarte por "cubierto por escaneo de carpeta" **no debe aplicarse a paths inexistentes**
  (un borrado se procesa siempre, aunque el padre se vaya a re-escanear).
- Observabilidad: el journal solo registra operaciones aplicadas; errores y decisiones previas
  (hash, caché, IA vs reglas, plan) no dejaban rastro. Sin registro es imposible explicar por qué un
  archivo acabó en cuarentena o por qué solo parte de un backlog se procesó (la estabilidad se evalúa
  por ticks y un backlog grande tarda en estabilizarse). `J4Log` cubre ahora todo el pipeline.

## Convenciones activas

- Taxonomía seed (configurable en `taxonomy.json`): ver `ARCHITECTURE.md`.
- Plantilla de nombre: `YYYY-MM-DD_Emisor_Tipo[_descriptor].ext`; saneado de caracteres ilegales; máx. 120 chars.
- Umbrales de confianza: < 0.5 → `99_SinClasificar`; resto → archivado (modo automático del usuario).
- Idioma de categorías: español; el matching normaliza acentos y mayúsculas.
- Búsqueda: query troceada a sub-tokens alfanuméricos → `token* AND token*`; FTS5 unicode61
  (`remove_diacritics 2`); ranking `bm25` con peso del nombre 5× respecto a la ruta.
- Organización: automática total (decisión del usuario) con undo/pausa/simulación; nunca borra.
- Clasificación: IA → reglas por nombre → reglas por texto → extensión (último recurso) → «sin clasificar»;
  umbral de confianza 0.5; nombre `YYYY-MM-DD_Emisor_Titulo.ext`.
- Build/versionado: `scripts/app_env.sh` (raíz del repo) + `J4ABuildStamp` en Info.plist.
- Registro: usar `J4Log.debug/info/warn/error(categoría, mensaje)` en código nuevo; visor en la app
  (⌘L); archivo en `~/Library/Logs/JUST4DESK/just4desk.log`; los tests silencian el archivo
  automáticamente (o `J4I_LOG_FILE=0` a mano).

## Deuda técnica / pendientes abiertos

- ✅ Licencia de Xcode aceptada el 2026-09-24 (`swift build`/`swift test` con toolchain de Xcode).
- ✅ Destino configurable resuelto: onboarding de primer arranque (carpeta raíz + carpeta de entrada).
- **QA manual del usuario** (bloqueante para cerrar el MVP): DMG real con `./scripts/build_dmg.sh` y flujo
  end-to-end con documentos reales (soltar PDFs en la carpeta de entrada → archivado → undo);
  revisar el registro en vivo (⌘L) para validar las decisiones de clasificación.
- Post-MVP: cap diario de llamadas DeepSeek + métricas; renombrar y drag & drop en el explorador;
  xlsx; imágenes reales para `Assets/JUST4DESK/` del hub.
- Mapa de mejoras priorizado (propuestas candidatas, sin aprobar): `MEJORAS.md` — pendiente de la
  elección del usuario para convertirlas en fases.
- Decidir en F5 si el primer arranque propone activar el modo simulación (recomendado) o arranca en automático directo.

## Dependencias externas

- **DeepSeek API** (`https://api.deepseek.com`, modelo `deepseek-flash`): opcional; key en
  `DEEPSEEK_API_KEY` o `.env.secrets`. JSON mode: `response_format=json_object` + "json" en el prompt.
- Sin otras dependencias de red. Dependencia local: `APPS/JUST4FOLDERS`.

## Histórico

- (vacío)
