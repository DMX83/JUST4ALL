# LIFEOS — qué falta por construir

Inventario honesto al 30-sep-2026: qué tiene la app ya, qué no, y qué depende del servidor.
Las casillas marcadas están en `TODO.md`; esto es la vista de conjunto para decidir el orden.

## 1. Lo que ya está (usable a diario)

| Pantalla | Qué hace |
|---|---|
| **Hoy** | Cierre del día, avisos próximos, agenda de hoy, tarjetas con las cifras (llevan a su sección) |
| **Capturar** | `POST /captures` con sensibilidad, propuesta revisable operación a operación, aclaraciones, cola sin conexión idempotente |
| **Agenda** | `GET /agenda` de la semana entera, los tres carriles (citas, bloques de foco, vencimientos), filtro por origen, crear/editar cita y decidir los pares acción+evento |
| **Ejecutar** | `GET/POST/PATCH /tasks`: agrupadas por estado, completar, reabrir, crear, con el rastro de Google |
| **Diario** | Escribir/leer/editar/borrar, ánimo y energía, cabecera `@hora:`/`@fecha:`, **selector de menciones** `@tarea:`/`@evento:` con vínculos reales |
| **Buscar** | `GET /search` y `GET /timeline` con filtros de periodo y tipo |
| **Bandeja** | Capturas con su estado, aviso del tope de 100, abrir en la web |
| **Ajustes** | Servidor, sensibilidad por defecto, avisos, atajo, cerrar sesión |
| **Extras** | ⌥Espacio (panel flotante), menú de barra con la cifra de pendientes, avisos del sistema, cola sin conexión |

Sesión: Google (`ASWebAuthenticationSession`, parche del servidor) o usuario/contraseña con TOTP, token en el
llavero 7 días.

## 2. Pantallas que faltan

**Ninguna.** F3 cerrada el 30-sep-2026: agenda, ejecutar y buscar/cronología están dentro, con tests en vivo
contra el servidor (crear/editar/borrar cita con su 409, acción completada y reabierta, agenda, búsqueda y
cronología). Lo que queda de aquí en adelante son **detalles y F4**.

## 3. F4 — lo que hace que una app de Mac sea una app de Mac

- ~~**Voz**: grabar y subir a `POST /captures/audio`~~ **hecho (30-sep-2026)**: grabación m4a mono 16 kHz,
  multipart, transcripción en el servidor y el caso privado (se guarda sin transcribir).
- **Enviar a LifeOS**: `application(_:open:)`, menú **Servicios** y **drag & drop** (texto, fichero, selección)
  → `POST /captures` / `POST /documents/upload`.
- **App de inicio** (opcional) y preferencia para no registrar ⌥Espacio (hoy choca con JUST4DESK: gana quien lo
  registró antes).
- **Atajo y panel compartidos**: promover el patrón G4 a `PACKAGES/J4SHARED` (hoy está copiado de JUST4DESK).

## 4. Detalles dentro de lo que ya existe

- **Bandeja**: no hay borrado de capturas porque **el servidor no lo tiene** (`/entities/{id}` da 404 para
  capturas); falta `POST /captures/{id}/retry-transcription`. El tope de 100 capturas ya se avisa.
- **Diario**: no hay buscador propio (la cronología y `/search` sí lo cubren) ni exportación; el selector de
  menciones se maneja con el ratón (sin ↑/↓/Enter); las menciones a mano se leen hasta final de línea (como en
  la web).
- **Agenda**: se mira de día en día (con la tira de la semana), no en rejilla horaria; no se publica todavía en
  Google desde la app (`POST /tasks/{id}/google/publish`).
- **Ejecutar**: no se edita el detalle de una acción (vencimiento, contexto) desde la app: se cambia el estado y
  se crea; el resto sigue en la web.
- **Ajustes**: no incluye `GET/DELETE /auth/sessions` (ver y cerrar sesiones abiertas) ni administración de
  MFA, avatar o contraseña (fuera de alcance v1 a propósito).
- **Enlaces a la web**: la web es **una sola página sin rutas**, así que la app abre su inicio; no hay enlace
  directo a la entidad. (Propuesta para el repo web: admitir `?view=` o rutas por sección.)
- **Animaciones**: entrada de la propuesta y del panel de captura (hoy sólo transiciones suaves).

## 5. Fuera de alcance v1 (a propósito, con enlace a la web)

Objetivos · Métricas · Conocimiento · Documentos · Decisiones · Áreas/Proyectos · Conectores de Google ·
Export/copia portable · Onboarding · Administración de MFA · Publicación en Google.

Regla de producto: **la app no duplica lógica de sincronización**; muestra «Abrir LifeOS en el navegador» y
sigue siendo la web la que manda ahí.

## 6. Depende del servidor (repo `0_server_dorticos/LifeOS`)

- ✅ **Parche del flujo nativo desplegado (30-sep-2026)**: el login con Google funciona ya contra
  `lifeos.perlatec.net`, y el traslado de los datos de la cuenta `owner` a la de Google está hecho.
- 🟠 `GET /captures` limita a 100 filas **antes** de filtrar; conviene filtrar en SQL y exponer `limit`/`offset`.
- ⚪️ `DELETE` de capturas (hoy no existe).
- ⚪️ Decidir si `/openapi.json` se usa para generar los modelos Swift (`swift-openapi-generator`) antes de que
  el subconjunto crezca más.

## 7. Distribución y deuda

- Firma con identidad de desarrollo **hecha** (el llavero ya no pregunta en cada recompilación).
- ⚪️ Notarización con Developer ID si el DMG sale de este Mac.
- 🟠 Avisos de `Sendable` (`UNUserNotificationCenter`) antes de subir el modo de lenguaje a Swift 6.
- 🟠 Capturas del hub con contenido real (Hoy, propuesta, diario) en vez de la puerta de entrada.

---

## Orden sugerido

1. ~~Agenda → Ejecutar → Buscar/cronología~~ **hecho (30-sep-2026)**.
2. ~~Voz~~ **hecho (30-sep-2026)**; queda **enviar a LifeOS** (Servicios, drag & drop, abrir ficheros con la app)
   y el arranque automático.
3. ~~Desplegar el parche y cerrar el login con Google contra producción~~ **hecho (30-sep-2026)**, incluido el
   traslado de los datos a la cuenta de Google.
4. Detalles de §4 y deuda de §7 cuando el ciclo esté completo.
