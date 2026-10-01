# LIFEOS — cliente nativo de macOS para LifeOS

App de macOS que habla **directamente con la API de LifeOS**. No incrusta la web ni levanta un servidor
propio: se conecta al LifeOS que ya tienes (el público o el de tu red local) y cubre el **ciclo diario**
completo: capturar → confirmar → hoy → agenda → ejecutar → diario → bandeja → buscar.

> Es la primera subapp del ecosistema que **necesita un servidor**. Sin LifeOS no funciona; a cambio, ofrece
> lo que la web no puede: atajo global, menú de barra, avisos del sistema con la app cerrada y captura que
> no se pierde sin conexión.

## Estado (30-sep-2026)

- Cliente nativo con acceso **con Google** (mismo flujo que la web) o usuario/contraseña con TOTP.
- Pantallas (⌘1…⌘8, **en este orden** en la barra lateral): **Hoy**, **Capturar**, **Diario**,
  **Agenda**, **Ejecutar**, **Buscar**, **Bandeja** y **Ajustes**. El orden de la barra lateral y
  los atajos salen del mismo sitio (`MainView.Pane.allCases`), con test que lo fija
  (`PaneOrderTests`); el 30-sep se movió el **Diario** por delante de la **Agenda** y se
  renumeraron los atajos para que se lean 1, 2, 3… de arriba abajo.
- **Diario con el ánimo y la energía en color**: la escala de 1 a 5 va de **rojo a verde**
  (`JournalScale`, con tono propio en claro y en oscuro) y el nivel elegido se **escribe** al
  lado en su color — el color refuerza, pero la palabra y el número son los que informan a
  quien no distingue el rojo del verde. Las palabras son **las mismas que la web**
  («Muy bajo…Muy bien» / «Sin energía…Mucha»).
- **Cabecera de la entrada, con aviso**: `@hora:`/`@fecha:` al principio del texto fijan la hora
  y el día de la entrada, y el compositor **avisa mientras escribes** de lo que hará («Se guardará
  como entrada de hoy a las 11:00») o de si no lo entendió. La hora vale escrita con «:»
  (`@hora:22:30`), con una o dos cifras (`@hora:22`) y **también a mano** (`@hora:1100` = 11:00,
  `@hora:830` = 8:30). Las tres reglas viven en el servidor; la app y la web las copian.
  · **Sin cabecera**, la entrada se queda con el **instante en que se escribió** (`created_at`) y se
  enseña en la hora local del dispositivo que la escribió: la hora de tu PC o tu móvil, no la del
  servidor. · **Con `@hora:`**, esa hora es la de la entrada **en la zona del dispositivo que escribe**
  (la app y la web mandan `tz`), así que `@hora:1100` son siempre las 11:00 de quien escribe, esté
  donde esté; si el cliente no manda zona (o manda una que no existe), se usa la del espacio de
  trabajo (`Europe/Madrid`), que es lo de antes. · Reabrir y guardar una entrada antigua **sí** le
  aplica la cabecera (comprobado).
- **⌥Espacio** desde cualquier aplicación abre el panel de captura.
- **Menú de barra** con las cifras del día, los próximos avisos y **el número de pendientes en el icono**.
- **Avisos del sistema** a partir de `GET /reminders/upcoming`.
- **Cola sin conexión** con clave de idempotencia: reintentar nunca duplica.
- **Voz**: grabar una nota y que la transcriba el servidor (si es privada, se guarda sin transcribir).
- **Diagnóstico del servidor** propio (`lifeos-doctor` y una tarjeta en Ajustes).
- 105 tests offline + 14 contra un servidor real, build Release y DMG validados.

Pendiente (ver `TODO.md` y `docs/ALCANCE_PENDIENTE.md`): voz, enviar texto/ficheros a LifeOS, arranque
automático; y **desplegar el parche del servidor** para el acceso con Google (ya desplegado el 30-sep-2026).

## Compilar y ejecutar

```sh
cd APPS/LIFEOS
swift build            # compila
swift run LIFEOS       # ejecuta en desarrollo (sin bundle)
swift test             # 105 tests offline (los de servidor real se saltan)
./scripts/build_dmg.sh # .app + DMG en dist/
./scripts/make_app_icon.sh   # icono del bundle (packaging/macos/AppIcon.icns)
```

`swift run` sirve para el día a día, pero **el acceso con Google necesita la app empaquetada**: la vuelta de
Google llega por el esquema `lifeos://` y eso exige un `Info.plist` (lo genera `build_dmg.sh`). Con
usuario y contraseña funciona igual en los dos casos.

`build_dmg.sh` firma el bundle con la **identidad de desarrollo** que haya en el llavero (`Apple Development: …`;
se puede forzar otra con `CODESIGN_IDENTITY="…"`). No es un detalle cosmético: con firma ad-hoc, cada
compilación produce un hash distinto y macOS considera que es **otra app**, así que vuelve a pedir permiso para
leer la sesión guardada en el llavero cada vez. Firmando por identidad, la ACL se satisface por equipo +
identificador y el aviso deja de aparecer entre compilaciones. Si algún día se distribuye el DMG fuera del Mac,
habría que firmarlo y notarizarlo con Developer ID (ver `TODO.md`).

También acepta un argumento para abrir directamente el panel de captura:

```sh
LIFEOS --quick-capture
```

## Diseño

El sistema visual **no se inventa aquí**: traduce los tokens del repo de LifeOS
(`design-system/tokens/*.json`) y su decisión **DS-018 «rediseño estilo Apple»**: paleta del sistema, acento
`#5e5ce6` (systemIndigo), radios 6/10/14/18/píldora, sombras difusas por jerarquía, tipografía del sistema con
roles y —esto sí es propio de una app de Mac— **colores dinámicos**: la app sigue la apariencia del sistema en
claro y en oscuro sin que nadie toque nada.

- `Sources/LifeOSUI/Theme.swift` — colores (claro/oscuro), espaciado, radios, sombras, tipografía y movimiento.
- `Sources/LifeOSUI/Components.swift` — tarjetas, etiquetas, campos, botones y cabeceras de pantalla.
- Regla: las vistas **no pintan colores sueltos**; eligen un componente o un token. Si falta algo, se añade ahí.

### Ver el diseño sin abrir la app

```sh
LIFEOS_RENDER_PREVIEWS=1 swift test --filter RenderPreviewsTests
```

Deja 14 imágenes en `docs/design/v2-apple/` (7 pantallas × claro y oscuro) renderizando las vistas **fuera de
pantalla**. Es la vía fiable: `screencapture` devuelve imágenes negras si la pantalla está dormida, y en este Mac
capturar por ventana o por rectángulo está bloqueado por el sistema.

Ojo con dos límites del render fuera de pantalla, ya resueltos con `\.lifeOSFlatSurfaces`:

1. Los **materiales** del sistema no se pintan → se cambia por el color de superficie.
2. Los **controles de AppKit** (campos de texto, editor, interruptores) salen como un bloque amarillo → se
dibuja su aspecto estático.

## Contra el servidor local (flujo de desarrollo)

El sitio más cómodo para trabajar es el LifeOS de tu Mac, que ya trae el flujo nativo porque el contenedor
compila este mismo código:

```sh
# 1) el servidor
cd ../0_server_dorticos/LifeOS && docker compose up -d

# 2) la app, apuntando a él y ya abierta
cd - && cd APPS/LIFEOS && ./scripts/dev_local.sh
```

`dev_local.sh` comprueba que el servidor responde, guarda `http://127.0.0.1:8000` como dirección de la app y la
lanza. Credenciales de desarrollo del compose: **`owner` / `change-me-in-dev`**.

### Tests contra un servidor de verdad

Los mismos clientes que usa la app, pero hablando con el servidor real (no hay dobles):

```sh
LIFEOS_LIVE_SERVER=http://127.0.0.1:8000 swift test --filter LifeOSLiveTests
```

Cubren sesión, cierre del día, avisos, bandeja y el ciclo completo capturar → propuesta → descartar, más la
idempotencia. **Sin** `LIFEOS_LIVE_SERVER` se saltan, así que `swift test` sigue siendo offline y determinista.
Usan un **llavero propio** (`com.dmx83.lifeos.livetests.<uuid>`): escribir en el llavero real dejaría una sesión
de verdad en el Mac de quien ejecuta los tests.

## Arquitectura

```
Sources/
├── LifeOSAPI/    red y contrato JSON (sin UI, sin AppKit)
├── LifeOSCore/   dominio local: llavero, ajustes, cola sin conexión, sesión
├── LifeOSUI/     vistas SwiftUI y tokens del sistema de diseño de LifeOS
└── LIFEOS/       ejecutable: composición, menú de barra, atajo global, avisos
Tests/
├── TestSupport/      doble de red (`URLProtocol`) compartido
├── LifeOSAPITests/   contrato: peticiones, cabeceras, decodificación, errores
└── LifeOSCoreTests/  llavero/sesión, ajustes, cola, ciclo de captura
```

Regla de dependencias: `LifeOSUI` nunca llama a la red directamente (sólo a `LifeOSAPI`), y `LifeOSApp` es
lo único que conoce `NSApplication` y `UNUserNotificationCenter`.

## El diario

Escribir el día desde el Mac, con las reglas del diario de LifeOS respetadas al pie de la letra:

- **Privado por defecto.** Cada entrada nace con sensibilidad `sensitive`, así que el servidor no la manda a
  ningún proveedor de IA externo. La app lo enseña con la etiqueta «Privado» en vez de esconderlo.
- **El texto manda.** Si la entrada empieza por `@hora:22:30` o `@fecha:20-09-2026`, de ahí salen la hora y el
  día de la entrada, aunque el cliente diga otra cosa. Por eso **no se reescribe el texto nunca**: en la
  lectura, esos tokens se enseñan aparte (arriba, en monoespaciada) y el cuerpo se lee limpio.
- **Los tokens de cabecera se interpretan igual que en el servidor.** `LifeOSAPI.JournalLeadHeader` es un
  espejo de `journal_strip_lead_tokens`: acepta `@hora:`/`@fecha:`/`@time:`/`@date:` sin distinguir
  mayúsculas, y **para en el primer token inválido**, porque lo que no se entendió como hora ni fecha es
  prosa y no se oculta. Hay un test contra el servidor real que comprueba esa paridad.
- **Título por defecto ≠ título del usuario.** Si no se escribe título, el servidor pone «Entrada del 30 de
  septiembre»; la app lo detecta (`hasUserTitle`) y muestra el texto de la entrada en la lista en vez de
  enseñar como título algo que nadie escribió.
- **Las referencias se declaran, no se adivinan.** El servidor **no** lee menciones del texto: `references[]` es la
  lista de vínculos declarados y `unresolved_references` son las que **se declararon y no se pudieron vincular**
  (destino borrado, de otro espacio o que no es acción ni evento). Escribir `@tarea:algo` a mano **no** crea el
  vínculo: para eso está el selector.
- **Selector de menciones.** Se abre solo al escribir `@…` en el texto (con espera de 220 ms, como la web) o con el
  botón «Mencionar». Busca con `GET /journal/reference-candidates` (`kinds=task,event`, `q`), inserta
  `@tarea:`/`@evento:` con la etiqueta elegida y deja la referencia vinculada. Al guardar sólo se declaran las
  referencias **cuyo token sigue escrito**: si se borra la mención, el vínculo desaparece. Las menciones escritas a
  mano que no pasan por el selector se avisan en el compositor (no se inventa el vínculo).
  *Límite conocido*: `TextEditor` no expone la posición del cursor en macOS 14, así que la detección automática mira
  el **final** del texto (que es donde se escribe el 99 % de las veces) y la inserción se hace al final. Para
  mencionar en medio de un párrafo está el botón, que es el camino que siempre funciona.
- **La sintaxis no tiene cierre**: `@tarea:` se come el resto de la línea menos la puntuación final, igual que en la
  web y en el servidor. Al **leer**, las referencias declaradas hacen de frontera (`JournalText.segments(known:)`),
  así que el chip es justo lo escrito y la frase que va detrás se lee como texto. Los detalles están en
  `Sources/LifeOSAPI/JournalText.swift`, espejo de `web/lib/journal-text.ts`, con 20 tests que fijan la regla.
- **Límites del esquema**: `target_id` ≤ 36 caracteres y `text` ≤ 240 (más → 422). La app recorta la etiqueta a 240
  para que una acción con un nombre larguísimo no rompa el guardado.
- **Borrar es reversible** (30 días en el servidor) y pide confirmación en la app.

## Agenda, Ejecutar y Buscar

Las tres pantallas que cierran el ciclo diario. Todas obeceden la misma regla: **la app no inventa nada ni
decide sola**; enseña lo que el servidor ya calculó y, cuando hay que decidir, pregunta.

- **Agenda** (`GET /agenda`): una llamada trae la **semana entera** y se lee un día, así que cambiar de día
es instantáneo. Tres carriles que no se mezclan: **citas** (eventos, con su origen de Google y su serie si
se repite), **bloques de foco** (eventos con destino) y **vencimientos** (acciones con fecha y sin hora).
Se crea y se edita una cita desde la app (`POST /events`, `PATCH /events/{id}` con `expected_version` → 409).
Y cuando una cita y una acción parecen lo mismo, el servidor devuelve el **par** y la app pregunta una vez:
«Son la misma» / «Son distintas» / «No preguntar más» (`POST /agenda/duplicates/resolve`). Nada se fusiona ni
se borra solo.
- **Ejecutar** (`GET/POST/PATCH /tasks`): las acciones agrupadas por estado, con prioridad, vencimiento,
contexto y de dónde vienen. Se completan, se reabren y se crean. Lo de Google se marca: si allí desapareció
(`missing`) o cambió en los dos sitios (`conflict`) se **dice**, no se resuelve por su cuenta.
- **Buscar y cronología** (`GET /search`, `GET /timeline`): la cronología pone en el mismo eje temporal lo que
ya existe en cada sección (diario, eventos, acciones, decisiones, métricas, capturas) con filtros de periodo
y tipo; la búsqueda devuelve el resumen con lo sensible marcado. Para editar se abre la web: **la web no tiene
rutas por sección**, así que se abre su inicio (no se inventan direcciones que darían 404).

### El `PATCH` de las acciones, con cuidado

En el servidor, **omitir un campo significa «no lo toques»** y mandar `null` significa «bórralo». Son dos cosas
distintas y confundirlas borra datos, así que en el código no es un `Int?` sino un `Patch`:

```swift
TaskUpdateRequest(priority: .set(1), dueDate: .clear, context: .set("Casa"))
// → {priority: 1, due_date: null, context: "Casa"}   (status y title no se tocan)
```

Hay tests de las dos caras (offline con el doble de red y en vivo contra el servidor real).

## Voz

En **Capturar** hay un botón de micrófono: graba en el Mac (mono, 16 kHz, m4a) y **sube la nota** a
`POST /captures/audio` para que la transcriba **el servidor**. Se hace así porque transcribir en el Mac no daba
la latencia (se midió con Whisper local y se descartó).

- **Si la nota es privada, no se transcribe.** Con «Sensible» activado el servidor guarda el audio y no lo manda
  a ningún proveedor; la app lo dice tal cual al enviarla (`stored_sensitive` + `original_preserved`).
- El audio vive en una carpeta temporal del Mac mientras se decide qué hacer con él y **se borra siempre** (al
  enviarlo, al descartarlo o si se cancela). Lo que queda guardado está en LifeOS, no duplicado en local.
- Límites: 25 MB en el servidor y 15 minutos de grabación en la app (que es mucho más de lo que se usa).
- El permiso de micrófono lo pide macOS la primera vez. Hace falta **la app empaquetada** (el permiso viaja en el
  `Info.plist`, que genera `build_dmg.sh`); con `swift run` no hay bundle y la grabación no funciona.

Validado contra el servidor local: subida real de un WAV (202 con `stored_sensitive` y el audio guardado) y
limpieza de la captura de prueba por SQL, porque **las capturas no se pueden borrar por API**.

## Enviar a LifeOS (desde fuera de la app)

La app no solo captura lo que se escribe en ella. Hay **tres puertas** para meter algo desde donde estés
trabajando, y las tres acaban en el mismo sitio: lo que se revisa y se confirma.

| Puerta | Cómo | Qué hace |
|---|---|---|
| **Servicios** | Selecciona texto → clic derecho → Servicios → **«Capturar en LifeOS»** | Abre el panel de captura con el texto y lanza la propuesta |
| **Abrir con** | Doble clic o «Abrir con → LifeOS» en un PDF, Word, texto o Markdown | Sube el documento y lo indexa |
| **Arrastrar** | Suelta ficheros, texto o enlaces **encima de la ventana** | Ficheros como documentos; texto y enlaces como anotación |

- **Un texto nunca se guarda a escondidas.** Pasa por el flujo de captura (propuesta y revisión) igual que si se
  hubiera escrito: `EvidenceIntake` decide **antes de salir a la red** qué se puede enviar, y por eso los avisos
  son frases («LifeOS guarda PDF, Word (.docx), texto y Markdown. «foto.jpg» no es de esos tipos») en vez de un
  422 del servidor.
- **Los cuatro tipos y el tamaño son los del servidor** (`.pdf`, `.docx`, `.txt`, `.md` y 20 MB;
  `POST /documents/upload`). Si un fichero no vale, se ofrece **anotar la ruta como nota**, que es mejor que
  perder el rastro.
- **Un documento repetido no es un error**: el servidor responde 409 y la app dice «ya estaba en LifeOS: no se ha
  duplicado».
- Un fichero **sensible** (según la preferencia) se guarda pero no se manda a ningún proveedor.

Qué se toca para que esto funcione: `CFBundleDocumentTypes` y `NSServices` en el `Info.plist` (los genera
`build_dmg.sh`), `SelectionReader` para leer lo que deja el menú Servicios, y `IntakeCoordinator` como única
puerta de entrada.

## Diagnóstico del servidor

Cuando algo no funciona contra un servidor que no es el de desarrollo, casi nunca es «la app está rota»: es
una **versión antigua** del servidor, una **sesión de otro servidor** o un **contrato que no encaja**. El
diagnóstico distingue esas tres cosas en vez de decir «algo falló».

Dos formas de ejecutarlo:

```sh
# En la terminal, sin abrir la app:
swift run lifeos-doctor                                  # el servidor configurado
swift run lifeos-doctor https://lifeos.perlatec.net      # otro servidor
LIFEOS_TOKEN=… swift run lifeos-doctor https://… --token-env LIFEOS_TOKEN
```

Y en la app: **Ajustes → Diagnóstico del servidor → Comprobar ahora**, con la sesión que ya tiene (no hay que
copiar ningún token). Deja un informe en `~/Library/Application Support/LIFEOS/diagnostico-servidor.txt` **sin la
sesión dentro**, para poder enseñarlo tal cual.

Qué comprueba, en orden:

1. **Dirección y salud**: que el servidor responda (`/health/ready`), con TLS y todo.
2. **Qué endpoints tiene**: lee `/openapi.json`; si no está publicado (es el caso de producción), **pregunta uno a
   uno sin sesión**, donde un `401` significa «existe, pide entrar» y un `404` «esa versión no lo tiene». Así se
   sabe qué hay al otro lado **sin credenciales**.
3. **Cómo se entra**: si existe `/api/v1/auth/native/login` (si no, la app usará usuario y contraseña como la web).
4. **La sesión**: si el token guardado vale *en ese* servidor (un token pertenece a un servidor).
5. **Cada pantalla** (nueve: cierre del día, avisos, **agenda**, bandeja, diario, candidatos de mención, acciones,
   cronología y búsqueda): pide el endpoint y comprueba **las dos cosas**, el estado y que el JSON encaje
   con los modelos de la app. Un 200 que no decodifica es el bug de verdad, y se dice cuál y por qué. La agenda es
   la única que no cabe en una URL fija (`/agenda` exige `start` y `end`), así que sus parámetros se calculan al
   vuelo y salen del mismo sitio que usa la pantalla (`APIClient.agendaQuery`): si se escribieran a mano en el
   diagnóstico, la prueba podría mentir.

Sale con código 0 si todo va bien, 1 si hay avisos y 2 si hay algo roto (`--quiet` imprime solo los problemas).

## Cómo se entra

| Vía | Cómo | Requiere |
|---|---|---|
| **Google** | `ASWebAuthenticationSession` → `/auth/google/authorize?native=true` → Google → `lifeos://auth?code=…` → `POST /auth/native/exchange` | Parche del servidor desplegado + app empaquetada |
| **Usuario y contraseña** | `POST /auth/native/login` (token en el cuerpo) | Parche del servidor desplegado |
| **Sesión de la web** | Se pega el valor de la cookie `lifeos_session` del navegador; se comprueba contra `/auth/me` antes de guardarla | Nada: funciona con el servidor de hoy |
| **Respaldo automático** | Si `/auth/native/login` no existe (404), usa `POST /auth/login` como la web y saca el token de `Set-Cookie` | Nada: funciona con el servidor de hoy |

### Vincular Google con una cuenta que ya existe

Hay un agujero que conviene conocer antes de que muerda: **entrar con Google no enlaza con una cuenta que ya
exista**. El servidor busca por `google_sub` o por `username == correo`, así que si tu cuenta de siempre tiene
otro usuario (p. ej. `owner`) te crea **una cuenta nueva y vacía** — con su propio espacio de trabajo. Pasó de
verdad el 30-sep-2026: dos cuentas, dos espacios, y los datos en el que no se veía al entrar con Google.

La otra mitad es **Ajustes → Sesión → «Vincular con Google»**: estando dentro, autorizas con Google y esa cuenta
pasa a ser la que responde a ese `sub`. Después, entrar con Google vuelve **aquí**, con tus datos. Lo que hace el
servidor (`POST /auth/google/link` + `lifeos://auth?linked=…`):

- Si esa cuenta de Google ya es de **otro** usuario → `taken`, y no se toca nada (no se puede uno quedar con la
  identidad de alguien).
- Si esta cuenta **ya tiene otra** identidad de Google → `conflict`, y tampoco se cambia sola.
- Si ya estaba vinculada a la misma → `already` (no es un error, es que no había nada que hacer).

En los cuatro casos el resultado es el mismo: un token de sesión (7 días) guardado en el **llavero** y
`Authorization: Bearer` en todas las llamadas, que la API ya aceptaba (`current_user` en el servidor).

**El usuario no siempre es el correo.** `POST /auth/login` busca por `username` **exacto** (distingue mayúsculas),
así que el campo de la app se llama «Usuario» a propósito. Matiz útil: una cuenta **creada con Google** guarda
`username = email.lower()`, de modo que en ese caso el «usuario» **sí es el correo**, en minúsculas. Si no se
sabe cuál es, está en `LIFEOS_BOOTSTRAP_USERNAME` del `.env` **del servidor** (las credenciales del `.env` local
solo valen contra el servidor local). Tras varios intentos fallidos el login responde **429**, así que conviene
no insistir a lo loco.

**Y hay cuentas sin contraseña posible.** Las creadas con Google nacen con una contraseña aleatoria que nadie
conoce, y `POST /auth/password` exige la contraseña **actual** para cambiarla; o sea que desde la web no hay
forma de ponerse una. Para esas cuentas la puerta es **«Usar la sesión que ya tengo en la web»**: entrar en el
navegador, copiar el valor de la cookie `lifeos_session` y pegarlo en la app (se pega **en la app**, nunca en
el chat ni en un correo). Se valida contra `/auth/me` antes de guardarla: una sesión que no vale no se queda
en el llavero.

Se usa `ASWebAuthenticationSession` y no una vista web propia porque Google rechaza las peticiones de
autorización hechas desde navegadores incrustados (`disallowed_useragent`); esta sesión es un navegador de
verdad y reutiliza la sesión de Safari, así que el consentimiento suele ser de un toque.

**Y ojo con los servidores sin parche**: en ellos `?native=true` se ignora, así que el servidor manda a la
**web** (no a `lifeos://auth`) y la ventana de Google se queda abierta en la consola mientras la app espera un
código que no va a llegar. Ahora la app **pregunta antes** si el servidor tiene `/auth/native/login` y, si no lo
tiene, no abre nada y lo dice claro («usa la sesión que ya tienes en la web»). Además hay un **límite de 90 s**: si la
ventana no responde, se cierra y se explica, en vez de quedarse esperando para siempre.

Comprobado contra `https://lifeos.perlatec.net` (**30-sep-2026, ya desplegado**): `/health/live` y
`/health/ready` dan 200, `POST /auth/native/login` responde 200 con `{token, expires_in, user}`,
`POST /auth/native/exchange` responde 401 «Código de canje inválido o expirado» con un código inventado (antes
ambos daban **404**) y `/auth/google/authorize?native=true` sigue dando 302. `lifeos-doctor` lo confirma:
**«Acceso nativo disponible»**.

## El parche del servidor (desplegado el 30-sep-2026)

El flujo nativo son **dos endpoints nuevos y un parámetro** en el repo de LifeOS
(`../0_server_dorticos/LifeOS`, con **188 tests verdes**):

- `POST /api/v1/auth/native/login` → `{token, expires_in, user}`
- `POST /api/v1/auth/native/exchange` → canjea el código de un solo uso del retorno de Google
- `GET /api/v1/auth/google/authorize?native=true` → hace que la vuelta sea `lifeos://auth?code=…`

Los códigos de un solo uso y el `state` viven en **Redis**, así que **no hay migración**: el parche es aditivo y
no cambia el contrato de la web.

Para desplegarlo (procedimiento completo en `deploy/README.md` del repo LifeOS): copia de seguridad del CT,
paquete limpio desde el Mac, `pct push` + extracción en `/opt/lifeos` y `bash deploy/release.sh` dentro del CT
(reconstruye api y web, aplica migraciones —ninguna nueva— y recrea el stack). Rollback: restaurar el tar
`/root/lifeos-pre-<fecha>.tgz` en `/opt` y volver a lanzar `release.sh`.

## Decisiones que conviene no deshacer

- **La captura es asíncrona en producción.** `POST /captures` responde 202 y el worker clasifica después,
  así que tras capturar hay que **sondear** `GET /captures/{id}` hasta que traiga `proposal_id`
  (`LifeOSService.awaitProposal`).
- **La propuesta se aplica por operaciones**, no entera: `POST /proposals/{id}/apply` exige `operation_ids`.
- **Nada se guarda sin confirmación.** La app nunca aplica una propuesta sola: siempre hay revisión humana.
- **La clave de idempotencia es la base de la cola offline** y por eso `createCapture` la exige.
- **Alcance acotado a propósito.** Objetivos, métricas, conocimiento, documentos, conectores de Google y
  copia portable siguen en la web; la app ofrece «Abrir en la web». No duplicar esa lógica.
- **El atajo global y el panel** siguen el patrón **G4** de JUST4DESK (`NSPanel` + Carbón
  `RegisterEventHotKey`). Hoy está copiado; cuando toque un tercer consumidor, se promueve a `PACKAGES/J4SHARED`.
- **`LIFEOS` y `com.dmx83.lifeos`**: el nombre del target, la carpeta, el binario y el `bundleId`.
- **La pantalla de arranque nunca se queda girando**: si el llavero o el servidor tardan más de 2,5 s, ofrece
  «Escribir mis datos» y deja seguir (medido: un token guardado por *otro* binario hace que macOS pida permiso
  y la lectura tarde ~7 s).
- **`GET /captures/{id}` devuelve `CaptureResponse` (sin `content`)**; el detalle completo sólo lo devuelve
  `GET /captures` (la lista). No son intercambiables.

## Límites conocidos del servidor

- `GET /api/v1/captures` devuelve **como mucho las 100 capturas más recientes** (`limit(100)` en el servidor).
  La tarjeta «Bandeja» de «Hoy» cuenta todas (ese número lo da `day-close`), así que con muchas capturas la
  lista puede mostrar menos de las que anuncia la tarjeta.
- Con `?status=…` el servidor filtra **después** de aplicar ese tope, de modo que una consulta filtrada puede
  devolver menos elementos de los que existen. La app no usa ese parámetro: pide la lista y filtra en local.

Las dos cosas son del servidor, no de la app; están anotadas en `TODO.md` para tratarlas en el repo de LifeOS.

## Privacidad

- El token vive en el llavero (`kSecAttrAccessibleWhenUnlocked`), no en `UserDefaults`.
- La marca **«Sensible»** decide antes de enviar: el servidor ya excluye lo sensible de los proveedores de
  IA externos, así que marcarlo aquí es lo que protege el contenido. El **diario** nace «Sensible» sin
  preguntar.
- La cola sin conexión guarda el texto en `~/Library/Application Support/LIFEOS/outbox.json` y se vacía al
  enviarse. Nada sale del Mac sin conexión al servidor configurado.

## Referencias

- Plan y alcance: `../../PLAN_LIFEOS_MACOS_API.md` y `../../PROPUESTA_LIFEOS_MACOS.md`
- **Qué falta por construir** (inventario y orden sugerido): `docs/ALCANCE_PENDIENTE.md`
- Documentación del producto LifeOS: `../0_server_dorticos/LifeOS/README.md`
- Skill de agente: `.github/skills/lifeos/SKILL.md`
