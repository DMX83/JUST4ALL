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

## Bloqueante actual (prioridad maxima)

- [ ] BUSQUEDA PROFUNDA: en ciertos arboles/directorios grandes sigue lenta o no retorna resultados en tiempos aceptables.
- [ ] Definir y aplicar timeout/feedback de progreso visible durante busqueda profunda para evitar estado "colgado".
- [ ] Ajustar pipeline de busqueda/indexacion para garantizar respuesta perceptible < 3s en casos comunes.

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
