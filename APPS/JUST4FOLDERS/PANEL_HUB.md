# Panel Hub — módulos intercambiables en el panel lateral

> Propuesta (29-sep, idea del usuario): que en el panel derecho (hoy vista previa) se puedan ver
> otros módulos con **botones de selección** — en particular una **mini-versión de JUST4DESK**
> para organizar documentos sin salir de JUST4FOLDERS — y a futuro JUST4PICT u otros.

## Concepto

El panel derecho (el del preview) se convierte en un **hub**: una fila de botones en su cabecera
(estilo segmented, pequeño) que cambia su contenido:

`Vista previa` · `DESK` · (futuro: `PICT`, `Actividad`, `Notas`…)

- El hub vive **dentro** del panel: no cambia el split ni la divisoria arrastrable (v2.2d).
- Selección recordada (`j4f.previewModule`), por defecto «Vista previa».
- ⌥⌘P sigue ocultando/mostrando el panel completo.

## Por qué es viable (motores ya existentes)

- JUST4DESK comparte motores con JUST4FOLDERS vía `PACKAGES/J4SHARED`: **`J4ICore`** (taxonomía,
  `FilingPlanner`, plantilla/saneado de nombres) y **`J4IIndex`** (SQLite FTS5 + crawler + FSEvents).
- JUST4FOLDERS ya tiene las piezas de producto equivalentes:
  - **Búsqueda global ⌘F** → `IndexedSearchService` + `J4IIndex` (índice propio en
    `~/Library/Application Support/JUST4FOLDERS/search-index.sqlite`; prohibido recorrer árbol en query).
  - **«Ordenar esta carpeta» (v2.0)** → `J4FOps.FolderOrderer` (plan puro + apply), journal de undo
    (`OrderingJournalStore`) y propuesta con **IA DeepSeek opcional** (`AIFilingAdvice`, solo dudosos).
- ⇒ El «mini DESK» es en gran parte **re-empaquetar** lo existente en UI compacta, no reescribir motores.

## Módulo DESK mini (fase 1)

Tres zonas apiladas en el panel (~≥220pt de ancho útil):

1. **Omnibox** — buscar en el índice al teclear (reusa el flujo global; resultados = filas con
   icono + ruta relativa; Enter abre en el panel activo; sin recorrer carpetas).
2. **Bandeja** — carpeta(s) vigiladas (p. ej. `~/Descargas`): últimos documentos con antigüedad;
   botón **«Ordenar»** por fila o en bloque → plan `FolderOrderer` → confirmación con destinos →
   apply con journal y **Deshacer** visible (reusa la ventana de Ordenar en modo compacto).
3. **Actividad / estado** — trabajos en curso (`JobQueueService`) y avisos de volumen, en formato
   lista; reusa la misma fuente que la pila inferior del commander.

### Guardrails de DESK que se respetan (no romper)

- **Nunca borrar**: archivar solo mueve; undo por lote e item siempre disponible.
- Dudosos → `99_SinClasificar` («por revisar»), nunca forzar.
- **Privacidad IA**: a DeepSeek solo texto truncado (≤4000 chars) + metadatos mínimos; nunca
  archivos; sin key → modo solo-reglas.
- Estabilidad de fichero antes de procesar (size+mtime estables; ignorar `.part/.crdownload/tmp/ocultos`).

## Fases

- **F1 — selector + DESK mini básico**: botones en el panel, persistencia, omnibox + bandeja
  (Descargas) + «Ordenar» con undo reutilizado. *Sin IA nueva.*
- **F2 — ciclo de revisión**: cola «sin clasificar / por revisar», reglas favoritas por carpeta,
  actividad en vivo con progreso, arrastrar un documento de un panel al hub para proponer destino.
- **F3 — módulos extra**: `PICT` (acciones rápidas sobre la imagen seleccionada: mejorar/convertir/
  redimensionar — requiere exponer el pipeline de JUST4PICT o mover parte a J4SHARED), `Notas` /
  `Workspaces`.

## Riesgos / notas

- El panel es estrecho: UI densa, tipografías caption/micro (J4FDesign), nada de formularios grandes.
- Reusar `IndexedSearchService` (ya probado) en vez de crear servicio nuevo; cuidado con el actor
  `SearchIndex` (llamadas `await`; no bloquear el hilo).
- El módulo no debe interferir con el drag de la divisoria ni con ⌥⌘P.
- `J4IFiling` (journal profesional de DESK) vive en `APPS/JUST4DESK/Sources`; para F1 basta el
  journal de FOLDERS (`OrderingJournalStore`). Si F2 necesita paridad total, evaluar mover J4IFiling
  a `J4SHARED`.

## Métrica de éxito (F1)

Flujo real completo sin abrir JUST4DESK: «llega un PDF a Descargas → lo veo en el panel → 2 clics
para archivarlo en la taxonomía → Deshacer funciona».

## Preguntas abiertas

- Módulo por defecto al arrancar: ¿Vista previa (conservador) o DESK?
- Bandeja: ¿solo `~/Descargas` o lista configurable de carpetas vigiladas?
- ¿Los botones del hub también en la toolbar del commander (acceso rápido)?
