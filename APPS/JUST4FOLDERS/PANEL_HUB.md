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

- **F1 — selector + DESK mini básico** ✅ **IMPLEMENTADA (v2.3, 29-sep)**: botones
  «Vista previa | DESK» en la cabecera del panel (persistencia `j4f.previewModule`), omnibox
  sobre el índice global (mismo servicio que ⌘F; 300 resultados, doble clic abre) y bandeja de
  Descargas (14 recientes con antigüedad) con «Ordenar…» (reusa la ventana v2.0 con diario y
  Deshacer), «Abrir en panel» y refresco. Validado en vivo (búsqueda «certificado» → 16
  resultados; ciclo de módulos y persistencia). OJO: el contenido del panel arranca a 44pt del
  borde superior porque la toolbar (fullSizeContentView) tapa los primeros ~38pt.
- **F2 — ciclo de revisión** ✅ **IMPLEMENTADA (v2.3.1, 29-sep)**: cola «POR REVISAR» (dudosos de
  `99_SinClasificar` del último destino de ordenación — persistido en `j4f.lastOrderingDestination`,
  contados con `QuarantineListing` de J4ICore; «Ver en panel» navega el panel activo) +
  **ACTIVIDAD** en vivo (espejo de la barra inferior del commander, con barra de progreso) +
  pulido F1 (Enter abre el primer resultado, Esc limpia el buscador, menús contextuales en
  resultados y bandeja, foco automático al buscador al cambiar de módulo). PENDIENTE del plan F2:
  reglas favoritas por carpeta y arrastrar un documento de un panel al hub para proponer destino.
- **F3 — módulos extra** ✅ **PARCIAL (v2.3.2, 29-sep)**: módulo `PICT` (acciones rápidas sobre la
  selección: convertir a PNG/JPEG y redimensionar 50 % con `sips`, creando ficheros nuevos —
  nunca sobrescribe; «Abrir en JUST4PICT» si está instalada) + **soltar documentos sobre el
  módulo DESK** → propuesta de categoría (reglas + taxonomía compartida) con confirmación y
  movimiento por la cola de trabajos (renombra en colisión; nunca borra) + **destino recordado
  por carpeta** (`j4f.folderDestinations`, se precarga al abrir «Ordenar»). PENDIENTE: reglas
  favoritas más ricas (por extensión, no solo destino) y «mejorar» de PICT (requiere exponer el
  pipeline de JUST4PICT o moverlo a J4SHARED).

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
