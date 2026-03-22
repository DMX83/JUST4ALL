# JUST4PICT (macOS)

App nativa macOS en SwiftUI para edicion y mejoramiento automatico de imagenes por lotes.

## Documentacion relacionada

- Hub principal: `../../README.md`
- Roadmap general: `../../TODO.md`
- Tareas del modulo: `TODO.md`
- Roadmap inicial: `ROADMAP_V1.md`
- Arquitectura activa: `ENHANCE_ARCHITECTURE.md`
- QA local: `QA_BATCH_LOCAL.md`
- Notas de release: `RELEASE_NOTES_v0.1.0.md`

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

Validacion baseline 2026-03-22:

- DMG generado y montado correctamente.
- App presente en el volumen: `JUST4PICT.app`.
- Build stamp validado: `20260322114546-6fe34bc`.
- pipeline de build del modulo deja tambien `dist/JUST4PICT.dmg` como alias canonico para release assets.

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
- `Retrato/PRO` mantiene una unica baseline activa; ya no se conserva un modo `legacy` paralelo dentro del pipeline.
- La preview manual con boton `Enhance` debe seguir siendo estable:
  - sin auto-refresh agresivo,
  - con vista `Original / PRO / IA`,
  - y con doble click para visor ampliado.
- `AUTO` debe seguir heredando `Retrato` cuando detecta cara. Cualquier refactor de escena debe preservar esa decision.
- `AUTO` ya distingue mejor documento por texto + baja saturacion, foto oscura por luminancia/saturacion y producto `ecommerce` por fondo claro/uniforme y sujeto centrado, sin dejar de priorizar retrato cuando detecta cara.
- `AUTO` ya esta validado tambien con muestras reales del repo para `document` y `ecommerce` (`images_document_orig.jpeg`, `image_commerce_orig.jpeg`).
- La heuristica `ecommerce` ya contempla tambien foto de catalogo movil real, no solo estudio con fondo blanco puro.
- En `Ecommerce`, el pipeline ya puede detectar el producto principal, eliminar el fondo y recomponerlo centrado sobre fondo blanco.
- En `Documento`, el pipeline ahora fuerza un remate mas claro para evitar fondos grises en export de hojas blancas.
- La `IA` actual debe entenderse como capa de decision y ajuste; no debe reemplazar sin control el pipeline local.
- La receta IA ya puede influir en `scene`, `preset`, `format`, `quality` y `upscale`.
- Cuando la receta IA trae una `scene` valida, esa escena ya puede sobreescribir la deteccion local para mantener coherencia entre la decision IA y el pipeline ejecutado.
- El balance de blancos adaptativo de `PRO` ya usa referencia de altas luces cuando existe suficiente blanco fiable en la escena, con fallback al promedio global cuando no la hay.
- En `Paisaje`, esa correccion ahora es mas conservadora: acepta nubes gris-claro como referencia util, pero mezcla la correccion de forma gradual para no calentar cielo ni bruma.
- El sharpen selectivo ya calcula aristas desde luminancia desaturada, no desde color completo, para reducir falsos bordes cromaticos.
- `faceRestore` ya existe como etapa local selectiva y conservadora sobre rostros detectados.
- Sigue sin ser un modelo dedicado de restauracion facial; hoy actua como refuerzo suave de detalle/tono en mascara facial.
- La resolucion IA por imagen se cachea en memoria durante la sesion para evitar llamadas repetidas sobre la misma foto en el mismo contexto base.
- El flujo IA ya obtiene dimensiones de entrada por metadata/pixel size, sin depender de `NSImage` para esa lectura.
- La recomposicion de producto sobre fondo blanco usa Vision foreground masking y debe mantenerse como mejora optica aislada del preset `Ecommerce`.
- Ese recorte de foreground queda activo en macOS 14+; fuera de ese rango el flujo debe degradar a no-op seguro.
- Ese recorte sigue siendo local; no reconstruye bordes ambiguos ni contenido parcialmente perdido. Si hace falta un recorte mas limpio, el siguiente paso correcto es una variante opcional con IA.
- El resize por destino se aplica solo al export final; la preview sigue mostrando el pipeline sin ese remuestreo de salida.
- La UI ya muestra mejor la decision efectiva de `AUTO` durante la preview para evitar ambigüedad sobre el preset realmente aplicado.
- El log de `AUTO` al cargar archivos debe seguir dejando claro que informa sobre la preview actual, no sobre una prediccion fija para todo el lote.
- El lote debe respetar el perfil de export seleccionado al iniciar; no debe mezclar destinos si el usuario cambia la UI a mitad de proceso.
- En `AUTO`, `ecommerce` puede seguir ganando con texto ligero si la imagen mantiene rasgos claros de producto; `documento` debe reservarse para densidad de texto real.
- El historial IA debe seguir guardando por defecto solo resumen del prompt, no el prompt completo.
- Los cambios futuros de `IA` deben mantener compatibilidad con:
  - export multi-formato,
  - naming con colisiones resueltas,
  - historial local,
  - y tests de diagnostico/QA del modulo.
- La suite ahora incluye `LocalPhotoPipelineTests` para cubrir activacion/no-disparo del balance de blancos y diferencia medible del sharpen selectivo.
- La QA diagnostica actual tambien cubre una muestra degradada controlada para `upscale` (`image_upscale_lowres.jpeg`).
- El upscale ya tiene un `UpscaleEngine` dedicado.
- `Real-ESRGAN` queda abierto como backend opcional por binario externo via `JUST4PICT_REAL_ESRGAN_BIN`.
- Si ese binario no existe o no aplica a la imagen, el pipeline cae automaticamente al upscale local actual con Lanczos.

## Recomendaciones de producto (siguiente paso)

- Before/After con slider.
- Resize inteligente para redes/ecommerce.
- Perfil de export rapido para miniaturas web.
- Integracion de deteccion de documento con Vision para recorte/enfoque automatizado.

## Cierre de MVP

`JUST4PICT` puede darse por cerrado como MVP cuando se cumplan estos puntos:

- `Retrato/PRO` queda congelado como baseline visual estable.
- `AUTO` funciona con fiabilidad razonable en retrato, documento, foto oscura y ecommerce.
- `Documento` y `Ecommerce` quedan validados con las muestras reales del repo.
- preview y export se mantienen coherentes.
- `PNG` sigue siendo el default de maxima calidad.
- perfiles de export e historial siguen estables.
- la suite `swift test` del modulo permanece verde.
- existe QA visible actualizada en `images/test`.
- se hace una pasada de lote real y una medicion basica de tiempos/memoria.
- existe un DMG funcional validado para esta baseline.

Todo lo demas debe tratarse ya como afinado post-MVP, no como requisito de cierre.

Estado actual del cierre:

- ya estan cerrados `AUTO`, `Documento`, `Ecommerce`, export por defecto, preview/export y QA visible
- `Retrato/PRO` queda congelado para la baseline actual del MVP con test de referencia sobre la muestra fija del repo
- ya existe una pasada local validada de lote real de 100 imagenes (`QA_BATCH_LOCAL.md`)
- ya existe una medicion explicita de tiempo y memoria para ese lote local de 100 imagenes
- ya existe un DMG funcional validado para esta baseline (`dist/JUST4PICT-0.1.0+20260322114546-6fe34bc.dmg`)
- con esto, `JUST4PICT` puede darse por cerrado como MVP funcional y el trabajo nuevo debe tratarse como afinado post-MVP
- como referencia post-MVP, ya hay tambien QA local validada de 100 y 1000 imagenes y una medicion simple por preset/tamaño en `QA_BATCH_LOCAL.md`
- la distribucion actual queda preparada como release unsigned; ver `RELEASE_NOTES_v0.1.0.md`
- release publicada del repo: `v0.1.3`

## Configuracion IA local

- Definir `OPENAI_API_KEY` en entorno o en `../../.env.secrets`.
- La app busca la key en este orden:
  1) variable de entorno `OPENAI_API_KEY`
  2) archivo `.env.secrets` en la raiz del repo (y padres cercanos)
- Nota: para apps distribuidas, no se recomienda embutir la key en cliente.

## Configuracion opcional de Real-ESRGAN

- Variables opcionales:
  - `JUST4PICT_REAL_ESRGAN_BIN`
  - `JUST4PICT_REAL_ESRGAN_MODELS`
- `JUST4PICT_REAL_ESRGAN_BIN` debe apuntar al binario ejecutable, por ejemplo `realesrgan-ncnn-vulkan`
- `JUST4PICT_REAL_ESRGAN_MODELS` debe apuntar al directorio que contiene al menos:
  - `realesrgan-x4plus.param`
  - `realesrgan-x4plus.bin`
- El motor externo solo se intenta usar cuando:
  - existen binario y modelos,
  - la imagen es realmente pequena,
  - y el upscale pedido es suficientemente grande
- En cualquier otro caso, `JUST4PICT` mantiene el fallback local actual sin romper preview ni export

## Privacidad de historial IA

- El historial guarda por defecto **resumen** del prompt IA (no el prompt completo).
- Esto reduce exposición de contenido sensible en `UserDefaults`.
- El flujo de IA está orientado a 1-click, sin edición manual de prompt.
