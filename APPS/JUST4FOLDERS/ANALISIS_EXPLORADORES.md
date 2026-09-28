# Análisis comparativo — JUST4FOLDERS vs los mejores exploradores (28-sep)

Objetivo: entender por qué el commander **aún se siente «feo y poco práctico»**, comparando con
los referentes del género, y convertirlo en un plan por olas. Honestidad por delante: el *motor*
(índice FTS5, ops con cola, IA de archivado) está por delante de la *experiencia*.

## 1) Los referentes

| App | Plataforma | Qué define su experiencia |
|---|---|---|
| **Finder** | macOS | Claridad absoluta: **QuickLook (Espacio)**, miniaturas, tags, breadcrumb, estados vacíos, búsqueda siempre-ahí |
| **Directory Opus 13** | Windows | El estándar «pro»: doble panel + árboles + pestañas, **folder formats**, **flat view filtrado**, rename regex, colas de copia, visor, scripting |
| **Total Commander** | Windows | Velocidad de teclado: **F-keys**, historial, branch view (= nuestra aplanada), búsqueda con find files, **todo por teclado** |
| **ForkLift 4** | macOS | Doble panel pulido + **Drop Stack**, preview, sync, FTP/S3 — se *siente* nativo y rápido |
| **Path Finder 11** | macOS | Módulos laterales, drop stack, editor hex, doble panel — potencia con UI densa |
| **Commander One** | macOS | Doble panel + FTP/cloud + proceso, atajos tipo TC |
| **QSpace Pro** | macOS | **Workspaces**, multi-panel (4), reglas de renombrado, integración Finder |
| **Nimble Commander** | macOS | Ligero, teclado puro (mac), doble panel instantáneo |
| **Dolphin** | Linux/KDE | Doble panel + tabs + terminal embebido + preview lateral |
| **Files (Win 11)** | Windows | Tabs, galería, widgets — «moderno» sobre lo básico |
| **yazi / lf (TUI)** | Terminal | Velocidad y preview: referente de *feedback inmediato* |

## 2) Qué hacen bien (patrones que definen «buen explorer»)

1. **Ver los ficheros**: miniaturas reales (Finder/Files) y **preview instantáneo con Espacio**
   (Finder, que Opus/ForkLift también tienen como visor). Trabajar sin abrir apps es *el* gesto.
2. **Mover las cosas**: **drag & drop** internal/external (todos). Copiar/mover con progreso
   visible **en el panel**, no en otra ventana.
3. **Orientarse**: **breadcrumb** clicable + historial con menú (Finder, Files, Opus).
4. **Teclado primero** (TC, Nimble, Opus configurable): F2/F3/F4/F5/F6/F7/F8, type-ahead,
   paletas. Los usuarios diarios *no usan el ratón*.
5. **Formato por carpeta** (Opus): el explorador recuerda cómo quieres ver cada carpeta.
6. **No perder el tiempo**: cola de operaciones, atajos de copia entre paneles, «pegar a la otra
   ventana», deshacer.

## 3) Diagnóstico honesto de JUST4FOLDERS

### Por qué se ve «feo» (percepción)

- **Sin miniaturas**: todo son iconos genéricos de 16 px → sensación de herramienta, no de
  explorador. Finder/Opus enseñan *contenido*.
- **Ritmo visual plano**: filas sin cebra, sin hairlines, mismo peso tipográfico para nombre y
  metadatos; celdas altas con aire irregular.
- **Sin identidad**: toolbar con SF Symbols genéricos, botones de texto, selección azul por
  defecto; el árbol y la sidebar no «se sienten» de la app.
- **Sin estados vacíos ni onboarding**: carpeta vacía = tabla en blanco; descubrimiento de atajos
  = cero.
- **Preview inexistente**: ni panel lateral ni QuickLook; el ojo no descansa en ningún sitio.

### Por qué se siente «poco práctico» (fricción real)

1. **No hay drag & drop** — el gesto nº 1 de cualquier explorador. Sin él, mover un fichero a
   otra carpeta = seleccionar → F6/cola → elegir destino. Fricción altísima.
2. **No hay QuickLook (Espacio)** — para ver un PDF/foto hay que abrir la app externa.
3. **No hay breadcrumb** — la única navegación al padre es ⌘↑ o editar la ruta a mano en ⌘L.
4. **F-keys incompletas** — F5/F6/F7/F8 existen; faltan F2 rename, F3 ver, F4 editar, y no hay
   menú que las enseñe (descubrimiento cero).
5. **Columnas fijas** — no se pueden elegir/quitar/añadir columnas (estándar en todo explorer).
6. **Sin thumbnails ni vista galería** — carpetas de fotos se ven como listas de nombres.
7. **Progreso fuera del panel** — la cola vive en su ventana; el flujo natural es espiarla en la
   barra del panel.
8. **Historial invisible** — back/forward sin pull-down de historial.
9. **Árbol solo en la sidebar global**, no por panel (Opus/TC lo llevan pegado a cada panel).
10. **Pestañas básicas** — sin renombrar, reordenar, duplicar.

### Lo que YA jugamos a favor (no perder de vista)

- Búsqueda instantánea FTS5 propia (Opus depende de Everything en Windows; en macOS nadie más la
  tiene así en un commander nativo).
- **Aplanada + filtro rápido + folder formats** (nivel Opus).
- **Archivado con IA + deshacer** — *nadie* lo tiene (moat).
- Ops con cola propia, duplicados SHA-256 streaming, etiquetas Finder, tamaños en background.

## 4) Plan por olas (impacto percibido / coste)

### Ola 1 — «Parece un explorador de verdad» (visual + gestos básicos)

1. **Drag & drop** (arrastrar a carpetas/otro panel/Finder; recibir de Finder) con cola existente.
2. **QuickLook con Espacio** (+ flechas para navegar el preview; Esc cierra).
3. **Miniaturas de imagen/PDF** en vez de icono (QLThumbnailGenerator + caché LRU 512; fallback
   icono). *Este cambio solo ya transforma la percepción.*
4. **Pulido de lista**: cebra sutil, fila 24 pt, metadatos en gris 11, hairlines, hover suave.
5. **Estado vacío** con mensaje + hint (⌘N nueva carpeta).
6. **Breadcrumb** bajo el header (clic en cada segmento; se sincroniza con ⌘L).

### Ola 2 — «Potencia sin fricción»

7. **Panel de preview lateral** (toggle ⌥⌘P): QuickLook empotrado + metadatos (tipo, tamaño,
   fechas, etiquetas) — estilo Opus/Dolphin.
8. **F-keys completas** F2/F3/F4/F5/F6/F7/F8 + menú «Tecla» que las enseñe.
9. **Columnas configurables** (menú de cabecera estándar) + «ajustar columnas».
10. **Historial con pull-down** en back/forward.
11. **Progreso por operación en la cabecera del panel** (mini-barra con el job activo).
12. **Pestañas**: renombrar (doble clic), duplicar (⌘⇧T), reordenar por arrastre.

### Ola 3 — «ADN propio»

13. **Paleta de comandos ⌘K** (buscar acciones, no solo ficheros).
14. **Árbol por panel** (columna lateral colapsable, como Opus/TC).
15. **Galería/mosaico** para carpetas de fotos + tamaño de miniatura ajustable.
16. **Workspaces** (QSpace-style): conjuntos de paneles/tabs guardados.
17. **Atajos configurables** + export/import.

## 5) Matriz resumida (lo que importa)

| Capacidad | Finder | Opus | TC | ForkLift | QSpace | **J4F** |
|---|---|---|---|---|---|---|
| Doble panel + tabs | ✗/✓ | ✓ | ✓ | ✓ | ✓ | ✅ |
| Drag & drop | ✓ | ✓ | ✓ | ✓ | ✓ | ❌ |
| QuickLook (Espacio) | ✓ | ✓ | ✗ | ✓ | ✓ | ❌ |
| Miniaturas/galería | ✓ | ✓ | ✗ | ✓ | ✓ | ❌ |
| Breadcrumb | ✓ | ✓ | ✓ | ✓ | ✓ | ❌ |
| F-keys completas | ✗ | parcial | ✓ | parcial | parcial | parcial |
| Flat view | ✗ | ✓ | ✓ | ✗ | ✗ | ✅ |
| Folder formats | ✗ | ✓ | parcial | ✗ | ✓ | ✅ |
| Rename regex lote | ✗ | ✓ | ✓ | ✓ | ✓ | ✅ |
| Búsqueda instantánea | ✓ (md) | ✓ (Everything) | ✓ | ✓ | ✓ | ✅ |
| Duplicados | ✗ | ✓ | ✓ | ✗ | ✓ | ✅ |
| Etiquetas Finder | ✓ | ✗ | ✗ | parcial | ✗ | ✅ |
| **Archivado con IA + undo** | ✗ | ✗ | ✗ | ✗ | ✗ | ✅ **solo nosotros** |

## 6) Conclusión

El gap no es de motor: es de **capa de interacción** (drag & drop, QuickLook, breadcrumb, F-keys)
y de **vida visual** (miniaturas, preview, ritmo de lista). La Ola 1 son ~4–6 piezas concretas y
cambia la percepción de la app por completo; la Ola 2 la pone a nivel de uso diario; la Ola 3 la
hace única además de la IA.

Regla de oro del género: *un explorador se siente bueno cuando (a) ves el contenido sin abrirlo,
(b) mueves las cosas sin pensar y (c) todo lo demás está a una tecla.*
