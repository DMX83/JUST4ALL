# Changelog — JUST4PICT

Este changelog sigue una convencion simple por version + build stamp.

Formato de build usado en artefactos:

- Version: `CFBundleShortVersionString`
- Build: `CFBundleVersion`
- Build stamp: `J4ABuildStamp` (`YYYYMMDDHHMMSS-<commit-corto>`)
- Artefacto: `JUST4PICT-<version>+<buildStamp>.dmg`

## [Unreleased] - 2026-03-23

### Changed

- Limpieza de documentacion del modulo para dejar solo contexto vigente en `README.md`.
- `TODO.md` reescrito como backlog post-MVP (sin historico mezclado).
- Se añadieron sugerencias nuevas etiquetadas como `[SUGERENCIA NUEVA]` en `TODO.md`.
- Refactor en curso de `ContentView`: estado extraido a `BatchStateViewModel`, `AIResolutionViewModel` y `PreviewStateViewModel`.

### Added

- Nuevo `CHANGELOG.md` para trazabilidad de cambios por version/build.
- Cobertura de test por escena para sharpen selectivo en `LocalPhotoPipelineTests` (bruma, detalle vegetal y texto denso).

## [0.1.0+20260322114546-6fe34bc] - 2026-03-22

### Added

- Baseline MVP funcional consolidada con presets `Auto`, `Retrato`, `Paisaje`, `Documento`, `Ecommerce`.
- Preview manual `Original / PRO / IA` con comparacion before/after.
- Modo opcional `Reconstruir IA` para casos extremos.
- Export por perfiles (`Original`, `Social`, `Web`, `Web <300KB`, `Ecommerce`).
- QA local de lote (100/1000 imagenes) y benchmarks por preset/tamano.

### Changed

- `ImageEnhancer` centraliza `CIContext` compartido para analisis/pipeline/upscale/aislamiento de producto.
- `ImageExportWriter` unifica politica de export y evita doble resize.
- Se incorporan `autoreleasepool` en rutas pesadas (preview/export/batch detached) para bajar RSS.

### Fixed

- Mayor estabilidad de memoria en corrida local de 100 imagenes (segun `QA_BATCH_LOCAL.md`).

### Packaging

- DMG validado localmente con volumen montable y `J4ABuildStamp` verificado.
- Alias canonicos de salida: `dist/JUST4PICT.dmg` y `dist/JUST4PICT-latest.dmg`.

## Nota

- La release del repositorio que contiene esta baseline del modulo se publico como `v0.1.3` (release unsigned).
