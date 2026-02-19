# QA Local — JUST4FOLDERS

## Estado actual validado por CLI

- `swift build`: OK
- `swift test`: OK
- `scripts/perf_100k_listing.sh`: OK
- `swift run JUST4FOLDERS`: arranca (sin crash inmediato)

## Incidencias cerradas (2026-02-19)

- Prompt de `Nueva carpeta` / `Renombrar` recupera foco de teclado.
- `Renombrar` funciona desde toolbar y menu contextual.
- Menu contextual incluye `Nueva carpeta`.
- `Pegar item` usa cola de jobs (progreso visible).
- Copia recursiva de carpetas conserva contenido interno (incluyendo archivos >1MB).
- Barra de direccion editable + `Go` robusto (normaliza/valida ruta).
- Click en area vacia del panel selecciona raiz del directorio actual.
- `Informacion` agrega `Tamano logico` y `Tamano en disco` (dedup hard links).
- Boton/accion de `Info carpeta actual` disponible sin depender de seleccion.
- Columna izquierda cambiada a arbol del directorio activo (navegacion rapida).

## Smoke test critico (dmx83/temp/orlando_salida)

1. Abrir `/Users/dmx83` en panel activo.
2. Crear carpeta `temp`.
3. Seleccionar `orlando_salida`.
4. Copiar y pegar dentro de `temp` (F5 + cambiar panel + pegar o menu contextual).
5. Verificar:
   - job visible en status/tasks,
   - carpeta `temp/orlando_salida` creada,
   - contenido interno completo presente.

## Checklist manual UI (desktop)

### 1) Arranque y navegación básica

- Abrir app y verificar ventana principal sin errores visibles.
- Cambiar panel activo con `Tab`.
- Navegar carpetas con doble click y `Enter`.
- Back/Forward en toolbar por panel.
- `Cmd+L` enfoca path bar y permite abrir ruta.

### 2) Sidebar y permisos

- `Add Location` autoriza carpeta con `NSOpenPanel`.
- Entrada aparece en `Autorizadas`.
- Doble click en `Autorizadas/Favoritos/Recientes` abre carpeta en panel activo.
- Reautorización funciona para bookmarks stale (si se simula/produce caso).

### 3) Tabs + atajos Commander

- `Cmd+T` crea tab en panel activo.
- `Cmd+W` cierra tab actual (si queda una sola, cierra ventana).
- `F5/F6/F7/F8` ejecutan copy/move/mkdir/delete.

### 4) Operaciones y Task Manager

- Copy/Move/Delete generan job y progreso.
- `Tasks` muestra jobs y actualiza estado.
- `Pause/Resume/Cancel` funcionan en jobs activos.
- Al finalizar jobs, paneles refrescan contenido.

### 5) Watchers y consistencia

- Cambios externos en carpeta autorizada se reflejan sin refresh manual.
- Durante operaciones masivas, watcher no genera tormenta visual.
- Botón `Refresh` actualiza panel activo manualmente.

### 6) Preferencias

- Abrir `Settings`.
- Cambiar `Comportamiento de borrar` y validar efecto en `Delete`.
- Cambiar `Mostrar archivos ocultos` y validar refresco.
- Cambiar `Buffer Big inicial` y validar que no rompe operaciones.

### 7) Menú contextual

- En tabla de archivos: `Abrir`, `Abrir en Finder`, `Copiar ruta`, `Informacion`, `Renombrar`, `Eliminar`, `Eliminar definitivamente`.

### 8) Diagnóstico

- Botón `Diagnostics` genera zip.
- Zip contiene `summary.json`, `preferences.json`, y `job-snapshots.json` (si existe).

## Criterio de pase local

- Sin crashes ni bloqueos.
- Operaciones de archivos finalizan con estado correcto.
- UI responde por teclado y mouse en flujos principales.
