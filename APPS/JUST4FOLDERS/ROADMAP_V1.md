# JUST4FOLDERS — Planificacion completa hasta v1.0 (App Store)

## Principios de arquitectura (fijos)

- Core AppKit-first para UI principal (2 paneles, tablas, atajos, drag and drop).
- Sandbox desde el inicio con security-scoped bookmarks.
- Motor de operaciones con cola + scheduler adaptativo + RAM budget global de 512MB.
- Sin sistema de plugins en v1.0.

## Definicion de v1.0 (cierre)

Incluye:

- UI 2 paneles estilo commander.
- Tabs por panel.
- Favoritos y recientes.
- Atajos de teclado base.
- Operaciones Copy/Move/Delete con cola y progreso.
- Sandbox con bookmarks.
- Watchers con refresh eficiente.
- Rendimiento para carpetas grandes.

No incluye:

- Plugins.
- FTP/SFTP.
- Sincronizacion bidireccional avanzada.
- Hashing/verificacion habilitado por defecto.

## 0) Preparacion

- Definir scope v1.0 sin red para llegar mas rapido.
- Target macOS 14+.
- CI base: build + tests + versionado SemVer.
- Wireframe UI + listado de atajos iniciales.

## 1) Base del proyecto (MVP-0)

- Estructura modular SPM:
  - J4FCore
  - J4FFileSystem
  - J4FOps
  - J4FUI
- Logging con os_log.
- Error handling centralizado (error tecnico + mensaje UX).

## 2) UI principal 2 paneles (MVP-1)

- Ventana AppKit con NSSplitViewController izquierda/derecha.
- Toolbar: Back/Forward, New Tab, Copy/Move/Delete, Search.
- Panel de archivos con NSTableView virtualizada.
- Columnas: Nombre, Tamano, Modificado, Tipo.
- Orden por columna, multi-select e indicador de panel activo.
- Navegacion:
  - Enter/doble click para abrir.
  - Back/Forward por panel.
  - Path bar editable (Cmd+L).

## 3) Sandbox + permisos (MVP-2)

- Entitlements minimos para App Sandbox.
- Flujo "Anadir ubicacion":
  - NSOpenPanel para carpeta.
  - Crear/guardar bookmark.
  - Resolver al iniciar + startAccessingSecurityScopedResource.
- Sidebar de ubicaciones autorizadas (favoritos/recientes).
- Manejo de bookmark stale con reautorizacion.
- Deteccion de volumen read-only / NTFS y aviso claro.

## 4) Listado eficiente + metadata (MVP-3)

- Loader asincrono por directorio (no bloquear UI).
- Cache LRU de URLResourceValues.
- Resolucion eficiente de iconos/UTType.
- Escala para carpetas grandes (10k-100k):
  - Render incremental.
  - Debounce de refresh.
- Acciones base:
  - rename
  - mkdir
  - delete a Papelera (si aplica) / delete definitivo con confirmacion

## 5) Motor de operaciones v1

- Perfilado pre-run de volumen:
  - `VolumeProfileProbe` (`SSDLike/HDDLike/NetworkLike/Unknown`).
  - `MountFlagsCheck` para bloquear jobs en destino RO y explicar motivo UX.
- Plan de ejecución en 2 listas:
  - `SmallList` (<=1MB) y `BigList` (>1MB).
  - Orden: `mkdirs -> BigPhase -> SmallPhase`.
- Scheduler adaptativo con lanes:
  - `LaneBig`, `LaneSmall`, `LaneMeta`.
  - Telemetría por ventana (2-3s): throughput, latencia, retries.
  - Auto-tuning de concurrencia +/-1 según reglas de estabilidad.
  - `PhaseGate`: small al final de big (con solape SSD cuando `Big` <20%).
- Runtime de memoria:
  - Budget global 512MB.
  - BufferPool reutilizable por tipo de carga (small/big).
  - Ajuste dinámico de tamaño de buffer (BufferSizer).
- Ejecutores robustos:
  - `CopyBig` streaming por chunk con progreso por bytes.
  - `CopySmall` en memoria para <=1MB.
  - `MoveStrategyResolver` (same-volume move, cross-volume copy+delete).
  - `DeleteExecutor` (trash/preferencia).
  - `RetryAndFallback` (2-3 retries + degradación).
- Control y eventos:
  - cancelación cooperativa por chunk + cleanup parcial.
  - pausa/reanudación sin corrupción.
  - stream de eventos para Task Manager.

## 6) UI de operaciones (Task Manager)

- Ventana/panel de Tasks:
  - Lista de jobs.
  - Progreso por job y global.
  - Botones pause/cancel.
  - Log por job (errores y rutas).
- Notificaciones opcionales al terminar.

## 7) Productividad commander (v1 core)

- Tabs por panel.
- Favoritos + recientes.
- Quick search incremental (filtra/selecciona).
- Atajos iniciales fijos:
  - Tab cambia panel.
  - F5 Copy.
  - F6 Move.
  - F7 Mkdir.
  - F8 Delete.
  - Cmd+T tab.
  - Cmd+W cerrar tab.
  - Cmd+L path.
- Menus contextuales: copiar ruta, abrir en Finder, info.

## 8) Watchers y consistencia

- Watch de carpeta activa via FSEvents (solo ubicaciones autorizadas).
- Debounce + refresh parcial (evitar full reload).
- Pausa temporal de watcher durante operaciones masivas.
- Refresh manual disponible.

## 9) Pulido App Store

- Preferencias (puede ser SwiftUI):
  - comportamiento delete
  - mostrar ocultos
  - tamano de buffers en rangos seguros
- Accesibilidad: labels, focus, keyboard navigation.
- Rendimiento y memoria:
  - pruebas con 100k archivos
  - limites de cache y budget
- Tests:
  - unit: scheduler, buffer budget, conflict resolver
  - integration: copy trees, cancel/resume
  - UI: navegacion basica y atajos criticos
- Export diagnostico (logs + contexto en zip).

## 10) Release v1.0

- Firma, notarizacion y App Store Connect.
- Capturas, descripcion y privacidad (sin tracking si no es necesario).
- Checklist de review:
  - permisos explicados
  - sin acceso fuera de bookmarks
  - manejo de NTFS/RO sin prometer escritura
- Beta (TestFlight) + fixes.
- Publicacion.

## Hitos sugeridos

- v0.2.0: MVP-1 (UI 2 paneles AppKit)
- v0.3.0: MVP-2 (sandbox + bookmarks)
- v0.4.0: MVP-3 (listado escalable + metadata)
- v0.6.0: Motor de operaciones v1 + Task Manager
- v0.8.0: productividad commander + watchers
- v0.9.0: pulido App Store y bateria de tests
- v1.0.0: release
