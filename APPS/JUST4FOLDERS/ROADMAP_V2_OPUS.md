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
| Batch rename (regex/macros) | 🔴 | — | propuesto v1.2 |
| Duplicados | 🔴 | ✅ (hash, G2) | compartible |
| Sync / comparar carpetas | 🔴 | — | v2.x, solo si se pide |
| Archivos comprimidos navegables | 🔴 | — | evaluar `unzip`/libarchive (v2.x) |
| Visor / preview | 🟡 QuickLook fácil | ✅ QuickLook | integrar |
| Labels/tags/ratings | 🔴 | 🟡 (etiquetas Finder, G5.1) | alinear |
| Colores/grupos/estados | 🔴 | — | v1.2 (filtros + colores) |
| Folder formats / temas | 🔴 | — | v2.0 (guardar estado por carpeta) |
| Toolbars/hotkeys configurables | 🟡 (toolbar fija) | — | v2.0 |
| Scripting/extensibilidad | 🔴 | ➕ **MCP** (agentes) | ➕ Shortcuts/JXA/MCP > scripting propietario |
| Cálculo de tamaños de carpeta | 🟡 (info) | — | v1.2 (background) |
| Índice propio + IA | — | ➕ semántica + chat | ➕ fusible: «ordena esta carpeta» |

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
- **Filtro rápido de panel** (teclas: escribir filtra la lista actual; Esc limpia).
- **Batch rename** con regex + previsualización (debajo: motor de rename de J4FOps).
- **Colores/etiquetas de estado** por fila (reusar etiquetas Finder de J4ICore: `FinderTags`).
- **Tamaños de carpeta** en background (cola J4FOps, cache LRU).
- Duplicados (portar el detector hash de DESK G2 al commander).

### v2.0 — Diferenciación IA (lo que Opus no tiene)
- «**Ordenar esta carpeta**»: la taxonomía de DESK (journal + undo) aplicada desde el commander
  (mover, no copiar; reversible; `sin clasificar` para dudas).
- Búsqueda **semántica** («los papeles del seguro del coche») y chat del archivo en el panel.
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
