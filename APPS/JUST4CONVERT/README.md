# JUST4CONVERT (macOS)

App nativa macOS en SwiftUI para conversion de audio, video e imagenes.

## Documentacion relacionada

- Hub principal: `../../README.md`
- Roadmap general: `../../TODO.md`

## Requisitos

- macOS 13+
- Xcode 15+

## Ejecutar

```bash
swift run
```

## Build DMG

```bash
./scripts/build_dmg.sh
```

## Alcance actual

- Cola multiarchivo con procesamiento paralelo configurable (default: 80% de nucleos disponibles).
- Progreso por item, progreso global y ETA.
- Edicion de presets por item (sin afectar preset global).
- Historial local de conversiones con abrir/revelar en Finder.
- Drag & drop de archivos y carpetas.
- Seleccion de carpetas con expansion recursiva de archivos compatibles.
- Nombres de salida por plantilla (`{name}`, `{format}`, `{date}`) con manejo de colisiones.
- Reintento rapido por item fallido y diagnostico basico de errores.

### Formatos soportados

- Audio:
  - Entrada: archivos de audio (`UTType.audio`)
  - Salida: `m4a`, `mp3`
  - `flac` aparece en UI como pendiente (no habilitado)
- Video:
  - Entrada: archivos de video (`UTType.movie` / `UTType.video`)
  - Salida: `mov`, `mp4`, `mkv`
  - `mkv` usa ffmpeg empaquetado en `Sources/JUST4CONVERT/ffmpeg/ffmpeg`
  - Codec/preset: H.264 o HEVC, con opciones de bitrate/resolucion/fps
- Imagen:
  - Entrada: imagenes (`UTType.image`)
  - Salida: `jpg`, `png`, `heic`, `heif`, `webp`, `tiff`, `bmp`, `gif`

## Notas

- La salida se guarda en la carpeta elegida por el usuario.
- FLAC real aun no esta implementado.
- El control de bitrate efectivo en la ruta AVFoundation de video sigue siendo limitado.
