# QA Local — JUST4FOLDERS

## Estado actual validado por CLI

- `swift build`: OK
- `swift test`: OK (55 tests, 28-sep)
- `scripts/perf_100k_listing.sh`: OK (28-sep: listado 100k + crawl/consultas del indice)
- `scripts/qa_smoke.sh`: OK (28-sep: build+tests+arranque+AX)
- `swift run JUST4FOLDERS`: arranca (sin crash inmediato)

## Incidencia de busqueda profunda (2026-02-19) — RESUELTA (28-sep)

- La busqueda profunda por recorrido de arbol se sustituyo por el **indice FTS5 compartido**
  (`J4IIndex`): consultas de 10–25 ms sobre 100k+ entradas (ver «Rendimiento» abajo); el
  comportamiento inestable ya no es reproducible.
- La decision original (no cerrar QA hasta respuesta consistente) queda cumplida; se mantiene la
  checklist manual de abajo para regresiones.

## Validaciones 28-sep (tarde-noche)

- [x] `⌘F` alterna «esta carpeta ⇄ todo el indice» (placeholder y estado lo reflejan); la busqueda
  global devuelve resultados de todo el indice (verificado por AX + captura).
- [x] Estado de indexado en vivo: «Indexando «ruta»: N entradas…» (probado con 12k ficheros; el
  listado en curso puede mostrar «Cargando N elemento(s)…» a la vez).
- [x] Reanudacion post-crash E2E: snapshot sintetico → dialogo al arrancar → «Reanudar pendientes»
  copia lo pendiente, omite origenes ya movidos y limpia el snapshot.
- [x] Historial de snapshots acotado (280 → 50 terminales; el JSON crecia sin limite).
- [x] VoiceOver no aplica aqui (app AppKit con labels propios); pendiente auditoria formal.

## Validaciones 28-sep (noche) — UI v2.1/v2.2/v2.2b

- [x] Layout a prueba de balas: ventana llena con ambos paneles completos (Nombre/Tamaño/
  Modificado/Tipo) y sin conflictos del solver (los conflictos de AppKit, si los hay, van al
  log unificado, no a stderr).
- [x] Modo de un solo panel (⌘\\ o **botón de la barra de herramientas**): ciclo completo con
  capturas — clic 2→1 y 1→2, solo el activo, Tab alterna izq/der, persistencia confirmada al
  relanzar la app y vuelta a dual con reajuste automatico de columnas.
- [x] Divisoria entre paneles: arrastre real validado (divisor 659 → 830) y persistencia al
  relanzar (838 ≈ proporcion × ancho nuevo; escala si cambia la ventana).
- [x] Divisoria del preview (v2.2d): encoger deja 464pt exactos guardados; agrandar topa en el
  minimo real de los paneles (~884pt en dual) y el valor guardado se autocorrige al resuelto
  (885) — sin valores fantasma tras relanzar.
- [x] Fill completo de la ventana (v2.2d): geometria verificada (view = 1.728 = ventana; split
  hasta 28pt del borde inferior: 10 de separacion + fila de estado de 18 + margen 12) y capturas
  sin bandas muertas arriba/abajo/izquierda/derecha.
- [x] Barra lateral sin hueco en «ARBOL» (v2.2e): captura con el arbol expandido — cabecera pegada
  al arbol y el arbol absorbiendo el sobrante (antes: fila «ARBOL» estirada con hueco enorme).
- [x] Panel Hub F1 (v2.3): ciclo Vista previa ⇄ DESK por clic (persistido `j4f.previewModule` =
  preview/desk); busqueda «certificado» → 16 resultados reales del indice con icono + ruta
  (~/IDMX83/..., ~/JUST4DESK/09_Identidad/...); bandeja de Downloads con 4 elementos y antiguedad
  («hace 3 sem», «hace 1 m»...); botones Ordenar…/Abrir en panel/⟳. Nota: el contenido del panel
  arranca a 44pt del borde superior (la toolbar fullSizeContentView oculta los primeros ~38pt).
- [x] Panel Hub F2 (v2.3.1): con destino real (~/JUST4DESK) la fila POR REVISAR muestra
  «nada pendiente en JUST4DESK ✓» y «Ver en panel» navego el panel activo a 99_SinClasificar
  (verificado en captura: «1: 99_SinClasificar»); ACTIVIDAD en reposo («sin trabajos en curso»);
  Enter/Esc y menus contextuales implementados. OJO al testear clics: el primer clic de un
  helper externo puede consumirse activando la app (el segundo ya entra).
- [x] Hueco inferior cerrado: los paneles ocupan todo el alto disponible (antes ~250 pt muertos
  a causa del stack de estado estirado; v2.2d: altura exacta por filas visibles).
- [x] Estilos visuales en vivo: cambio a Oceano reflejado al instante (chip, toggles, sidebar);
  restaurado a Esmeralda.
- [x] Comprobado en el mismo ciclo: barra de direccion por panel (atras/adelante + edicion),
  sidebar con acciones contextuales, portapapeles completo (⌘C/⌘X/⌘V/⌘D, cortar=mover, pegar
  desde Finder, Comprimir/Duplicar) y columnas manuales persistentes.
- [x] Panel Hub F3 (v2.3.2): drop de «a-factura-luz-test.pdf» sobre el modulo DESK → alerta
  «Archivar 1 documento(s) en JUST4DESK» con propuesta «01_Fiscal/Facturas/… (regla local:
  «factura» en el nombre)» → «Mover» → el fichero aparecio en ~/JUST4DESK/01_Fiscal/Facturas y
  desaparecio del origen (fixture limpiado despues). Modulo PICT: seleccion sincronizada
  («a-foto-test.png»), «Redimensionar 50 %» creo 120x80 (original 240x160) SIN sobrescribir;
  fixture limpiado. 55 tests verdes.
- [x] Submenu JUST4PICT en el clic derecho (v2.3.4): SIN imagenes seleccionadas el menu
  contextual no incluye JUST4PICT y el selector del Panel Hub muestra solo «Vista previa |
  DESK» (2 segmentos); al seleccionar un PNG aparecen el 3er segmento y el submenu «JUST4PICT ▸»
  (capturas de ambos estados). Fix de coherencia: un «pict» persistido sin seleccion util se
  normaliza a «Vista previa» (antes: segmento decia Vista previa con el modulo PICT visible).
- [x] Integracion JUST4PDF (v2.3.5): submenu «JUST4PDF ▸» visible con PDFs (capturas) y OCULTO
  con una carpeta (ni JUST4PDF ni JUST4PICT); «Unir PDFs en uno…» habilitado con 2 PDFs y
  «Crear PDF con estas imagenes…» deshabilitado (reglas); **merge E2E desde el menu** →
  ~/unido.pdf con 4 paginas (fixtures 2+2) y aparece en el panel tras refrescar (fixtures
  limpiados). CLI JUST4PDF: 7 tests + smoke manual (compress 1936→1326 B; pdf2img 4 PNG).
  **Pendiente de clic manual**: Comprimir (3 niveles), Exportar paginas, Crear PDF con imagenes
  y Abrir con JUST4PDF (misma plomeria del merge ya validado).
- [x] Pestañas con clic derecho (v2.3.6): con 2 pestañas, clic derecho sobre la primera → menú
  con «Cerrar pestaña» · «Cerrar las demás» · «Duplicar pestaña» · «Renombrar pestaña…» ·
  «Mover a la izquierda» (deshabilitado, es la primera) · «Mover a la derecha» (captura);
  pulsar «Cerrar pestaña» cerró la tab extra y quedó «1: dmx83». Toolbar: ítem `Diagnostics`
  ya no está; indicadores al final «CPU 18% · RAM 71% · Batería 82%», «CPU 19% · RAM 69% ·
  Disco 89% · Batería 80%» y con actividad (formatos previos en MB/s): «I/O 59 MB/s» en
  reposo-arranque + «I/O 1.5 GB/s» (y 661 MB/s) durante un `dd` de 4 GB (capturas 1:1; el
  89% de disco cuadra con `df`: 860G usados de 995G = 89%). Diseño con avisos por color
  validado en capturas: «Disco 89%» NARANJA (casi lleno), «I/O 65%» NARANJA (carga, formato
  final %) y «I/O 3%» tras parar; antes (formato MB/s): «I/O 1.2 GB/s» naranja y «I/O
  1.6 GB/s» ROJO + negrita; etiquetas atenuadas y valores a color pleno; 55 tests.
- [x] `swift test`: 55 en `J4FOpsTests`, 0 fallos.

## Checklist manual — Panel Hub v2.3.x (para verificar con la app en mano)

Validado por automatizacion/capturas; falta el tacto real (raton/teclado humano):

- [ ] Selector `Vista previa | DESK | PICT` en el panel derecho: cambia sin parpadeos y se
  recuerda al reabrir la app (`j4f.previewModule`).
- [ ] DESK · buscador: teclear muestra resultados del indice; Enter abre el primero; Esc limpia.
  Clic derecho en un resultado: Abrir / Abrir la carpeta contenedora.
- [ ] DESK · bandeja: «Ordenar…» abre la ventana de clasificacion con el **Destino precargado**
  (destino recordado por carpeta: `j4f.folderDestinations`, se guarda al ordenar).
- [ ] DESK · POR REVISAR: tras ordenar una carpeta con dudosos, el contador sube; «Ver en panel»
  abre 99_SinClasificar en el panel activo.
- [ ] DESK · ACTIVIDAD: al copiar/mover un fichero, la fila muestra el progreso con barra y
  vuelve a «sin trabajos en curso» al terminar.
- [ ] Soltar (arrastrar de un panel) un documento sobre el modulo DESK: la fila se resalta en
  azul al pasar por encima, aparece la propuesta con categoria/motivo, «Mover» archiva y
  «Cancelar» no toca nada. **OJO**: este flujo mueve SIN el diario de Deshacer (⇧⌘Z solo cubre
  «Ordenar esta carpeta»); decidir si se unifica.
- [ ] PICT: seleccionar una imagen activa los botones; «Convertir a PNG/JPEG» y «Redimensionar
  50 %» crean un fichero nuevo junto al original (nunca sobrescribe; sufijos -png/-jpg/-50%);
  «Abrir en JUST4PICT» funciona si la apps esta instalada (bundle com.dmx83.just4pict).
- [ ] **Clic derecho en una imagen → submenú «JUST4PICT»**: probar los 3 ítems (mismo motor
  sips que el módulo; deshabilitado si la selección no tiene imágenes).
- [ ] **JUST4PDF**: clic derecho sobre PDFs → «Comprimir ▸» (probar Bajo/Medio/Alto), «Exportar
  páginas a imágenes…» y «Abrir con JUST4PDF» (requiere la app JUST4PDF registrada); «Crear PDF
  con estas imágenes…» seleccionando 2+ imágenes (sin PDFs). El submenú solo aparece con
  selección usable.
- [ ] **Pestanas (v2.3.6)**: clic derecho sobre una pestaña en cada estado (1 tab: Cerrar y
  Cerrar las demas deshabilitados; 2+: habilitados), «Renombrar pestaña…» sobre una tab no
  activa (debe renombrarla SIN cambiarla de activa) y «Mover a la derecha» en la ultima
  (deshabilitado). Comprobar que el clic derecho NO cambia la pestana activa.
- [ ] **Monitor (v2.3.6)**: los valores de CPU/RAM/Disco se mueven (abrir una operacion
  pesada); el % de disco (OCUPACION, cuadra con «Acerca de este Mac»/`df`) y el segmento
  **I/O** es el % de TRABAJO: dirección más cargada (lectura/escritura, nunca sumadas)
  frente al **máximo registrado** — en reposo 0-5 %, una copia grande sube a naranja/rojo y
  puede llegar a 100 % cuando iguala el máximo visto; el pico se aprende y persiste (haz una
  copia grande para calibrar la referencia; el tooltip muestra «máximos vistos: L/E»); avisos
  por color: NARANJA al cruzar el umbral de atencion y ROJO (mas peso) al de saturacion —
  Disco >=85 %, I/O >=60 %→85 %; el tooltip trae GB usados/totales/libres (memoria y disco)
  y desglose escritura/lectura/ops/s; **clic derecho → menú** (Reiniciar máximos
  registrados / Abrir Monitor de Actividad — comprobar que un clic derecho simple NO
  dispara los ítems al soltar); **batería en verde con el cargador puesto** (el estado
  «cargando» aparece también en el tooltip); clic → abre Monitor de Actividad; al cerrar la
  ventana el timer se detiene (sin lecturas en segundo plano). En Mac sin batería el bloque
  desaparece (queda CPU · RAM · Disco · I/O).
- [ ] **Atrás/Adelante del toolbar con clic derecho (v2.3.6)**: el menú de historial se
  despliega de verdad (antes no lo hacía) y elegir una entrada salta a esa carpeta; el clic
  izquierdo sigue navegando atrás/adelante normal.
- [ ] **Exportar diagnostico (v2.3.6)**: menu `Operaciones ▸ Exportar diagnóstico…` y paleta
  (⌘K) generan el zip con `summary.json` etc.
- [ ] **«Mejorar con JUST4PICT ▸» (v2.3.7)**: con una imagen seleccionada, clic derecho →
  `JUST4PICT ▸` → `Mejorar con JUST4PICT ▸` (5 presets: Automático · Retrato · Paisaje ·
  Documento · Ecommerce). Debe salir el aviso «JUST4PICT: mejorando N imagen(es) (preset X)…» y,
  al terminar, un **fichero NUEVO junto al original** (sufijo `-enhanced…`, nunca sobrescribe) y
  la lista refrescada. Con selección sin imágenes el submenú no aparece; si el CLI
  `just4pict-cli` no está disponible, el ítem se **oculta** (el resto del submenú `sips` sigue).
  *Validado por CLI sintético (29-sep): Paisaje sobre un JPEG de 267 KB → PNG de 3,0 MB;
  salida idéntica ejecutando el CLI a mano.*
- [ ] **Vista previa lateral (v2.3.8)**: seleccionar una foto (JPEG/PNG) → se pinta al instante,
  también si acaba de aparecer (p. ej. la salida de «Mejorar con JUST4PICT»); un PDF se pinta por
  QuickLook; sin selección se ve el estado vacío («Selecciona un archivo…») y con varios
  elementos «N elementos seleccionados». Comprobar que después de mejorar/convertir una imagen la
  tarjeta NO se queda con el icono genérico del tipo de fichero (fallo corregido en v2.3.8).
  *Validado (29-sep): PNG recién creado + JPEG renderizados, PDF por QuickLook, carpeta con icono.*
- [ ] Drag & drop interno de ficheros entre paneles (pendiente historico) — comprobar tambien.
- [ ] Decision de diseno: la vista previa perdio ~65pt de alto (fila del selector + franja de la
  toolbar); valorar selector compacto (iconos) o moverlo a la barra de herramientas.

## Rendimiento (100k, 28-sep)

- `J4I PERF · crawl: 100.101 entradas en 11,4 s` (J4IIndex; `perf_100k_listing.sh`).
- Queries FTS5: 10–25 ms tipicas (`archivo-500`: 25,0 ms · `dir-50`: 10,5 ms · `txt` (termino muy
  comun): 102 ms).
- Listado incremental 100k: test en verde (umbral <300 s; 230 s incl. creacion de los ficheros).

## Incidencias cerradas (2026-02-19)

- Prompt de `Nueva carpeta` / `Renombrar` recupera foco de teclado.
- `Renombrar` funciona desde toolbar y menu contextual.
- Menu contextual incluye `Nueva carpeta`.
- `Pegar item` usa cola de jobs (progreso visible).
- Copia recursiva de carpetas conserva contenido interno (incluyendo archivos >1MB).
- Barra de direccion editable + `Go` robusto (normaliza/valida ruta).
- Click en area vacia del panel selecciona raiz del directorio actual.
- `Informacion` agrega `Tamano logico` y `Tamano en disco` (dedup hard links).
- Boton/accion de `Info carpeta actual` disponible sin depender de seleccion.
- Columna izquierda cambiada a arbol del directorio activo (navegacion rapida).
- Arbol anclado estable (Home/volumen), con soporte `..` para subir nivel.
- Boton `Home` en toolbar para volver rapido al directorio base.
- Barra de ruta con autocompletado basico de rutas existentes.

## Smoke test critico (dmx83/temp/orlando_salida)

1. Abrir `/Users/dmx83` en panel activo.
2. Crear carpeta `temp`.
3. Seleccionar `orlando_salida`.
4. Copiar y pegar dentro de `temp` (F5 + cambiar panel + pegar o menu contextual).
5. Verificar:
   - job visible en status/tasks,
   - carpeta `temp/orlando_salida` creada,
   - contenido interno completo presente.

## Checklist manual UI (desktop)

### 1) Arranque y navegación básica

- Abrir app y verificar ventana principal sin errores visibles.
- Cambiar panel activo con `Tab`.
- Navegar carpetas con doble click y `Enter`.
- Back/Forward en toolbar por panel.
- `Cmd+L` enfoca path bar y permite abrir ruta.

### 2) Sidebar y permisos

- `Add Location` autoriza carpeta con `NSOpenPanel`.
- Entrada aparece en `Autorizadas`.
- Doble click en `Autorizadas/Favoritos/Recientes` abre carpeta en panel activo.
- Reautorización funciona para bookmarks stale (si se simula/produce caso).

### 3) Tabs + atajos Commander

- `Cmd+T` crea tab en panel activo.
- `Cmd+W` cierra tab actual (si queda una sola, cierra ventana).
- `F5/F6/F7/F8` ejecutan copy/move/mkdir/delete.

### 4) Operaciones y Task Manager

- Copy/Move/Delete generan job y progreso.
- `Tasks` muestra jobs y actualiza estado.
- `Pause/Resume/Cancel` funcionan en jobs activos.
- Al finalizar jobs, paneles refrescan contenido.

### 5) Watchers y consistencia

- Cambios externos en carpeta autorizada se reflejan sin refresh manual.
- Durante operaciones masivas, watcher no genera tormenta visual.
- Botón `Refresh` actualiza panel activo manualmente.

### 6) Preferencias

- Abrir `Settings`.
- Cambiar `Comportamiento de borrar` y validar efecto en `Delete`.
- Cambiar `Mostrar archivos ocultos` y validar refresco.
- Cambiar `Buffer Big inicial` y validar que no rompe operaciones.

### 7) Menú contextual

- En tabla de archivos: `Abrir`, `Abrir en Finder`, `Copiar ruta`, `Informacion`, `Renombrar`, `Eliminar`, `Eliminar definitivamente`.

### 8) Diagnóstico

- `Operaciones ▸ Exportar diagnóstico…` (o paleta ⌘K) genera el zip — v2.3.6: ya no es boton
  del toolbar.
- Zip contiene `summary.json`, `preferences.json`, y `job-snapshots.json` (si existe).

## Criterio de pase local

- Sin crashes ni bloqueos.
- Operaciones de archivos finalizan con estado correcto.
- UI responde por teclado y mouse en flujos principales.
