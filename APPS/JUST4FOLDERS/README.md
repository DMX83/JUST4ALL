# JUST4FOLDERS (macOS)

App nativa macOS en SwiftUI para analizar y organizar archivos por carpetas de categoria.
La meta v1.0 es evolucionar a arquitectura AppKit-first tipo commander (2 paneles).

## Documentacion relacionada

- Hub principal: `../../README.md`
- Roadmap general: `../../TODO.md`
- Tareas de este modulo: `TODO.md`
- Plan completo v1.0: `ROADMAP_V1.md`
- Roadmap v2 (ADN Directory Opus: flat view, batch rename, IA): `ROADMAP_V2_OPUS.md`
- Checklist motor adaptativo: `TODO.md` (seccion "Motor adaptativo v1.0")

## Requisitos

- macOS 14+
- Xcode 15+

## Ejecutar

```bash
swift run
```

## Build DMG

```bash
./scripts/build_dmg.sh
```

## MVP actual

- Seleccion de carpeta origen y destino.
- Analisis recursivo de archivos no ocultos.
- Resumen por categoria:
  - Imagenes
  - Videos
  - Audios
  - Documentos
  - Comprimidos
  - Otros
- Organizacion por copia en carpeta destino con estructura por categoria.
- Manejo de colisiones de nombre (`archivo-1.ext`, `archivo-2.ext`, ...).
- Barra de progreso durante organizacion.
- Busqueda indexada (**v1.1, 28-sep**): indice FTS5 compartido (`J4IIndex`, ver `PACKAGES/J4SHARED`)
  con indexado cooperativo por carpeta y consultas <100 ms (sustituye al recorrido propio).
- Vista aplanada (**v1.2, 28-sep**): boton «Aplanada» por panel (o ⌥⌘F) que lista al instante
  todos los ficheros del subarbol desde el indice (`listByPathPrefix`: recorrido por ruta, ms con
  300k+ entradas); columna Tipo = ruta relativa, filtro en vivo y refresco silencioso por watcher.
- Filtro rapido (**v1.2**): teclea sobre la tabla para filtrar la lista actual (⌫ borra, Esc limpia).
- Renombrar en lote (**v1.2**, ⇧⌘R): buscar/reemplazar o regex con previsualizacion en vivo,
  deteccion de conflictos y ejecucion en dos fases (permite intercambios de nombre).
- Duplicados (**v1.2**, ⇧⌘D): tamano + SHA-256 en streaming, grupos con bytes recuperables,
  revelar en Finder y mover a la Papelera con confirmacion (nunca borrado permanente).
- Etiquetas Finder (**v1.2**): color del nombre por etiqueta + submenu para poner/quitar los 7 colores.
- Tamanos de carpeta (**v1.2**): calculo en background con cache LRU y refresco al cambiar el contenido.
- Ordenar carpeta (**v2.0**, ⌥⌘O): clasifica los ficheros con las reglas y la taxonomia compartidas
  de JUST4DESK (`01_Fiscal`, `13_Multimedia`…, `99_SinClasificar`), previsualiza y **mueve**
  (nunca copia ni borra); «Deshacer ultima ordenacion» (⌥⌘Z) con diario.
- Folder formats (**v2.0**): cada carpeta recuerda su vista (aplanada, orden, ocultos) y se restaura
  al volver; «Olvidar formato de esta carpeta» en el menu contextual.
- Sidebar con ubicaciones autorizadas, favoritos y recientes.
- Reautorizacion guiada de bookmarks invalidos/stale.
- Deteccion de volumen read-only / NTFS con aviso en UI.
- Entitlements minimos definidos para App Sandbox.
- Listado incremental por lotes para carpetas grandes.
- Cache LRU de metadata (URLResourceValues) para reducir lecturas repetidas.
- Cache de UTType e iconos para reducir recomputo en tablas grandes.
- Operaciones locales base: mkdir, rename, delete a Papelera y delete permanente con confirmacion.
- Cola de jobs inicial (OperationQueue) para Copy/Move con progreso por items.
- Motor v1 inicial con:
  - Copy streaming por bytes.
  - BufferPool global (512MB).
  - Scheduler adaptativo por volumen (chunk/concurrencia heuristica).
  - Preflight de volumen (probe + mount check writable) con fail temprano en RO/NTFS sin escritura.
  - Planificador pre-run con orden: `mkdirs -> BigPhase -> SmallPhase`.
  - Auto-tuning por ventanas de telemetria (2-3s) con ajuste dinamico de workers.
  - BufferSizer adaptativo (big lane 4MB, escala hasta 8MB en SSD estable y reduce ante errores).
  - CopySmall (<=1MB en memoria) y Retry/Fallback con reintentos y cleanup de parciales.

## Notas

- El flujo actual copia archivos (no mueve ni elimina origen).
- No modifica metadata ni renombra por fecha en este MVP.
- El estado actual es bootstrap funcional; la UI definitiva de v1.0 sera AppKit-first.

## Ultimos fixes locales (2026-02-19)

- App fuerza activacion al arrancar para recuperar foco de teclado en prompts.
- Renombrar (toolbar y menu contextual) estabilizado:
  - renombra por URL objetivo capturada (no depende de seleccion post-modal),
  - mismo nombre se trata como no-op sin error.
- Columna izquierda migrada a arbol del directorio activo.
- Variante actual del arbol:
  - anclado estable al Home (o volumen cuando aplica),
  - nodo `..` para subir nivel,
  - conserva expansion/seleccion por panel.
- Toolbar con boton `Home`.
- Barra de ruta con autocompletado basico de rutas.
- Accion explicita para `Info carpeta actual` (toolbar y sidebar).
- Menu contextual ampliado con `Nueva carpeta`.
- Pegado (`Cmd+V` / `Pegar item`) encola job de copia para mostrar progreso y usar motor J4FOps.
- Motor de copia recursiva corregido:
  - copia estable de archivos grandes en arboles,
  - correccion de calculo de rutas relativas (casos `/var` vs `/private/var`).
- Informacion de carpetas separa `Tamano logico` vs `Tamano en disco` (dedup hard links).
