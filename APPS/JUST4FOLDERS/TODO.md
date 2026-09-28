# TODO — JUST4FOLDERS (v1.0 App Store)

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
- [ ] Validar en campo con árboles reales enormes (100k+): primer indexado, resultados en vivo y
  feedback de progreso fino en la UI (el estado se muestra en `onStatus`).
- [ ] Decidir si el atajo del commander añade búsqueda global (todos los roots del índice).

## v1.2 — «Fiel a Opus» (en curso, 28-sep)

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

## MVP-0 — Fundaciones

- [x] Definir principios de arquitectura (AppKit-first + sandbox + copy engine).
- [x] Definir scope v1.0 y exclusions.
- [x] Subir target a macOS 14+.
- [x] Estructura SPM modular creada:
  - [x] J4FCore
  - [x] J4FFileSystem
  - [x] J4FOps
  - [x] J4FUI
- [ ] Logging con os_log en todos los modulos.
- [ ] Error model central (tecnico + UX message).
- [ ] CI base (build + tests) para modulo.

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
- [ ] Reanudación completa de jobs post-crash/muerte de app (v1.1 si se recorta alcance v1.0).

### Mapeo por módulos

- [ ] `J4FFileSystem`: `VolumeProfileProbe`, `MountFlagsCheck` y `FileEnumerationStream` implementados; falta `BookmarkAccessManager`.
- [ ] `J4FOps`: planner (`SizeClassifier`, `MkdirPlanBuilder`, `ConflictScan`, `ExecutionPlanFinalize`).
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
- [ ] Tests unit/integration/UI de caminos criticos (unit+integration listos; UI pendiente).
- [x] Export de diagnostico (zip de logs).
- [ ] Firma/notarizacion/App Store Connect/TestFlight.
- [ ] Publicacion v1.0.0.

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
