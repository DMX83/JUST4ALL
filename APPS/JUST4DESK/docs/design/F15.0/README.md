# F15.0 — Sistema de diseño e interfaz (25-sep)

Rediseño visual completo de JUST4DESK: de «herramienta interna» a producto presentable.
Decisiones tomadas de forma autónoma (el usuario no estaba disponible) siguiendo su petición
—«un diseño moderno y elegante»— y las recomendaciones de la auditoría:

- **Acento de marca**: índigo/violeta del sistema (combina con las chispas de la IA).
- **Estilo**: «nativo refinado» — materiales y jerarquía de macOS, llevados al detalle;
  sin glass ni gradientes llamativos que envejezcan mal.
- **Alcance**: sistema de diseño + las cuatro ventanas (buscador, Explorador, Por revisar,
  Ajustes) con QA visual en **claro y oscuro**.

## Sistema (`Sources/JUST4DESK/DesignKit.swift`)

- Tokens: `J4I.Space` (4/8/12/16/24), `J4I.Radius` (6/10/14), semánticos
  (`brand`, `success`, `warning`, `danger`, `surface`, `well`, `hairline`), sombra de tarjeta.
- Componentes: `BrandMark`, `Chip`/`ToggleChip`/`ChipLabel`, `J4ICard`, `SectionHeader`,
  `PropertyRow`, `StatusPill`, `J4IEmptyState`, `GhostIconButton`, `ToolbarSeparator`.
- Títulos en `design: .rounded`; contadores con cifras tabulares; `tint` de marca por ventana.

## Capturas

Antes (`*-antes.png`) y después (`*-despues-*.png`), en oscuro y claro:

| Ventana | Antes | Después (oscuro) | Después (claro) |
|---|---|---|---|
| Buscador | `buscador-antes.png` | `buscador-despues-oscuro.png` | `buscador-despues-claro.png` |
| Explorador | `explorador-antes.png` | `explorador-despues-oscuro.png` | `explorador-despues-claro.png` |
| Por revisar | `revisar-antes.png` | `revisar-despues-oscuro.png` | `revisar-despues-claro.png` |
| Ajustes (IA) | `ajustes-antes.png` | `ajustes-despues-oscuro.png` | `ajustes-despues-claro.png` |

Capturas hechas con `screencapture -l <windowID>` (ventana al frente + pantalla despierta).

## Pendientes de diseño (candidatos, ver `TODO.md` → F15.x)

Icono propio de app/Dock, densidad de listas configurable, animaciones de paneles,
pasada de accesibilidad (VoiceOver, contraste AA) y pantalla de bienvenida si se decide.
