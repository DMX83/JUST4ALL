# JUST4PICT (macOS)

App nativa macOS en SwiftUI para edicion y mejoramiento automatico de imagenes por lotes.

## Documentacion relacionada

- Hub principal: `../../README.md`
- Roadmap general: `../../TODO.md`
- Tareas del modulo: `TODO.md`
- Plan v1: `ROADMAP_V1.md`

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

## Alcance MVP actual

- Seleccion de imagenes por archivo o carpeta (escaneo recursivo).
- Cola por lotes con progreso global y log por item.
- Salida por defecto orientada a maxima calidad:
  - `PNG` aparece como primera opcion del selector.
  - `PNG` es el formato por defecto del proyecto.
  - La calidad por defecto es `1.0`; no se fuerza `JPG` con compresion por defecto.
- Presets 1-click:
  - Auto
  - Retrato
  - Paisaje
  - Documento
  - Ecommerce
- Pipeline de mejora automatica:
  - Deteccion discreta del tipo de imagen en preset Auto (retrato/documento/paisaje) para ajustar parametros sin intervención manual.
  - Auto-ajustes de Core Image.
  - Correccion de brillo/contraste/saturacion.
  - Reduccion de ruido suave.
  - Sharpen de luminancia.
  - Upscale automatico con Lanczos a HD (lado mayor >= 1920) si la imagen es pequena.
  - Recuperacion de detalle post-upscale (denoise + nitidez adaptativa) para mejorar fotos pequenas.
  - Modo interno conservador para retratos en post-upscale (evita sobreprocesado de piel/rostro).
  - Ajuste "Retrato Pro" interno: recupera detalle de cabello/ropa manteniendo aspecto natural.
- Sugerencia IA opcional (OpenAI) para:
  - Recomendar y aplicar preset/calidad objetivo para mejora maxima (HD/calidad alta).
  - Usar prompt interno del sistema (sin que el usuario escriba prompt).
- Export con colisiones resueltas (`-enhanced`, `-enhanced-1`, ...).
- Formatos de salida:
  - PNG (default recomendado para maxima calidad)
  - JPG
  - HEIC
  - WEBP
  - TIFF

## Recomendaciones de producto (siguiente paso)

- Before/After con slider.
- Resize inteligente para redes/ecommerce.
- Perfil de export rapido para miniaturas web.
- Integracion de deteccion de documento con Vision para recorte/enfoque automatizado.

## Configuracion IA local

- Definir `OPENAI_API_KEY` en entorno o en `../../.env.secrets`.
- La app busca la key en este orden:
  1) variable de entorno `OPENAI_API_KEY`
  2) archivo `.env.secrets` en la raiz del repo (y padres cercanos)
- Nota: para apps distribuidas, no se recomienda embutir la key en cliente.

## Privacidad de historial IA

- El historial guarda por defecto **resumen** del prompt IA (no el prompt completo).
- Esto reduce exposición de contenido sensible en `UserDefaults`.
- El flujo de IA está orientado a 1-click, sin edición manual de prompt.
