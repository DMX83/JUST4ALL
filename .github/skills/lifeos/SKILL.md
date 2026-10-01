---
name: lifeos
description: Use when working on LIFEOS (APPS/LIFEOS): the native macOS client that talks to the LifeOS API (capture with reviewable proposals, «Hoy», inbox, ⌥Espacio quick capture, menu bar, system notifications, offline outbox). Covers the API contract facts that bite (async classification, per-operation apply, Idempotency-Key), the native auth flow (Google via ASWebAuthenticationSession + lifeos:// scheme, /auth/native/* endpoints and the classic-login fallback), build/test/DMG commands inside a JUST4ALL hub context, and the scoped-product rules (what belongs in the web, not here). Trigger words: LIFEOS, LifeOS Mac, LifeOS app, lifeos.perlatec.net, captura rápida, propuesta, bandeja, outbox, sin conexión, /auth/native, lifeos://, ASWebAuthenticationSession, DayClose, day-close, reminders, LifeOSAPI, LifeOSCore, LifeOSUI, LIFEOS bundle, com.dmx83.lifeos.
---

# LIFEOS — cliente nativo de macOS para LifeOS

App de macOS (SwiftUI, SPM) que **consume la API de LifeOS**. Vive en `APPS/LIFEOS` de JUST4ALL, pero el
producto y su servidor están en otro repo: `/Users/dmx83/Repos/0_server_dorticos/LifeOS`.

## Reglas que no se negocian

1. **Alcance acotado.** Aquí sólo el ciclo diario: capturar → confirmar → Hoy → bandeja → ajustes. Objetivos,
   métricas, conocimiento, documentos, decisiones, conectores de Google, copia portable y onboarding son de la
   **web**; la app ofrece «Abrir en la web». No duplicar esa lógica sin decisión explícita del owner.
2. **Nada se guarda sin confirmación humana.** La app nunca aplica una propuesta sola.
3. **La app necesita servidor.** Es la única subapp de JUST4ALL que no funciona sola: declararlo siempre en
   requisitos, tarjeta del hub y documentación.
4. **`LIFEOS` / `com.dmx83.lifeos`** para target, carpeta, binario y bundle. Carpeta `APPS/LIFEOS`.
5. **No tocar `ReleaseStore` ni el modelo de distribución del hub**: al ser app nativa con DMG, cumple el
   contrato tal cual (basta la entrada en `SubAppsCatalog.items`).

## Hechos del contrato de la API (verificados, 30-sep-2026)

| Hecho | Consecuencia |
|---|---|
| `current_user` acepta `Authorization: Bearer` **o** cookie `lifeos_session` | El cliente nativo usa Bearer; no depende de cookies |
| `POST /captures` responde **202** y en producción encola a Celery | Hay que **sondear** `GET /captures/{id}` hasta que traiga `proposal_id` (`LifeOSService.awaitProposal`) |
| `POST /captures` soporta **`Idempotency-Key`** (≤200) | Es la base de la cola sin conexión: reintentar no duplica. `createCapture` **exige** la clave |
| `POST /proposals/{id}/apply` exige **`operation_ids`** | Se aplica por operaciones, no todo o nada |
| Las operaciones son `{id: "op-N", operation, entity_kind, after{…}, confidence, dependencies, warnings}` | `after` es JSON libre por tipo de entidad → se decodifica con `JSONValue` |
| La captura puede traer `clarifying_question` / `manual_kind` | Hay flujo de aclaración (`PATCH /captures/{id}`) |
| `GET /day-close` y `GET /reminders/upcoming` ya vienen calculados (`at`, `remind_at`) | La app **no** reinterpreta fechas; sólo las pinta |
| **`GET /captures/{id}` devuelve `CaptureResponse` (sin `content`)**; el detalle completo sólo lo da `GET /captures` | `captureStatus(id:)` devuelve `CaptureSummary`; `inbox()` usa `CaptureDetail`. No son intercambiables |
| `GET /captures` limita a **las 100 más recientes** antes de filtrar, y con `?status=` filtra en Python **después** del tope | Con muchas capturas, la lista puede mostrar menos de las que cuenta la tarjeta «Bandeja» (ese número lo da `day-close`). La app no usa `?status=` |
| Las capturas **no son entidades**: `DELETE /entities/{id}` da 404 | No hay borrado de capturas por API (para limpiar pruebas hace falta SQL) |
| Las entradas de diario **sí son entidades**: `DELETE /entities/{id}` borra (reversible 30 días) | Los tests en vivo se limpian solos; la app pide confirmación antes |
| `GET/POST /journal`, `GET/PATCH /journal/{id}`; `entry_date` es un **día** (`"2026-09-30"`), no un instante | `JournalEntry.entryDate` es `String`; se agrupa por ese día, no por `createdAt` |
| El diario nace con sensibilidad **`sensitive`** | Es privado por defecto: el servidor no lo manda a proveedores de IA |
| El PATCH usa `model_dump(exclude_unset=True)`: **omitir un campo = no tocarlo** | Para *quitar* ánimo/energía hay que mandar `null` explícito (lo hace `JournalUpdateRequest.explicitNulls`) |
| `expected_version` en el PATCH → **409** si la entrada cambió | Control optimista; la app lo explica en vez de pisar el cambio |
| La cabecera del texto manda: `@hora:22:30` / `@fecha:20-09-2026` (también `@time:`/`@date:`, sin distinguir mayúsculas) fijan hora y día; `journal_strip_lead_tokens` **para en el primer token inválido** | El texto **no se reescribe nunca**; `JournalLeadHeader` es el espejo en Swift y los tokens se enseñan aparte al leer |
| **La hora escrita «a mano» también vale** (30-sep-2026): `@hora:1100` = 11:00 y `@hora:830` = 8:30, además de `@hora:22` y `@hora:22:30`. La regla **sólo aplica a los prefijos de hora** (`hora`/`time`): `@fecha:1100` sigue sin ser nada. El valor se recorta a los extremos raros como siempre (1175 → 75 minutos → inválido) | La regla vive en **tres** sitios que van juntos: `api/app/main.py` (`journal_parse_lead_value(value, kind)` + `JOURNAL_TIME_KINDS`), `web/lib/journal-text.ts` (`parseLeadValue(value, kind)`) y `JournalLeadHeader.classify(_:kind:)` en la app. Y **sólo el servidor aplica la hora**: sin desplegarlo, la app avisa y oculta el token pero la entrada se guarda con la hora del momento |
| El compositor del diario **avisa de lo que hará la cabecera** mientras se escribe (los tres estados: se entendió / no se entendió / no hay cabecera) | Es el mismo aviso que la web (`journal-view.tsx`). Sin él, un token mal escrito no cambia nada y parece que el diario «ignora» lo que escribes (pasó con «@Time:1100»). `JournalLeadHeader.schedule(in:)` devuelve los números; el texto y el idioma son de la vista |
| La hora del token se lee en la zona de **quien escribe**: las tres partes aceptan/mandan `tz` (nombre IANA) — app `TimeZone.current.identifier`, web `Intl.DateTimeFormat().resolvedOptions().timeZone`, servidor `journal_zone_name(payload.tz, workspace.timezone)` (cae a la del espacio si falta o no existe) | Verificado e2e contra el servidor local: `tz=America/New_York` + `@hora:1100` → `2026-10-01T11:00:00-04:00`; zona inventada → `+02:00` (Madrid). El campo es **aditivo** (pydantic no prohíbe extras) ⇒ un servidor viejo lo ignora y no rompe: la app puede mandarlo antes de desplegar |
| Verificado **de punta a punta con el servidor local** (1-oct-2026, `uvicorn --reload` monta `./api`): `@Time:1100` → `occurred_at: 2026-10-01T11:00:00+02:00`; sin cabecera → `occurred_at: null` (la app enseña `created_at`, formateado en la **zona del dispositivo** — `TimeFormatting` no fija `timeZone`); y **re-guardar** una entrada antigua (PATCH) **sí** le aplica la cabecera | La hora del token se compone con la zona que manda el cliente (ver fila de `tz`), no con la del servidor |
| El servidor local se prueba con `docker compose up -d` + login `owner` / `change-me-in-dev` en `http://127.0.0.1:8000`; las entradas de diario de prueba **se borran** con `DELETE /api/v1/entities/{id}` (reversible 30 días) | `pip install -r requirements.txt && uvicorn --reload` dentro del contenedor: los cambios de `api/app/*.py` entran **en caliente**, sin reconstruir nada |
| Sin título, el servidor pone «Entrada del 30 de septiembre» | `JournalEntry.hasUserTitle` lo detecta: no se enseña como título ni se precarga al editar |
| Las referencias `@tarea:`/`@evento:` **no se deducen del texto**: se declaran aparte (`references`), y las que no se pudieron vincular vuelven en `unresolved_references` | La app avisa de las no resueltas; falta el selector con `GET /journal/reference-candidates` |
| `unresolved_references` = declaradas que **no se pudieron vincular** (destino borrado, de otro espacio, o que no es acción ni evento). NO significa «menciones escritas sin selector» | El aviso local de menciones a mano sin vincular se calcula en el cliente; el del servidor es otra cosa (costó un aviso mal redactado) |
| `JournalReferenceIn`: `target_id` ≤ **36** y `text` ≤ **240** (más → **422**) | Recortar la etiqueta antes de enviar; un nombre larguísimo no debe romper el guardado |
| La sintaxis de mención no tiene cierre: `@tarea:` se come el resto de la línea menos la puntuación final | `web/lib/journal-text.ts` es la referencia: `segments` (chips), `plainText`, `unlinkedMentions`. `JournalText.swift` es el espejo, y al leer usa las referencias declaradas como frontera |
| **`POST /captures/audio`** es `multipart/form-data`: `file` + `sensitivity` + `language`; responde **202** con `{id, status, transcript?, original_preserved}`. Máximo **25 MB** (413 si se pasa, 422 si el audio está vacío) | El multipart se construye a mano (`MultipartFormData`) y tiene test del formato: boundary, `\r\n` y nombre del fichero |
| Con **`sensitivity=sensitive`** el audio se guarda y **NO se transcribe** (`status: stored_sensitive`, `transcript: null`) | Es la regla de privacidad del producto; la app lo dice antes y después. Es además la ruta **determinista** para probar contra el servidor |
| Sin ser sensible, la transcripción va al MCP Hub (`/v1/audio/transcriptions`); si falla, `status: transcription_failed` | Sin hub configurado en local, lo normal es que la transcripción falle: el audio se guarda igual |
| Grabar requiere `NSMicrophoneUsageDescription` en el `Info.plist` (lo genera `build_dmg.sh`) y **app empaquetada** | Con `swift run` no hay bundle: la grabación no funciona. La transcripción la hace el servidor, nunca el Mac |
| En un servidor **sin el parche**, `?native=true` se ignora: el callback de Google va a la **web** (no a `lifeos://auth`), así que la ventana queda abierta en la consola y la app espera para siempre | La app **comprueba antes** si existe `/auth/native/login` (un 404 = no abrir nada y decirlo) y tiene **límite de 90 s**; sin eso, «le di a Google y se quedó ahí» (pasó el 30-sep contra producción) |
| Rate limit de login: 5 intentos / 300 s → bloqueo 900 s | Hay que mostrar el 429 tal cual |
| **Producción (`lifeos.perlatec.net`) ya tiene el parche** (desplegado 30-sep-2026): `/auth/native/login` → 200, `/auth/native/exchange` → 401 con código falso, `/health/live|ready` → 200. Antes daba 404. No publica `/openapi.json` (404) pero sí toda la API | Para saber qué tiene un servidor: sondear **sin sesión** — `401` = existe, `404` = no está, `405` = existe y solo acepta POST, `422` = existe y valida el cuerpo. Es la base de `lifeos-doctor` |
| **En producción, tras el traslado del 30-sep-2026, la cuenta buena es la de Google**: `amachin.83@gmail.com` tiene **138 entidades** (72 tareas, 21 eventos, 19 áreas, 17 objetivos, 8 diario) + 13 capturas, 13 propuestas y la conexión con Google de **escritura**. `owner` se queda **vacía** (entra con contraseña) y `patri91v@gmail.com` también | El login de Google busca por `google_sub` **o** por `username == correo`, así que entrar con Google **crea una cuenta nueva** en vez de enlazar con la de siempre (pasó aquí). La otra mitad ya existe: **vincular** desde la app |
| `api/scripts/mover_espacio.py` mueve un espacio de trabajo a otra cuenta: simula por defecto, volca las tablas afectadas, **se niega a mover** si hay claves únicas que chocarían y comprueba los totales antes de confirmar | Solo **12 tablas** tienen `workspace_id`; tareas, áreas, objetivos, eventos y métricas cuelgan de `entities` por id y se mueven solas. `memberships` **no** se mueve (cada cuenta sigue en el suyo) y de las conexiones con Google gana la de **escritura** |
| `lifeos-doctor [servidor] [--token-env NOMBRE]` corre las comprobaciones (salud, endpoints, acceso, sesión y **que cada pantalla decodifique**: nueve, con **agenda** dentro) y sale 0/1/2 | Un 200 que no decodifica es el bug de verdad; el diagnóstico lo distingue de un 404 (versión antigua) y de un 401 (sesión). Verificado contra producción con sesión: **«todo bien»** |
| `POST /captures` acepta **`content` de hasta 10 000 caracteres** (`min_length=1`), y `channel` es solo `text` | Un texto más largo da 422: `EvidenceIntake` lo corta **antes** de enviar y lo dice («son 12 345 caracteres y una anotación admite 10 000») |
| **`POST /documents/upload`** es `multipart/form-data` con `file` (+ `title` y `sensitivity` opcionales); responde **201** con `{id, title, filename, mime_type, content_text, sensitivity, content_hash, index_status}` | Solo **20 MB** y **`.pdf`, `.docx`, `.txt`, `.md`** (422 en cualquier otro). Un fichero con el mismo `content_hash` en el espacio → **409** (no se duplica). El texto se indexa en segundo plano: `index_status` puede ser `pending`/`queued`/`indexed`/`local_only` |
| `sensitivity=sensitive` en un documento → `index_status: local_only` y **no** se manda a proveedores | Igual que el audio y el diario: lo sensible se guarda, no se comparte |
| **`POST /api/v1/auth/google/link`** (autenticado) devuelve `{authorize_url, state}` para **vincular** Google con la cuenta que ya tiene sesión; el retorno es `lifeos://auth?linked=…` con `ok` / `already` / `taken` / `conflict` / `expired` | Arregla la raíz del lío de las dos cuentas. Seguridad con test: si ese `sub` ya es de **otro** usuario → `taken` y **no se toca nada**; si la cuenta ya tiene otra identidad → `conflict` y no se cambia sola |
| `UserResponse` incluye **`google_linked`** (propiedad `User.google_linked`) | La app no ofrece «vincular» a quien ya lo tiene. En Swift es `LifeOSUser.googleLinked`, **opcional**: los servidores viejos no lo mandan y eso no puede romper el login |
| **Desplegar el servidor deja ~2-3 minutos de 502**: `release.sh` recrea el stack y **la web es la última en arrancar** (después del healthcheck de la api) | No asustarse ni «arreglar» nada: NPM devuelve 502 «connection refused» mientras la web está `Created`. Comprobar **después** de que `release.sh` imprima su `compose ps` final |
| `GET /agenda` no cabe en una URL fija (exige `start` y `end`), así que el diagnóstico los calcula al vuelo con un `queryProvider` y los saca de `APIClient.agendaQuery` (el mismo sitio que la pantalla) | Una prueba que construye la URL a mano puede mentir: comprobaría algo que la app no pide |
| El token de la app es de **ese** servidor: un token del local da 401 en producción | El diagnóstico lo dice como aviso, no como fallo: «la sesión guardada no vale en ese servidor» |
| **`GET /agenda` exige `start` y `end`** (si no, 422; `end <= start` también) y devuelve **tres carriles**: `events` (citas y bloques de foco), `tasks` (con `scheduled_start`) y `due_tasks` (con fecha y sin hora) + `duplicates` | Una llamada trae la **semana** entera y la app agrupa por día; el solapamiento es `ends_at > start && starts_at < end` (final exclusivo) |
| Los pares acción+evento (`duplicates`) se deciden con `POST /agenda/duplicates/resolve` (`same`/`different`/`forget`) y la decisión se guarda en `subject_relations` | Se pregunta **una vez**; nada se fusiona ni se borra solo |
| `AgendaEvent` es entidad: `DELETE /entities/{id}` lo borra (reversible). `POST/PATCH /events` con `expected_version` → 409 | La app puede crear y editar citas, con el mismo control de versión que el diario |
| **Las fechas en los cuerpos viajan en ISO-8601** (el encoder del cliente lo fija); como número, el esquema no las acepta | Un `Date` mal codificado no falla en el cliente: falla con un 422 en el servidor |
| `PATCH /tasks/{id}` usa `exclude_unset=True`: omitir = «no lo toques», `null` = «bórralo» | En Swift es un `Patch<T>` (`.unchanged` / `.clear` / `.set`) y no un `Int?`: confundirlos borraría el vencimiento al cambiar el estado |
| `TaskResponse` trae `blocked`, `source`, `external_state` (`synced`/`missing`/`conflict`) y `origin` (`Tasks · Compras`) | La app **enseña** el desajuste con Google; no lo resuelve sola |
| `GET /timeline?days&kinds&limit&include_sensitive` → `{start,end,days,items,counts}`; `GET /search?q=` → `{query,results}` | `counts` cuadra con los tipos pedidos; los elementos llevan `sensitive` para marcarlos |
| **La web es una sola página sin rutas** (`web/app/page.tsx`, 4.674 LOC, sin `useSearchParams`) | «Abrir en LifeOS» abre el inicio: inventar `/ejecutar` daría 404. Propuesta para el repo web: admitir `?view=` |
| Errores = `application/problem+json` `{title, detail, status}` | `APIError.from` conserva el `detail` en lugar de inventar un mensaje |
| **El orden de la barra lateral y los ⌘1…⌘8 salen del mismo sitio**: `MainView.Pane.allCases` (declaración del enum) + `shortcut` por caso. El 30-sep-2026 (petición del dueño) el **Diario pasó por delante de la Agenda** y se **renumeraron** los atajos para que la barra lea 1…8 de arriba abajo: `Hoy, Capturar, Diario, Agenda, Ejecutar, Buscar, Bandeja, Ajustes`. El `rawValue` (lo que se guarda en `lifeos.lastPane`) **no cambia** al reordenar | Lo fija `PaneOrderTests` (orden, Diario<Agenda, numeración, iconos). Si se vuelve a mover una sección, hay que **renumerar** o el test lo canta. La captura por script (`scripts/qa_screenshots.sh`) usa los `rawValue`, así que no le afecta |
| **Ánimo y energía: escala de color de 1 a 5, rojo → verde** (`JournalScale`, LifeOSUI): tonos dinámicos claro/oscuro (los extremos reutilizan `danger` y `positive`, `adaptive` pasó de `private` a internal para eso); los puntos **sin elegir** llevan el anillo de su color (la escala se lee entera aunque no haya valor) y el nivel elegido se **escribe** al lado en su color | El color es **refuerzo, nunca el único canal** (rojo/verde es el par que no distingue ~8 % de los hombres): cada punto tiene palabra + número en `help` y en el lector («Ánimo 4 de 5: Bien»). Las palabras son **las de la web** (`MOOD_LABELS`/`ENERGY_LABELS` en `web/components/journal-view.tsx`): app y web dicen lo mismo. Tests: `JournalScaleTests` |
| **Revisión visual sin tocar la pantalla del usuario**: `LIFEOS_RENDER_PREVIEWS=1 swift test --filter RenderPreviewsTests` renderiza las pantallas fuera de pantalla (claro y oscuro) a `docs/design/v2-apple/*.png` con `ImageRenderer` | El test **exige un recuento exacto** de PNGs (38): al añadir una vista hay que subir el número o falla a propósito. `screencapture` no sirve aquí (devuelve negro con la pantalla dormida). Ojo: tocar `Theme.swift` recompila todo el paquete (~8 min) |
| `APPS/LIFEOS` **ya está versionado** (1-oct-2026, commit `e4f17ee` de JUST4ALL: app + skill + plan + registro en el hub; 125 ficheros, con las 38 previsualizaciones de `docs/design/v2-apple/`). El servidor vive en el **monorepo** `/Users/dmx83/Repos/0_server_dorticos` (raíz git, ¡ojo!: contiene además `JaguaERP/` y `trading_tv_mt5_lab/`), rama `feat/lifeos-apple-design`; los cambios de LifeOS se commitearon en `9b7f1cc5` | Al commitear en el monorepo, **acotar las rutas** (`git add LifeOS/api LifeOS/web`): `git add -A` arrastraría JaguaERP, `backups/` y los logs de backtest. Ambos repos suelen ir **muy por detrás del remoto** (JUST4ALL llegó a estar 84 commits por delante de `origin/main`): commitear ≠ publicar, preguntar antes de `push`. `swift test` imprime «CoreData: error: Failed to create NSXPCConnection» (ruido del host de pruebas, inofensivo) |

## Autenticación (cómo entra de verdad)

- **Google** (lo que pidió el owner, igual que la web): `ASWebAuthenticationSession` sobre
  `GET /auth/google/authorize?native=true`; el servidor vuelve a **`lifeos://auth?code=…`** y la app canjea con
  `POST /auth/native/exchange`. Se usa `ASWebAuthenticationSession` porque Google **rechaza** los navegadores
  incrustados (`disallowed_useragent`); una `WKWebView` propia no vale para esto.
- **Usuario y contraseña + TOTP**: `POST /auth/native/login` (el token viene en el cuerpo).
- **Respaldo automático**: si `/auth/native/login` responde 404 (servidor sin actualizar), se usa
  `POST /auth/login` como la web y el token se saca del `Set-Cookie` (`APIClient.sessionToken(fromSetCookie:)`),
  sin depender del almacén de cookies. Ojo: `X-LifeOS-Session` **no** existe en el servidor (401); lo que
  devuelve el login es la cookie **`lifeos_session`**.
- **Sesión pegada a mano** («Usar la sesión que ya tengo en la web»): se pega el valor de la cookie
  `lifeos_session` del navegador y la app lo valida contra `/auth/me` **antes** de guardarlo
  (`AuthService.adoptSession(token:)`); si el 401 llega, no se guarda nada en el llavero.
- ⚠️ **`POST /auth/login` busca por `username` exacto, NO por correo** (`User.username == payload.username`, sin
  `lower()` → en Postgres distingue mayúsculas), y tras varios fallos responde **429**. El campo de la app se llama
  «Usuario» a propósito. Matiz importante: una cuenta **creada con Google** guarda `username = email.lower()`, así
  que en ese caso el «usuario» **sí es el correo** (en minúsculas). Si no se sabe, está en
  `LIFEOS_BOOTSTRAP_USERNAME` del `.env` **del servidor** (las credenciales del `.env` local solo valen contra el
  servidor local).
- ⚠️ **`X-LifeOS-Session` no vale como credencial.** El servidor lo **emite** solo si `app_env != "prod"`, pero
  `current_user` únicamente lee `Authorization: Bearer …` o la cookie `lifeos_session`. Se creyó que servía; no.
- ⚠️ **Una cuenta creada con Google no puede tener contraseña**: nace con una aleatoria
  (`find_or_create_google_user`) y `POST /auth/password` exige la **actual** (+ MFA) y además borra todas las
  sesiones. Para esas cuentas hace falta entrar con Google (ya desplegado) o pegar la sesión de la web.
- ⚠️ **Entrar con Google NO enlaza con una cuenta que ya exista**: solo busca por `google_sub` o por
  `username == correo`, así que si la cuenta de siempre tiene otro usuario (p. ej. `owner`) se crea **otra
  cuenta** con el correo y un espacio de trabajo nuevo y vacío. Pasó en producción.
- El token (7 días) va al **llavero** (`kSecAttrAccessibleWhenUnlocked`) y de ahí a `Authorization: Bearer`.
  Comprobado contra el servidor local: el valor de la cookie vale tal cual como `Bearer` (200 en `/auth/me`).
- ⚠️ **Google sólo funciona con la app empaquetada** (el esquema `lifeos://` necesita `Info.plist`, y
  `CFBundleURLTypes` debe declarar `lifeos`) y con el parche del servidor desplegado (ya lo está).

## Parche del servidor (repo LifeOS, aditivo)

- `api/app/connectors.py`: `NATIVE_SIGNIN_MARKER`, `create_signin_state(native:)`, `create_native_code` /
  `consume_native_code` (código de un solo uso en Redis, 120 s).
- `api/app/main.py`: `POST /auth/native/login`, `POST /auth/native/exchange`, `?native=true` en el authorize y
  `NATIVE_SIGNIN_MARKER` en el callback. El `state` y los códigos de un solo uso van a **Redis** (`connectors.py`),
  así que **no hay migración**: el parche es aditivo. Ya está desplegado en producción (30-sep-2026).
  vuelta a `lifeos://auth`.
- `api/app/schemas.py`: `NativeLoginRequest`, `NativeExchangeRequest`, `NativeSessionResponse`.
- **Sigue pendiente de desplegar** en producción (`./deploy/release.sh` en el repo LifeOS).
- Validación: 186 tests verdes; los 2 fallos de `test_connectors.py` son **pre-existentes** (Redis apagado si
  Docker no está corriendo), comprobado ejecutándolos contra el código original.

## Arquitectura

```
Sources/LifeOSAPI/   red y contrato JSON — sin UI, sin AppKit (actor APIClient, DTOs, JSONValue, APIError)
Sources/LifeOSCore/  dominio local — llavero, ajustes, cola, AuthService, LifeOSService
Sources/LifeOSUI/    SwiftUI — LifeOSModel (@MainActor ObservableObject), vistas y tokens
Sources/LIFEOS/      ejecutable — composición, MenuBarExtra, GlobalHotKey, panel, avisos
Tests/TestSupport/   doble de red por URLProtocol (compartido por los dos targets de test)
```

- Un **único** `LifeOSModel` para toda la app (ventana, panel y menú de barra): una sola fuente de verdad.
- `LifeOSUI` nunca llama a la red directamente; sólo `LifeOSAPI`.
- El atajo global y el panel son el patrón **G4** de JUST4DESK (`NSPanel` borderless + Carbón
  `RegisterEventHotKey`). Hoy están copiados; al tercer consumidor, promover a `PACKAGES/J4SHARED`.

## Diseño

El sistema visual traduce los tokens del repo LifeOS (`design-system/tokens/*.json`) y su decisión **DS-018**
(«rediseño estilo Apple»): acento `#5e5ce6`, radios 6/10/14/18/píldora, sombras difusas, roles tipográficos y
**colores dinámicos** (claro/oscuro siguiendo al sistema; no hay tema oscuro fijo).

- `Sources/LifeOSUI/Theme.swift` (tokens) y `Sources/LifeOSUI/Components.swift` (piezas).
- **Regla**: las vistas no pintan colores sueltos; eligen un componente o un token. Si falta algo, se añade ahí.
- Referencia viva: `docs/design/v2-apple/` (14 imágenes, claro y oscuro).

### Cómo se generan las imágenes de revisión

```sh
LIFEOS_RENDER_PREVIEWS=1 swift test --filter RenderPreviewsTests
```

Renderiza las vistas **fuera de pantalla** (no usa `screencapture`). Tres trampas ya resueltas:

1. `ImageRenderer` **no pinta dentro de un `ScrollView`** → cada pantalla separa su contenido en
   `XxxContent` (sin scroll) y la vista pública sólo envuelve. El render usa el `Content`.
2. Los **materiales** del sistema no se pintan sin ventana → `\.lifeOSFlatSurfaces` los cambia por el color de
   superficie equivalente.
3. Los **controles de AppKit** (`TextField`, `SecureField`, `TextEditor`, `Toggle(.switch)`) salen como un bloque
   amarillo → en modo render se dibuja su aspecto estático (`LifeOSField`, `LifeOSSwitch`, editor sustituido).

### Lecciones de la revisión visual (30-sep-2026)

- **En oscuro, el acento suave tiene que llevar tinte.** Si `brandSoft` se queda en gris (`#2c2c2e`, como el
tema oscuro del sistema de diseño), «operación elegida» y «no elegida» se ven iguales: en oscuro es `#282650`.
- **La marca necesita el aro visible**, o el disco violeta con un punto blanco parece un botón de grabar.
- **Botón primario a ancho completo**: el `.frame(maxWidth: .infinity)` va **dentro** del `label` del `Button`,
no aplicado al botón (si no, se queda centrado y pequeño).
- **Los `VStack` de un panel van en `alignment: .leading`**; con el valor por defecto, bloques como
«Servidor https://…» salen centrados aunque su contenido interno sea leading.
- **Un campo dentro de una tarjeta blanca no se lee como campo**: para eso está `elevated` (hueco hundido) y
reservar el borde para el anillo de foco.
- Título de pantalla a **24 pt**, no 28: el `display` es para la marca (login), no para cada pantalla.

## Comandos

```sh
cd APPS/LIFEOS
swift build                                  # compila
swift test                                   # 35 tests offline (los de servidor real se saltan)
swift run LIFEOS                             # dev (sin bundle: Google no funciona)
swift run LIFEOS --quick-capture             # abre el panel de captura directamente
./scripts/build_dmg.sh                       # .app + DMG en dist/ (genera el Info.plist con lifeos://)
./scripts/dev_local.sh                       # apunta la app al LifeOS local y la lanza
python3 scripts/make_logo.py <destino.png>   # logo del hub (PIL; usar el .venv del repo JUST4ALL)

# Contra el servidor local (docker compose del repo LifeOS; `owner` / `change-me-in-dev`)
LIFEOS_LIVE_SERVER=http://127.0.0.1:8000 swift test --filter LifeOSLiveTests
```

Release desde la raíz: `./scripts/release.sh` (ya incluye LIFEOS) y `./scripts/sync_local_dmgs.sh`.

## Arranque del servidor local

```sh
cd /Users/dmx83/Repos/0_server_dorticos/LifeOS && docker compose up -d
```

Necesita Docker Desktop en marcha (`open -a Docker`; si el daemon está parado, el API no arranca y el
contenedor tarda ~40 s en `pip install` antes de responder). Comprobación: `curl $BASE/health/ready` →
`{"status":"ready"}`. El contenedor monta `./api` y ejecuta `uvicorn --reload`, así que **corre este mismo
código**: los endpoints `/auth/native/*` están vivos en local aunque producción aún no los tenga.

## Capturas de pantalla para el hub

`screencapture -l <windowID> -o -x salida.png` con el ID de `CGWindowList` (owner `LifeOS`). El panel flotante
se abre sin automatización con `--quick-capture`, así que las capturas son reproducibles sin permisos de
Accesibilidad. Assets en `Sources/JUST4ALL/Resources/Assets/LIFEOS/`.

## Lecciones aprendidas (30-sep-2026)

- **Codificar y decodificar la cola con la misma estrategia de fechas.** El `OutboxStore` escribía ISO-8601 y
  leía con el decodificador por defecto: al reiniciar, la cola se vaciaba en silencio. Lo cazó un test.
- **No depender del almacén de cookies de `URLSession`** para recuperar el token: leer `Set-Cookie` de la
  respuesta funciona también por HTTP en la red local (donde una cookie `Secure` no se guardaría) y además es
  testeable sin servidor. (`X-LifeOS-Session` se creyó que existía; probado contra el servidor: **no**.)
- **`XCTAssertEqual(await …)` no compila** (no se admite `await` en una autoclosure): asignar a una constante
  primero.
- Un `enum Section` dentro de una vista **choca con `SwiftUI.Section`**; llamarlo `Pane`.
- `UNUserNotificationCenter` puede fallar/avisar sin bundle: comprobar `Bundle.main.bundleIdentifier != nil`
  antes de usarlo (y así `swift run` no revienta).
- `ASWebAuthenticationSession.start()` devuelve `false` sin bundle: mensaje claro en vez de cuelgue.
- **El llavero no es de fiar como reloj**: un token guardado por **otro binario** hace que macOS pida permiso en
  cada lectura y que `SecItemCopyMatching` tarde ~7 s (con `SecurityAgent` por medio). Medido el 30-sep-2026.
  Consecuencias: (1) los tests en vivo deben usar su **propio** `CredentialsStore`, nunca el real — si no,
  dejan una sesión de verdad en el Mac de quien los ejecuta; (2) la pantalla de «Comprobando la sesión…» debe
  tener salida (botón a los 2,5 s), no un giro infinito.
- **Las capturas no se pueden borrar por API** (no son entidades). Para limpiar capturas de prueba hay que ir a
  Postgres: borrar primero `proposals` y después `captures`, en una transacción y con un `WHERE` de contenido
  concreto. Y **comprobar el dry run antes**.
- `docker exec` sin `-i` **no** pasa stdin: un heredoc a `psql` se queda en nada.
- **`screencapture` no es fiable aquí**: con la pantalla dormida devuelve imágenes **negras** (y a veces falla
  con «could not create image from window/rect» también por ventana o rectángulo). Para QA visual, renderizar
  las vistas fuera de pantalla; si se usa `screencapture`, antes `caffeinate -u -t 600 &`.
- **Firmar la app antes de probarla, o el llavero preguntará siempre.** `build_dmg.sh` firma con la identidad
  de desarrollo del llavero (`Apple Development: …`, o `CODESIGN_IDENTITY`). Con firma **ad-hoc** el cdhash
  cambia en cada compilación, macOS lo trata como otra app y pide permiso *otra vez* para leer la sesión
  guardada (y `SecItemCopyMatching` se queda esperando al `SecurityAgent`). Comprobación de que quedó bien:
  `codesign -d -r- <app>` debe dar la misma *designated requirement* en dos compilaciones seguidas.
  Diagnóstico: `pgrep -fl SecurityAgent` (si hay proceso, hay aviso pendiente) y
  `log show --predicate 'process == "securityd"' | grep "displaying keychain prompt"`.
- **Un binario distinto de la app no puede leer su sesión sin permiso.** `lifeos-doctor` es otro ejecutable, así que
  leer el llavero de la app dispara el `SecurityAgent` y **bloquea** (pasó: el diagnóstico se quedó colgado sin
  imprimir nada). Por eso no toca el llavero salvo con `--keychain`, y acepta `--token-env` o `--token`. Para
  diagnosticar desde dentro, la app lo hace en proceso (Ajustes → Diagnóstico) y deja el informe en
  `~/Library/Application Support/LIFEOS/diagnostico-servidor.txt`, sin la sesión dentro.
- **Un test no debe salir a internet.** El primer test del flujo de Google «pasaba» porque creaba su propio
  `APIClient` con `URLSession.shared` y llegaba **a producción de verdad** (que por casualidad responde 404 donde
  el test esperaba 404). Las clases que hacen red deben poder recibir la `URLSession` (`GoogleSignInController(network:)`)
  y los tests inyectan el doble.
- **`swift script.swift` recompila en cada llamada** (~20-30 s): para un bucle de QA, compilar una vez con
  `swiftc -O` y usar el binario.
- **Antes de escribir un cliente, leer la semántica del `PATCH` en el servidor.** El diario usa
  `exclude_unset=True`: el `Encodable` sintetizado de Swift **omite** los opcionales `nil`, así que «quitar el
  ánimo» no hacía nada (el servidor entendía «no lo toques»). Se arregla mandando `null` explícito. Un test
  con el `URLProtocol` de doble lo enseña sin necesidad de servidor.
- **Los valores por defecto del servidor no son del usuario.** Sin título, el diario se guarda como «Entrada
  del 30 de septiembre»; si el cliente muestra `title` sin más, cada entrada sin título aparece titulada así y
  el texto queda escondido. Detectar el valor por defecto y preferir el texto.
- **Copiar la lógica de presentación del servidor, no improvisarla.** `journal_strip_lead_tokens` no quita
  cualquier línea que empiece por `@hora:`, sólo los tokens **válidos** y para en el primero que no lo es. Un
  espejo aproximado en el cliente habría ocultado prosa escrita por la persona. Se verificó con un test en
  vivo que crea una entrada con `@hora:xx` y comprueba que el servidor tampoco lo interpreta.

## Pendientes inmediatos

Ver `PENDIENTES.md` §7 y `APPS/LIFEOS/TODO.md`. Lo primero: **desplegar el parche del servidor** y validar en
vivo Google, ⌥Espacio, avisos y cola sin conexión.
