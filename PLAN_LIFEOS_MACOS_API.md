# Plan v2 — LifeOS Mac: cliente nativo sobre la API

- **Fecha**: 30-sep-2026
- **Estado**: **F1 y F2 entregadas** el mismo día (35 tests verdes, DMG validado y app registrada en el hub).
  Lo entregado está en §11, y lo que sigue en `APPS/LIFEOS/TODO.md`.
- **Sustituye a**: `PROPUESTA_LIFEOS_MACOS.md` (documento de evaluación; se conserva como justificación del alcance)
- **Ubicación**: `APPS/LIFEOS` (SPM, macOS 14+) — ver `APPS/LIFEOS/README.md`

---

## 1. Decisión y alcance

Una app macOS nativa (SwiftUI) que habla **directamente con la API de LifeOS**. Nada de `WKWebView`, nada de
incrustar la web, nada de servidor propio.

- **Lo que sí**: el ciclo diario completo — capturar → clasificar/confirmar → hoy → diario → agenda.
- **Lo que no**: paridad con las 12 secciones. Objetivos, métricas, conocimiento, documentos, decisiones,
  conectores de Google, onboarding y administración quedan en la web, y la app enlaza a ella.

Esto convierte el problema de «reescribir 4.674 líneas» en «consumir ~35 endpoints de 103». Sigue siendo un
producto real, pero de 2–3 semanas, no de 6–12 meses.

**Efecto colateral bueno**: al ser app nativa con DMG, **el contrato del hub se cumple sin cambios de modelo**
(`isInstalled` por `bundleId`, `ReleaseStore` con DMG + `SHA256SUMS.txt`). La extensión `SubAppKind` que pedía la
propuesta v1 **ya no hace falta**: sólo una entrada más en `SubAppsCatalog.items`.

---

## 2. Contrato real de la API (verificado en el código, 30-sep-2026)

### Autenticación — soporta cliente nativo sin cambios

| Hecho | Evidencia |
|---|---|
| `current_user` acepta `Authorization: Bearer <token>` **o** la cookie `lifeos_session` | `api/app/main.py:142-148` |
| Login: `POST /api/v1/auth/login` (`username`, `password`, `mfa_code`) → `UserResponse` + cookie | `api/app/main.py:628-649` |
| TOTP obligatorio si está activo; hay códigos de recuperación de un solo uso | `api/app/security.py:79-95` |
| Sesión opaca de 48 bytes, TTL **168 h**, revocable; tabla `SessionToken` con `ip` y `user_agent` | `api/app/security.py:28-36`, `config.py` |
| Listado y revocación de dispositivos: `GET /api/v1/auth/sessions`, `DELETE /api/v1/auth/sessions/{id}` | `main.py` |
| En **dev** el token se expone en la cabecera `X-LifeOS-Session`; en **prod** no | `main.py:647-648` |
| Cookie: `httponly=True`, `secure=<LIFEOS_COOKIE_SECURE>`, `samesite="strict"` | `main.py:646` |
| El rate limit de login es real: 5 intentos / 300 s → bloqueo 900 s | `api/app/auth_guard.py`, `config.py` |
| Los errores son `application/problem+json` con `{title, detail, status, request_id, errors}` | `main.py:107-111` |

### Cómo entra el cliente nativo (implementado el 30-sep-2026)

El owner pidió que la app entre **con Google igual que la web**. Google rechaza las peticiones de
autorización hechas desde navegadores incrustados (`disallowed_useragent`), así que no vale una vista web
propia: se usa **`ASWebAuthenticationSession`**, que sí es un navegador de verdad.

El flujo original de la web termina poniendo una cookie y volviendo a `lifeos.perlatec.net`, y la app no
puede leer esa cookie. Por eso se añadió al servidor un **parámetro y dos endpoints** (aditivos, sin tocar
la base de datos ni el contrato de la web):

| Pieza | Qué aporta |
|---|---|
| `GET /auth/google/authorize?native=true` | Marca el `state` como nativo y hace que la vuelta sea `lifeos://auth?code=…` |
| `POST /auth/native/exchange` | Canjea ese código de un solo uso (2 min en Redis) por el token de sesión |
| `POST /auth/native/login` | Usuario/contraseña + TOTP con el token en el cuerpo, para no depender de cookies |

El token nunca viaja en la URL del navegador: en la URL va un código de un solo uso, y el token se obtiene
en una petición HTTPS de la propia app. Se guarda en el **llavero** y se envía como `Authorization: Bearer`,
que la API ya aceptaba de antes (`current_user`), así que funciona igual por HTTPS público que por HTTP en la
red local.

**Respaldo sin tocar el servidor**: si `/auth/native/login` no existe (servidor sin actualizar), la app usa
`POST /auth/login` como la web y saca el token de `X-LifeOS-Session` (dev) o de `Set-Cookie`. Es decir, se
puede usar la app hoy mismo con usuario y contraseña, y Google en cuanto se despliegue el parche.

### Endpoints por pantalla (subconjunto curado)

| Pantalla | Endpoints |
|---|---|
| **Login** | `POST /auth/login` · `GET /auth/me` · `POST /auth/logout` |
| **Hoy** | `GET /day-close` · `GET /reminders/upcoming` · `GET /agenda` |
| **Capturar** | `POST /captures` (+ `Idempotency-Key`) · `GET /captures/{id}` · `PATCH /captures/{id}` (aclaración) · `GET /proposals/{id}` · `PATCH /proposals/{id}` · `POST /proposals/{id}/apply` · `POST /proposals/{id}/reject` |
| **Bandeja** | `GET /captures` · `GET /captures/{id}` · `POST /captures/{id}/retry-transcription` |
| **Voz** | `POST /captures/audio` (multipart: `file`, `sensitivity`, `language`) |
| **Diario** | `GET /journal` · `POST /journal` · `GET /journal/{id}` · `PATCH /journal/{id}` · `GET /journal/reference-candidates` |
| **Agenda** | `GET /agenda` · `POST /events` · `PATCH /events/{id}` · `POST /agenda/duplicates/resolve` |
| **Ejecutar** | `GET /tasks` · `POST /tasks` · `PATCH /tasks/{id}` |
| **Buscar** | `GET /search` · `GET /timeline` |
| **Ajustes** | `GET /auth/sessions` · `DELETE /auth/sessions/{id}` · base URL · cerrar sesión |

### Detalles del contrato que condicionan la UI

- **La captura es asíncrona en producción.** `POST /captures` responde `202` con `{id, status, proposal_id?}`.
  En `prod` encola a Celery (`main.py:1433-1438`); en dev la procesa en `BackgroundTasks`. Es decir: tras
  capturar, la app muestra «clasificando…» y **sondea** `GET /captures/{id}` hasta que aparezca `proposal_id`.
- **La propuesta no se aplica sola.** `GET /proposals/{id}` devuelve `operations[]` + `explanation`;
  `POST /proposals/{id}/apply` exige `operation_ids` (aplicación selectiva, no todo o nada).
- **Hay flujo de aclaración.** La respuesta de captura puede traer `clarifying_question` y `manual_kind`:
  la app debe poder responder con `PATCH /captures/{id}` (`clarification_answer`, `manual_kind`).
- **Sensibilidad se decide antes de enviar.** `CaptureCreate.sensitivity` ∈ {`standard`, `sensitive`}; el
  contenido máximo es 10.000 caracteres.
- **La idempotencia ya existe.** `POST /captures` acepta `Idempotency-Key` y devuelve la captura previa si se
  repite (máx. 200 caracteres). Es la base de la cola offline, y viene gratis.
- **`day-close` y `reminders/upcoming` ya están resueltos para el cliente**: `ReminderItem` trae `at` y
  `remind_at` calculados; `DayCloseResponse` trae completadas, eventos, tareas abiertas, capturas pendientes y si
  ya escribiste. La app no reinterpreta nada.

---

## 3. Arquitectura del cliente

SPM modular, siguiendo el patrón de `APPS/JUST4DESK` (targets separados, núcleo testeable, sin UI en las capas
bajas):

```
APPS/LIFEOS/
├── Package.swift                 macOS 14+ · producto ejecutable LIFEOS
├── Sources/
│   ├── LifeOSAPI/                ← capa de red, sin UI (testeable)
│   │   ├── APIClient.swift       actor: baseURL, Bearer/cookies, problem+json, reintentos
│   │   ├── Endpoints.swift       ~35 rutas tipadas del subconjunto v1
│   │   ├── Models.swift          DTOs Codable (o generados desde OpenAPI)
│   │   └── APIError.swift        401/402/422/429 traducidos a mensajes humanos
│   ├── LifeOSCore/               ← dominio local, sin UI ni red
│   │   ├── AppSettings.swift     baseURL, preferencias, toggles de sensibilidad
│   │   ├── OutboxStore.swift     cola offline persistente (idempotente)
│   │   └── KeychainStore.swift   token de sesión
│   ├── LifeOSUI/                 ← SwiftUI
│   │   ├── LoginView · TodayView · CaptureView · InboxView
│   │   ├── JournalView · AgendaView · SearchView · SettingsView
│   │   ├── DesignTokens.swift    generado desde design-system/tokens/*.json
│   │   └── StyleKit.swift        componentes (marca #5e5bd8 sobre #101421)
│   └── LifeOSApp/                ← ejecutable: composición + integración con el sistema
│       ├── LifeOSApp.swift       @main, Scene, ventana principal
│       ├── MenuBarExtra.swift    cierre del día desde la barra
│       ├── QuickCapturePanel.swift  panel flotante del atajo global
│       ├── Notifications.swift   UNUserNotificationCenter + sondeo de reminders
│       └── OutboxCoordinator.swift  drena la cola al recuperar red
├── Tests/                        LifeOSAPITests · LifeOSCoreTests
└── scripts/build_dmg.sh          plantilla canónica de JUST4PICT
```

**Regla de dependencias**: `LifeOSUI` no llama a red directamente, sólo a `LifeOSAPI`; `LifeOSApp` es el único
que conoce `NSApplication`/`UNUserNotificationCenter`. Nada de UI en `LifeOSAPI` ni `LifeOSCore`.

**Modelos**: el servidor sirve OpenAPI en `/openapi.json` (FastAPI). Con 100 esquemas, escribirlos a mano es deuda
garantizada → generar con `swift-openapi-generator` y usar sólo el subconjunto. Si el plugin complica el build
del DMG, plan B: DTOs a mano sólo para las ~25 estructuras del subconjunto v1.

**Tokens visuales**: `design-system/tokens/{primitives,semantic,light,dark}.json` → `DesignTokens.swift`
generado, para que el Mac no derive del sistema de diseño de LifeOS.

---

## 4. Lo nativo de verdad (por qué no basta la web)

1. **⌥Espacio desde cualquier app** abre un panel de captura. Es el corazón del producto (captura universal) y la
   web no puede hacerlo. Patrón ya resuelto en **G4 de JUST4DESK** (`GlobalHotKey` Carbon + panel flotante):
   hay que **promoverlo a `PACKAGES/J4SHARED`** para no copiarlo (hoy vive en el target de app de JUST4DESK).
2. **Notificaciones con la app cerrada.** `GET /reminders/upcoming` ya devuelve `remind_at`; con
   `UNUserNotificationCenter` + app de inicio, LifeOS avisa aunque no haya pestaña abierta. **Cierra el hueco
   que el propio README de LifeOS declara** («con LifeOS cerrado no pueden sonar»).
3. **Menú de barra** con el cierre del día (`/day-close`) y «Abrir LifeOS».
4. **Cola offline idempotente.** Si no hay red (o estás fuera de casa), la captura se guarda local y se envía al
   recuperar, con la `Idempotency-Key` ya generada → sin duplicados.
5. **Enviar a LifeOS**: `application(_:open:)`, menú Servicios y drag&drop (texto, fichero, selección) → captura.
6. **Grabar voz** con `AVFoundation` y subir a `POST /captures/audio`; **la transcripción la hace el servidor**
   (worker + Whisper), así se esquiva el riesgo de latencia local que ya se midió y se descartó en su día.

---

## 5. Fases

| Fase | Contenido | Esfuerzo | Criterio de salida |
|---|---|---|---|
| **F1** | Esqueleto SPM + `APIClient` + login/MFA (jarra de cookies) + **Hoy** + captura de texto + aplicar/rechazar propuesta | 2–3 días | Se hace login contra producción, se captura, se confirma la propuesta y se ve el cierre del día |
| **F2** | ⌥Espacio + menú de barra + notificaciones + cola offline | 2–3 días | Capturar sin abrir ventana; aviso con la app en segundo plano; captura sin red que llega sola al volver |
| **F3** | Diario + Agenda + Ejecutar + Buscar/Cronología | 3–5 días | Ciclo diario completo sin tocar la web |
| **F4** | Voz (grabar y subir) + Bandeja + Ajustes/Dispositivos + token en Keychain | 2–3 días | Captura por voz y gestión de la sesión desde la app |
| **F5** | Alta en el hub + DMG + `SHA256SUMS` + README/TODO + skill `.github/skills/lifeos/` | 1 día | La app aparece y se instala desde JUST4ALL |

**Total**: ~2–3 semanas para una app usable a diario.

---

## 6. Integración con JUST4ALL

- [ ] `Sources/JUST4ALL/SubAppModel.swift`: entrada `LIFEOS` en `SubAppsCatalog.items`
      (`bundleId: com.dmx83.lifeos`, acento `#5e5bd8`, icono `brain.head.profile`, `requirements:
      ["macOS 14+", "Requiere cuenta y servidor LifeOS"]`, enlaces a `https://lifeos.perlatec.net`).
- [ ] `Sources/JUST4ALL/Resources/Assets/LIFEOS/` (logo + 2 capturas).
- [ ] `APPS/LIFEOS/` con `Package.swift`, `Sources/`, `Tests/`, `scripts/build_dmg.sh`.
- [ ] `JUST4ALL.xcworkspace/contents.xcworkspacedata` + `scripts/release.sh` + `sync_local_dmgs.sh` +
      `clean_artifacts.sh`.
- [ ] `README.md`, `agent.md`, `PENDIENTES.md` y `.github/skills/lifeos/SKILL.md`.
- **Sin cambios en `ReleaseStore`** ni en el modelo de distribución: es una app nativa con DMG como las demás.

---

## 7. Fuera de alcance (v1, explícito)

Objetivos · Métricas · Conocimiento · Documentos · Decisiones · Áreas/Proyectos · Conectores de Google ·
Export/copia portable · Onboarding y `setup` · Administración de MFA, avatar y contraseña · Publicación en Google.

Todos ellos: la app muestra un enlace «Abrir en LifeOS web». Nada de duplicar lógica de sincronización.

---

## 8. Riesgos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Sin servidor la app no sirve (rompe «cada subapp funciona sola») | Medio | Declararlo en `requirements` de la tarjeta; modo degradado con cola offline |
| Deriva del contrato de API (103 endpoints, 23 migraciones) | Alto | Modelos generados desde `/openapi.json`; los tests de `LifeOSAPITests` fallan si cambia el contrato |
| Red LAN vs. pública | Medio | URL base configurable con detección y aviso claro |
| `secure=True` en prod impide cookie por HTTP en la LAN | Medio | Pasar a token Bearer en Keychain (fase F4); funciona en ambos casos |
| Divergencia visual respecto a la web | Medio | `DesignTokens.swift` generado desde `design-system/tokens/*.json` |
| Barrido de alcance hacia «la app tiene que hacerlo todo» | Alto | §7 es contractual: cualquier sección nueva entra por decisión explícita, no por inercia |

---

## 9. Decisiones que hacen falta antes de F1

1. **Nombre del binario y bundle**: `LIFEOS` / `com.dmx83.lifeos` (¿o `JUST4LIFE`?). *Propuesta: LIFEOS.*
2. **Versión mínima**: macOS 14 (coincide con `J4SHARED`, permite reutilizar G4). Alternativa macOS 13 si se
   prefiere el alcance de JUST4PICT. *Propuesta: 14.*
3. **Token**: ¿jarra de cookies primero (0 cambios en el servidor) o token explícito desde el principio?
   *Propuesta: cookies en F1, token en F4.*
4. **¿Se toca el servidor?** Cualquier cambio sería en el repo LifeOS, no en este. *Propuesta: una sola línea
   opcional en F4.*

---

## 10. Evidencia consultada (30-sep-2026)

- `api/app/main.py` (rutas, `current_user:142`, login:628, capturas:1420-1450, day-close:3538, search:4025,
  CORS:104, `problem()`:107)
- `api/app/security.py` (sesiones, TOTP) · `api/app/auth_guard.py` (rate limit) · `api/app/config.py`
  (`session_ttl_hours=168`, `cookie_secure`, `allowed_origin`)
- `api/app/schemas.py` (500-660: `DayCloseResponse`, `ReminderItem`, `TimelineItem`, `CaptureCreate`,
  `CaptureResponse`, `ProposalResponse`, `ApplyProposalRequest`)
- `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`, `docs/SECURITY_PRIVACY.md`, `docs/ROADMAP.md`,
  `docs/SESSION_HANDOFF.md`, `README.md`, `web/app/manifest.ts`
- Este repo: `Sources/JUST4ALL/SubAppModel.swift`, `ReleaseStore.swift`, `ContentView.swift`,
  `PACKAGES/J4SHARED/Package.swift`, `APPS/JUST4DESK/Package.swift`, memoria de **G4**

---

## 11. Qué se ha entregado (30-sep-2026)

### En el repo de LifeOS (`../0_server_dorticos/LifeOS`) — **pendiente de desplegar**

| Archivo | Cambio |
|---|---|
| `api/app/connectors.py` | `NATIVE_SIGNIN_MARKER`, `create_signin_state(native:)`, `create_native_code` / `consume_native_code` |
| `api/app/schemas.py` | `NativeLoginRequest`, `NativeExchangeRequest`, `NativeSessionResponse` |
| `api/app/main.py` | `/auth/native/login`, `/auth/native/exchange`, `?native=true` en el authorize y vuelta a `lifeos://auth` |
| `api/tests/test_connectors.py` | 6 tests nuevos del flujo nativo; el doble `FakeOAuthState` acepta `native:` |

**Validación**: 186 tests verdes (2 fallos pre-existentes por Redis apagado — Docker no está corriendo en esta
máquina; se comprobó que fallan igual con el código original).

### En JUST4ALL

- `APPS/LIFEOS/` — paquete SPM completo: `LifeOSAPI`, `LifeOSCore`, `LifeOSUI`, `LIFEOS`, `Tests/TestSupport`.
- Pantallas: Hoy · Capturar (con propuesta revisable y aclaración) · **Agenda** · **Ejecutar** · **Diario** ·
  **Buscar y cronología** · Bandeja · Ajustes. **F3 cerrada** (30-sep-2026): ciclo diario completo sin tocar la
  web. El diario respeta las reglas de LifeOS (nace privado, el texto manda, referencias declaradas con selector)
  y la agenda lee los tres carriles del servidor sin mezclarlos, con los pares acción+evento decididos una vez.
- ⌥Espacio + panel flotante, menú de barra, avisos del sistema, cola sin conexión idempotente.
- `scripts/build_dmg.sh` (genera el `Info.plist` con el esquema `lifeos://`) y `scripts/make_logo.py`.
- Hub: entrada `LIFEOS` en `SubAppsCatalog.items`, workspace, `release.sh`, `sync_local_dmgs.sh`,
  `clean_artifacts.sh` y assets en `Sources/JUST4ALL/Resources/Assets/LIFEOS/`.
- Docs: `APPS/LIFEOS/README.md`, `APPS/LIFEOS/TODO.md` y este plan.

**Validación**: `swift build` y `swift test` verdes (**89 tests offline**, 70 de contrato + 19 de dominio) y
**14 tests contra el servidor real** (`LIFEOS_LIVE_SERVER=http://127.0.0.1:8000`): ciclo completo del diario
(alta → lista → edición con versión → 409 → borrado real), referencia declarada a una tarea real, paridad de la
cabecera `@hora:`/`@fecha:`, **cita creada/editada/borrada con su 409**, **acción completada y reabierta con el
vencimiento vaciado por `null` explícito**, agenda de la semana, búsqueda y cronología.
DMG Release creado y app arrancada; 34 imágenes de revisión en `docs/design/v2-apple/`; compilación sin avisos;
`swift build` del hub OK.

### Bugs reales que encontraron los tests

1. La cola sin conexión **escribía fechas ISO-8601 y las leía con el decodificador por defecto**: al reiniciar,
   la cola se vaciaba. Ahora codifica y decodifica igual.
2. La recuperación del token en el acceso clásico **dependía del almacén de cookies de `URLSession`**; ahora se
   lee la cabecera `Set-Cookie` / `X-LifeOS-Session` directamente, así funciona también por HTTP en la red local.
3. `GET /captures/{id}` devuelve `CaptureResponse` (sin `content`): el cliente lo pedía con el tipo equivocado.
4. Los tests en vivo escribían en el **llavero real**; ahora usan uno propio por prueba.
5. En el diario, **quitar el ánimo no hacía nada**: el `Encodable` sintetizado omite los `nil` y el `PATCH` del
   servidor interpreta «omitido» como «no lo toques». Ahora se manda `null` explícito.
6. El **título por defecto** del servidor («Entrada del 30 de septiembre») se colaba como si fuera del usuario y
   escondía el texto de la entrada en la lista.
7. `unresolved_references` **no** significa «menciones escritas sin pasar por el selector»: son referencias
   declaradas que no se pudieron vincular. La app lo decía al revés.
8. El esquema rechaza `target_id` > 36 y `text` > 240 con **422**: ahora la etiqueta se recorta antes de enviar.

### Lo que falta para que Google funcione en producción

Desplegar el parche del servidor (`./deploy/release.sh` en el repo de LifeOS). Hasta entonces la app funciona
con usuario y contraseña (respaldo automático) y el botón de Google devuelve un error explícito.

