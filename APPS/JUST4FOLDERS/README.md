# JUST4FOLDERS (macOS)

App nativa macOS en SwiftUI para analizar y organizar archivos por carpetas de categoria.
La meta v1.0 es evolucionar a arquitectura AppKit-first tipo commander (2 paneles).

## Documentacion relacionada

- Hub principal: `../../README.md`
- Roadmap general: `../../TODO.md`
- Tareas de este modulo: `TODO.md`
- Plan completo v1.0: `ROADMAP_V1.md`
- Checklist motor adaptativo: `TODO.md` (seccion "Motor adaptativo v1.0")

## Requisitos

- macOS 14+
- Xcode 15+

## Ejecutar

```bash
swift run
```

## Build DMG

```bash
./scripts/build_dmg.sh
```

## MVP actual

- Seleccion de carpeta origen y destino.
- Analisis recursivo de archivos no ocultos.
- Resumen por categoria:
  - Imagenes
  - Videos
  - Audios
  - Documentos
  - Comprimidos
  - Otros
- Organizacion por copia en carpeta destino con estructura por categoria.
- Manejo de colisiones de nombre (`archivo-1.ext`, `archivo-2.ext`, ...).
- Barra de progreso durante organizacion.
- Sidebar con ubicaciones autorizadas, favoritos y recientes.
- Reautorizacion guiada de bookmarks invalidos/stale.
- Deteccion de volumen read-only / NTFS con aviso en UI.
- Entitlements minimos definidos para App Sandbox.
- Listado incremental por lotes para carpetas grandes.
- Cache LRU de metadata (URLResourceValues) para reducir lecturas repetidas.
- Cache de UTType e iconos para reducir recomputo en tablas grandes.
- Operaciones locales base: mkdir, rename, delete a Papelera y delete permanente con confirmacion.
- Cola de jobs inicial (OperationQueue) para Copy/Move con progreso por items.
- Motor v1 inicial con:
  - Copy streaming por bytes.
  - BufferPool global (512MB).
  - Scheduler adaptativo por volumen (chunk/concurrencia heuristica).
  - Preflight de volumen (probe + mount check writable) con fail temprano en RO/NTFS sin escritura.
  - Planificador pre-run con orden: `mkdirs -> BigPhase -> SmallPhase`.
  - Auto-tuning por ventanas de telemetria (2-3s) con ajuste dinamico de workers.
  - BufferSizer adaptativo (big lane 4MB, escala hasta 8MB en SSD estable y reduce ante errores).
  - CopySmall (<=1MB en memoria) y Retry/Fallback con reintentos y cleanup de parciales.

## Notas

- El flujo actual copia archivos (no mueve ni elimina origen).
- No modifica metadata ni renombra por fecha en este MVP.
- El estado actual es bootstrap funcional; la UI definitiva de v1.0 sera AppKit-first.

## Ultimos fixes locales (2026-02-19)

- App fuerza activacion al arrancar para recuperar foco de teclado en prompts.
- Renombrar (toolbar y menu contextual) estabilizado:
  - renombra por URL objetivo capturada (no depende de seleccion post-modal),
  - mismo nombre se trata como no-op sin error.
- Menu contextual ampliado con `Nueva carpeta`.
- Pegado (`Cmd+V` / `Pegar item`) encola job de copia para mostrar progreso y usar motor J4FOps.
- Motor de copia recursiva corregido:
  - copia estable de archivos grandes en arboles,
  - correccion de calculo de rutas relativas (casos `/var` vs `/private/var`).
