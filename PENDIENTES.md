# PENDIENTES — JUST4ALL (revisión 1-oct-2026)

Consolidado a partir de los TODO de cada app, `QA_LOCAL.md` y la memoria de trabajo.

**Leyenda**: 🟠 código/tarea · 🔵 validación manual · ⚪️ opcional/futuro · 🔴 bloqueado (licencia Apple)

---

## 0) Entorno / configuración (esta semana)

- [ ] 🔵 Recargar la ventana de VS Code para aplicar los ajustes de DeepSeek
      (`reasoningEffort` max→**medium**, `maxTokens` 16384, `debugMode` metadata) y verificar en *Manage Models*.
- [x] ❌ **Descartado por el dueño**: «Configure Tools ≤64» (dijo que no cree que el número de herramientas
      consuma apenas; no volver a proponerlo).
- [ ] ⚪️ Con ≤64 tools: probar `deepseek-copilot.experimental.stabilizeToolList: true` (mejor cache-hit).
- [ ] ⚪️ Si aparece el MCP `tradingview-local` (de Claude Desktop) en la lista de herramientas: desactivarlo.
- [ ] ⚪️ Opcional: `nextEditSuggestions` (consume cupo de Copilot, no de DeepSeek).

## 1) JUST4FOLDERS (v2.3.15 — teclado: Return abre, Retroceso vuelve)

**Hecho hoy (29-sep)**
- [x] 🟠 **Integración JUST4PICT por CLI**: submenú **JUST4PICT ▸ → «Mejorar con JUST4PICT ▸»** con 5
      presets (Automático · Retrato · Paisaje · Documento · Ecommerce) sobre `just4pict-cli`, en background
      y sin sobrescribir (`Just4PictActions.swift`). Validado e2e: menú → Paisaje → PNG de 3 MB desde un
      JPEG de 267 KB; IDÉNTICO al CLI a mano.
- [x] 🟠 **Vista previa lateral fiable (v2.3.8)**: las imágenes se pintan en local con ImageIO
      (`LocalImagePreview.swift`) en vez de por QuickLook — éste devolvía el icono genérico la primera vez
      que se pedía un fichero recién creado y se quedaba pegado. QuickLook sigue para PDF/vídeo/documentos
      y ahora reintenta (`refreshPreviewItem()` a 0,4/1,6 s); al crear ficheros la vista previa se refresca.
- [x] 🟠 **Orden por Tamaño correcto (v2.3.9)**: ordenaba con `sizeBytes` (nil en carpetas) y la lista se
      rebarajaba en cada recarga; ahora usa el tamaño efectivo + desempate por nombre, pide todos los
      tamaños al pulsar la cabecera y reordena una sola vez al terminar (las desconocidas, al final).
- [x] 🟠 Nit de estado: el aviso «Actualizado (N cambio(s) en disco)» del watcher ya no pisa los mensajes
      de operación (prioridad temporal en el estado del commander).
- [x] 🟠 **Tamaños de carpeta correctos y estables (v2.3.10)**: se sumaba el tamaño lógico (un fichero
      disperso hacía que `~/Library` mostrara 1,06 TB en un disco de 995 GB); ahora se suma el asignado en
      disco (`Library` = 135 GB ≈ `du`), el watcher ya no borra el valor (adiós al parpadeo) y los cálculos
      van a `.userInitiated` con tope de 3 a la vez.
- [x] 🟠 **Motor de copia rápido + caché de tamaños (v2.3.11)**: clon APFS (`clonefile`) y `copyfile` en
      lugar de leer a memoria + escritura atómica; el progreso ya no reescribe el JSON de trabajos por
      ítem. Medido: 96 MB clonados en 0,009 s / 0 MB; mecanismo 400×8 KB 12,6x más rápido; motor completo
      2,602 s → 0,114 s; caché en disco de tamaños (el recorrido de un árbol ya está en el óptimo del
      sistema: 18,9 s vs 14,4 s de `du`).
- [ ] 🔵 Validar en hardware real la copia a volumen externo (sin clones APFS) y la conservación de
      metadatos en el Finder (checklist de `QA_LOCAL.md`).
- [x] 🟠 **Teclado: abrir/volver y foco (v2.3.12 → v2.3.15)**: mapa final **Return/Enter = abrir** y
      **Retroceso ⌫ = volver** (`KeyNavigationKeys`, con tests) + atajos nuevos ⌘[ / ⌘] / ⌘↑ / ⌘↓
      en el menú Navegación. En v2.3.12 Return se puso a «volver» por una confusión de tecla del
      usuario; por el camino aparecieron dos bugs reales de foco y modificadores: al arrancar el
      foco era la tabla del sidebar vacía (la tecla se consumía en silencio) y macOS añade
      `.numericPad`/`.function`/`.capsLock` (la tecla grande «Enter» de los teclados Windows llega
      como Enter del teclado numérico). Ahora hay respaldo de foco por panel, el arranque enfoca la
      lista y los modificadores de ruido se ignoran (también arregla F5–F8). 73 tests verdes.
- [ ] 🔵 Comprobar a mano: `⌘L` + Return navega a la ruta escrita, y F5–F8 con las teclas F reales
      (`QA_LOCAL.md`; herramienta `scripts/qa_keys.swift`).
- [ ] 🟠 Pico de CPU al arrancar: perfilar el warm-up del **índice SQLite** (`sample` mostró sqlite3VdbeExec
      como dominante; los tamaños ya no son el cuello) y decidir si conviene diferirlo.

**Código**
- [ ] 🟠 Integración JUST4PDF **F3** (opcional): progreso en la cola de trabajos, Quick Actions del Finder
      (v0.3 de JUST4PDF) y módulo del Panel Hub (F4). Ref: `APPS/JUST4FOLDERS/JUST4PDF_INTEGRATION.md`.
- [ ] 🟠 Panel Hub — pendientes menores: reglas favoritas por extensión, unificar el diario de Deshacer para
      el drop del módulo DESK (hoy mueve sin diario), selector compacto (la vista previa perdió ~65 pt de
      alto). El módulo del Panel Hub con el pipeline de PICT sigue pendiente.
- [ ] 🟠 Nit conocido: la última columna («Tipo») puede recortar 1 carácter si el ancho queda justo.
- [ ] ⚪️ Drag & drop interno de ficheros entre paneles (histórico) — comprobar y decidir.

**Validación manual** (`QA_LOCAL.md` § «Checklist manual — Panel Hub v2.3.x»)
- [ ] 🔵 Panel Hub completo: selector persistente, buscador DESK, bandeja, POR REVISAR, ACTIVIDAD, drop→propuesta.
- [ ] 🔵 Submenús contextuales: JUST4PICT (3 ítems `sips` + **Mejorar con JUST4PICT ▸** con 5 presets) y
      JUST4PDF ▸ (Comprimir 3 niveles, Exportar páginas, Crear PDF desde imágenes, Abrir con).
- [ ] 🔵 Pestañas: botón derecho en cada estado; «Renombrar» sobre tab no activa sin activarla.
- [ ] 🔵 Monitor: menú del clic derecho (Reiniciar máximos / Abrir Monitor) sin dispararse al soltar;
      batería en verde con cargador; I/O % en reposo y bajo carga.
- [ ] 🔵 Atrás/Adelante del toolbar: el menú de historial por clic derecho.
- [ ] 🔵 `Operaciones ▸ Exportar diagnóstico…` y paleta ⌘K generan el zip.

**Artefactos**
- [ ] ⚪️ `dist/JUST4FOLDERS.dmg` y `build/Build/Products/Release/*.app` están **atrasados** (el .app es de
      marzo, v0.1.0 = «instancia fantasma»): regenerar antes de distribuir o hacer demos.

## 2) JUST4PICT

- [x] 🟠 **CLI mínimo `just4pict-cli`** (lote sin UI) — HECHO (29-sep): ver `APPS/JUST4PICT/README.md`.
- [x] 🟠 **Integración del CLI en FOLDERS** — HECHO (29-sep): «Mejorar con JUST4PICT ▸» (5 presets) en el
      clic derecho de JUST4FOLDERS; validado e2e. Queda como opcional un «Editar con JUST4PICT» (abrir la app
      con la imagen) cuando la app declare tipos de documento.
- [ ] 🔵 Validación visual final de retrato (ojos/cejas en muestras reales adicionales).
- [ ] 🟠 Telemetría local por build (JSON por corrida: preset, tiempo, memoria, fallos) para comparar regresiones.
- [ ] 🟠 Snapshot de receta efectiva por ítem (incluido fallback IA) para reproducibilidad exacta.
- [ ] 🟠 Matriz QA por escena (muestras fijas con «expected windows» en archivo dedicado).
- [ ] 🟠 Afinar criterios de `AUTO` (documento vs ecommerce con branding ligero).
- [ ] 🟠 Consolidar reportes QA en una salida única por corrida.
- [ ] ⚪️ Copy de estado IA más corto/consistente; preset rápido para web/marketplaces.
- [ ] 🔴 Firma y notarización.

## 3) JUST4PDF

- [ ] 🔵 Checklist manual del `README` (navegación/zoom, PDFs medianos, «Open With», PDF→imágenes,
      imágenes→PDF, unir, compresión 3 niveles + modo seguro).
- [ ] ⚪️ Quick Actions del Finder + progreso en FOLDERS (v0.3) — ligado a FOLDERS F3.
- [ ] 🔴 Firma y notarización.

## 4) JUST4DESK

- [ ] 🔵 Validación visual manual (`swift run`: añadir carpeta real y probar búsqueda/filtros/acciones).
- [ ] 🔵 QA manual: DMG real (`./scripts/build_dmg.sh`) y flujo end-to-end con documentos reales.
- [ ] 🟠 **N6** — Empaquetado real (DMG + sandbox + Quick Action de Finder; las notificaciones ya están).

## 5) JUST4ALL (hub) y global

- [ ] 🟠 Icono placeholder → icono real (icns) y validar tamaños.
- [ ] 🟠 Logos y screenshots reales en `Sources/JUST4ALL/Resources/Assets`.
- [ ] 🟠 Textos, links y requisitos reales por subapp; copy del panel de detalle; accesibilidad básica.
- [ ] 🟠 Build reproducible por subapp (versionado, release notes, checksum) y empaquetado final.
- [ ] 🔴 Firma/notarización, App Store Connect/TestFlight y publicación v1.0.0 — **bloqueado por la licencia
      de Apple** (los DMG locales sí se generan y validan).

## 6) JUST4CONVERT (la subapp más atrasada)

- [ ] 🟠 FLAC real (encoder dedicado o AudioToolbox); bitrate efectivo en export (AVAssetReader/Writer);
      MKV real (evaluar ffmpeg).
- [ ] 🟠 Presets por ítem en la cola; límite de workers (80 % núcleos) como preferencia; toggle de
      aceleración con aviso según formato.
- [ ] 🟠 Errores de apertura con mensajes accionables; pipeline de releases; QA en macOS 13/14/15 (Intel y AS).

## 7) LIFEOS (cliente nativo de la API de LifeOS)

App en `APPS/LIFEOS` (SPM: `LifeOSAPI` · `LifeOSCore` · `LifeOSUI` · `LIFEOS` + `lifeos-doctor`), servidor en
`0_server_dorticos` (CT115 · `https://lifeos.perlatec.net`). **F1–F3 cerradas** (30-sep) y **desplegado el
1-oct-2026**, con el Diario ya afinado y **verificado por el dueño** (editó una entrada y le puso la hora:
funcionó). Todo commiteado y publicado (`f8ecd06` en JUST4ALL, `4cad6771` en el servidor).

**Hecho (30-sep – 1-oct)**
- [x] 🟠 Paquete SPM completo: capturar con propuesta revisable, Hoy, Agenda, Ejecutar, Diario, Buscar, Bandeja y
      Ajustes; voz (audio → transcripción en el servidor); ⌥Espacio; menú de barra; avisos del sistema; cola sin
      conexión idempotente; acceso nativo (Google y usuario/contraseña con TOTP) y «vincular Google».
- [x] 🟠 Diario afinado: ánimo y energía en escala de color rojo → verde (con palabra y número, no solo color),
      aviso en el compositor de lo que hará `@hora:`/`@fecha:`, hora escrita a mano (`@hora:1100` = 11:00) y
      **zona horaria del dispositivo que escribe** (`tz`), con la del espacio como respaldo.
- [x] 🔵 Producción verificada tras el release: `/health/live`, `/health/ready` y `/` a 200; `lifeos-doctor` con
      sesión → «todo bien» (las nueve pantallas decodifican); 4 contenedores sin reinicios; discos al 21 % y
      31 %; backups diarios cifrados al día.

**Pendiente**
- [ ] 🔵 Recorrer la app con datos reales: Bandeja, Capturar y Ajustes; provocar una **propuesta** desde el panel
      ⌥Espacio y confirmarla; **avisos del sistema**; **cola sin conexión**; menú de barra con las cifras; y
      decidir el **choque de ⌥Espacio con JUST4DESK** (gana quien lo registra antes).
- [ ] 🟠 **Revisión del dueño de las previsualizaciones de diseño**: `APPS/LIFEOS/docs/design/v2-apple/` (38
      imágenes, claro y oscuro) — decir qué cambiar antes de seguir puliendo la UI.
- [ ] 🟠 **F4 «Enviar a LifeOS»**: menú **Servicios** + **drag & drop** + `application(_:open:)` →
      `POST /captures` y `POST /documents/upload`. Es la pieza que falta para que sea una app de Mac redonda
      (la voz ya está dentro).
- [ ] 🟠 **`/openapi.json` no está publicado en producción** (404 con el resto de la API viva): arreglarlo en el
      proxy (NPM) o habilitar el documento. Además desbloquea generar los modelos Swift desde el contrato.
- [ ] 🟠 **Bandeja**: `GET /captures` corta a las 100 más recientes **antes** de filtrar (el aviso ya está en la
      pantalla) y no existe `DELETE` de capturas (no son entidades: `/entities/{id}` da 404).
- [ ] 🔴 **Las cuentas creadas con Google no pueden tener contraseña** (hallazgo: nacen con una aleatoria y
      `POST /auth/password` exige la actual): decidir el arreglo (fijar la primera contraseña o «¿olvidaste la
      contraseña?» por correo). Mientras, la app ofrece «Usar la sesión que ya tengo en la web».
- [ ] ⚪️ Detalles: buscar/exportar entradas del diario y racha de días escritos; animación de entrada de la
      propuesta; icono del menú de barra con la cifra de pendientes; publicar a Google Tasks/Calendar desde la
      app; promover el panel flotante de ⌥Espacio a `PACKAGES/J4SHARED` (hoy copiado de DESK); firmar y
      notarizar el DMG si sale de este Mac.
- [ ] 🔵 Decidir si la web admite `?view=` (o rutas) para que «Abrir en LifeOS» lleve a la sección y no solo al
      inicio: hoy es una sola página sin rutas.
Google y con usuario/contraseña, pantallas Hoy/Capturar/Diario/Bandeja/Ajustes, ⌥Espacio, menú de barra,
avisos del sistema y cola sin conexión. Rediseño visual v2 (estilo Apple, claro y oscuro), **diario** (texto que
manda, selector de menciones con vínculos reales) y **F3 cerrada**: agenda con tres carriles y pares por decidir,
ejecutar acciones y buscar/cronología.
89 tests offline + 14 contra el servidor local verdes, DMG validado y firmado con identidad de desarrollo,
tarjeta en el hub. Parche del servidor aplicado en el repo de LifeOS (**188 tests verdes**) y **desplegado en
producción el 30-sep-2026**: `/auth/native/login` → 200, `/auth/native/exchange` → 401 con código falso (antes
ambos daban 404), `/health/live|ready` → 200 y `lifeos-doctor` dice «Acceso nativo disponible». Sin migración
(el `state` y los códigos de un solo uso viven en Redis). Además: entrada sin contraseña con
**«Usar la sesión que ya tengo en la web»**, útil para cuentas de Google en servidores sin el parche.

- [x] ✅ **Desplegado el parche del servidor** (30-sep-2026, copia de rollback en el CT115:
      `/root/lifeos-pre-20260930-googleauth.tgz`). Ya no hay que caer al respaldo: el botón de Google funciona.
- [ ] 🔵 Probar en vivo: **Google de punta a punta** (pulsar «Continuar con Google» en la app), ⌥Espacio con
      otra app delante, avisos reales, cola sin conexión y menú de barra. Detalle en `APPS/LIFEOS/TODO.md` §0 y §1.
- [x] ✅ **«Vincular con Google» hecho y desplegado (30-sep-2026)** — el arreglo de raíz del lío de las dos
      cuentas. Servidor: `POST /api/v1/auth/google/link` (autenticado) + retorno `lifeos://auth?linked=…` con
      `ok`/`already`/`taken`/`conflict`/`expired`; `UserResponse` gana `google_linked`. App: botón en
      **Ajustes → Sesión**. 7 tests, incluidos los dos que importan: si ese Google ya es de **otro** usuario no se
      toca nada, y si la cuenta ya tiene otra identidad no se cambia sola. Rollback del CT:
      `/root/lifeos-pre-20260930-vincular.tgz`.
- [x] ✅ **Datos trasladados a la cuenta de Google (30-sep-2026)**: `amachin.83@gmail.com` tiene ya **138
      entidades** + 13 capturas + 13 propuestas + la conexión de Google de escritura; `owner` queda vacía. Se hizo
      con `api/scripts/mover_espacio.py` (simula por defecto, se niega a mover si hay claves únicas que chocarían,
      y comprueba totales antes de confirmar), con volcado previo de las filas afectadas en
      `0_server_dorticos/backups/` y la copia completa de la base del 30-sep en el CT107.
- [x] 🟠 **F4 (menos publicar en Google)**: voz, **enviar a LifeOS** (menú Servicios, abrir ficheros, arrastrar a
      la ventana), **arranque al iniciar sesión** y preferencia para soltar ⌥Espacio, y **anillo del menú de
      barra** con lo cerrado que está el día. 128 tests offline + 195 del servidor en verde (§2).
- [ ] ⚪️ Publicar en Google Tasks/Calendar desde la app (`POST /tasks/{id}/google/publish`) — lo único que queda
      de F4.
- [ ] 🟠 Deuda: promover el atajo global a `J4SHARED`, capturas del hub con contenido real (§3).
- [ ] 🔴 **El repo del servidor tiene sin commitear lo que YA está en producción** (parche de auth, vinculación,
      herramientas de traslado). Producción ejecuta el árbol de trabajo: un `git reset` dejaría lo desplegado
      fuera del repo. Hacer los commits.
- ⚠️ **Ojo con ⌥Espacio**: JUST4DESK usa el mismo atajo global; si las dos apps están abiertas, gana la que lo
  registró primero. En LIFEOS ya se puede desactivar desde Ajustes.
- ℹ️ **Un despliegue del servidor deja ~2-3 minutos de 502** en `lifeos.perlatec.net`: `release.sh` recrea el
  stack y la web es la última en arrancar. Es normal; se comprueba después de que imprima su `compose ps`.

---

### Orden sugerido

1. **LIFEOS, lo más caliente**: `docs/design/v2-apple/` para que el dueño diga qué cambiar, y en paralelo la
   ronda de validación con datos reales (Bandeja/Capturar/Ajustes, propuesta desde ⌥Espacio, avisos, cola sin
   conexión, y decidir el ⌥Espacio compartido con JUST4DESK).
2. **LIFEOS F4 «Enviar a LifeOS»** (Servicios + drag & drop + `application(_:open:)`): es lo que cierra la app.
3. **10 min, mientras está fresco**: la validación manual que quedó de FOLDERS (`⌘L` + Return, F5–F8 con las
   teclas F reales) y el checklist del Panel Hub → tachar en `QA_LOCAL.md`.
4. **FOLDERS**: JUST4PDF F3 o los menores del Panel Hub (elegir según uso).
5. **Servidor LifeOS**: publicar `/openapi.json` en el proxy (desbloquea el cliente Swift generado) y las dos
   decisiones de producto que quedan (contraseña de las cuentas de Google, `?view=` en la web).
6. **Hub/global**: icono y assets reales cuando se acerque una demo o distribución.
7. **JUST4PICT · JUST4PDF · JUST4DESK · JUST4CONVERT**: cuando haya hueco; de esos, **DESK N6** (DMG + Quick
   Action del Finder) es el que más desbloquea.
