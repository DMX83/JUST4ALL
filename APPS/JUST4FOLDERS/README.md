# JUST4FOLDERS (macOS)

App nativa macOS en SwiftUI para analizar y organizar archivos por carpetas de categoria.
La meta v1.0 es evolucionar a arquitectura AppKit-first tipo commander (2 paneles).

## Documentacion relacionada

- Hub principal: `../../README.md`
- Roadmap general: `../../TODO.md`
- Tareas de este modulo: `TODO.md`
- Plan completo v1.0: `ROADMAP_V1.md`
- Roadmap v2 (ADN Directory Opus: flat view, batch rename, IA): `ROADMAP_V2_OPUS.md`
- Propuesta Panel Hub (DESK mini dentro del panel de vista previa): `PANEL_HUB.md`
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

## Novedades 28-sep (tarde-noche)

- **Busqueda global (⌘F)**: la barra del commander busca en la carpeta actual; **⌘F** alterna a
  «todo el indice» (todas las ubicaciones indexadas) y ⌘F de nuevo vuelve. Tambien en la paleta ⌘K.
- **Reanudacion tras caida**: si la sesion anterior murio con un trabajo activo, al arrancar se
  ofrece «Reanudar pendientes» (omite lo ya hecho; los conflictos se renombran, nunca sobrescribe).
  Diario por trabajo (`job-<id>-items.json`); historial de snapshots acotado a 50 terminales.
- **Error model central (`J4FError`)**: mensajes UX unificados (permisos, conflictos, volumen RO,
  sin espacio…) + detalle tecnico; adoptado en commander/panel.
- **Logging os_log** por modulo (commander, panel, jobs, stores) con subsystem
  `com.dmx83.just4folders`; los espectadores de `log stream` ven ademas el detalle.
- **QA**: `scripts/qa_smoke.sh` (build + tests + arranque + AX) y `scripts/perf_100k_listing.sh`
  (100k: listado + crawl/consultas del indice).
- **UI v2.1**: barra lateral de navegacion (Ubicaciones/Favoritos/Recientes; Arbol colapsable),
  chip IZQ/DER y barra de ruta pulidos, estado vacio del preview, columnas a prueba de balas
  (reparto contra el viewport real) y autocuracion de divisorias; el contenido ahora llena la
  ventana a cualquier tamano.

## Novedades v2.2 (navegacion + portapapeles + estilos)

- **Barra de direccion por panel**: atras/adelante + breadcrumb navegable; **doble clic** (o ⌘L)
  la convierte en campo editable (Enter va, Esc cancela). La tira superior con la ruta
  compartida desaparece: el chip del panel activo vive ahora junto al estado.
- **Barra lateral de navegacion**: sin botones sueltos; acciones por **clic derecho** (abrir,
  revelar, copiar ruta, quitar de Ubicaciones/Favoritos, limpiar recientes, reautorizar).
- **Portapapeles completo**: ⌘C/⌘X/⌘V/⌘D; copiar/pegar funciona tambien con archivos copiados
  en **Finder**, **cortar+mover** (el corte se consume al pegar) y «Comprimir» (zip) en el menu.
- **Menu contextual estilo Finder+** revisado: Abrir/Abrir con/Ver/Mostrar en Finder/Terminal,
  Nueva carpeta/Renombrar/Duplicar/Comprimir, Cortar/Copiar/Pegar, Papelera/Borrar, Copiar ruta,
  Favoritos/Ubicaciones/Informacion, Etiquetas, Compartir y Herramientas.
- **Columnas por carpeta**: anchos manuales persistentes (arrastra el divisor), doble clic en el
  divisor = ajustar al contenido, «Ajustar columnas a la ventana» en la cabecera.
- **Ajustes ▸ Apariencia**: estilos visuales (Esmeralda, Oceano, Amatista, Grafito, Color del
  sistema) aplicados en vivo (chip, toggles, barra lateral).
- **Modo de un solo panel (⌘\\)**: alterna Commander ⇄ panel unico con el **boton de la barra de
  herramientas** (el icono refleja el reparto actual), el menu Navegacion, la paleta ⌘K o ⌘\\
  (persistente). En modo simple, Tab cambia cual de los dos paneles se ve; el reparto de
  columnas se reajusta solo al cambiar de modo.
- **Divisoria entre paneles arrastrable y recordada**: reparte libremente izquierdo/derecho
  (puedes dejar uno mas ancho que el otro); la proporcion se guarda (`j4f.panelsLeftRatio`) y se
  mantiene al redimensionar la ventana. El arrastre nativo de NSSplitView resultaba no-op en este
  contexto (Auto Layout + hosting de SwiftUI): el reparto lo controla `J4FPanelSplitView` con
  constraints propias y arrastre propio (cursor ↔).
- **Divisoria de la vista previa arrastrable y recordada** (`J4FBodySplitView`): arrastra el
  borde izquierdo del preview para agrandarlo (util con imagenes/documentos, sobre todo en modo
  de un panel); el ancho se guarda (`j4f.previewWidth`) y se autocorrige si los minimos de los
  paneles no conceden lo pedido (el tope real en modo dual ronda los 880pt; en modo simple hay
  mas espacio). El preview nunca invade el minimo usable de los paneles (220pt).
- **Panel Hub (v2.3)**: el panel lateral tiene tres modulos con selector
  («Vista previa | DESK | PICT», recordado en `j4f.previewModule`): la vista previa de siempre;
  **DESK mini** — buscador instantaneo sobre el indice (mismos resultados que ⌘F; Enter o doble
  clic abre, Esc limpia) + **bandeja** de Descargas con «Ordenar…» (clasifica y mueve con diario
  y Deshacer; nunca borra) + cola **POR REVISAR** (dudosos de 99_SinClasificar del ultimo
  destino, «Ver en panel») + **ACTIVIDAD** (trabajo en curso) y **soltar documentos sobre el
  modulo** para proponerles categoria (confirmacion + movimiento por la cola); y **PICT mini** —
  acciones rapidas sobre la seleccion (convertir a PNG/JPEG, redimensionar 50 % con `sips`,
  creando ficheros nuevos; «Abrir en JUST4PICT» si esta instalada). Ademas, **clic derecho sobre
  imagenes → submenu JUST4PICT** (Convertir a PNG/JPEG, Redimensionar 50 %; mismo motor
  `PictQuickActions`, fichero nuevo junto al original): tanto el submenu como el tercer segmento
  del selector **solo aparecen cuando la seleccion incluye imagenes**. Propuesta completa en
  `PANEL_HUB.md` y evaluacion de la integracion de JUST4PDF en `JUST4PDF_INTEGRATION.md`.
- **Integracion JUST4PDF (v2.3.5)**: clic derecho sobre PDFs → submenu **JUST4PDF ▸**:
  «Unir PDFs en uno…» (≥2), «Comprimir ▸ Bajo/Medio/Alto», «Exportar paginas a imagenes…»,
  «Crear PDF con estas imagenes…» (seleccion solo de imagenes) y «Abrir con JUST4PDF».
  Usa el CLI real `just4pdf-cli` (PATH del usuario o venv del repo; fallback
  `python -m just4pdf.cli`), en background, con nombres unicos junto al origen y **nunca
  sobrescribe**; el submenu solo aparece si hay una accion usable.
- **Pestanas y toolbar (v2.3.6)**: clic derecho sobre una pestana del panel → «Cerrar
  pestana», «Cerrar las demas», «Duplicar pestana», «Renombrar pestana…», «Mover a la
  izquierda/derecha» (las acciones operan sobre la pestana pulsada, sin cambiar la activa).
  El toolbar deja el boton `Diagnostics` (pasa al menu Operaciones, a la paleta ⌘K y al editor
  de atajos), normaliza sus etiquetas al espanol y termina con indicadores de vida de
  **CPU · RAM · Disco · I/O · Bateria** (refresco cada 2 s; el tooltip detalla GB de memoria y de
  disco — usados/totales/libres —, MB/s de lectura/escritura con ops/s, los «máximos vistos»
  de E/S y el estado de la bateria; clic abre el Monitor de Actividad; `SystemMonitor.swift`,
  solo lectura: Mach/IOKit, sin dependencias). El segmento **I/O** es el **% de trabajo**: la
  direccion mas cargada (lectura o escritura, **nunca sumadas** — la suma L+E puede superar el
  maximo real de una sola direccion) frente al **maximo registrado en este Mac** (picos por
  direccion aprendidos y persistidos; 100 % = su tope conocido; macOS no expone un % de
  ocupacion oficial fiable). Diseno con jerarquia
  (etiquetas atenuadas, separadores tenues, valores a color pleno) y **avisos por color**:
  naranja = atencion (I/O >=60 %; CPU >=80 %; RAM >=85 %; disco >=85 % ocupado; bateria
  <=25 % sin cargador) y rojo = critico/saturado (I/O >=85 %; CPU/RAM >=95 %; disco
  >=93 %; bateria <=15 %), con mas peso tipografico al subir de nivel. El monitor ademas:
  **clic derecho** → menu (Reiniciar maximos registrados / Abrir Monitor de Actividad) y
  **bateria en verde al cargar**. Fix relacionado: los botones Atras/Adelante del toolbar
  prometian «clic derecho: historial» pero su menu nunca se abria (el `menu` nativo de
  `NSButton` no hace popup en este contexto); ahora usan `J4FMenuButton` (popup manual) y el
  historial SI se despliega con clic derecho.
- **Contenido que llena la ventana completa (v2.2d)**: tras detectar que el hosting de SwiftUI
  dejaba la vista del controlador en tamano «fitting» (hueco muerto a la derecha y banda inferior
  de ~36pt), se corrige con `.ignoresSafeArea()` en `ContentView` y con el ancho del split del
  cuerpo fijado al de la ventana (requerido). Ademas, la pila inferior (avisos/progreso/estado)
  usa altura EXACTA calculada de sus filas visibles: `NSStackView` no expone intrinsic, asi que
  ni hugging ni cap la gobernaban (el solver le daba 96pt y dejaba una banda vacia bajo los
  paneles). Leccion: no ACTIVAR constraints dentro de `layout()` (bucle de «Update Constraints»
  que aborta la app): activar en configuracion y solo actualizar constantes en layout.
- **Fix de layout importante**: el campo de edicion de la direccion conservaba constraints de
  autoresizing y envenenaba al solver (20 conflictos; el contenido no llenaba la ventana en
  algunos estados). Ademas: refit de columnas tras asentarse el layout y limpieza de anchos
  envenenados guardados.

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
- IA opcional en la ordenacion (**v2.0**): con `DEEPSEEK_API_KEY` (o `.env.secrets`), «Usar IA para
  los dudosos» consulta solo lo que las reglas no clasifican (se envia unicamente el nombre).
- Ola 1 de explorador (**v2.0**): miniaturas reales (imagen/PDF/video), **QuickLook con Espacio**,
  **breadcrumb clicable**, **drag & drop** (interior mueve/⌥ copia; desde Finder copia/⌘ mueve),
  filas estilo Finder y estados vacios («Carpeta vacia · ⌘N»).
- Ola 2 de explorador (**v2.0**): **vista previa lateral** (⌥⌘P) con metadatos, **F2/F3/F4**
  completan la fila de teclas, **columnas configurables** (cabecera; recordadas por carpeta),
  **historial con menu** en Atras/Adelante, **progreso en la ventana** y **pestañas completas**
  (duplicar ⌥⌘T, renombrar ⌥⌘R, mover ⌥⌘←/→).
- Ola 3 (**v2.0**): **paleta de comandos ⌘K**, **workspaces** (⌥⌘S guardar / ⌥⌘L restaurar:
  pestañas, activo y preview de ambos paneles), **vista en galería** (⌥⌘G, mosaico recordado por
  carpeta, tamaño S/M/L), **árbol por panel** (⌥⌘E), **atajos configurables** (⌥⌘K, JSON) y
  **búsqueda semántica** (⌥⌘B: la IA convierte la consulta en términos cuando hay clave).
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
