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

### Ola 1 — «Parece un explorador de verdad» (visual + gestos básicos) — ✅ aplicada (28-sep)

1. ✅ **Drag & drop** (arrastrar a carpetas/otro panel/Finder; recibir de Finder): interior mueve
   (⌥ copia), desde fuera copia (⌘ mueve), con la cola existente. *Gesto pendiente de prueba manual.*
2. ✅ **QuickLook con Espacio** (+ ↑/↓ para navegar el preview; Espacio/Esc cierran; se refresca
   al cambiar la selección).
3. ✅ **Miniaturas de imagen/PDF/vídeo** en la lista (QLThumbnailGenerator + caché LRU 512,
   generación perezosa y recarga de celda al llegar).
4. ✅ **Pulido de lista**: estilo `.inset`, fila 22 pt, sin rayas en filas vacías, metadatos
   discretos. (Hover por fila: pendiente.)
5. ✅ **Estado vacío** («Carpeta vacía · ⌘N» / «Sin coincidencias · Esc»).
6. ✅ **Breadcrumb clicable** (Macintosh HD › … › carpeta actual, último segmento en negrita).

### Ola 2 — «Potencia sin fricción» — ✅ aplicada (28-sep)

7. ✅ **Panel de preview lateral** (⌥⌘P, persistente): QLPreviewView + metadatos (tipo, tamaño,
   fecha, etiquetas); sigue a la selección del panel activo.
8. ✅ **F-keys completas**: F2 renombrar · F3 QuickLook · F4 abrir · F5 copiar · F6 mover ·
   F7 nueva carpeta · F8 borrar.
9. ✅ **Columnas configurables**: menú en la cabecera (mostrar/ocultar cada columna + «Ajustar
   columnas») con visibilidad recordada por carpeta (folder formats).
10. ✅ **Historial con pull-down**: clic derecho en Atrás/Adelante abre la lista y salta a
    cualquier entrada (rebobinado correcto).
11. ✅ **Progreso en la ventana**: barra + «TIPO n/m (%)» encima del estado en copias/movimientos.
12. ✅ **Pestañas completas**: duplicar (⌥⌘T), renombrar (⌥⌘R, nombre personalizado) y mover a
    izquierda/derecha (⌥⌘←/→).

Validado en vivo: preview lateral con foto real, pestaña duplicada y toolbar nueva. *Hover por
fila: pendiente (cosmético).*

### Ola 3 — «ADN propio» — ✅ completada (28-sep)

13. ✅ **Paleta de comandos ⌘K**: busca acciones (título + teclas), ↑/↓ navegan, Enter ejecuta,
    Esc cierra; 23 comandos de toda la app.
14. ✅ **Árbol por panel** (⌥⌘E, columna lateral colapsable por panel, como Opus/TC): raíz en
    Home, expande solo lo necesario y resalta la ruta activa; doble clic navega y se recuerda
    entre sesiones. Validado en vivo.
15. ✅ **Galería/mosaico** (⌥⌘G, recordada por carpeta): rejilla de miniaturas grandes (128 px)
    con nombre debajo; doble clic abre; convive con orden/filtro/aplanada y con la vista previa
    lateral. Tamaño de miniatura ajustable: ✅ S/M/L (cíclico desde la paleta, recordado).
16. ✅ **Workspaces** (QSpace-style): guarda pestañas/activo/preview de ambos paneles con nombre;
    restaurar desde el menú, el contextual (Workspaces ▸) o la paleta.
17. ✅ **Atajos configurables**: editor (⌥⌘K) con tabla de los comandos del monitor, reasignación
    («Cambiar…» y pulsa la combinación), restablecer y apertura del JSON (`shortcuts.json`) en el
    Finder. Los menús SwiftUI conservan sus teclas. Validado en vivo.
18. ✅ **Búsqueda semántica (IA)**: con ⌥⌘B, la IA expande la consulta en términos («los papeles
    del seguro del coche» → seguro · coche · papeles, validado contra la API real) y se unen los
    resultados del índice sin duplicados; sin clave sigue siendo literal.

Extra ✅: **hover por fila** sutil (no se dibuja sobre la fila seleccionada).

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
