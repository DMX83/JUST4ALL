---
name: just4desk
description: "Use when working on JUST4DESK (APPS/JUST4DESK): macOS app with a control-room home («Inicio»: inbox, activity, state, omnibox ⌘K) plus instant search (SQLite FTS5 + FSEvents) and intelligent document filing (PDFKit/Vision OCR + optional DeepSeek JSON API). Covers module map, build/test/DMG commands, privacy guardrails, automatic-filing safety (undo journal, «sin clasificar» review queue, never-delete) and the mandatory MEMORY.md update cycle. Trigger words: JUST4DESK, Inicio, omnibox, buscador instantáneo, organizador de documentos, taxonomía, archivar documentos, Descargas, FTS5, FSEvents, DeepSeek, FilingPlanner, sin clasificar, por revisar, undo."
---

# JUST4DESK — desarrollo

App macOS (SwiftUI + SPM) en `APPS/JUST4DESK`. Tres pilares: **Inicio** (centro de control: bandeja,
actividad, estado, accesos) + **buscador instantáneo** (omnibox ⌘K en Inicio y ventana «Buscar» ⌘F)
+ **organizador inteligente** de documentos. Subapp del hub JUST4ALL.

## Ciclo obligatorio (implementar → validar → documentar)

1. **Leer** `APPS/JUST4DESK/MEMORY.md` y `TODO.md` antes de tocar nada.
2. **Implementar** un paso de fase (ver `TODO.md`).
3. **Validar**: `swift build` + `swift test` en `APPS/JUST4DESK`; para UI, `swift run`.
4. **Actualizar docs**: entrada nueva en `MEMORY.md` (estado + hito), `CHANGELOG.md` si hay
   cambios de producto, y marcar `TODO.md`.

## Mapa de módulos

| Módulo | Ruta | Qué vive aquí |
|---|---|---|
| `J4ICore` | `Sources/J4ICore` | Modelos, `Taxonomy`, `FilingProposal`, plantilla/saneado de nombres, `FilingPlanner` |
| `J4IIndex` | `Sources/J4IIndex` | Índice SQLite FTS5, crawler, ingesta FSEvents, query API |
| `J4IDocs` | `Sources/J4IDocs` | PDFKit, Vision OCR, txt/md/rtf, docx/xlsx, regex de metadatos |
| `J4IAI` | `Sources/J4IAI` | `DeepSeekClient`, `DeepSeekFilingAdvisor`, cache por hash |
| `J4IFiling` | `Sources/J4IFiling` | Ejecución mkdirs+move (J4FOps), journal+undo, «sin clasificar», simulación |
| `J4IMCP` / `JUST4DESKMCP` | `Sources/J4IMCP`, `Sources/JUST4DESKMCP` | Servidor MCP local (stdio, solo lectura) para agentes: `buscar_archivos` / `leer_documento` (ver `docs/MCP.md`) |
| `JUST4DESK` | `Sources/JUST4DESK` | App SwiftUI: **Inicio** (`HomeView`), ventana «Buscar», explorador, revisión, ajustes |

Dependencia local: `APPS/JUST4FOLDERS` (`.package(path: "../JUST4FOLDERS")`, productos
`J4FFileSystem`/`J4FOps`; los library products se añadieron en F0).

## Comandos

```bash
cd APPS/JUST4DESK
swift build
swift test
swift run                 # app en dev
swift build --product JUST4DESKMCP   # servidor MCP para agentes (docs/MCP.md)
./scripts/run.sh          # relanza la app desacoplada de la terminal (dev)
./scripts/build_dmg.sh    # DMG en dist/ (usa scripts/app_env.sh del repo)
./scripts/qa_smoke.sh     # build + test + checklist manual
./scripts/log_watch.sh    # registro en vivo (unificado o --file)
```

QA/benchmarks grandes: env-gated (p. ej. `J4I_RUN_100K_PERF=1`), nunca en el camino normal de tests.

## Guardrails (no romper)

- **Nunca borrar**: el archivado solo mueve; undo por lote e item siempre disponible.
- **Búsqueda = índice**: prohibido recorrer el árbol en tiempo de query (lección de JUST4FOLDERS).
- **Completitud por root**: nunca marcar un root como indexado con datos parciales; filtrar por `root_id`, no con `LIKE`.
- **Privacidad**: a DeepSeek solo texto truncado (≤ 4000 chars) + metadatos mínimos; nunca archivos.
  Sin key → modo solo-reglas. La key no se persiste.
- **Estabilidad de fichero**: no procesar hasta que size+mtime estén estables; ignorar
  `.part/.crdownload/.download/.tmp` y ocultos.
- **Colisiones**: sufijo `-1`, `-2`… nunca overwrite. Nombres saneados según plantilla.
- **IA no bloquea**: error/JSON vacío → retry corto → reglas locales (nombre → texto → extensión) →
  sin clasificar si hay duda.

## Convenciones

- Taxonomía seed en español (12 categorías), configurable en `taxonomy.json`; carpetas creadas de forma perezosa.
- Plantilla de nombre: `YYYY-MM-DD_Emisor_Tipo[_descriptor].ext`.
- macOS 14+ (forzado por la dependencia de JUST4FOLDERS).
- Versionado/stamp: `scripts/app_env.sh` (raíz del repo); `J4ABuildStamp` inyectado por `scripts/build_dmg.sh`.
- Registro: `J4Log.debug/info/warn/error(categoría, mensaje)`; visor en la app (⌘L); archivo en
  `~/Library/Logs/JUST4DESK/just4desk.log`; los tests lo silencian solos (`J4I_LOG_FILE=0` a mano).

## Referencias

- Docs del módulo: `README.md`, `ARCHITECTURE.md`, `PRIVACY.md`, `MEMORY.md`, `TODO.md` (en `APPS/JUST4DESK/`).
- Patrón IA/planner: `APPS/JUST4PICT/Sources/JUST4PICT/{OpenAIImageAdvisor,EnhancementPlanner}.swift`.
- MCP para agentes: `docs/MCP.md` (protocolo, herramientas y configuración).
- Auditoría vigente: `docs/AUDITORIA-2026-09-28.md` (verificaciones, incidencias y deudas).
- Motor de operaciones: `APPS/JUST4FOLDERS/Sources/J4FOps/`.
- Antipatrones de búsqueda a evitar: `APPS/JUST4FOLDERS/Sources/J4FFileSystem/PathSearchIndex.swift`.
