# JUST4PICT (macOS)

App nativa macOS en SwiftUI para mejora automatica de imagenes por lotes.

## Documentacion vigente

- Tareas activas: `TODO.md`
- Changelog por version/build: `CHANGELOG.md`
- Arquitectura activa: `ENHANCE_ARCHITECTURE.md`
- QA local (100/1000 + benchmarks): `QA_BATCH_LOCAL.md`

## Documentacion historica

- Roadmap inicial MVP: `ROADMAP_V1.md`
- Release notes historicas: `RELEASE_NOTES_v0.1.0.md`
- Checklist post-MVP (archivo historico): `JUST4PICT_POSTMVP_CHECKLIST.md`

## Requisitos

- macOS 13+
- Xcode 15+

## Ejecutar

```bash
swift run
```

## CLI de lote (`just4pict-cli`)

El mismo binario funciona como CLI **sin UI**, usando el pipeline local (PRO) de la app:
si el primer argumento es un comando conocido, se ejecuta el lote y se sale; sin argumentos,
arranca la interfaz normal.

```bash
# Ayuda / presets / versión
scripts/just4pict-cli help
scripts/just4pict-cli presets
scripts/just4pict-cli version

# Procesar imágenes (ficheros NUEVOS con sufijo, nunca sobrescribe)
scripts/just4pict-cli enhance ~/fotos/*.jpg -p documento -f png -o ~/salida
scripts/just4pict-cli enhance foto.jpg -p auto --profile web --json
```

Opciones de `enhance`: `-p/--preset` (auto·retrato·paisaje·documento·ecommerce),
`-f/--format` (png·jpg·heic·webp·tiff), `-q/--quality` (0.1–1.0), `-o/--output`,
`--profile` (original·social·web·weblite·ecommerce), `--scene` (forzar escena) y `--json`.

Convenciones: **stdout** = una ruta por fichero creado (JSON con `--json`), **stderr** =
progreso/errores; códigos `0` ok · `2` uso inválido · `3` fallo total · `4` parcial.

El wrapper `scripts/just4pict-cli` **verifica que el binario soporte el CLI** antes de usarlo
(marca incrustada): un build anterior al CLI arrancaría la app con UI y dejaría el comando
colgado; por eso, si falla, compila primero (`swift build`) y vuelve a probar.

**Integración en JUST4FOLDERS (hecha, v2.3.7)**: el submenú contextual «JUST4PICT ▸ → Mejorar con
JUST4PICT ▸» de JUST4FOLDERS ejecuta este CLI con 5 presets (Automático · Retrato · Paisaje ·
Documento · Ecommerce) sobre la selección, en background y sin sobrescribir; se oculta si el CLI
no está disponible y los presets se deshabilitan si la selección no tiene imágenes. Es el **mismo
binario y el mismo pipeline**: no hay código duplicado entre ambas apps.

## Build DMG

```bash
./scripts/build_dmg.sh
```

## Estado actual (2026-03-23)

JUST4PICT esta cerrado como MVP funcional y en fase de afinado post-MVP.

### Capacidades activas

- Batch por archivo/carpeta con progreso y reintento por item.
- Presets: `Auto`, `Retrato`, `Paisaje`, `Documento`, `Ecommerce`.
- Preview manual con boton `Enhance` y comparativa `Original / PRO / IA`.
- Modo `Reconstruir IA` opcional (si hay `OPENAI_API_KEY`).
- `AUTO` con decision por escena y persistencia de decision efectiva en historial.
- Export por perfil de destino: `Original`, `Social`, `Web`, `Web <300KB`, `Ecommerce`.
- Formatos de salida: `PNG`, `JPG`, `HEIC`, `WEBP`, `TIFF`.
- Cobertura de tests de sharpen selectivo por escena (`bruma`, `detalle vegetal`, `texto denso`) en `LocalPhotoPipelineTests`.

### Contratos de producto vigentes

- `PNG` sigue como formato por defecto y primera opcion visible.
- Calidad por defecto `1.0`.
- `PRO` es baseline visual principal y no debe degradarse.
- La preview sigue siendo manual (sin auto-refresh agresivo).
- `IA` decide receta; el render final sigue en pipeline local salvo `Reconstruir IA` explicito.

## Build, versionado y naming

JUST4PICT compila con version + build + build stamp.

- `CFBundleShortVersionString`: version de marketing.
- `CFBundleVersion`: build incremental.
- `J4ABuildStamp`: marca de build (timestamp + commit corto).

Nomenclatura de artefactos DMG:

- `dist/JUST4PICT-<version>+<buildStamp>.dmg`
- Alias: `dist/JUST4PICT.dmg` y `dist/JUST4PICT-latest.dmg`

La traza de cambios por build se mantiene en `CHANGELOG.md`.

## Configuracion IA

Definir `OPENAI_API_KEY` en entorno o `.env.secrets`.

Orden de resolucion:

1. Variable de entorno `OPENAI_API_KEY`
2. Archivo `.env.secrets` en raiz del repo (o padres cercanos)

## Configuracion opcional Real-ESRGAN

Setup recomendado:

```bash
./scripts/setup_realesrgan_local.sh
```

Variables opcionales:

- `JUST4PICT_REAL_ESRGAN_BIN`
- `JUST4PICT_REAL_ESRGAN_MODELS`

Si no existen, el modulo intenta autodeteccion local en `.cache/realesrgan`.

## Sugerencias nuevas (post-MVP)

- Extraer la orquestacion de `ContentView` a view-models/modulos para reducir complejidad.
- Consolidar un `ExportPipeline` dedicado (hoy parte vive en `ImageEnhancer` + `ImageExportWriter`).
- Completar validacion visual manual final de ojos/cejas en retratos reales adicionales.
- Formalizar release firmada/notarizada cuando exista cuenta Apple Developer.
