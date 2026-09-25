# MEJORAS — JUST4DESK (mapa priorizado)

> Propuestas de mejora priorizadas (candidatas, **sin aprobar**). Fecha: 2026-09-24.
> Origen: análisis solicitado por el usuario («cómo mejorar el proyecto»), verificado contra el código.
> Estado de referencia: F8.3 completada · 93 tests (92 en verde + 1 skip opt-in).
> Cuando una propuesta se apruebe, pasa a fase (F8+) en `TODO.md`.

## Objetivo maestro (usuario, 2026-09-24): limpiar Descargas

> «Mi objetivo final es limpiar la carpeta de descargas (muchos ficheros, la mayoría misceláneos) y
> moverla organizadamente a otro directorio, en este caso `~/JUST4DESK`. Hay que tener en cuenta las
> extensiones (si son vídeos → su carpeta) y la IA apoya con criterio: un vídeo que es una película
> debe ir a «Peliculas», no a «MEDIAS» misceláneo; según lo que analice (pdf, docx, txt, jpeg…) la IA
> sugiere carpetas de destino por contexto: trabajo, empresa, ocio…»

- **✅ F8.3 (2026-09-24) — ingesta por unidades**: la entrada ya procesa cada hijo directo como unidad
  (fichero **o carpeta completa**); antes solo se miraba el primer nivel y las carpetas se ignoraban
  (caso real: 63 subdirectorios invisibles). Carpeta = unidad: se mueve entera, sin descomponer ni
  renombrar (apps portables/estructuras intactas), clasificada por perfil de contenido
  (`FolderProfiler`: extensión dominante + muestras de nombres/texto) con reglas nuevas
  (audiolibro, documental/película/serie, curso/tutorial, portable).
- **✅ Pendiente 1 — Taxonomía fina (F9.2, 24-sep)**: `13_Multimedia` → `Peliculas`, `Series`,
  `Documentales`, `Audiolibros`, `Musica`; `06_Educacion/Cursos`; `15_Libros`. Los contextos
  trabajo/empresa/ocio quedan para la capa IA (pendiente 2).
- **Pendiente 2 — IA semántica para unidades**: ampliar el prompt del asesor (nombre + resumen de
  contenido + extensión dominante) para decidir «Películas» vs «multimedia varios»; requiere
  `DEEPSEEK_API_KEY` (hoy sin clave: solo reglas locales). → diseño: `SKILL_IA.md`.
- **Pendiente 3 — Repaso con el usuario** de los resultados reales de `~/Descargas` para ajustar
  reglas/taxonomía (lo dudoso cae en `99_SinClasificar` y se revisa con ⌘R).

## Hallazgos verificados (ya funciona, pero está apagado)

1. **Búsqueda por contenido implementada… y desactivada.**
   - El índice ya tiene `doc_text_fts` con bm25 y el merge en `search()`:
     `Sources/J4IIndex/SearchIndex.swift` (`queryContent`, flag `includeContent`, ~líneas 240–302).
   - La fila de resultados ya sabe pintar el chip «contenido»:
     `Sources/JUST4DESK/SearchResultRow.swift` (~línea 23, `matchedContent`).
   - Pero la UI no lo activa: `Sources/JUST4DESK/SearchViewModel.swift` (~línea 477) construye
     `IndexSearchRequest` sin `includeContent` (default `false` en `Sources/J4IIndex/IndexModels.swift`,
     línea 92). No hay toggle en Ajustes.
   - **Propuesta**: toggle «Buscar en contenido» + activar el flag + snippet resaltado de la coincidencia.
     Cubre lo archivado (donde ya se guarda texto); extensible después al resto del índice.
     → **✅ implementado en F7.5.**

2. **La cuarentena es un callejón sin salida.**
   - Solo existe «Abrir cuarentena» (abre la carpeta en Finder): `Sources/JUST4DESK/ContentView.swift`
     (~línea 268).
   - **Propuesta**: cola de reclasificación asistida en el explorador (sugerencia por reglas/IA + mover
     en un clic, con undo del journal). Era un pendiente de F5.
     → **✅ implementado en F7.6** (ventana propia «Por revisar», ⌘R).

## Deuda a cerrar (antes que features nuevas)

- QA manual + DMG real (`./scripts/build_dmg.sh` existe, la release no está validada); firma/notarización
  cuando haya cuenta Apple (mismo pendiente que JUST4PICT).
- Cap diario + métricas de uso de IA (post-MVP de F4).

## Mejoras propuestas (por prioridad)

### 1. Encender la búsqueda por contenido — horas — ✅ implementada (F7.5)

Toggle «En contenido» + `includeContent: true` + snippets del texto. Impacto máximo: diferencia frente
a un simple gestor de ficheros.

**Estado: ✅ hecha en F7.5** — toggle en la barra de filtros (persistente), fragmento resaltado en los
resultados y test de índice ampliado.

### 2. Cuarentena como cola asistida — 1–2 días — ✅ implementada (F7.6)

Vista «Por revisar» con los ficheros de `99_SinClasificar`, sugerencia de destino (reglas → IA) y mover
en un clic; queda en el journal (undo).

**Estado: ✅ hecha en F7.6** — sugerencia por reglas locales (la sugerencia IA queda como mejora
futura), `Picker` de destino, mover con journal/undo, índice al momento y colisión `-1` sin
sobrescribir. **F7.7** añade orden por extensión (con secciones) y selección múltiple con destino
común; **F7.8**, papelera para la selección.

### 3. Explorador 2.0 — 2–3 días — ✅ implementada (F8.0)

- Multiselección + acciones en lote (papelera/mover).
- QuickLook con barra espaciadora y preview en el panel.
- Orden/filtro por columnas (nombre/tamaño/fecha).
- Duplicados visibles: el pipeline ya detecta «ya archivado en X»; mostrarlo en propiedades.

**Estado: ✅ hecha en F8.0** — multiselección con ⌘/mayús-clic y acciones en lote («Mover a…» con
journal/undo y papelera, desde barra/propiedades/menú contextual); orden (nombre/tamaño/fecha) +
filtro por nombre; duplicados visibles con «Revelar duplicado»; vista previa con la barra espaciadora
sobre los seleccionados. **F8.2** rediseña el panel izquierdo como **árbol de carpetas** (navegación
de un clic, expandir/contraer).

### 4. Reglas aprendidas y editables — 2–3 días

- Registrar correcciones (undo, movimientos manuales) y proponer reglas
  («*.ctrader → 02_Banca/Inversiones»).
- Editor de reglas en Ajustes (hoy viven en código: `Sources/J4ICore/RulesFilingClassifier.swift`).
- Es la palanca más barata para subir el acierto sin IA.
- → **Diseño detallado: `SKILL_IA.md`** — decisión del usuario (24-sep): la skill es **interna y
  versionada con la app** (sin editor para el usuario); se afina con **casos curados + tests de
  regresión** (F9.0 ✅ · F9.2 ✅ · F9.3 ✅ · F9.4 ✅ extensiones técnicas).

### 5. Presencia en macOS — 1–2 días

- MenuBarExtra (estado, pausa, buscar) + atajo global ⌥Espacio.
- App Intent / Acción rápida «Archivar ahora» para Atajos/Finder.

### 6. Plataforma — continuo

- CI (build + tests por push; hoy la validación es manual con `scripts/qa_smoke.sh`).
- Varias carpetas de entrada (hoy una sola).
- xlsx (docx ya va por unzip del sistema).
- Panel de estadísticas (archivados/día, % cuarentena, % reglas vs IA) — datos ya en `ops_journal`/J4Log.

## Orden recomendado

1. QA + DMG firmado → 2. Búsqueda por contenido ON (✅ F7.5) → 3. Cuarentena asistida (✅ F7.6) →
4. Explorador 2.0 (✅ F8.0) → 5. Reglas aprendidas → 6. MenuBar/global, CI, stats.

*Actualizado 2026-09-24 tras F8.3 (ingesta por unidades ✅): la prioridad declarada por el usuario
pasa a ser la del bloque «Objetivo maestro»: **taxonomía fina + IA de contexto para las unidades de
Descargas**, antes de «Reglas aprendidas».*

*Actualizado 2026-09-24 (tarde): F7.9/F9.0/F9.2 ✅ y la **IA en vivo** (clave DeepSeek, validada
end-to-end). «Reglas aprendidas» quedó resuelto como **skill interna versionada** (`SKILL_IA.md`).
La lista vigente es **«Nuevas prioridades»**. Marca: N1–N9.

*Actualizado 2026-09-24 (noche): **F9.4 — catálogo de extensiones técnicas** ✅ (skill v4: `.rsc`/red →
`12_Software/Redes`; código → `12_Software/Desarrollo`; los 4 `.rsc` reales de cuarentena quedan
reevaluables con ⌘R).*

*Actualizado 2026-09-24 (noche, 2): **F10.0 — desglose de cajones** ✅ (la IA decide `folder` vs
`split` con el campo `mode`; acción manual «Desglosar y organizar por ficheros…» en ⌘R; barandillas:
confianza ≥0,6 · ≤500 ficheros · profundidad ≤4 · lote único de undo).*

*Actualizado 2026-09-25: **N4 — segunda carpeta de entrada** ✅ («~/Descargas» + «~/Downloads»;
un watcher por carpeta y pipeline compartida; activación verificada con 385 unidades).*

*Actualizado 2026-09-25 (2): **F12.0** ✅ — tokens reales por llamada (Ajustes → IA) y **conocimiento
local** que aprende de la IA y de tus correcciones (promoción ≥3 · ≥75 % · conf media ≥0,7) para
clasificar sin gastar tokens lo ya aprendido.**

## Nuevas prioridades (revisión 2026-09-24 · con la IA en vivo)

> Lo que falta ya no es «más clasificador», sino **control, cierre del ciclo y presencia**.

### N1. Control y visibilidad de la IA — 1 día
- ✅ **Implementado (24-sep)**: `AIControlCenter` (interruptor + cap diario 200 + contadores hoy/total)
  con pestaña «IA» en Ajustes; gates en el pipeline con aviso al alcanzar el cap.
- Contador de llamadas IA (hoy/total) en Ajustes/barra + **cap diario configurable** (al alcanzarlo:
  solo reglas y aviso en el registro); interruptor «IA activada» sin borrar la clave.
- *Motivo*: cada fichero/unidad consume una llamada; el usuario debe ver y limitar el gasto
  (deuda ya anotada: «cap diario + métricas de uso de IA»).

### N2. F9.3 — Reevaluar la cuarentena con la skill actual — 1–2 días
- ✅ **Implementado (24-sep)**: «Reevaluar con IA» en ⌘R (selección o todo; propuesta fresca con la
  skill, aplicable con «Mover»); la cuarentena ya incluye carpetas.
- ✅ Ajuste (24-sep, uso real): propuestas conservadas tras mover · «Mover sugeridos (N)» con
  confirmación · **caché persistente** (`AISuggestionStore`) — reabrir la ventana o la app no vuelve
  a gastar tokens por lo ya consultado.
- En «Por revisar» (⌘R): **«Reevaluar con IA»** para lo seleccionado (y opción «todo»): re-analiza
  con la skill vN y propone destino; aprobar en lote con journal/undo y colisiones resueltas.
- *Motivo*: la cuarentena real (~124 ficheros) se puede resolver ya; cierra el ciclo del objetivo
  maestro de Descargas.

### N3. «Sugerir destino (IA)» en el Explorador — 0,5–1 día
- ✅ **Implementado (24-sep)**: botón + menú contextual → hoja de propuestas → «Aplicar sugerencias»
  (journal/undo; los que apuntan a cuarentena se omiten).
- En el menú contextual de la selección: pedir propuesta al asesor (nombre + resumen/contenido) y
  aplicarla con «Mover a…» (journal/undo). Válido también para carpetas.
- *Motivo*: corrige misfiles antiguos (p. ej. un vídeo-curso en Videos) y **alimenta casos curados**
  con cada corrección (nuestro ciclo de afinado de la skill).

### N4. Varias carpetas de entrada — 1 día
- Lista de carpetas vigiladas (p. ej. `~/Descargas` + `~/Downloads`), misma semántica de unidades.
- *Motivo*: el objetivo declarado incluye la otra carpeta real del usuario (~385 elementos intactos).

### N5. Presencia en macOS — 1–2 días
- MenuBarExtra (estado, pausa, buscar) + atajo global ⌥Espacio + **notificaciones** («X archivado
  en Y»), que ahora tienen sentido con la IA viva. (Punto 5 del mapa original; sigue pendiente.)

### N6. Empaquetado real (DMG + sandbox) — 1–2 días
- `build_dmg.sh` end-to-end: **security-scoped bookmarks** para las carpetas elegidas (el sandbox no
  cubre carpetas custom como `~/Descargas`), resolución de la clave/red documentada, firma cuando
  haya cuenta Apple.
- *Motivo*: hoy solo se usa en dev vía `scripts/run.sh`; esto es el paso a «app de verdad».

### N7. Panel de estadísticas y afinado — 1 día
- Archivados/día, % IA vs reglas vs cuarentena, llamadas IA, % undo; datos ya en `ops_journal`/`J4Log`.
- *Motivo*: con N1, permite decidir cuándo afinar la skill y cuánto cuesta; cierra el ciclo
  «afinar nosotros».

### N8. Menores de uso diario — 1 día (lote)
- ⌘Z global = deshacer el último archivado (el journal ya lo soporta).
- Operadores de búsqueda: `ext:pdf`, `tipo:vídeo`, `fecha:2026-09`.
- xlsx en extracción (docx ya va) y QuickLook también en resultados de búsqueda.

### N9. CI — 0,5 día
- Build + tests por push (hoy validación manual con `scripts/qa_smoke.sh`).

*Orden sugerido: **N1 → N2 → N3** (IA bajo control y ciclo cerrado) → N4/N6 según prioridad →
N5 → N7/N8/N9.*

## Referencias

- Estado y decisiones: `MEMORY.md` · Fases: `TODO.md` · Cambios: `CHANGELOG.md` · Arquitectura: `ARCHITECTURE.md`.
