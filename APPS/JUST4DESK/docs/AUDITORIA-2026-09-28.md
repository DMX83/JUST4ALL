# Auditoría — JUST4DESK (2026-09-28)

Auditoría completa tras cerrar **G7.2–G7.4** (MCP para agentes, re-extracción de contenido y
reindexado conservador). Alcance: build, suite completa, datos reales, verificación en vivo,
documentación y deuda técnica.

## 1. Verificaciones

| Qué | Resultado |
|---|---|
| `swift build` (app + `JUST4DESKMCP` + módulos) | ✅ sin errores |
| `swift test` | ✅ **211 ejecutados** (210 en verde + 1 skip = benchmark opt-in) |
| MCP por tubería real | ✅ `initialize` + `tools/list` + `buscar_archivos` «recibo de luz» → 9 resultados (Iberdrola Gas primero) |
| App en vivo | ✅ arranca; semántica con **3.997 vectores** (324 de contenido); **344 textos re-extraídos** |
| Journal/undo (G6) | ✅ intacto; el ciclo aplicar→Deshacer ya quedó verificado en vivo y no se tocó |

## 2. Incidencias encontradas y resueltas

1. **«Reindexar» borraba textos y vectores** (grave y silencioso): el reindexado del 27-sep
   (4.603 entradas) dejó los 3.950 ficheros sin `doc_text` ni `embeddings`. **Arreglado (G7.4)**:
   snapshot en tablas temporales + re-vinculado por ruta tras el crawl + mantenimiento post-crawl;
   la app recuperó sola los datos al arrancar.
2. **299 textos históricos huérfanos** (de reindexados anteriores a G7): el carry-over evita
   nuevas pérdidas y `ContentBackfill` (G7.3) re-extrajo todo lo pendiente con marcadores vacíos
   para no repetir OCR.
3. **El chat citaba carpetas** (feedback del usuario): filtradas del contexto del chat; la
   búsqueda normal y el MCP siguen mostrando carpetas donde corresponde.
4. **Los tests ensucian el registro real**: `ContentBackfillTests`/`ColdArchiveTests` escriben
   líneas en `~/Library/Logs/JUST4DESK/just4desk.log` (J4Log no se silencia en todos los targets).
   Cosmético; candidato a limpieza.
5. **Huérfanos residuales de `embeddings`** (~50 por el vaivén de ficheros): inocuos (la búsqueda
   los ignora); candidato a barrido periódico.

## 3. Estado real del sistema (medido)

- Archivo: **4.603 entradas · 3.950 ficheros** (~32 GB) organizados; taxonomía de 17 nodos.
- Texto: cientos de ficheros con `doc_text` (344 recuperados hoy; 2 marcados «sin texto»).
- Semántica: **3.997 vectores locales** (`ctx-latin-512`), relleno completo en ~1 min.
- IA: contadores reales de llamadas/tokens; cap diario 400; chat y sugerencias respetan el interruptor.
- Suite: **211** (210 ✅ + 1 skip); compilación sin warnings relevantes.

## 4. Deudas y pendientes (orden sugerido)

1. **G5.1 — etiquetas Finder** (necesita decisión del usuario).
2. **DMG firmado/notarizado + Quick Action de Finder + notificación de lote** (para «vendible»).
3. **UI de estado de los rellenos** (contenido/vectores) en Ajustes (hoy solo registro).
4. **xlsx** en `TextExtractor` (cobertura documental).
5. **Silenciar el log en tests** (`J4I_LOG_FILE=0` automático en todos los targets).
6. **Auditoría visual/accesibilidad** (VoiceOver, contraste, densidad) e **icono propio**.
7. **CI** (GitHub Actions con `swift test`).

## 5. Riesgos

- **Privacidad**: sin cambios — DeepSeek solo con interruptor y texto truncado (≤4.000 caracteres);
  MCP es local y de solo lectura (lo que un agente externo haga con el texto queda bajo sus reglas;
  documentado en `docs/MCP.md`).
- **Rendimiento**: el puntuado semántico es fuerza bruta sobre 4k vectores (< 20 ms); si el archivo
  crece ×10, valorar un índice ANN — no necesario hoy.
- **Reindexados**: ahora conservadores y cubiertos por tests (`ReindexPreservationTests`).

## 6. Actualización (28-sep, tarde)

Resueltas desde esta foto (verificadas): **G5.1** etiquetas Finder (commit `a4f384a`, validado en
vivo), lote **N5–N9** (avisos del sistema, ⌘Z + operadores, panel Estadísticas, **xlsx** en
extracción, QuickLook en resultados, **CI en GitHub Actions** → deudas 4 y 7 cerradas) y el **log
en tests** (deuda 5): la causa era que SwiftPM no define las variables de XCTest — guard añadido en
`J4Log` (`NSClassFromString("XCTestCase")`) y verificado por mtime/tamaño del archivo real.

**Corrección de conteo**: la suite DESK es **125** (5 bundles) tras el refactor `19d3d5e` que movió
`J4ICoreTests` a `PACKAGES/J4SHARED` (**116** allí). El «211» de la sección 1 sumaba tests ya
movidos. Estado global hoy: DESK 125 + J4SHARED 116 + FOLDERS 43 = **284 en verde**.

**Deuda #3 resuelta (28-sep, tarde)**: Ajustes → Indexado muestra el estado de los rellenos
(contenido/vectores, última pasada) con «Rellenar ahora»; validado en vivo (manual → semántica
3950/3950). Deudas vivas: DMG firmado/notarizado + Quick Action (N6; firma con licencia),
accesibilidad/icono y densidad/animaciones (F15.x).
