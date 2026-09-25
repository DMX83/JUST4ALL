# G1 — Pantalla «Inicio» (centro de control + omnibox ⌘K) — 25-sep

El buscador deja de ser la identidad de arranque: la ventana principal pasa a ser **Inicio**
(bandeja de decisiones, actividad de hoy, estado y accesos), y la búsqueda se reparte entre el
**omnibox ⌘K** (resultados inmediatos bajo el campo; Enter abre el primero) y la ventana
**«Buscar» ⌘F** (la vista completa de filtros/contenido, con el mismo `SearchViewModel`
compartido e idempotente).

## Capturas

| Fichero | Qué muestra |
|---|---|
| `inicio.png` | Inicio: bandeja (cuarentena + deshacer), actividad (94 hoy), estado (destino/índice/IA/reglas) y accesos |
| `inicio-omnibox.png` | Omnibox ⌘K con «pdf»: resultados inmediatos + «Ver todos los resultados (227)» |
| `buscar.png` | Ventana «Buscar» con la consulta compartida, filtros y «En contenido» activo |

Capturadas con `screencapture -l <windowID>` (app al frente + `caffeinate -u`).

## Piezas

- `HomeView.swift` (nueva); `ContentView` pasa a ser la ventana «Buscar»; `Just4DeskApp` crea el
  `SearchViewModel` compartido y añade `Window("Buscar", id: "search")` + comandos ⌘F/⌘K.
- Modelo: `start()` idempotente (`hasStarted`) y `refreshQuarantineCount()` (listado plano).
- Notificaciones nuevas: `j4iOpenSearch`, `j4iFocusOmnibox`.
