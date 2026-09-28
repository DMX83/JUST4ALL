# JUST4FOLDERS — Roadmap v2 «ADN Directory Opus» (borrador 28-sep)

> Objetivo: convertir JUST4FOLDERS en **el gestor de archivos de referencia de macOS**
> (el «Directory Opus de Mac»): commander nativo + **índice instantáneo propio** + capa IA.
> Este documento fija la matriz de referencia y las fases; no sustituye a `ROADMAP_V1.md`
> (que sigue vigente para el cierre de v1.0).

---

## 0) Qué es Directory Opus (referencia) y qué tomamos de él

Datos de agosto 2026: DOpus 13.25, GPSoftware (Jonathan Potter; nacido en el Amiga en 1990),
**solo Windows x64 (sin ARM)**, ~89 AUD, trial 30–60 días. Es «el gestor para power users»:
configurabilidad extrema sobre un núcleo C++ 64-bit multihilo.

**Los 6 pilares de Opus (lo que hay que igualar o superar):**

1. Doble panel de verdad: single/dual pane, árboles duales, pestañas, navegación independiente.
2. Vista deluxe: flat view, filtros/orden/agrupación instantáneos, tamaños de carpeta,
   color/labels/ratings/tags.
3. Operaciones serias: cola de copias con progreso, **batch rename con regex/macros**, sync,
   duplicados, ZIP/RAR/7z internos, FTP/SSH/MTP. Integración con motores de indexado
   (Windows Search / **Everything**) para búsqueda instantánea.
4. Visor + metadata: preview panel y editor de metadatos.
5. Configurabilidad brutal: 600+ colores/fuentes, toolbars/menús/hotkeys propios,
   **folder formats** (vista por carpeta), temas.
6. Extensibilidad: scripting completo (diálogos y comandos propios), tools externas.

**Lo que NO copiamos (decisión):** FTP/MTP (fuera de foco), plugins propietarios,
sobre-configuración total (mejor «opinión por defecto» + ajustes donde importa), ARM inexistente
(en Mac somos nativos Apple Silicon — ventaja).

---

## 1) Matriz: Opus vs JUST4FOLDERS + JUST4DESK (28-sep)

Leyenda: ✅ hecho · 🟡 en curso/parcial · 🔴 pendiente · ➕ ventaja nuestra

| Pilar Opus | FOLDERS | DESK | Nota |
|---|---|---|---|
| Doble panel + árboles + pestañas | 🟡 (commander en curso) | — | v1.0 |
| Cola de operaciones con progreso | 🟡 (J4FOps listo; UI parcial) | — | motor propio |
| **Búsqueda instantánea** | ✅ **v1.1 (28-sep)**: J4IIndex compartido | ✅ FTS5 | ➕ Opus depende de Everything; nosotros lo tenemos |
| Flat view filtrado en vivo | ✅ **(28-sep, v1.2)** | — | botón «Aplanada» por panel + ⌥⌘F |
| Batch rename (regex/macros) | ✅ **(28-sep, v1.2)** | — | regex + preview en vivo (⇧⌘R) |
| Duplicados | ✅ **(28-sep, v1.2)** | ✅ (hash, G2) | tamaño + SHA-256 streaming |
| Sync / comparar carpetas | 🔴 | — | v2.x, solo si se pide |
| Archivos comprimidos navegables | 🔴 | — | evaluar `unzip`/libarchive (v2.x) |
| Visor / preview | 🟡 QuickLook fácil | ✅ QuickLook | integrar |
| Labels/tags/ratings | ✅ etiquetas Finder **(v1.2)** | 🟡 (etiquetas Finder, G5.1) | color por fila + toggle |
| Colores/grupos/estados | ✅ colores por etiqueta **(v1.2)** | — | grupos/estados pendientes |
| Folder formats / temas | ✅ formats **(28-sep, v2.0)**; temas pendientes | — | aplanada + orden + ocultos por carpeta |
| Toolbars/hotkeys configurables | 🟡 (toolbar fija) | — | v2.0 |
| Scripting/extensibilidad | 🔴 | ➕ **MCP** (agentes) | ➕ Shortcuts/JXA/MCP > scripting propietario |
| Cálculo de tamaños de carpeta | ✅ background **(v1.2)** | — | caché LRU + invalidación watcher |
| Índice propio + IA | ✅ «Ordenar esta carpeta» **(28-sep)** | ➕ semántica + chat | reglas+taxonomía compartidas; IA pendiente |

**El hueco de mercado:** en macOS no hay un Opus. Hay comandantes buenos (Nimble Commander,
ForkLift, Path Finder, Commander One, Marta) pero ninguno con **índice instantáneo propio +
IA + automatización por agentes**. Ese es el moat.

---

## 2) Fases propuestas

### v1.0 — Commander (ya en `ROADMAP_V1.md`, sin cambios)
2 paneles, tabs, bookmarks/sandbox, cola UI (J4FOps), listado eficiente 10k–100k.

### v1.1 — Índice compartido ✅ (28-sep)
- `PACKAGES/J4SHARED`: J4ICore/J4IIndex (DESK) + J4FCore/J4FFileSystem (FOLDERS), sin
  dependencias cruzadas entre apps.
- **FOLDERS busca con J4IIndex** (`IndexedSearchService`): indexado cooperativo por carpeta,
  consultas FTS5 <100 ms, poda de lo desaparecido, refresh por watcher. Sustituye al
  recorrido propio (`PathSearchIndex`) — **bloqueante de búsqueda resuelto**.
- Pendiente de campo: validación con árboles reales enormes + timeout/feedback fino en la UI.

### v1.2 — «Fiel a Opus» (barato y muy visible)
- ✅ **Flat view (28-sep):** botón «Aplanada» por panel (y ⌥⌘F en el menú Navegación) que lista
  de inmediato los ficheros del subárbol desde el índice — nuevo `SearchIndex.listByPathPrefix`
  (recorrido del índice único de `entries.path`: milisegundos con 300k+ entradas), columna
  «Tipo» = ruta relativa, filtro incremental en vivo y refresco silencioso por watcher.
  De paso, motor: `removeEntries` por lotes (antes 5 DELETE por path; el replay de FSEvents
  saturaba el actor y bloqueaba búsquedas) y refresh del watcher coalescido + troceado.
- ✅ **Filtro rápido de panel:** teclear sobre la tabla filtra la lista actual (⌫ borra, Esc
  limpia); el foco vuelve a la tabla tras ir a una ruta (⌘L).
- ✅ **Batch rename (⇧⌘R):** buscar/reemplazar o regex, con previsualización en vivo, detección
  de conflictos (disco + colisiones internas) y ejecución en dos fases vía temporales (permite
  intercambios de nombre sin colisiones); guardado en `J4FOps.BatchRenamer` (plan puro + tests).
- ✅ **Colores/etiquetas:** color del nombre por etiqueta Finder (caché por ruta) y submenú
  «Etiquetas» (7 colores + quitar) con toggle; `FinderTags.TagEntry`/`addColored` reutilizable por DESK.
- ✅ **Tamaños de carpeta en background:** caché LRU + single-flight + invalidación por watcher
  (`J4FOps.FolderSizeCalculator`); la columna Tamaño se rellena sin bloquear el listado.
- ✅ **Duplicados (⇧⌘D):** tamaño + SHA-256 en streaming; grupos con bytes recuperables,
  «seleccionar sobrantes», revelar en Finder y mover a la Papelera con confirmación.

### v2.0 — Diferenciación IA (lo que Opus no tiene)
- ✅ **«Ordenar esta carpeta» (28-sep):** clasificación con el motor compartido de DESK
  (`RulesFilingClassifier` + `FilingPlanner` + `DefaultTaxonomy`) desde el commander (⌥⌘O):
  preview de categoría/nombre/motivo, **mueve** (crea `01_Fiscal`…`99_SinClasificar`, nunca copia
  ni borra), diario JSON y «Deshacer última ordenación» (⌥⌘Z). IA **opcional** (28-sep): con clave
  configurada, «Usar IA para los dudosos» consulta a DeepSeek solo los ficheros que las reglas no
  clasifican (nombre + categorías; validado contra la taxonomía; máx. 40 por lote).
- Búsqueda **semántica** («los papeles del seguro del coche») y chat del archivo en el panel.
- ✅ **Folder formats (28-sep):** cada carpeta recuerda su vista (aplanada, orden por columna y
  ocultos) y se restaura al volver (`J4FOps.FolderFormatStore`, JSON con LRU de 500 carpetas);
  «Olvidar formato de esta carpeta» en el menú contextual. Temas: pendiente.
- **Folder formats** (vista por carpeta) y temas.
- Toolbars/hotkeys configurables + **acciones MCP** (agentes de IA operando el gestor).
- Quick Action de Finder / servicios del sistema (integración con el Finder de macOS).

### v2.x — Solo si el uso lo pide
- Comparar/sync de carpetas · navegar ZIP/7z · rename masivo por plantillas
  (la plantilla `YYYY-MM-DD_Emisor_Tipo.ext` de DESK ya existe).

---

## 3) Lo que se queda fuera a propósito

FTP/SFTP/MTP · plugins binarios · edición de metadatos EXIF a fondo · conversión de formatos
(eso es JUST4CONVERT/JUST4PICT; aquí, integración como herramienta externa).

---

## 4) Decisiones abiertas (para el usuario)

1. ¿FOLDERS + DESK convergen en UNA app (fusión por fases de `v2.0`) o se quedan como suite
   con motores compartidos? (Análisis en curso; ver discusión 28-sep).
2. ¿La búsqueda del commander debe ser del panel (subárbol) o global (todos los roots del índice)?
   Propuesta: ambas — barra del panel = subárbol; `Cmd+F` = global.
3. ¿Flat view persistente por carpeta (folder format) desde v1.2 o diferir a v2?
