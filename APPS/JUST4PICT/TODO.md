# TODO — JUST4PICT (Post-MVP)

Fecha de actualizacion: 2026-03-23

Este archivo es la fuente de verdad de trabajo activo.
El backlog historico del MVP queda en `ROADMAP_V1.md` y `JUST4PICT_POSTMVP_CHECKLIST.md`.

## Guardrails vigentes (no romper)

- `PNG` sigue como formato default y primera opcion visible.
- Calidad default `1.0`.
- Preview manual con `Enhance` (sin auto-refresh agresivo).
- `PRO` se mantiene como baseline visual principal.
- `IA` no reemplaza el pipeline local por defecto.
- Compatibilidad con historial, naming con colisiones y export multi-formato.

## Prioridad alta

- [ ] **Refactor UI/orquestacion:** dividir `ContentView.swift` en view-models y componentes de dominio para batch, preview e IA.
- [x] **Test por escena de sharpen selectivo:** cubiertos casos de paisaje con bruma, detalle vegetal y texto denso en `LocalPhotoPipelineTests`.
- [ ] **Validacion visual final de retrato:** cerrar revision manual de ojos/cejas en muestras reales adicionales.
- [ ] **Firma y notarizacion:** preparar release firmada cuando exista cuenta Apple Developer.

## Prioridad media

- [ ] Extraer `ExportPipeline` dedicado (coordinar escritura/render final fuera de `ImageEnhancer`).
- [ ] Afinar criterios de `AUTO` en casos limite (documento vs ecommerce con branding ligero).
- [ ] Añadir metrica simple de regresion visual automatizada para presets clave (`Retrato`, `Paisaje`, `Documento`, `Ecommerce`).
- [ ] Consolidar reportes QA en una salida unica por corrida (tiempo, memoria, conteo de errores).

## Prioridad baja

- [ ] Revisar texto/copy de estado IA para hacerlo mas corto y consistente en UI.
- [ ] Agregar comando CLI minimo para ejecucion de lote local sin UI (`just4pict-cli`).
- [ ] Evaluar opcion de preset de export rapido para web/marketplaces con defaults cerrados.

## Sugerencias nuevas

- [ ] **[SUGERENCIA NUEVA] Telemetria local por build:** guardar resumen JSON por corrida (`buildStamp`, preset, tiempo, memoria max, fallos) para comparar regresiones entre builds.
- [ ] **[SUGERENCIA NUEVA] Snapshot de receta efectiva por item:** persistir receta final aplicada (incluyendo fallback IA) para reproducibilidad exacta.
- [ ] **[SUGERENCIA NUEVA] Smoke test de release:** script unico que ejecute build DMG + `swift test` criticos + validacion de `J4ABuildStamp` en `Info.plist`.
- [ ] **[SUGERENCIA NUEVA] Matriz QA por escena:** set fijo de muestras por escena con expected windows mantenibles en un archivo dedicado.

## Hecho recientemente (resumen operativo)

- [x] `ImageExportWriter` unificado para evitar doble resize y centralizar byte-budget.
- [x] `CIContext` compartido en modulos principales.
- [x] `autoreleasepool` aplicado en rutas pesadas (preview/export/batch detached).
- [x] QA local validada para lotes de 100 y 1000 imagenes.
- [x] Baseline MVP con DMG funcional y build stamp validado.

## Referencias

- Arquitectura activa: `ENHANCE_ARCHITECTURE.md`
- QA local y benchmarks: `QA_BATCH_LOCAL.md`
- Changelog por build: `CHANGELOG.md`
