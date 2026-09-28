# QA Local — JUST4FOLDERS

## Estado actual validado por CLI

- `swift build`: OK
- `swift test`: OK (55 tests, 28-sep)
- `scripts/perf_100k_listing.sh`: OK (28-sep: listado 100k + crawl/consultas del indice)
- `scripts/qa_smoke.sh`: OK (28-sep: build+tests+arranque+AX)
- `swift run JUST4FOLDERS`: arranca (sin crash inmediato)

## Incidencia de busqueda profunda (2026-02-19) — RESUELTA (28-sep)

- La busqueda profunda por recorrido de arbol se sustituyo por el **indice FTS5 compartido**
  (`J4IIndex`): consultas de 10–25 ms sobre 100k+ entradas (ver «Rendimiento» abajo); el
  comportamiento inestable ya no es reproducible.
- La decision original (no cerrar QA hasta respuesta consistente) queda cumplida; se mantiene la
  checklist manual de abajo para regresiones.

## Validaciones 28-sep (tarde-noche)

- [x] `⌘F` alterna «esta carpeta ⇄ todo el indice» (placeholder y estado lo reflejan); la busqueda
  global devuelve resultados de todo el indice (verificado por AX + captura).
- [x] Estado de indexado en vivo: «Indexando «ruta»: N entradas…» (probado con 12k ficheros; el
  listado en curso puede mostrar «Cargando N elemento(s)…» a la vez).
- [x] Reanudacion post-crash E2E: snapshot sintetico → dialogo al arrancar → «Reanudar pendientes»
  copia lo pendiente, omite origenes ya movidos y limpia el snapshot.
- [x] Historial de snapshots acotado (280 → 50 terminales; el JSON crecia sin limite).
- [x] VoiceOver no aplica aqui (app AppKit con labels propios); pendiente auditoria formal.

## Validaciones 28-sep (noche) — UI v2.1/v2.2/v2.2b

- [x] Layout a prueba de balas: ventana llena con ambos paneles completos (Nombre/Tamaño/
  Modificado/Tipo) y sin conflictos del solver (los conflictos de AppKit, si los hay, van al
  log unificado, no a stderr).
- [x] Modo de un solo panel (⌘\\ o **botón de la barra de herramientas**): ciclo completo con
  capturas — clic 2→1 y 1→2, solo el activo, Tab alterna izq/der, persistencia confirmada al
  relanzar la app y vuelta a dual con reajuste automatico de columnas.
- [x] Divisoria entre paneles: arrastre real validado (divisor 659 → 830) y persistencia al
  relanzar (838 ≈ proporcion × ancho nuevo; escala si cambia la ventana).
- [x] Divisoria del preview (v2.2d): encoger deja 464pt exactos guardados; agrandar topa en el
  minimo real de los paneles (~884pt en dual) y el valor guardado se autocorrige al resuelto
  (885) — sin valores fantasma tras relanzar.
- [x] Fill completo de la ventana (v2.2d): geometria verificada (view = 1.728 = ventana; split
  hasta 28pt del borde inferior: 10 de separacion + fila de estado de 18 + margen 12) y capturas
  sin bandas muertas arriba/abajo/izquierda/derecha.
- [x] Hueco inferior cerrado: los paneles ocupan todo el alto disponible (antes ~250 pt muertos
  a causa del stack de estado estirado; v2.2d: altura exacta por filas visibles).
- [x] Estilos visuales en vivo: cambio a Oceano reflejado al instante (chip, toggles, sidebar);
  restaurado a Esmeralda.
- [x] Comprobado en el mismo ciclo: barra de direccion por panel (atras/adelante + edicion),
  sidebar con acciones contextuales, portapapeles completo (⌘C/⌘X/⌘V/⌘D, cortar=mover, pegar
  desde Finder, Comprimir/Duplicar) y columnas manuales persistentes.
- [x] `swift test`: 55 en `J4FOpsTests`, 0 fallos.

## Rendimiento (100k, 28-sep)

- `J4I PERF · crawl: 100.101 entradas en 11,4 s` (J4IIndex; `perf_100k_listing.sh`).
- Queries FTS5: 10–25 ms tipicas (`archivo-500`: 25,0 ms · `dir-50`: 10,5 ms · `txt` (termino muy
  comun): 102 ms).
- Listado incremental 100k: test en verde (umbral <300 s; 230 s incl. creacion de los ficheros).

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
- Arbol anclado estable (Home/volumen), con soporte `..` para subir nivel.
- Boton `Home` en toolbar para volver rapido al directorio base.
- Barra de ruta con autocompletado basico de rutas existentes.

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
