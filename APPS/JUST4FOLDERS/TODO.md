# TODO — JUST4FOLDERS (v1.0 App Store)

## v2.2 — Navegación, portapapeles y estilos (28-sep, noche)

- [x] **Barra de dirección única por panel**: atrás/adelante + breadcrumb clicable; doble clic o
  ⌘L editan la ruta (Enter va, Esc cancela); sin tira superior compartida (chip junto al estado).
- [x] **Barra lateral de navegación con clic derecho**: sin botones sueltos (Añadir ubicación /
  Info viven en menús contextuales, incluido «Quitar de Ubicaciones»).
- [x] **Portapapeles real**: ⌘C/⌘X/⌘V/⌘D + pegar desde Finder + cortar=mover al pegar +
  Comprimir (zip) + Duplicar; «Pegar» se deshabilita sin contenido válido.
- [x] **Columnas**: redimensión manual persistente por carpeta; doble clic en el divisor =
  ajustar al contenido; el marcado de «anchos del usuario» solo con arrastre real.
- [x] **Estilos visuales en Ajustes ▸ Apariencia** (Esmeralda/Océano/Amatista/Grafito/Sistema),
  aplicados en vivo.
- [x] **Modo de un solo panel** (**botón en la barra de herramientas**, ⌘\\, menú Navegación,
  paleta; persistente): solo se ve el panel activo; Tab alterna izquierdo/derecho; las columnas
  se reajustan al cambiar de modo.
- [x] **Divisoria de paneles arrastrable** (`J4FPanelSplitView`): reparto libre izq/der con  proporción persistente (`j4f.panelsLeftRatio`), aplicada al arrancar y al redimensionar;
  arrastre propio con cursor ↔ (el arrastre nativo y `setPosition` eran no-op en este contexto).
- [x] **Divisoria de la vista previa arrastrable** (`J4FBodySplitView`, v2.2d): agranda el preview
  arrastrando su borde izquierdo (útil con imágenes/documentos, sobre todo en modo de un panel);
  ancho persistente (`j4f.previewWidth`) con techo requerido atado a la ventana y autocorrección
  al valor resuelto si los mínimos de los paneles no conceden lo pedido.
- [x] **Fill total de la ventana** (v2.2d): `.ignoresSafeArea()` en `ContentView` + ancho del
  split del cuerpo fijado al de la ventana; sin huecos muertos a ningún lado.
- [x] **Fix del hueco inferior**: el stack de estado se estiraba (~250 pt) y los paneles
  acababan en el aire; ahora el split ocupa todo el alto disponible y la pila inferior usa
  altura EXACTA calculada de sus filas visibles (`NSStackView` no expone intrinsic: hugging/cap
  no la gobernaban). Lección: no activar constraints dentro de `layout()` (aborta la app).
- [x] **Fixes de layout**: el pathEditField con autoresizing envenenaba el solver (contenido no
  llenaba la ventana); refit de columnas tras asentarse; limpieza de anchos guardados envenenados.
- [x] **Barra lateral sin huecos** (v2.2e): las cabeceras de sección ya no se estiran (hugging
  requerido) y el árbol absorbe el espacio sobrante (mín. 160, prioridad 249; espaciador invisible
  cuando está colapsado) — se acabó el hueco entre «ÁRBOL» y el árbol.
- [x] **Panel Hub F1 (v2.3)**: selector «Vista previa | DESK» en el panel lateral — módulo
  **DESK mini** (`DeskMiniPanel.swift`): buscador sobre el índice global (`IndexedSearchService`,
  cap 300, doble clic abre), bandeja de Descargas (14 recientes con antigüedad), «Ordenar…»
  (ventana v2.0 con diario/Deshacer) y «Abrir en panel»; persistente (`j4f.previewModule`).
  OJO: el contenido del panel arranca a 44pt del borde superior (la toolbar tapa los primeros ~38pt).
- [x] **Panel Hub F2 (v2.3.1)**: cola **POR REVISAR** (dudosos de `99_SinClasificar` del último
  destino de ordenación, recordado en `j4f.lastOrderingDestination`; «Ver en panel» navega el
  panel activo — reusa `QuarantineListing` de J4ICore) + **ACTIVIDAD** (trabajo en curso con
  barra, espejo de la barra inferior) + pulido F1 (Enter abre el primer resultado, Esc limpia,
  menús contextuales en resultados y bandeja, foco automático al buscador al cambiar de módulo).
- [x] **Panel Hub F3 (v2.3.2)**: módulo **PICT mini** (convertir a PNG/JPEG y redimensionar 50 %
  con `sips`, fichero nuevo — nunca sobrescribe; «Abrir en JUST4PICT» si está instalada) +
  **drop de documentos sobre el módulo DESK** con propuesta de categoría + confirmación +
  movimiento por la cola (validado e2e: factura → 01_Fiscal/Facturas) + **destino recordado por
  carpeta** (`j4f.folderDestinations`, precargado en «Ordenar»).
- [x] **Submenú JUST4PICT en el clic derecho (v2.3.3)**: sobre imágenes → «Convertir a PNG»,
  «Convertir a JPEG» y «Redimensionar 50 %» (sips; fichero nuevo), reutilizando
  `PictQuickActions` (mismo motor que el módulo PICT). «Editar/Mejorar con J4P» llegará cuando
  la app acepte ficheros (su app compilada aún no declara tipos de documento).
- [x] **PICT solo con imágenes (v2.3.4)**: el submenú contextual y el tercer segmento del
  selector («Vista previa | DESK | PICT») aparecen únicamente cuando la selección del panel
  activo incluye imágenes; un módulo «pict» persistido sin selección útil se normaliza a «Vista
  previa» (fix de coherencia selector↔contenido). Validado en ambos estados con capturas.
- [x] **Integración JUST4PDF F1+F2 (v2.3.5)**: CLI real `just4pdf-cli` en JUST4PDF (merge ·
  compress · pdf2img · img2pdf, sobre sus servicios sin Qt; 7 tests) + submenú **«JUST4PDF ▸»**
  en FOLDERS (reglas de visibilidad; runner en background con detección PATH → venv del repo;
  nombres únicos). Merge validado e2e desde el menú; CLI validado (compress real 1936→1326 B).
  Evaluación completa y pendientes en `JUST4PDF_INTEGRATION.md`.
- [x] **Pestañas con clic derecho · toolbar revisado · monitor del sistema (v2.3.6)**:
  menú contextual sobre cada pestaña del panel (Cerrar pestaña · Cerrar las demás · Duplicar ·
  Renombrar… · Mover izq/der) con acciones **por índice** (no cambian la pestaña activa;
  validado e2e: clic derecho → «Cerrar pestaña» cerró la tab extra). «Exportar diagnóstico»
  sale del toolbar (herramienta de soporte) al menú Operaciones + paleta ⌘K + editor de atajos;
  etiquetas del toolbar normalizadas a español (Inicio/Copiar/Mover/Papelera/Nueva carpeta/…);
  indicadores **CPU · RAM · Disco · I/O · Batería** al final del toolbar (`SystemMonitor.swift`:
  Mach ticks CPU, `vm_statistics64`, capacidad del volumen de arranque, contadores
  `IOBlockStorageDriver` para la actividad (Bytes Read/Write, excluyendo «Disk Image»), IOKit;
  refresco 2 s; clic → Monitor de Actividad; el timer solo vive mientras la vista está en
  ventana). Nota: el % de disco es OCUPACIÓN; el segmento I/O es TRABAJO (caudal en MB/s —
  macOS no da un % de ocupación fiable: los tiempos por operación suman >100 %). Capturas
  verificadas: «CPU 18% · RAM 71% · Batería 82%»; «CPU 19% · RAM 69% · Disco 89% · Batería 80%»
  (89% = `df`); y con actividad: «I/O 59 MB/s» en reposo-arranque (replay FSEvents) y «I/O
  1.5 GB/s» durante un `dd` de 4 GB (también 661 MB/s). El tooltip detalla GB usados/totales/
  libres de memoria y disco, y lectura/escritura/ops de la E/S.
- [ ] **Integración JUST4PDF F3** (opcional): progreso en la cola de trabajos, Quick Actions del
  Finder (v0.3 de JUST4PDF) y módulo del Panel Hub (F4).
- [ ] Panel Hub — pendientes menores: reglas favoritas por extensión, «mejorar» con pipeline de
  PICT, unificar el diario de Deshacer para el drop (hoy mueve sin diario), selector compacto
  (la vista previa perdió ~65pt de alto).
- [ ] Menor conocido: la última columna («Tipo») puede recortar un carácter si el ancho queda
  justo; arrastrar el divisor lo resuelve. Reproducir con AppKit puro antes de tocarlo.

## v2.1 — UI: navegación + layout a prueba de balas (28-sep, noche)

- [x] **Barra lateral de navegación**: secciones UBICACIONES / FAVORITOS / RECIENTES con las
  tablas ya existentes, REAUTORIZAR solo cuando hay bookmarks rotos y **ÁRBOL como sección
  colapsable** (chevron; estado en `j4f.sidebarTreeExpanded`, por defecto colapsado).
- [x] **Bug raíz de layout**: el `NSViewControllerRepresentable` no se estiraba (solo `minWidth`)
  → el commander quedaba a ~965pt aunque la ventana fuese mayor; los paneles caían a su mínimo
  y las columnas se cortaban. Arreglado con `maxWidth/maxHeight: .infinity` + `bodySplit` al
  ancho del contenedor.
- [x] **Columnas a prueba de balas**: reparto determinista por anchos base contra el **viewport**
  real (no el ancho de la tabla), suelos (nombre 110 / resto 52), refit en `layout()` de la tabla
  y tras cambios de divisorias, y `reloadData` si cambian los anchos.
- [x] **Celdas sin «soup»**: con `attributedStringValue` el `lineBreakMode` del label se ignora —
  párrafos con truncado medio explícito (los textos envolvían y se solapaban entre filas).
- [x] **Autocuración de divisorias** (`healSplitLayoutIfNeeded`): si la barra lateral/preview o el
  reparto de paneles quedan absurdos (NSSplitView sin frames guardados divide a partes iguales),
  se recolocan (250 / 50-50 / 220). Prioridades de retención para que al redimensionar cedan los
  paneles.
- [x] **Pulido**: chip IZQ/DER con acento de marca, «Ir» como icono, barra superior sin texto
  «debug», estado vacío del preview con icono y ayuda, cabeceras de panel con jerarquía
  tipográfica, contadores terciarios, barra de estado `◀/▶` sin jerga («watcher» → «en disco»),
  tarjetas con estilo común (`J4FDesign` en J4FUI) y tamaño de ventana por defecto 1320×860.

## Documentacion relacionada

- Plan del modulo: `README.md`
- Plan completo v1.0: `ROADMAP_V1.md`
- Hub principal: `../../README.md`
- Roadmap general: `../../TODO.md`

## Estado actual (bootstrap)

- [x] App base SwiftUI funcional.
- [x] Escaneo recursivo + resumen por categoria.
- [x] Organizacion por copia + progreso.
- [x] Script de build DMG.
- [x] Integracion inicial en JUST4ALL.
- [x] Fixes de foco/rename/context menu/paste job queue en UI local.
- [x] Fix de copia recursiva con archivo grande en J4FOps.

## Bloqueante RESUELTO (28-sep) — búsqueda indexada v1.1

- [x] BUSQUEDA PROFUNDA: **sustituida por el índice FTS5 compartido** (`J4IIndex` de
  `PACKAGES/J4SHARED`): `IndexedSearchService` crawlea cada carpeta (cooperativo) y responde en
  <100 ms; poda lo desaparecido y se refresca con el watcher. Ya no se recorre el árbol a mano.
- [x] Validar en campo con árboles reales enormes (100k+): primer indexado, resultados en vivo y
  feedback de progreso fino en la UI. Evidencia 28-sep: crawl de 100.101 entradas en 11,4 s y
  consultas FTS5 de 10–25 ms (`scripts/perf_100k_listing.sh`); sonda de 12k en la UI: indexado
  cooperativo en ~2 s con estado «Indexando «ruta»: N entradas…» (el listado en curso puede
  mostrar su propio «Cargando N elemento(s)…» al mismo tiempo).
- [x] Decidir si el atajo del commander añade búsqueda global: **implementado (28-sep)** — la barra
  busca en la carpeta actual y **⌘F** alterna a «todo el índice» (propuesta aprobada del
  `ROADMAP_V2_OPUS.md`); también en la paleta ⌘K.

## v1.2 — «Fiel a Opus» (completada, 28-sep)

- [x] **Flat view:** botón «Aplanada» por panel + ⌥⌘F (menú Navegación). Lista instantánea de
  los ficheros del subárbol vía `SearchIndex.listByPathPrefix` (nuevo: recorrido del índice único
  de `entries.path`, ms incluso con 317k entradas); «Tipo» muestra la ruta relativa; filtro
  incremental en vivo con el filtro del panel; refresco silencioso por watcher (sin parpadeos).
- [x] **Motor J4IIndex:** `removeEntries` por lotes (tabla temporal → un DELETE por tabla; antes
  5 DELETE por path y el replay de FSEvents saturaba el actor) y refresh del watcher coalescido
  + troceado con `yield`.
- [x] **Filtro rápido de panel:** escribir sobre la tabla filtra la lista (⌫ borra, Esc limpia);
  el foco vuelve a la tabla tras ir a una ruta con ⌘L.
- [x] **Batch rename con regex + previsualización** (⇧⌘R): plan puro con detección de conflictos
  (disco + colisiones internas), preview en vivo con motivos, ejecución en dos fases
  (temporales → final, permite intercambios) y rollback best-effort.
- [x] **Colores/etiquetas Finder por fila:** color por primera etiqueta (caché) + submenú
  «Etiquetas» (7 colores + quitar) con toggle por selección; API `TagEntry`/`addColored` en J4ICore.
- [x] **Tamaños de carpeta en background:** `FolderSizeCalculator` (caché LRU 4096, single-flight,
  invalidación de ancestros por watcher); la columna Tamaño se rellena en vivo.
- [x] **Duplicados** (⇧⌘D): tamaño + SHA-256 en streaming; grupos ordenados por desperdicio,
  «seleccionar sobrantes», revelar en Finder y mover a la Papelera con confirmación.

## v2.0 — Diferenciación IA (completada, 28-sep)

- [x] **«Ordenar esta carpeta»** (⌥⌘O / menú contextual): clasifica con las reglas y taxonomía
  compartidas de DESK (`RulesFilingClassifier` + `FilingPlanner` + `DefaultTaxonomy`),
  previsualiza destino/categoría/nombre y **mueve** (nunca copia ni borra); diario JSON +
  «Deshacer última ordenación» (⌥⌘Z) que restaura los ficheros a su sitio.
- [x] **Clasificación con IA (DeepSeek)** como mejora de la propuesta por reglas: checkbox
  «Usar IA para los dudosos» (solo si hay clave `DEEPSEEK_API_KEY` o `.env.secrets`); consulta
  únicamente los que las reglas no clasifican (máx. 40 por lote), valida la respuesta contra la
  taxonomía (confianza ≥ 0,5 y categoría permitida) y muestra el motivo «IA: …». Privacidad:
  solo sale el nombre del fichero y la lista de categorías.
- [x] **Búsqueda semántica (IA)** (⌥⌘B): con clave, la consulta se expande con DeepSeek en términos
  («los papeles del seguro del coche» → seguro · coche · papeles) y se unen los resultados del
  índice sin duplicados; sin clave permanece literal. Motor validado contra la API real + 6 tests.
- [x] **Folder formats** (v2.0): cada carpeta recuerda su vista — aplanada, columna/dirección de
  orden y ficheros ocultos — y se restaura al navegar de vuelta (`FolderFormatStore`, JSON con
  LRU de 500 carpetas; «Olvidar formato de esta carpeta» en el menú contextual). Temas: fuera de
  alcance del diseño evaluado (`EVALUACION_DISENO.md`); se reevaluará si vuelve al alcance.

## v2.0 — Ola 1 «explorador de verdad» (28-sep)

- [x] Miniaturas reales (imagen/PDF/vídeo) con caché LRU y generación perezosa (`FileThumbnailCache`).
- [x] QuickLook con Espacio (↑/↓ navegan el preview; se refresca al cambiar selección).
- [x] Breadcrumb clicable bajo la cabecera de cada panel.
- [x] Drag & drop: filas arrastrables; soltar en carpeta/panel/Finder; interior mueve (⌥ copia),
  desde fuera copia (⌘ mueve), todo por la cola existente. *Falta prueba manual del gesto.*
- [x] Pulido de lista (`.inset`, fila 22, sin rayas) + estados vacíos («Carpeta vacía · ⌘N»).
- [x] Hover por fila y Ola 2 — completados (ver secciones "Ola 2" y "Ola 3" más abajo).

## v2.0 — Ola 2 «potencia sin fricción» (28-sep)

- [x] Vista previa lateral (⌥⌘P, persistente): QuickLook empotrado + metadatos; sigue a la selección.
- [x] F-keys completas: F2 renombrar · F3 QuickLook · F4 abrir · F5-F8 ya existían.
- [x] Columnas configurables desde la cabecera (mostrar/ocultar + ajustar) y recordadas por carpeta.
- [x] Historial con menú (clic derecho en Atrás/Adelante) con salto directo y rebobinado correcto.
- [x] Progreso del trabajo en la propia ventana: barra + «TIPO n/m (%)» encima del estado.
- [x] Pestañas completas: duplicar (⌥⌘T), renombrar (⌥⌘R: nombre o dejar vacío) y mover (⌥⌘←/→).
- [x] Hover por fila (cosmético) y Ola 3 — completados (ver sección "Ola 3" más abajo).

## v2.0 — Ola 3 «ADN propio» (completada, 28-sep)

- [x] Paleta de comandos ⌘K (buscador de acciones con teclas; 31 comandos tras v2.2).
- [x] Workspaces: guardar (⌥⌘S) y restaurar (⌥⌘L / contextual «Workspaces ▸») pestañas, activo
  y vista previa de ambos paneles (`WorkspaceStore` JSON; 2 tests).
- [x] Hover por fila (sutil, fuera de la selección).
- [x] Galería/mosaico (⌥⌘G): rejilla NSCollectionView con miniaturas grandes (128 px), doble
  clic abre, recordada por carpeta en el folder format; convive con orden/filtro/aplanada.
- [x] Árbol por panel (⌥⌘E, colapsable, resaltado de ruta, persistente).
- [x] Tamaño de miniaturas S/M/L (cíclico desde la paleta; recordado).
- [x] Atajos configurables (⌥⌘K: reasignar/restablecer/JSON).
- [x] Búsqueda semántica IA (⌥⌘B; expansión validada contra la API real).

## MVP-0 — Fundaciones

- [x] Definir principios de arquitectura (AppKit-first + sandbox + copy engine).
- [x] Definir scope v1.0 y exclusions.
- [x] Subir target a macOS 14+.
- [x] Estructura SPM modular creada:
  - [x] J4FCore
  - [x] J4FFileSystem
  - [x] J4FOps
  - [x] J4FUI
- [x] Logging con os_log en todos los modulos (28-sep): commander/panel/busqueda y J4FOps (jobs,
  stores, ordenacion) con subsystem `com.dmx83.just4folders`; los modulos compartidos
  (J4FCore/J4FFileSystem) registran vía `J4Log` en sus rutas clave; J4FUI es solo bootstrap (N/A).
- [x] Error model central (tecnico + UX message) (28-sep): `J4FError` (J4FOps) con `userMessage`,
  `technicalDescription` y `J4FError.from(error)` para NSError propios, Cocoa y POSIX; adoptado en
  los puntos de presentacion del commander/panel (+8 tests).
- [x] CI base (build + tests) para modulo: cubierto por `.github/workflows/ci.yml` (J4SHARED +
  JUST4DESK + JUST4FOLDERS en cada push/PR).

## MVP-1 — UI 2 paneles AppKit

- [x] Crear shell AppKit 2 paneles (left/right) con split view.
- [x] Toolbar nativa con Back/Forward, New Tab, Copy/Move/Delete, Search.
- [x] Tabla por panel con columnas Nombre/Tamano/Modificado/Tipo.
- [x] Navegacion por teclado y mouse (Enter/doble click).
- [x] Indicador de panel activo.
- [x] Path bar editable (Cmd+L).

## MVP-2 — Sandbox y permisos

- [x] Entitlements de App Sandbox minimos.
- [x] Flujo "Anadir ubicacion" con NSOpenPanel.
- [x] Persistencia de security-scoped bookmarks.
- [x] Resolucion de bookmarks al iniciar + access scope lifecycle.
- [x] Sidebar de ubicaciones autorizadas/favoritos/recientes.
- [x] Manejo de bookmark stale y reautorizacion.
- [x] Deteccion read-only/NTFS con aviso claro.

## MVP-3 — Listado escalable + metadata

- [x] Loader asincrono por directorio.
- [x] Cache LRU de URLResourceValues.
- [x] Cache de iconos/UTType eficiente.
- [x] Render incremental para directorios grandes.
- [x] Debounce de refresh.
- [x] rename, mkdir, delete (trash/permanent con confirmacion).

## Motor adaptativo v1.0 (fuente de verdad)

### A) Perfilado de volumen (pre-run)

- [x] `VolumeProfileProbe`: detectar `isReadOnly`, `isRemovable`, volumen destino (y opcional origen) e inferir perfil inicial (`SSDLike`, `HDDLike`, `NetworkLike`, `Unknown`).
- [x] `MountFlagsCheck`: confirmar `writable`; si `RO` marcar `failed` con mensaje UX claro (incluyendo NTFS/RO).

### B) Planificación con 2 listas + lanes

- [x] `FileEnumerationStream`: enumeración streaming para árboles grandes.
- [x] `SizeClassifier`: `SmallList` (<=1MB) y `BigList` (>1MB).
- [x] `MkdirPlanBuilder`: construir lista ordenada top-down de carpetas.
- [x] `ConflictScan`: escaneo de conflictos pre-run según policy.
- [x] `ExecutionPlanFinalize`: orden final `mkdirs -> BigPhase -> SmallPhase`.

### C) Scheduler adaptativo (auto-tuning)

- [x] `SchedulerBootstrap`: concurrencia inicial por perfil y creación de `LaneBig`, `LaneSmall`, `LaneMeta`.
- [x] `TelemetryWindowSampler`: muestreo cada 2-3s (`throughput`, latencia write, retries).
- [x] `ConcurrencyController`: ajustar workers (+/-1) por ventana.
- [ ] Reglas adaptativas:
  - [x] si throughput sube estable >10% => `+1 worker`
  - [x] si throughput baja o latencia sube fuerte => `-1 worker`
  - [x] si retries/errors => `-1 worker` y reducir buffer
- [x] `PhaseGate`:
  - [x] default: `LaneSmall` inicia al terminar `LaneBig`
  - [x] excepción SSDLike: solapar cuando `Big` restante <20%

### D) Presupuesto de RAM global + buffer pool

- [x] `MemoryBudgetManager` base: budget global 512MB.
- [x] Tokens de memoria por solicitud de buffer.
- [x] `BufferPool` base reutilizable.
- [x] Pools diferenciados: `1MB small`, `4MB big`, subir a `8MB` si SSDLike estable.
- [x] `BufferSizer` runtime según latencia/throughput.

### E) Ejecutores robustos (copy/move/delete)

- [x] `CopyBigExecutor` inicial (streaming).
- [x] `CopyBigExecutor` completo: progreso por chunk + `fsync` opcional/seguro.
- [x] `CopySmallExecutor` (<=1MB en memoria, paralelo por lane + budget).
- [x] `MoveStrategyResolver` base (same-volume move, fallback copy+delete).
- [x] `DeleteExecutor` con preferencia (`trash`/`permanent`) configurable.
- [x] `RetryAndFallback`: 2-3 retries + cleanup parciales (degradación dinámica conectada vía scheduler + BufferSizer).

### F) Control (pause/cancel) + eventos

- [x] `CooperativeCancellation`: checkpoints por chunk + cleanup parcial.
- [x] `PauseResumeCoordinator`: pausa al fin de chunk, cerrar handles, liberar buffers.
- [x] `EventStreamEmitter`: `started/progress/retry/error/finished` para Task Manager.

### G) Persistencia y reanudación

- [x] `JobSnapshotStore` para diagnóstico y recuperación básica al reabrir app.
- [x] Reanudación de jobs post-crash (28-sep): diario de items por trabajo (`job-<id>-items.json`),
  diálogo al arrancar («Reanudar pendientes / Descartar / Más tarde») y botón «Reanudar» en Tasks
  para snapshots de sesiones anteriores; omite orígenes ya movidos y nunca sobrescribe (policy
  rename). Validado E2E con snapshot sintético. Historial de snapshots acotado a 50 terminales
  (antes crecía sin límite: 280 entradas).

### Mapeo por módulos

- [x] `J4FFileSystem`: `VolumeProfileProbe`, `MountFlagsCheck` y `FileEnumerationStream` implementados; el rol «BookmarkAccessManager» lo cubren `SecurityScopedBookmarkStore` (J4SHARED) + la gestion de security-scope del commander (no se necesita clase aparte).
- [x] `J4FOps`: planner (`SizeClassifier`, `MkdirPlanBuilder`, `ConflictScan`, `ExecutionPlanFinalize`) — implementados en `ExecutionPlanner.swift` (el mapeo estaba desactualizado).
- [x] `J4FOps`: scheduler (`SchedulerBootstrap`, `TelemetryWindowSampler`, `ConcurrencyController`, `PhaseGate`).
- [x] `J4FOps`: runtime (`MemoryBudgetManager`, `BufferPool`, `BufferSizer`).
- [x] `J4FOps`: executors (`CopyBig`, `CopySmall`, `Move`, `Delete`, `RetryAndFallback`).
- [x] `J4FOps`: control (`PauseResumeCoordinator`, `CooperativeCancellation`, `EventStreamEmitter`).

## UI Tasks + Productividad

- [x] Ventana/panel Tasks con progreso por job y global.
- [x] Logs por job y acciones pause/cancel.
- [x] Tabs por panel.
- [x] Favoritos y recientes funcionales.
- [x] Quick search incremental.
- [x] Atajos base v1 implementados (Tab/F5/F6/F7/F8/Cmd+T/Cmd+W/Cmd+L).
- [x] Menus contextuales completos.

## Watchers + consistencia

- [x] FSEvents en carpeta activa autorizada.
- [x] Debounce y refresh parcial.
- [x] Pausa watcher durante operaciones masivas.
- [x] Refresh manual.

## Pulido App Store y release

- [x] Preferencias (delete/show hidden/buffer).
- [x] Accesibilidad completa y keyboard-first.
- [x] Pruebas de rendimiento con 100k archivos.
- [x] Tests unit/integration de caminos criticos (55 en `J4FOpsTests`). UI: `scripts/qa_smoke.sh`
  (build+tests+arranque+comprobaciones AX) al estilo de JUST4DESK; XCUITest formal pendiente de un
  target Xcode (la app vive en SPM).
- [x] Export de diagnostico (zip de logs).
- [ ] Firma/notarizacion/App Store Connect/TestFlight — **BLOQUEADO: requiere licencia Apple**
  (no abordado por indicacion del usuario, 28-sep).
- [ ] Publicacion v1.0.0 — bloqueada por la firma/licencia; el DMG local se genera y valida con
  `scripts/build_dmg.sh`.

## Validaciones recientes (2026-02-19)

- [x] `swift test` en verde con nuevo integration test de copia recursiva con archivo grande (>1MB).
- [x] Smoke UI local:
  - [x] crear carpeta `temp` en `/Users/dmx83`
  - [x] copiar `orlando_salida` dentro de `temp` con motor J4FOps y progreso visible
  - [x] renombrar desde toolbar y desde menu contextual
  - [x] click en vacio del panel selecciona raiz para acciones de contexto/info
  - [x] `Info carpeta actual` muestra metrica logica y en disco
  - [x] barra de ruta editable + `Go` con validacion
  - [x] arbol en columna izquierda sincronizado con panel activo
  - [x] arbol anclado estable + nodo `..` para subir nivel
  - [x] boton `Home` en toolbar
  - [x] autocompletado basico en barra de ruta
