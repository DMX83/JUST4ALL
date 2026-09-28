# Evaluación de diseño — JUST4FOLDERS (28-sep, tras v1.2/v2.0)

Método: revisión de la app en vivo durante la validación de las features v1.2/v2.0 (capturas
en ventana normal y maximizada) + lectura del layout en `CommanderViewController.swift`
(constraints, columnas, cableado de estado). No es una auditoría de accesibilidad formal.

## Fortalezas (mantener)

1. **Patrón consistente de ventanas auxiliares** (Renombrar en lote / Duplicados / Ordenar):
   título claro, tabla de previsualización, resumen numérico, Enter para confirmar / Esc para
   cancelar, y nada destructivo sin confirmación (Papelera con alerta).
2. **Feedback continuo**: barra de estado + contador por panel («N items · aplanada · filtro «x»»).
3. **La columna «Tipo» se reutiliza como ruta relativa en vista aplanada** — información
   contextual útil sin añadir columnas nuevas.
4. **Colores de etiquetas Finder sobre el nombre**: se siente «del sistema», sin widgets extra.
5. **Folder formats sin diálogos**: la app recuerda la vista por carpeta sola (muy Opus).
6. **Atajos disciplinados por familias**: ⌘ navegación · ⇧⌘ operaciones · ⌥⌘ vista, con menú
   contextual espejo.

## Hallazgos priorizados

### P1 · Los paneles no aprovechan el ancho de la ventana
**Evidencia**: al ensanchar la ventana a ~1680 pt quedan >400 pt vacíos a la derecha; los paneles
mantienen ~340/235 pt (misma anchura con la ventana pequeña que máxima).
**Causa probable**: `panelsSplit` no fija prioridades (`setHoldingPriority`) ni constraints de
crecimiento para sus subviews; `NSSplitView` conserva los anchos y el hueco sobra al final.
**Propuesta**: (a) `setHoldingPriority(.defaultLow, forSubviewAt:)` en ambos paneles y
`widthAnchor >= 260` en cada uno; (b) constraint de llenado
(`panelsSplit.widthAnchor == bodySplit.widthAnchor - sidebar - divider`); (c) opcional: «igualar
paneles» (⌘=).

### P1 · Columnas por defecto más anchas que el panel
**Evidencia**: `name 280 + size 100 + modified 140 + type 120 = 640 pt` frente a ~340 pt de panel:
en la práctica solo se ve **Nombre** (capturas: Tamaño/Modificado/Tipo quedan recortados).
**Propuesta**: `name 200` flexible, `size 70` (**alineado a la derecha** — hoy los números van a
la izquierda), `modified 105`, `type 90`; `tableView.columnAutoresizingStyle =
.uniformColumnAutoresizingStyle`.

### P1 · Un único `statusLabel` para los dos paneles (last-writer-wins)
**Evidencia**: «Aplanando /tmp/…» fue sustituido por «Actualizado por watcher…» del otro panel
durante la validación del flat view.
**Propuesta**: prefijar el origen en `onStatus` («IZQ · …» / «DER · …») o un label por panel.

### P2 · Copy inconsistente (tildes y términos)
**Evidencia**: «Tamano», «Arbol», «Anadir ubicacion», «Informacion», «Navegacion», botón «Go»;
contador «items» vs estado «elemento(s)».
**Propuesta**: pasada de copy: tildes correctas, «Ir» en lugar de «Go», unificar «elementos».

### P2 · «aplanada» está triplicada
Título («… · aplanada») + contador («… · aplanada») + checkbox marcado.
**Propuesta**: dejar una sola señal (chip junto al contador); el título limpio.

### P2 · Filtro rápido sin representación visual propia
Lo tecleado solo aparece en contador/estado; en una lista larga no se ve «qué estás filtrando».
**Propuesta**: HUD transitorio sobre la tabla (patrón type-select de Finder/Opus) o pseudo-campo
en el header con el texto y un ✕.

### P2 · Colores de etiqueta vs selección
Con la fila seleccionada (fondo azul) los colores `systemYellow`/`systemOrange` pierden contraste.
**Propuesta**: punto de color a la izquierda del nombre (mantiene contraste y funciona con
VoiceOver) o atenuar el color en selección.

### P2 · El divisor de paneles no persiste
No se usa `setPosition`/delegate: al reabrir, proporción por defecto.
**Propuesta**: guardar la posición en `UserDefaults` al arrastrar (`splitViewDidResizeSubviews`)
y restaurarla; añadir «igualar paneles».

### P3 · Barra superior y toolbar
Toolbar con muchos iconos sin separadores de grupo; título de ventana grande centrado.
**Propuesta**: separadores visuales por grupo; evaluar `.unifiedCompact`.

### P3 · Menú contextual largo (14 ítems)
**Propuesta**: agrupar en «Etiquetas ▸» (ya existe) y «Herramientas ▸» (renombrar lote,
duplicados, ordenar).

### P3 · Ventanas auxiliares vs sheets
Las utility windows permiten multitarea (bien); si el uso diario las abre sobre el panel activo,
un sheet anclado daría más contexto. Mantener salvo feedback.

### P3 · Sidebar del árbol
«Anadir ubicacion» + «Info carpeta actual» ocupan dos líneas grandes; un menú «+» compacto
liberaría altura para el árbol.

### P3 · Jerarquía del header de panel
Título «Panel Izquierdo — carpeta»: la carpeta debería ser protagonista (nombre en negrita, ruta
en secundario) y el contador un dato discreto a la derecha.

## Quick wins — ✅ aplicados (28-sep)

1. ✅ Columnas por defecto (180/65/100/80) + tamaño alineado a la derecha + autoresizing uniforme.
2. ✅ Paneles: `setHoldingPriority(.defaultLow)` ambos + ancho mínimo 220 → estiran con la ventana.
3. ✅ Prefijo de panel en la barra de estado («IZQ · …» / «DER · …»).
4. ✅ Copy: tildes («Árbol», «Añadir ubicación», «Tamaño», «vacío»…), «Ir» en vez de «Go»,
   «elemento(s)» unificado.
5. ✅ Chip única de «aplanada» (fuera del título, solo en el contador).
6. ✅ Divisor persistente vía `autosaveName` en ambos splits (paneles y cuerpo/sidebar).

Validado en vivo con la ventana maximizada: los dos paneles llenan el ancho, columnas visibles
con cifras a la derecha, estado con origen y copy corregido.

*(Fuera de alcance de esta evaluación: temas, iconografía a medida, i18n completa,
accesibilidad formal. Pendientes P2/P3 restantes: HUD del filtro rápido, contraste de etiquetas
en selección, toolbar/menú contextual, jerarquía del header.)*
