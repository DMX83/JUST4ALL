# TODO — JUST4INDEX

Fuente de verdad del trabajo activo. Plan por fases (F0–F6).

## Guardrails (no romper)

- Nunca se borra un archivo: solo se mueve (undo por lote e item siempre disponible).
- Privacidad: a DeepSeek solo texto truncado; sin key → modo solo-reglas; nunca se envían archivos.
- Búsqueda: siempre contra el índice; nunca recorrer el árbol en tiempo de query.
- Colisiones: sufijo `-1`, `-2`… (nunca overwrite).
- El índice debe ser incremental y reparable: si algo se desincroniza, "Reindexar" debe resolverlo.

## F0 — Fundaciones

- [x] Scaffold SPM (`Package.swift`; módulos `J4ICore`/`J4IIndex`/`J4IDocs`/`J4IAI`/`J4IFiling` + ejecutable).
- [x] App shell placeholder (ventana + estado de módulos).
- [x] Script de build DMG con `J4ABuildStamp` + entitlements sandbox.
- [x] Dependencia local a JUST4FOLDERS + library products (reuso de J4FFileSystem/J4FOps).
- [x] Docs base: README/TODO/CHANGELOG/MEMORY/ARCHITECTURE/PRIVACY.
- [x] Skill `.github/skills/just4index/SKILL.md`.
- [x] Validación build: `swift build` verde (toolchain Command Line Tools).
- [ ] Validación tests: `swift test` bloqueado hasta aceptar la licencia de Xcode (acción del usuario, una vez): `sudo xcodebuild -license accept`.

## F1 — Motor de índice (J4IIndex) — completada

- [x] Esquema SQLite (roots/entries/entries_fts/doc_text) + migraciones (`user_version`).
- [x] Actor `SearchIndex` (WAL, lotes, optimize).
- [x] Crawler cooperativo con completitud por root y cancelación.
- [x] Ingesta FSEvents incremental con `eventId` persistido + reconciliación.
- [x] Query API (prefix AND por sub-tokens, ranking bm25, filtros, scope por root).
- [x] Tests: 20 en verde (crawl→query, incremental, diacríticos, filtros, multi-root, watcher FSEvents).
- [x] Perf env-gated 100k (`J4I_RUN_100K_PERF=1`): crawl 6.92 s; queries típicas 0.3–38 ms (peor caso 193 ms).

## F2 — UI Buscador — completada

- [x] Ventana keyboard-first (campo auto-focus, Enter abre, flechas en la lista, acciones abrir/revelar/copiar ruta).
- [x] Lista de resultados con highlight + chips de tipo (Todo/Documentos/Imágenes/Audio/Vídeo/Comprimidos) + scope por carpeta + toggle "solo carpetas".
- [x] Estado/progreso de indexación visible (polling 1 s) + "Reindexar"/"Quitar del índice" por carpeta.
- [x] Debounce (120 ms) + cancelación de queries obsoletas.
- [x] Tests de UI-lógica (highlight/filtros): 6 en verde.
- [ ] Validación visual manual (usuario): `swift run`, añadir carpeta real y probar búsqueda/filtros/acciones.

## F3.0 — Configuración inicial (destino + taxonomía + carpeta de entrada) — completada

- [x] Onboarding de primer arranque: elegir/crear carpeta raíz (sugerencia `~/JUST4INDEX`) y carpeta de entrada (sugerencia `~/Descargas`).
- [x] Generación del esqueleto de taxonomía (12 categorías) con preview, instalación idempotente y detección de conflictos.
- [x] Persistencia (UserDefaults) + indicador en barra de estado + reconfiguración desde el menú «Carpetas».
- [x] La carpeta de organización se indexa automáticamente (buscable al instante).
- [x] Tests `J4ICoreTests` de taxonomía/instalador (5).

## F3 — Ingesta y análisis (J4IDocs) — completada

- [x] Watcher origen (default `~/Descargas`) con estabilidad de fichero + ignore-list + backlog inicial.
- [x] Dedupe por hash (SHA-256) + cache de análisis por hash en el índice.
- [x] Extractores: PDFKit; Vision OCR (escaneados/imágenes); txt/md/csv/rtf; docx básico.
- [x] Regex deterministas (fechas ES, NIF/CIF/NIE, IBAN, importes €).
- [x] Persistencia de texto en índice (`doc_text`) al archivar (toggle UI de contenido: pendiente).

## F4 — Clasificación IA (J4IAI) — completada

- [x] `DeepSeekClient` (URLSession, JSON mode, retry si respuesta vacía, timeout, key por entorno/`.env.secrets`).
- [x] `DeepSeekFilingAdvisor` (taxonomía + profile truncado ≤ 4000 chars → JSON de propuesta).
- [x] `FilingPlanner` + `RulesFilingClassifier` fallback + taxonomía seed (fold sin acentos/prefijos numéricos).
- [x] Cache por hash integrada en el pipeline (no re-analiza ni re-clasifica).
- [ ] Cap diario de llamadas + métricas de uso estimadas (post-MVP).

## F5 — Archivado automático (J4IFiling) — completada

- [x] Ejecución mkdirs + move con colisiones `-1`/`-2` resueltas y sin sobreescritura (executor propio; J4FOps disponible para operaciones masivas futuras).
- [x] Journal persistente (SQLite) + undo por item y "deshacer el último" + historial en panel de Actividad.
- [x] Cuarentena `99_SinClasificar` + "Abrir cuarentena" desde el menú (reclasificación asistida: pendiente).
- [x] Modo simulación + kill switch (pausar/reanudar organización).

## F6 — Hub + release + QA — completada (validación manual pendiente)

- [x] Catálogo hub (`SubAppsCatalog.items`) + assets `Assets/JUST4INDEX/` (placeholder README; imágenes pendientes).
- [x] `release.sh` + `sync_local_dmgs.sh` + `clean_artifacts.sh` (también se añadieron FOLDERS/PICT a la limpieza).
- [x] Workspace (FOLDERS/PICT/INDEX) + docs raíz (README, agent.md, MODULOS_A_CREAR).
- [x] QA: `scripts/qa_smoke.sh` (build+test+checklist); suite completa en verde; hub compila.
- [ ] QA manual del usuario: DMG real (`./scripts/build_dmg.sh`) y flujo end-to-end con documentos reales.

## F6.1 — Observabilidad (registro en vivo) — completada

- [x] `J4Log` en `J4ICore`: niveles + categorías, buffer/stream, archivo rotativo y `os.Logger`
  (subsystem `com.dmx83.just4index`).
- [x] Instrumentación del pipeline completo (índice, ingesta, extracción, IA, archivado, búsquedas).
- [x] Visor «Registro» en la app (⌘L) con filtros, auto-scroll, copiar/revelar/limpiar.
- [x] `scripts/log_watch.sh` + tests `J4LogTests` (7).

## F7 — Reconocimiento por nombre/extensión + Explorador + concurrencia — completada

- [x] Análisis «lite» (hash+nombre+metadatos) cuando no hay texto extraíble: nada queda sin procesar.
- [x] Taxonomía `12_Software`, `13_Multimedia`, `14_Comprimidos` + sincronización idempotente al arrancar.
- [x] Reglas por nombre (software/trading/instaladores) + `classifyByExtension` como último recurso.
- [x] IA por nombre: prompt específico cuando no hay texto.
- [x] Explorador (⌘E) con `children(ofDirectory:)` del índice.
- [x] `FilingPipeline` con concurrencia acotada (4) + prioridad `utility` para hash/OCR.
- [x] Tests nuevos (9) y suite completa en verde.

## F7.1 — Ajustes + menú Ver + explorador con propiedades — completada

- [x] Ventana de Ajustes (⌘,): Organización, Indexado y Acerca de/Diagnóstico (puente por notificaciones).
- [x] Menú Ver con «Abrir explorador» (⌘E) y «Ver registro» (⌘L) visibles con su atajo.
- [x] Explorador: panel de propiedades (ficheros/subcarpetas/tamaño) + selección marcada (carpetas: todas visibles, decisión del usuario; ocultos fuera del índice).
- [x] Ocultos fuera del índice (el watcher los limpia, p. ej. `.DS_Store`).
- [x] Pausa persistente + `SettingsLink` en el menú Carpetas.
- [x] Test de `subtreeStats` y suite en verde.

## F7.2 — Atajos ⌘E/⌘L/⌘, fiables — completada

- [x] Monitor local de `NSEvent` en `J4IAppDelegate` (funciona también sin bundle).
- [x] El menú Ver conserva los atajos visibles; trazas en el registro al usar cada atajo.
- [x] Aclarado: **⌘A = Ajustes** (⌘, también) **siempre** (sin passthrough — el foco del buscador lo interceptaba; apertura con respaldos); explorador ⌘E; botón «Ajustes» en la barra de estado.

## F7.3 — Explorador: selección visible + mensaje claro — completada

- [x] Resaltado propio al seleccionar carpetas/ficheros (un clic marca, doble clic entra/abre).
- [x] Mensaje del panel de ficheros cuando los ficheros están en subcarpetas («N en total»).
- [x] Estructura de carpetas sin cambios (decisión del usuario).

## F7.4 — Mover a la papelera desde el explorador — completada

- [x] Menú contextual + botón en propiedades: «Mover a la papelera» (manual y reversible; el motor automático no borra).
- [x] Índice actualizado al momento + traza en el registro.

## F7.5 — Búsqueda por contenido en la UI — completada

- [x] Toggle «En contenido» en la barra de filtros (persistente en `UserDefaults`) + `includeContent` en las queries.
- [x] Fragmento del texto (snippet FTS5) resaltado en los resultados.
- [x] Traza en el registro («(con contenido)») + test de contenido ampliado (fragmento).

## F7.6 — Revisión asistida de cuarentena — completada

- [x] Ventana «Por revisar» (⌘R): ficheros de `99_SinClasificar` con sugerencia por reglas y destino editable.
- [x] «Mover» con journal (undo) + colisiones sin sobrescribir + índice al momento (texto reutilizado, sin re-OCR).
- [x] `suggestDestination` + `reclassify` + tests (reclasificación con undo y colisión resuelta).

## F7.7 — Orden y selección múltiple en «Por revisar» — completada

- [x] Orden por Extensión (secciones; también Nombre, Fecha, Tamaño) con selector en la barra.
- [x] Selección múltiple (⌘/mayús-clic) + barra: destino común, «Mover seleccionados», quitar selección.
- [x] Tests de ordenación (4) y resumen de lote en la barra de estado.

## F7.8 — Papelera en «Por revisar» — completada

- [x] «Mover a la papelera» para la selección (barra) y por fila (menú contextual); índice al momento.
- [x] Reversible desde el Finder (sin journal: no es un archivado).

## F8.0 — Explorador 2.0 — completada

- [x] Multiselección (clic/⌘/mayús) + acciones en lote: «Mover a…» (journal/undo) y papelera.
- [x] Orden (nombre/tamaño/fecha) y filtro por nombre dentro de cada carpeta.
- [x] Duplicados visibles en propiedades (hash → caché) + «Revelar duplicado».
- [x] Vista previa con la barra espaciadora (QuickLook, navegación con flechas).
- [x] Tests de orden/filtro (3).

## F8.1 — Interfaz más agradable — completada

- [x] Buscador con anillo de foco/sombra; chips con iconos y acento; estado inicial con tarjetas de atajos.
- [x] Barra de estado con iconos + tooltips; menú Carpetas sin borde.
- [x] Hover en listas (resultados/explorador/«Por revisar») + encabezados con iconos; ventana 1020×680.
- [x] `StyleKit.swift` (`hoverHighlight`, `KeycapBadge`).

## F8.2 — Explorador con árbol de carpetas — completada

- [x] Panel izquierdo jerárquico: chevrons, indentación, expandir/contraer todo y carpeta actual resaltada.
- [x] Navegación de un clic (expandir + subcarpetas visibles + ficheros en el centro).
- [x] Reconstrucción del árbol con caché (~8 s) y forzada tras acciones; test de filas visibles.

## F8.3 — Ingesta por unidades (carpetas completas) + permisos — completada

- [x] Backlog de la carpeta de entrada: hijos directos (ficheros **y carpetas**) como unidades.
- [x] Archivado de carpeta completa (perfil de contenido: extensión dominante + muestras); nombre y estructura intactos.
- [x] Cuarentena de carpeta completa cuando no hay señal; journal/undo también para carpetas.
- [x] Reglas nuevas: audiolibro, documental/película/serie/temporada, curso/tutorial, portable.
- [x] Aviso de permisos con «Abrir Ajustes del Sistema…» + «Reintentar»; descripciones TCC en el DMG.
- [x] Tests: unidades del watcher (carpeta del backlog) + carpeta completa (mover/cuarentena/undo) — 93 en total.
- [x] Taxonomía fina + IA de contexto para unidades (F9.0–F9.4 completadas; IA en vivo validada) — ver `MEJORAS.md` y `SKILL_IA.md`.

## F9.0 — Skill interna del clasificador (few-shot + regresión) — completada

- [x] `FilingSkill` (J4ICore): `version`, instrucciones curadas y 12 casos curados (few-shot + regresión).
- [x] Prompt del asesor compuesto desde la skill + contrato JSON + few-shot; contexto «carpeta (unidad completa)».
- [x] «Skill de clasificación vN» en el registro al arrancar; `FilingSkillCasesTests` (3) en verde.
- [x] F9.1 (continuo) … F9.2 taxonomía fina ✅ · F9.3 reevaluar cuarentena ✅ (N2) · F9.4 extensiones técnicas ✅ (skill v4).

## F7.9 — Búsqueda por subcadena (estilo «Everything») — completada

- [x] Columna `name_norm` (migración v3 + rellenado único) y normalización al indexar.
- [x] Pasada «contiene» tras el MATCH por prefijos: «net» encuentra «dotnet-sdk» e «Internet…»; prefijos primero; insensible a acentos.
- [x] Test de índice (subcadena + acentos + orden prefijo-primero).

## F9.2 — Taxonomía fina (Peliculas/Series/Documentales/Audiolibros/Musica/Libros/Cursos) — completada

- [x] `13_Multimedia` + Peliculas/Series/Documentales/Audiolibros/Musica; `06_Educacion/Cursos`; `15_Libros` (epub/mobi).
- [x] Reglas por vocabulario + cotejo sin diacríticos; skill v2 con 14 casos curados.
- [x] Carpetas creadas al arrancar (7 nuevas); casos reales reclasificados; tests (16 top-level + reglas finas).
- [x] F9.3: «reevaluar cuarentena» con la skill actual (N2, completada).

## F9.4 — Catálogo de extensiones técnicas (Redes + código) — completada

- [x] Nueva `12_Software/Redes`: `.rsc` (RouterOS/MikroTik), `.ovpn`, `.pcap`, `.backup`, `.conf/.cfg`.
- [x] Código (`.py`, `.sh`, `.ps1`, `.sql`, `.js`…) → `12_Software/Desarrollo`; `.ts` excluido (colisión con vídeo MPEG-TS).
- [x] Skill v4 (17 casos): familias de extensión + «reason» cita la señal; reglas locales espejo; +1 test (suite 107).
- [x] Casos reales: `111.rsc`, `222.rsc`, `a2.rsc`, `cake.rsc` (eran cuarentena) → reevaluables con ⌘R → `Redes`.

## Ajuste — Carpetas en cuarentena (cáscaras) + sección CARPETAS — completada

- [x] `isEmpty` = sin ficheros en todo el árbol: cáscaras con subcarpetas vacías (`AnyUkit`) se dejan en origen, no van a cuarentena.
- [x] «Por revisar»: sección «CARPETAS (N)» propia con resumen de contenido; sugerencia con extensión dominante perfilada sin leer texto.
- [x] Tests: `FolderProfilerTests` (2) + cáscara en coordinador (1) + agrupación (1); suite 117.

## F10.0 — Desglose de carpetas-cajón (la IA decide entera vs por ficheros) — completada

- [x] Advisor: campo `mode` («folder»/«split») + skill v5 (coherencia: nombres relacionados/portable → entera; cajón dispar → split).
- [x] Pipeline: desglose automático con barandillas (confianza ≥0,6 · ≤500 ficheros · profundidad ≤4); lote único de undo; cáscara queda en origen.
- [x] «Por revisar»: «Desglosar y organizar por ficheros…» (contextual, con confirmación) + hint «IA: cajón heterogéneo → desglosar»; estrategia persistida en `AISuggestionStore`.
- [x] Tests: `mode` (2) + desglose E2E (1) + estrategia en caché (1); suite 121.

## N4 — Segunda carpeta de entrada (~/Downloads) — completada

- [x] Configuración con varias entradas (`sourcePaths`; migración de la clave antigua) + watchers por carpeta (idempotentes, sonda TCC por carpeta).
- [x] Ajustes → Organización: lista con «Quitar» + altas («Añadir…», «Usar ~/Descargas», «Usar ~/Downloads»).
- [x] Activadas `~/Descargas` + `~/Downloads` (385 unidades, 28 GB); verificado en registro sin errores; duplicados por hash se quedan en origen.
- [x] Tests `FilingConfigurationTests` (2); suite 123.

## F12.0 — Tokens reales + conocimiento local aprendido — completada

- [x] Tokens reales (usage de la API) en `AIControlCenter` + Ajustes → IA + registro de arranque.
- [x] `LocalKnowledgeStore` + `KnowledgeFeatures` (extensiones y palabras de carpeta; sin ruido).
- [x] Consulta sin IA (fuente `knowledge`) + aprendizaje de IA y de correcciones; promoción conservadora; los cajones `split` no enseñan.
- [x] Tests: tokens (1) + store (6) + integración (2); suite 132.

## F13.0 — Buscador de destino con autocompletado («Mover a…») — completada

- [x] `DestinationChooser` (búsqueda al momento; padre + subitems; sin acentos; Enter/Esc) en Explorador (toolbar/contextual/panel) y «Por revisar» (fila/selección).
- [x] Tests `DestinationSearchTests` (5); suite 137.

## F14.0 — Categorías al vuelo + cap escribible — completada

- [x] «Crear categoría «X»» en el buscador de destino (Explorador y ⌘R) cuando no hay coincidencias; creación al mover; nombre saneado.
- [x] `TaxonomyInventory` en disco (≤2 niveles, sin cuarentena): UI + planificador + categorías permitidas de la IA.
- [x] Ajustes → IA: cap diario escribible (0–5000) además del stepper.
- [x] Tests: `TaxonomyInventoryTests` (3) + saneado (1); suite 141.

## F15.0 — Sistema de diseño + rediseño de la interfaz — completada

- [x] `DesignKit.swift`: marca, tokens (espaciado/radios/colores) y componentes (chips, tarjetas,
  cabeceras, píldoras de estado, estados vacíos, botones fantasma, separadores).
- [x] Buscador: marca + anillo de foco, chips sin cortes (carrusel con fundido), toggles-chip,
  menú de carpeta con el mismo lenguaje, estado inicial con datos y barra de estado segmentada.
- [x] Explorador: cabeceras en versalitas, selección visible, filtro integrado, propiedades en
  tarjeta, toolbar con acción primaria.
- [x] Por revisar: toolbar adaptable sin truncados (menú «⋯»), vacío con placa de éxito, barra de
  selección en índigo suave.
- [x] Ajustes: tarjetas J4I en las cuatro pestañas; cap con botones −/+50; Acerca de con marca y
  atajos.
- [x] Títulos de ventana limpios + `tint` de marca; QA visual claro/oscuro de las 4 ventanas.

## F15.x — Siguientes de diseño (candidatos)

- [ ] Icono de app propio (Dock/DMG) y pantalla «Acerca de» con créditos.
- [ ] Densidad configurable de listas (compacta/cómoda).
- [ ] Animaciones de transición de paneles + respeto a «Reducir movimiento».
- [ ] Revisión de accesibilidad (VoiceOver en listas/árbol, contraste AA) y tamaño de texto.

## N1 — Control de la IA (cap, contadores, interruptor) — completada

- [x] `AIControlCenter` (J4IAI): interruptor, cap diario (200 por defecto) y contadores hoy/total con reinicio diario.
- [x] Gates en el pipeline (ficheros y carpetas) + línea «Control IA:…» al arrancar.
- [x] Ajustes → pestaña «IA»: interruptor, límite (stepper), uso y versión de skill; puente por NotificationCenter.
- [x] Tests `AIControlCenterTests` (3).

## N2 — F9.3: reevaluar cuarentena con la IA — completada

- [x] «Reevaluar con IA» en ⌘R (selección o todo) con propuesta fresca por elemento (skill actual).
- [x] La cuarentena lista también carpetas (sugerencia por nombre; IA la reevalúa completa).
- [x] `FilingCoordinator.proposeDestination(for:)` (sin mover) + tests `FilingSuggestTests` (3).
- [x] Ajuste (24-sep): propuesta IA conservada tras mover + «Mover sugeridos (N)» con confirmación + caché persistente `AISuggestionStore` (reabrir sin gastar tokens; «Olvidar propuesta de la IA» para re-consultar).

## N3 — «Sugerir destino (IA)» en el Explorador — completada

- [x] Botón «Sugerir con IA» (selección) + menú contextual por fila.
- [x] Hoja con propuestas (categoría · fuente · confianza) y «Aplicar sugerencias» (reclassify con journal/undo).

## Referencias

- Propuestas de mejora priorizadas (candidatas, sin aprobar): `MEJORAS.md`
- Arquitectura: `ARCHITECTURE.md` · Memoria maestra: `MEMORY.md` · Privacidad: `PRIVACY.md`
