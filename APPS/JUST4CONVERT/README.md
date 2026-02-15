# JUST4CONVERT (Native MVP)

MVP nativo macOS en SwiftUI para conversion basica de audio, video e imagenes.

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

- Audio: exporta a M4A (AVFoundation)
- Video: exporta a MOV (AVFoundation)
- Imagen: exporta a JPG o PNG (ImageIO)

## Notas

- Usa conversion de un archivo por ejecucion.
- La salida se guarda en la carpeta elegida o al lado del archivo original.
