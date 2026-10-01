# LIFEOS — pendientes

**Estado**: F1, F2 y **F3 completas** (30-sep-2026): Hoy · Capturar · Diario · Agenda · Ejecutar · Buscar ·
Bandeja · Ajustes. Sistema visual v2 (estilo Apple), diario con selector de menciones y firma con identidad
de desarrollo.
89 tests offline + 14 en vivo verdes; DMG con icono propio; hub integrado; 34 imágenes de revisión en
`docs/design/v2-apple/`.**Leyenda**: 🟠 código · 🔵 validación manual · 🔴 bloqueado por el servidor · ⚪️ futuro

---

## 0.4) Diagnóstico del servidor (30-sep-2026)

- [x] 🟠 `lifeos-doctor`: ejecutable de terminal que comprueba dirección, salud, qué endpoints tiene el servidor
      (por `/openapi.json` o sondeando sin sesión: 401 = existe, 404 = no está), cómo se entra, si la sesión vale
      ahí y **si cada pantalla decodifica** con los modelos de la app.
- [x] 🟠 Tarjeta «Diagnóstico del servidor» en Ajustes, con la sesión de la app e informe en
      `~/Library/Application Support/LIFEOS/diagnostico-servidor.txt` (sin la sesión dentro).
- [x] 🟠 6 tests del ejecutable + 6 de las sondas (contrato roto, 404, sin conexión, y que la sonda de existencia
      **no** manda la sesión).
- [x] ✅ **Contra producción con sesión (30-sep-2026): «todo bien», las 9 pantallas decodifican.**
      `lifeos-doctor https://lifeos.perlatec.net --token-env …` con la cuenta `owner`: perfil, cierre del día,
      avisos, **agenda**, bandeja, diario, candidatos de mención, acciones, cronología y búsqueda. Además el
      login con Google **funciona ya de punta a punta** (la app entró como «Andy Machin»).
- [x] ❓ No hay una «prueba que falte» para dar el visto bueno al online: **ya está dado** (ver arriba).
      Queda la prueba de campo: usar la app un día entero y ver qué se rompe.
- [x] 🟠 La **Agenda estaba fuera del diagnóstico** (existía en `requiredPaths`, pero no se comprobaba su
      decodificación): era la única pantalla a la que no le vale una URL fija, porque `GET /agenda` exige
      `start` y `end`. Se añadió con un `queryProvider` que calcula la semana al vuelo, y los parámetros salen de
      `APIClient.agendaQuery` (el mismo sitio que usa la pantalla), con 2 tests de regresión. Ya salen las 9.

## 0.3) Diario (30-sep-2026)

- [x] 🟠 **El ánimo y la energía, en color (petición del dueño, 30-sep noche)**: la escala de 1 a 5 va de
      **rojo a verde** (`JournalScale`, con tono propio en claro y en oscuro; los extremos reutilizan los
      tokens `danger` y `positive`). Decisiones que van con el color: los puntos **sin elegir** llevan el
      anillo de su color, así la escala se lee entera incluso sin valor (leyenda); el nivel elegido se
      **escribe** al lado en su color; y cada punto lleva palabra + número en el `help`/lector de pantalla
      («Ánimo 4 de 5: Bien»). El color es refuerzo, nunca el único canal: rojo y verde es justo el par que
      no distingue ~8 % de los hombres. Las **palabras son las de la web** (`MOOD_LABELS`/`ENERGY_LABELS`).
      También en la fila de la entrada (punto de color + «ánimo 4/5»). 9 tests (`JournalScaleTests`) y
      revisión visual en claro y oscuro (`docs/design/v2-apple/*-journal-escala.png`).
- [x] 🟠 **Reordenación de la barra lateral (petición del dueño)**: el **Diario** pasa por delante de la
      **Agenda** → `Hoy, Capturar, Diario, Agenda, Ejecutar, Buscar, Bandeja, Ajustes`. El orden y los
      atajos salen de `MainView.Pane.allCases`, así que se **renumeraron los ⌘1…⌘8** para que la barra se
      lea de arriba abajo sin saltos (antes el Diario era ⌘5 y habría quedado 1, 2, 5, 3, 4). El `rawValue`
      guardado en `lifeos.lastPane` no cambia. Test de regresión: `PaneOrderTests`.
- [x] 🟠 **`@hora:1100` = 11:00 (incidencia real del dueño, 30-sep noche)**: escribió «@Time:1100 fui a
      pelarme» y no pasaba nada — el token quedaba en el texto y la entrada se guardaba con la hora del
      momento (en su lista, las **23:05**). La causa: los tres parsers (servidor, web y app) sólo aceptaban
      1–2 cifras como hora pelada. Ahora una hora escrita **a mano** (3–4 cifras: `1100` → 11:00, `830` →
      8:30) vale, y **sólo con prefijo de hora**: `@fecha:1100` sigue sin ser nada. Cambia en
      `api/app/main.py` (`journal_parse_lead_value(value, kind)` + `JOURNAL_TIME_KINDS`), en
      `web/lib/journal-text.ts` (`parseLeadValue(value, kind)`) y en `JournalLeadHeader.classify(_:kind:)`.
- [x] 🟠 **El compositor avisa de lo que hará la cabecera, mientras escribes**: sin ese aviso, un token mal
      escrito no cambia nada y parece que el diario ignora lo que escribes. Los tres estados, como en la
      web: **se entendió** («Se guardará como entrada de hoy a las 11:00»), **no se entendió** («No entiendo
      «X» como hora ni como fecha…» + cómo se escribe) y **no hay cabecera** (la pista del principio:
      `@hora:22:30`, `@hora:2230` o `@fecha:20-09-2026`). Previsualización del caso real en
      `docs/design/v2-apple/*-journal-cabecera.png`.
- [x] 🟠 **La hora del token es la del dispositivo que escribe (`tz`)**: `@hora:1100` desde Nueva York son
      las 11:00 de Nueva York, no las de Madrid. Cambio **aditivo** en los tres lados: el servidor acepta
      `tz` (nombre IANA, ≤64) en alta y edición y lee la cabecera con esa zona (`journal_zone_name`, cae a
      la del espacio si falta o no existe); la app manda `TimeZone.current.identifier`; la web, la del
      navegador. Los servidores viejos **ignoran** el campo (pydantic no prohíbe extras), así que la app
      puede mandarlo desde ya. Verificado de punta a punta contra el servidor local: `tz=America/New_York`
      → `2026-10-01T11:00:00-04:00`; zona inventada → `+02:00` (Madrid); PATCH con `tz` → también. Tests:
      24 del diario en el servidor (2 nuevos) y 22 en la app (1 nuevo).
- [x] ✅ **Desplegado en producción y verificado por el dueño (1-oct-2026)**: release en CT115 (build de api y web,
migraciones, recreación del stack), `/health/live`, `/health/ready` y `/` a 200, y `lifeos-doctor` con sesión
→ **«todo bien»** (las nueve pantallas decodifican). Copia de rollback: `/root/lifeos-pre-20261001.tgz`.
El dueño **editó la entrada de «fui a pelarme» y le puso la hora: funcionó**. Notas del procedimiento y del
post-chequeo (4 contenedores sin reinicios, discos al 21 % y 31 %, backups diarios al día) en el skill del repo.
- [x] 🟠 `JournalModels.swift`: contrato del diario (entrada, referencias, candidatos, altas y ediciones).
- [x] 🟠 `APIClient` + `LifeOSService` + `LifeOSModel`: listar, crear, editar, borrar y candidatos.
- [x] 🟠 Pantalla **Diario** (⌘3) con compositor (título opcional, texto, ánimo y energía), entradas agrupadas
      por día (Hoy / Ayer / fecha), lectura al desplegar, editar y «A la papelera» con confirmación.
- [x] 🟠 La tarjeta «Diario» de **Hoy** cuenta las entradas de hoy (no las de la última entrada escrita) y abre
      la pantalla al pulsarla.
- [x] 🟠 Paridad con el servidor en la **cabecera del texto**: `JournalLeadHeader` copia
      `journal_strip_lead_tokens` (`@hora:`/`@fecha:`/`@time:`/`@date:`, sin distinguir mayúsculas) y **para en
      el primer token inválido**. En lectura los tokens se enseñan aparte y el cuerpo se lee limpio.
- [x] 🟠 Corregido: el título por defecto del servidor («Entrada del 30 de septiembre») ya **no tapa el texto**
      en la lista ni aparece en el campo de título al editar (`hasUserTitle`).
- [x] 🟠 Corregido: en un `PATCH`, omitir un campo significa «no lo toques», así que **quitar el ánimo o la
      energía no funcionaba**. Ahora se mandan como `null` explícito.
- [x] 🟠 Fechas y contenido: `entry_date` es un día (`2026-09-30`), no un instante.
- [x] 🟠 9 tests de contrato + 2 en vivo (ciclo completo con borrado real y paridad de la cabecera).
- [x] 🔵 **Revisión visual del diario** (dos esquemas): botón principal deshabilitado en gris inerte (antes
      parecía pulsable), «A la papelera» en rojo, hora del chip desde `@hora:`.
- [x] 🟠 **Selector de menciones** `@tarea:`/`@evento:` con `GET /journal/reference-candidates`: se abre al
      escribir `@…` o con el botón «Mencionar», inserta el token y deja la referencia vinculada. Al guardar sólo
      se declaran las referencias cuyo token sigue escrito (si se borra la mención, el vínculo desaparece).
- [x] 🟠 `JournalText` (espejo de `web/lib/journal-text.ts`): tokens, segmentos para leer las menciones como
      etiquetas, menciones sin vincular y detección de `@…` mientras se escribe. 20 tests fijan la regla.
- [x] 🟠 Corregido: `unresolved_references` **no** son «menciones escritas sin selector» (eso es local), son
      referencias declaradas que no se pudieron vincular. El aviso de la app decía lo que no era.
- [x] 🟠 Corregido: la etiqueta se recorta a 240 caracteres y el id del test a 36, que es lo que acepta el
      esquema (más → 422).
- [x] 🔵 **Revisión visual**: compositor con texto y referencias (`*-journal-draft`) y panel del selector
      (`*-journal-picker`).
- [ ] ⚪️ Diario: buscar entradas, exportar y racha de días escritos.

---

## 0.2) Rediseño visual v2 (30-sep-2026)

- [x] 🟠 `Theme.swift` + `Components.swift`: tokens del sistema de diseño de LifeOS y de **DS-018 (estilo Apple)**:
      acento `#5e5ce6`, radios 6/10/14/18/píldora, sombras difusas, roles tipográficos y **colores dinámicos**
      (claro y oscuro siguiendo al sistema, no un tema oscuro fijo).
- [x] 🟠 Reescritura de las seis pantallas + menú de barra con el sistema nuevo (cabeceras con eyebrow,
      tarjetas con borde de un pelo, píldoras, campos con anillo de foco propio, estados vacíos cuidados).
- [x] 🟠 Icono propio del bundle (`scripts/make_app_icon.sh` → `packaging/macos/AppIcon.icns`).
- [x] 🟠 Imágenes de revisión renderizadas fuera de pantalla (`RenderPreviewsTests`, 34 imágenes).
- [x] 🟠 La app recuerda la última sección; `--appearance light|dark` para revisar los dos temas.
- [x] 🔵 **Revisión visual hecha (30-sep, por el agente)**: encontrado y corregido:
      ① la marca parecía un botón de grabar (aro invisible) → aro marcado;
      ② el botón de Google salía con la etiqueta a la izquierda y «Entrar» pequeño y centrado →
      Google centrado y el principal a ancho completo;
      ③ los bloques del panel salían centrados por falta de alineación → panel en `.leading`;
      ④ en oscuro «operación elegida» y «no elegida» se veían iguales → `brandSoft` con tinte violeta;
      ⑤ el compositor era un blanco sobre blanco → ahora es un hueco hundido (`elevated`) con anillo sólo al enfocar;
      ⑥ títulos de pantalla de 28 a 24 pt (demasiado peso para uso diario) y el atajo ⌘↩ junto a su botón.
- [ ] 🔵 **Revisión del owner**: mirar `docs/design/v2-apple/` y decir qué cambiar.
- [ ] ⚪️ Animación de entrada de la propuesta y del panel de captura (hoy sólo transiciones suaves).
- [ ] ⚪️ Icono del menú de barra con la cifra de capturas pendientes.

## 0) Hecho en la ronda del servidor local (30-sep-2026)

- [x] 🟠 `Tests/LifeOSLiveTests`: 9 pruebas contra un servidor real (sesión, cierre del día, avisos, bandeja,
      ciclo capturar → propuesta → descartar, idempotencia y diario). Se saltan sin `LIFEOS_LIVE_SERVER`.
- [x] 🟠 `scripts/dev_local.sh`: apunta la app al LifeOS local y la lanza (con comprobación previa del servidor).
- [x] 🟠 Bug corregido: `GET /captures/{id}` devuelve `CaptureResponse` (sin `content`), no `CaptureDetailResponse`.
      El cliente lo pedía con el tipo equivocado; lo cazó el test en vivo.
- [x] 🟠 Bug corregido: los tests en vivo escribían en el **llavero real** (la app encontraba esa sesión al
      abrirse). Ahora usan un llavero propio por prueba y lo borran al terminar.
- [x] 🟠 La pantalla de arranque ya no se queda girando: a los 2,5 s ofrece «Escribir mis datos».
- [x] 🟠 La app recuerda la última sección abierta (`mainView` + `lifeos.lastPane`).
- [x] 🟠 `build_dmg.sh` firma con la identidad de desarrollo del llavero (no ad-hoc): con ad-hoc, cada
      recompilación invalidaba la ACL del llavero y macOS volvía a pedir permiso para leer la sesión guardada.
      Verificado: la *designated requirement* es idéntica entre dos compilaciones seguidas.
- [ ] ⚪️ Firmar y notarizar el DMG con Developer ID si se distribuye fuera de este Mac (Apple Development sólo
      vale en máquinas con ese certificado).

## 0.1) Traslado al repo de LifeOS (hallazgos del servidor, no de la app)

- [ ] 🟠 `GET /api/v1/captures` limita a **100** filas antes de filtrar; con `?status=…` devuelve menos de lo que
      existe. Arreglo: filtrar en SQL antes del tope y exponer `limit`/`offset`.- [x] 🟠 La app avisa cuando la bandeja llega al tope de 100 capturas del servidor.
- [ ] ⚪️ `DELETE` de capturas: hoy no existe (las capturas no son entidades, así que `/entities/{id}` da 404).
- [ ] 🔴 **Las cuentas creadas con Google no pueden tener contraseña** (hallazgo del servidor):
      `find_or_create_google_user` las crea con una contraseña aleatoria y `POST /auth/password` pide la
      **actual**, así que no hay forma de ponerse una ni desde la web. Opciones: dejar fijar la primera
      contraseña a quien entra por Google y no tenía ninguna, o un «¿olvidaste la contraseña?» por correo.
      Mientras no se arregle, en la app se entra con **«Usar la sesión que ya tengo en la web»**.
- [x] ✅ **Ya se puede vincular Google con una cuenta que existe** (30-sep-2026): `POST /api/v1/auth/google/link`
      (autenticado) devuelve la URL de Google con un `state` que lleva el identificador de usuario dentro, y el
      retorno (`lifeos://auth?linked=…`) puede decir `ok`, `already`, `taken`, `conflict` o `expired`. En la app:
      **Ajustes → Sesión → «Vincular con Google»**. Reglas de seguridad con test: si ese Google ya es de otro
      usuario **no se toca nada** (`taken`) y si la cuenta ya tiene otra identidad **no se cambia sola**
      (`conflict`). 7 tests, y `UserResponse` gana `google_linked` para que la app sepa si ya está vinculada.
      Copia de rollback del CT: `/root/lifeos-pre-20260930-vincular.tgz`.
- [x] ✅ **Resuelto (1-oct-2026)**: el árbol de trabajo del servidor está **commiteado** (`9b7f1cc5` en
      `feat/lifeos-apple-design`: parche del flujo nativo, tests y las dos herramientas de espacios) y las
      notas del despliegue (`4cad6771`); los dos commits están **publicados** en `origin`. Producción ya
      ejecuta exactamente lo que está en el repo.
- [ ] 🟠 **En producción no está publicado `/openapi.json`** (404, con el resto de la API viva): el diagnóstico
      tiene que sondear endpoint por endpoint en vez de leer el contrato. Se arregla en el proxy (NPM) o
      habilitando el documento; sirve también para cualquier cliente.
- [ ] 🔵 Decidir si la web admite `?view=` (o rutas) para que «Abrir en LifeOS» lleve a la sección y no solo al
      inicio: hoy es una sola página sin rutas.

## 0.4) Cómo se entra: credenciales y sesión (30-sep-2026)

> El diagnóstico del servidor (hecho y verificado contra producción) está en el §0.4 de arriba; esto es lo que
> se averiguó sobre las cuentas y las puertas de entrada.

- [x] 🟠 Averiguado **cómo se entra** en producción (30-sep-2026, leyendo el servidor y probando contra local):
      `POST /auth/login` busca por **`username` exacto** (sin `lower()`, y tras varios fallos da 429); una cuenta
      **creada con Google** guarda `username = email.lower()`, así que ahí el usuario **sí es el correo** en
      minúsculas. `POST /auth/password` exige la contraseña **actual** (+ MFA) y borra todas las sesiones; las
      cuentas creadas con Google nacen con una contraseña aleatoria que nadie conoce, así que **no pueden ponerse
      una desde la web**. En local se comprobó que el valor de la cookie `lifeos_session` vale también como
      `Authorization: Bearer` (200 en `/auth/me`), que es lo que hace posible la vía de abajo. Ojo:
      `X-LifeOS-Session` **no** sirve como credencial (el servidor lo emite fuera de producción, pero
      `current_user` solo lee el `Bearer` o la cookie).
- [x] 🟠 Nueva vía de entrada **«Usar la sesión que ya tengo en la web»**: se pega el valor de `lifeos_session`
      en la app y se valida contra `/auth/me` antes de guardarla en el llavero (3 tests). Resuelve el caso
      «cuenta de Google en un servidor sin parche», donde no hay contraseña que teclear.

## 1) Para que funcione del todo

- [ ] 🔵 **Iniciar sesión a mano en la app contra el servidor local** (`owner` / `change-me-in-dev`) y recorrer
      Bandeja, Capturar y Ajustes con datos reales.
- [x] ✅ **Traslado hecho (30-sep-2026): los datos de `owner` están ya en la cuenta de Google.**
      `amachin.83@gmail.com` → **138 entidades** (72 tareas, 21 eventos, 19 áreas, 17 objetivos, 8 diario),
      13 capturas, 13 propuestas, 131 actividades, 43 sincronizaciones y la conexión con Google de
      **escritura**. `owner` queda **vacía** (sigue existiendo: entrar con su contraseña da un LifeOS en blanco).
      Verificado con la API y una sesión temporal: las siete pantallas responden 200 y no hay huérfanos ni
      relaciones cruzando espacios. Herramienta: `api/scripts/mover_espacio.py` (simula por defecto, se niega a
      mover si hay claves únicas que chocarían). Copia de las filas afectadas:
      `0_server_dorticos/backups/copia-espacios-20260930-espacios.tgz`; copia completa de la base:
      `/var/backups/lifeos/lifeos-20260930T024236Z.dump.enc` (CT107).
- [ ]  Provocar una **propuesta** desde el panel ⌥Espacio y confirmarla/descartarla desde la app.
- [ ] 🔵 Probar los **avisos del sistema**: crear una acción con recordatorio a pocos minutos y comprobar que
      suena con la app en segundo plano.
- [ ] 🔵 Probar la **cola sin conexión**: capturar con el contenedor parado, cerrar la app, levantarlo y ver que
      sale sola y sin duplicar.
- [ ] 🔵 Confirmar que el menú de barra muestra las cifras del día.
- [x] ✅ **Parche del servidor DESPLEGADO en producción (30-sep-2026)**. Antes: `POST /auth/native/login` y
      `/auth/native/exchange` → 404 (por eso Google se quedaba colgado). Ahora: `native/login` → 200 con
      `{token, expires_in: 604800, user}`, `native/exchange` → 401 «Código de canje inválido o expirado» con un
      código inventado, `/health/live` y `/health/ready` → 200, web → 200, y `lifeos-doctor` dice
      **«Acceso nativo disponible»**. Sin migraciones (el `state` y los códigos de un solo uso van a Redis).
      Copia de rollback en el CT115: `/root/lifeos-pre-20260930-googleauth.tgz`.
- [ ] 🔵 Comprobar el atajo **⌥Espacio** con otra app en primer plano (JUST4DESK usa el mismo: gana quien lo
      registró primero).

## 2) F3 — el resto del ciclo diario (30-sep-2026: **cerrada**)

- [x] 🟠 **Agenda**: `GET /agenda` (una llamada trae la semana), los tres carriles (citas, bloques de foco,
      vencimientos), filtro por origen, crear/editar cita y **decidir los pares acción+evento**
      (`POST /agenda/duplicates/resolve`).
- [x] 🟠 **Ejecutar**: `GET /tasks`, crear, completar, reabrir y cambiar estado con menú, con el `Patch`
      explícito para no borrar datos al editar (`due_date: null` sólo cuando se pide).
- [x] 🟠 **Diario**: `GET/POST/PATCH /journal`, modo lectura, edición y borrado con confirmación (ver §0.3).
- [x] 🟠 **Buscar y cronología**: `GET /search` y `GET /timeline` con filtros de periodo y tipo.
- [x] 🟠 11 tests de contrato + 6 del cálculo de intervalos + 4 en vivo (cita creada/editada/borrada con su 409,
      acción completada y reabierta, agenda, búsqueda y cronología).
- [ ] 🟠 Probar los modelos Swift generados desde `/openapi.json` (`swift-openapi-generator`) antes de que el
      subconjunto crezca más: con 100 esquemas, a mano es deuda garantizada.

## 2) F4 — voz, ficheros y presencia (30-sep-2026: **casi cerrada**, queda publicar en Google)

- [x] 🟠 **Voz**: grabar con `AVFoundation` (mono 16 kHz, m4a) y subir a `POST /captures/audio` (multipart
      construido a mano, con test del formato). La transcribe el servidor; si es sensible, se guarda sin
      transcribir y la app lo dice. Permiso de micrófono en el `Info.plist`. 5 tests de contrato + validación
      real contra el servidor local.
- [x] 🟠 **Enviar a LifeOS** (30-sep-2026): menú **Servicios** («Capturar en LifeOS»), **abrir ficheros** con la app
      (`application(_:open:)`, con `CFBundleDocumentTypes` en el `Info.plist`) y **arrastrar a la ventana**
      (ficheros, texto y enlaces). `EvidenceIntake` decide antes de salir a la red qué se puede enviar y con qué
      mensaje, con 14 tests (incluido el caso de «pesa 21 MB y el máximo son 21 MB», que salió al probarlo).
- [x] 🟠 **Arranque al iniciar sesión** (`SMAppService`, con su interruptor en Ajustes) y **preferencia para no
      registrar ⌥Espacio** (estaba guardada pero **no se usaba**: el atajo se registraba siempre; ahora se
      registra y se suelta en caliente).
- [ ] ⚪️ Publicar en Google Tasks/Calendar desde la app (`POST /tasks/{id}/google/publish`).
- [x] 🟠 **Anillo del menú de barra**: la marca lleva un anillo con lo cerrado que está el día (cerradas sobre el
      total), en naranja cuando hay algo esperando, y el número de capturas pendientes al lado.

## 3) Deuda técnica conocida

- [ ] 🟠 **Promover el atajo global y el panel a `PACKAGES/J4SHARED`**: hoy están copiados de JUST4DESK (G4).
      Al tercer consumidor, se comparte.
- [x] 🟠 **Icono propio**: `packaging/macos/AppIcon.icns` existe (lo genera `scripts/make_app_icon.sh`) y
      `build_dmg.sh` lo mete en el bundle con `CFBundleIconFile`.
- [ ] 🟠 **Capturas del hub**: `screen-1`/`screen-2` son reales pero de la puerta de entrada y del panel de
      captura. Refrescar con pantallas con contenido real (Hoy, propuesta de captura, diario) tras el primer uso.
- [x] 🟠 **Avisos de concurrencia de Swift 6**: `@preconcurrency import UserNotifications`; la compilación sale
      sin avisos.
- [ ] ⚪️ **Notarización**: la app ya se firma con la identidad de desarrollo (ver §0). Si el DMG sale de este
      Mac, habría que firmarlo y notarizarlo con Developer ID (el resto de la suite tampoco lo está).

## 4) Ideas aparcadas (no ahora)

- [ ] ⚪️ Vista hoy en el Dock con el progreso del día.
- [ ] ⚪️ Reglas de «no molestar» por franja horaria para los avisos.
- [ ] ⚪️ Publicar la app en el menú de compartir de macOS («Compartir → LifeOS»).
- [ ] ⚪️ Modo «sólo lectura» para consultar sin poder capturar.
