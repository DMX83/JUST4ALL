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
  - Deteccion discreta del tipo de imagen en preset Auto (retrato/documento/paisaje/foto oscura) para ajustar parametros sin intervención manual.
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
  - Resolver por imagen en batch sin reutilizar una unica receta para todo el lote.
  - Reutilizar cache local de receta por imagen para no repetir analisis IA innecesario dentro de la misma sesion.
- Export con colisiones resueltas (`-enhanced`, `-enhanced-1`, ...).
- Perfil de export por destino:
  - `Original`: conserva tamaño actual.
  - `Social`: limita el lado mayor a `2048`.
  - `Web`: limita el lado mayor a `1600`.
  - `Ecommerce`: limita el lado mayor a `2000` o `2200` si el preset es `Ecommerce`.
- Formatos de salida:
  - PNG (default recomendado para maxima calidad)
  - JPG
  - HEIC
  - WEBP
  - TIFF

## Contratos actuales que no se deben romper

- `PNG` es la salida por defecto del proyecto y debe seguir siendo la primera opcion visible en la UI.
- La calidad por defecto del proyecto es `1.0`; no se debe reintroducir `JPG` con compresion por defecto.
- El modo `PRO` es la referencia visual del producto y no debe degradarse al introducir logica nueva de `IA`.
- La preview manual con boton `Enhance` debe seguir siendo estable:
  - sin auto-refresh agresivo,
  - con vista `Original / PRO / IA`,
  - y con doble click para visor ampliado.
- `AUTO` debe seguir heredando `Retrato` cuando detecta cara. Cualquier refactor de escena debe preservar esa decision.
- `AUTO` ya distingue mejor documento por texto + baja saturacion, foto oscura por luminancia/saturacion y producto `ecommerce` por fondo claro/uniforme y sujeto centrado, sin dejar de priorizar retrato cuando detecta cara.
- La `IA` actual debe entenderse como capa de decision y ajuste; no debe reemplazar sin control el pipeline local.
- La receta IA ya puede influir en `preset`, `format`, `quality` y `upscale`.
- `faceRestore` ya existe como etapa local selectiva y conservadora sobre rostros detectados.
- Sigue sin ser un modelo dedicado de restauracion facial; hoy actua como refuerzo suave de detalle/tono en mascara facial.
- La resolucion IA por imagen se cachea en memoria durante la sesion para evitar llamadas repetidas sobre la misma foto en el mismo contexto base.
- El resize por destino se aplica solo al export final; la preview sigue mostrando el pipeline sin ese remuestreo de salida.
- La UI ya muestra mejor la decision efectiva de `AUTO` durante la preview para evitar ambigüedad sobre el preset realmente aplicado.
- El lote debe respetar el perfil de export seleccionado al iniciar; no debe mezclar destinos si el usuario cambia la UI a mitad de proceso.
- En `AUTO`, `ecommerce` puede seguir ganando con texto ligero si la imagen mantiene rasgos claros de producto; `documento` debe reservarse para densidad de texto real.
- El historial IA debe seguir guardando por defecto solo resumen del prompt, no el prompt completo.
- Los cambios futuros de `IA` deben mantener compatibilidad con:
  - export multi-formato,
  - naming con colisiones resueltas,
  - historial local,
  - y tests de diagnostico/QA del modulo.

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
