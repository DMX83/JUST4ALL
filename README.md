# JUST4ALL — web y descargas

Este repositorio **solo publica los instaladores (DMG) y la web de producto**. No contiene
código fuente: el desarrollo vive en un repositorio privado.

| Qué | Dónde |
|---|---|
| Web | <https://app.amgprotech.com> — se sirve desde `docs/` de este repositorio con GitHub Pages |
| Descargas | [Releases](../../releases) — un DMG por app + `SHA256SUMS.txt` |
| Soporte | <hola@amgprotech.com> |
| Términos | <https://app.amgprotech.com/legal/terminos.html> |
| Terceros | <https://app.amgprotech.com/legal/terceros.html> |

## Qué contiene un release

- **`JUST4ALL-<versión>.dmg`** — el lanzador (hub) que instala y abre el resto de apps.
- **Un DMG por app**: `JUST4FOLDERS`, `JUST4DESK`, `JUST4PICT`, `JUST4PDF`, `JUST4CONVERT`, `LIFEOS`.
- **`SHA256SUMS.txt`** — hashes SHA-256 de cada DMG; el hub verifica el hash antes de abrir un DMG.

Los DMGs van **sin firma ni notarización** (pendiente de la cuenta de Apple Developer): la primera
vez macOS pedirá permitir la app en *Ajustes del Sistema → Privacidad y seguridad*.

## Licencia

Gratis para uso personal. El detalle legal está en la web:
[términos de uso](https://app.amgprotech.com/legal/terminos.html) y
[licencias de terceros](https://app.amgprotech.com/legal/terceros.html).
