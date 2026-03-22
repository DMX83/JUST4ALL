# Enhance Architecture — JUST4PICT

## Estado actual

Baseline activa validada manualmente:

- build de referencia visual con `PRO` ya estable en retrato
- preview manual con boton `Enhance`
- doble click en previews abre visor ampliado con navegacion solo entre imagenes disponibles
- `PRO` ya no rompe el retrato y sirve como base conservadora usable
- `PRO` ya tiene un remate pequeno de detalle local con proteccion facial
- `AUTO` ya hereda `Retrato` cuando detecta cara
- `AUTO` ya detecta mejor paisaje vertical por contenido, documento por texto+saturacion, producto `ecommerce` por fondo claro/uniforme y contiene mejor la nocturna
- muestra fija de QA en `APPS/JUST4PICT/images/PHOTO-2026-03-18-22-18-19 2.jpg`
- muestras reales adicionales de QA para escena:
  - `APPS/JUST4PICT/images/image_doc_orig.jpeg`
  - `APPS/JUST4PICT/images/image_product_orig.jpeg`
- QA multiprueba con salidas visibles en `APPS/JUST4PICT/images/test/*-pro-sample.png`

Situacion del producto ahora:

- la UI y el versionado ya son fiables
- `PRO` es usable y ya funciona bien como baseline visual para retrato
- la validacion ya no depende solo de prueba manual: existe un set pequeno dentro del repo
- `IA` existe, pero todavia no debe marcar la direccion del producto hasta que `PRO` y `AUTO` queden solidos
- la arquitectura ya no depende solo de un archivo monolitico:
  - `ImageAnalyzer` concentra analisis local de imagen,
  - `EnhancementPlanner` resuelve decisiones derivadas de receta/fallback,
  - `LocalPhotoPipeline` ejecuta el pipeline local
- `ImageEnhancer` ya centraliza un `CIContext` compartido e inyecta esa dependencia a analisis, pipeline local, upscale y aislamiento de producto
- la politica de exportacion ya queda centralizada en `ImageExportWriter`, usada tanto por `PRO` como por `Reconstruir IA`
- `ContentView` sigue siendo el punto principal de orquestacion UI, pero ya no duplica tanto manejo de logs/resultados de batch y arranque de estado como en fases anteriores
- existe una primera pasada de afinado visual en evaluacion sobre `LocalPhotoPipeline`:
  - balance de blancos adaptativo
  - curva tonal por escena
  - sharpen selectivo por mascara de bordes
- esa pasada ya no usa solo promedio global para blancos: puede tomar referencia de altas luces cuando la escena ofrece blancos fiables
- en `Paisaje`, el balance de blancos ya no se aplica con la misma fuerza a toda la imagen: usa un umbral de altas luces mas flexible para nubes y una mezcla vertical conservadora para proteger cielo/bruma
- el sharpen selectivo ya genera su mascara desde luminancia desaturada para no sobrerreaccionar a bordes de color
- esa pasada ya mantiene la suite verde, pero todavia debe validarse visualmente antes de congelarse como nueva baseline

## Invariantes actuales antes de tocar IA

Estos puntos ya estan estabilizados y deben preservarse en cualquier refactor o ampliacion:

- `PNG` es el formato de salida por defecto del proyecto.
- `PNG` debe aparecer primero en el selector de formatos.
- La calidad por defecto es `1.0`; no se debe volver a una salida con perdida por defecto.
- La preview es manual y se dispara con `Enhance`; no debe reintroducirse auto-refresh costoso o agresivo.
- `PRO` es la baseline visual principal. La integracion IA no puede degradar `PRO` ni mezclar responsabilidades.
- `Retrato/PRO` ya no mantiene una variante `legacy` activa; la baseline actual es unica y se valida contra la muestra fija del repo.
- `AUTO` ya hereda `Retrato` cuando detecta cara. Ese comportamiento es contrato actual del producto.
- El historial IA guarda resumen de prompt por defecto y evita persistir el prompt completo salvo eleccion explicita.
- El naming de salida versionado y con manejo de colisiones debe seguir intacto.
- Los tests del modulo deben seguir cubriendo:
  - formatos de salida,
  - historial,
  - y QA diagnostica de `ImageEnhancer`.

## Estado tecnico real de IA hoy

Para evitar suposiciones falsas antes del siguiente cambio:

- La `IA` ya genera una `EnhancementRecipe` estructurada y la muestra en UI.
- La `IA` ya puede sugerir preset, calidad y `tuning`.
- La `IA` ya resuelve por imagen en batch a traves del planner.
- La resolucion IA por imagen ya puede reutilizarse desde cache local en sesion para evitar analisis repetidos.
- `scene`, `preset`, `exportFormat`, `exportQuality` y `upscale` ya pueden influir en la ejecucion real.
- Si la `EnhancementRecipe` trae una `scene` valida, esa escena ya puede sobreescribir la deteccion local dentro del motor para mantener coherencia entre planner, preview y export.
- La `IA` todavia no es la fuente de verdad completa del pipeline final.
- El flujo IA ya toma dimensiones de entrada desde metadata/pixel size y no debe volver a depender de `NSImage` para esa lectura.
- export, preview y worker detached de batch ya envuelven los tramos pesados de Core Image/Core Graphics en `autoreleasepool` para liberar antes objetos intermedios.
- `faceRestore` ya esta cableado como contrato de planner/UI/pipeline y viaja por preview y export.
- `faceRestore` ya aplica una mejora local selectiva sobre mascara facial.
- Sigue sin ser un modelo dedicado de restauracion facial; la implementacion actual es deliberadamente conservadora.
- `LocalPhotoPipeline` ya tiene cobertura unitaria directa para balance de blancos y sharpen selectivo, sin depender solo de QA visual.
- Ya existe perfil de export por destino (`Original`, `Social`, `Web`, `Ecommerce`) con resize aplicado solo al archivo final.
- `Reconstruir IA` ya no mantiene una ruta de escritura separada: comparte el export writer comun y debe respetar los mismos perfiles de exportacion (`Web`, `Web <300KB`, `Ecommerce`, etc.).
- La decision efectiva de `AUTO` ya se refleja mejor en la UI de preview para que el usuario vea que pipeline se esta aplicando.
- El perfil de export se considera parte del snapshot del lote; no debe variar a mitad de una ejecucion ya iniciada.
- La clasificacion `ecommerce` debe seguir funcionando con branding ligero; `document` debe quedar reservado para imagenes realmente dominadas por texto.
- La clasificacion `ecommerce` ya no debe depender solo de fondo blanco puro; tambien debe cubrir fotos reales de catalogo movil con sujeto centrado y poco texto.
- En `Ecommerce`, el producto principal ya puede aislarse con Vision foreground masking y recomponerse centrado sobre fondo blanco.
- Esa etapa debe mantenerse encapsulada fuera del pipeline fotografico general y caer a no-op seguro cuando la mascara no sea fiable o la API no este disponible.
- Como variante manual, `Reconstruir IA` ya puede usar un prompt especifico de producto cuando el preset o la escena efectiva son `Ecommerce`, para limpiar bordes complejos y recomponer sobre blanco sin autoactivarse.
- `Documento` ya incorpora un remate especifico para recuperar fondo blanco y evitar exportaciones demasiado grises sobre hojas claras.

## Regla para la siguiente fase

El siguiente trabajo de `IA` no debe introducir comportamiento nuevo sin respetar este orden:

1. preservar defaults actuales de exportacion y preview
2. mantener `PRO` y `AUTO` visualmente estables
3. hacer que `IA` decida por imagen
4. hacer que `EnhancementRecipe` gobierne realmente la ejecucion
   Ya no es solo estructural: la escena recomendada por IA ya puede cablearse hasta el motor y modificar el pipeline efectivo.
5. solo despues ampliar motores, upscale dedicado o restauracion facial

## Nota sobre baseline visual

- El test numerico de baseline de retrato sigue atado a la muestra historica `PHOTO-2026-03-18-22-18-19 2.jpg`.
- Si esa muestra no esta en el repo local, el test debe hacer `skip` en vez de aplicar esas ventanas a otra foto distinta.

## Objetivo

Construir un modulo `Enhance` que mejore fotografias de forma natural, exporte con calidad alta y pueda evolucionar desde una base local rapida a una version comercial seria en macOS.

El objetivo no es "aplicar filtros". El objetivo es:

- preservar identidad y composicion
- corregir tono, color, ruido y detalle
- decidir si una imagen necesita upscale real
- exportar con calidad alta y resultados consistentes

## Principio rector

`PRO` y `IA` no deben competir haciendo lo mismo.

- `PRO`: pipeline local, rapido, determinista, sin red
- `IA`: analiza la imagen real y decide que pipeline local debe ejecutarse

La IA no debe renderizar la foto final por defecto. Debe orquestar la mejora local.

## Arquitectura por capas

### 1. Base tonal local

Responsabilidad:

- auto adjust inicial
- exposicion
- highlights/shadows
- contraste suave
- correccion de color
- nitidez ligera

Tecnologia:

- `CoreImage`
- `CIContext` con `extendedSRGB` como working space
- Metal cuando este disponible

Responsabilidad del modulo:

- producir una base estable y natural
- no inventar detalle
- no cambiar identidad

### 2. Decision inteligente

Responsabilidad:

- analizar la imagen real
- detectar degradacion, ruido, compresion, subexposicion, detalle insuficiente
- decidir preset y parametros concretos
- decidir si conviene upscale
- decidir si conviene restauracion de rostro

Tecnologia:

- OpenAI vision para diagnostico
- salida estructurada estricta
- receta local tipada, nunca texto libre como fuente de verdad

La IA debe devolver:

- tipo de imagen
- objetivo de mejora
- parametros locales
- necesidad de upscale
- necesidad de face restore
- formato/calidad de export recomendados

### 3. Mejora perceptual

Responsabilidad:

- recuperar detalle real donde el pipeline tonal no alcanza
- upscale cuando la resolucion sea insuficiente

Opciones:

- `v1`: `Real-ESRGAN`
- `v2`: modelo `Core ML` nativo

Regla:

- no aplicar por defecto a todas las fotos
- activarlo por decision del analizador o por resolucion umbral

### 4. Restauracion facial opcional

Responsabilidad:

- reparar rostros degradados, pequeños o con artefactos severos

Opciones:

- `CodeFormer` o modelo equivalente

Regla:

- desactivado por defecto
- solo si hay rostro realmente degradado
- intensidad regulable

## Modos de producto

### PRO

Pipeline:

1. deteccion local de escena
2. pipeline local especifico por escena
3. base tonal
4. detalle local moderado
5. upscale opcional
6. exportacion alta calidad

Objetivo:

- mejora rapida
- cero red
- resultado seguro y consistente

Estado actual:

- es la referencia principal del producto
- ya usa preview manual disparada por el usuario
- ya tiene una baseline visual buena en retrato
- ya tiene una base razonable en paisaje y nocturna
- la prioridad inmediata es ajuste fino y cierre de baseline, no reescritura
- el criterio visual debe validarse contra las muestras del repo en `images/test`

### IA

Pipeline:

1. enviar imagen real a OpenAI vision
2. recibir diagnostico estructurado
3. traducir diagnostico a `EnhancementRecipe`
4. ejecutar receta local
5. activar modulos extra si aplica
6. exportar en maxima calidad viable

Objetivo:

- mejor decision por imagen concreta
- no solo preset/quality
- misma fidelidad que `PRO`, pero con mejor criterio

Estado actual:

- no debe ir por delante de `PRO`
- debe apoyarse en un `PRO` ya fiable
- en esta fase es secundario frente a cerrar bien `Retrato` y `AUTO`

## Modelo de datos recomendado

```swift
struct EnhancementRecipe: Codable, Hashable {
    let scene: SceneKind
    let tonal: TonalRecipe
    let detail: DetailRecipe
    let upscale: UpscaleRecipe
    let faceRestore: FaceRestoreRecipe
    let export: ExportRecipe
}

struct TonalRecipe: Codable, Hashable {
    let exposureEV: Double
    let shadowAmount: Double
    let highlightAmount: Double
    let contrast: Double
    let saturation: Double
    let vibrance: Double
    let warmth: Double
}

struct DetailRecipe: Codable, Hashable {
    let denoise: Double
    let sharpen: Double
    let sharpenRadius: Double
}

struct UpscaleRecipe: Codable, Hashable {
    let enabled: Bool
    let targetLongSide: Int?
    let model: String?
}

struct FaceRestoreRecipe: Codable, Hashable {
    let enabled: Bool
    let strength: Double
}

struct ExportRecipe: Codable, Hashable {
    let format: String
    let quality: Double
    let preserveMetadata: Bool
}
```

## Motor interno recomendado

Separar implementacion por modulos:

- `ImageAnalyzer`
- `EnhancementPlanner`
- `LocalPhotoPipeline`
- `UpscaleEngine`
- `FaceRestoreEngine`
- `ExportPipeline`

Estado actual del repo:

- `ImageAnalyzer`: implementado para escena/caras/texto/luminancia
- `ImageAnalyzer`: ya reutilizable tambien para lectura de pixel size desde metadata
- `EnhancementPlanner`: implementado para resolucion de receta IA y fallback
- `LocalPhotoPipeline`: implementado para pipeline local de mejora
- `UpscaleEngine`: pendiente como modulo dedicado; hoy vive dentro del pipeline local
- `UpscaleEngine`: ya extraido como modulo dedicado
- `UpscaleEngine`: backend local activo + backend opcional `Real-ESRGAN` por binario externo con fallback automatico
- `Real-ESRGAN` solo se considera disponible cuando existen ejecutable y modelos (`realesrgan-x4plus.param/.bin`)
- el bootstrap local recomendado queda formalizado en `scripts/setup_realesrgan_local.sh`
- ese setup usa el asset oficial macOS `realesrgan-ncnn-vulkan-20220424-macos.zip`, que incluye `realesrgan-x4plus.param/.bin`
- `UpscaleEngine` puede autodetectar ese setup local desde `.cache/realesrgan/` o `APPS/JUST4PICT/.cache/realesrgan/`, sin exigir variables de entorno manuales
- la estrategia actual evita `Real-ESRGAN` por defecto en retrato, y cuando lo usa lo hace como paso interno `x4` con resize final posterior
- `OpenAIImageReconstructionService`: nuevo modulo opcional para reconstruccion generativa conservadora con `gpt-image-1`
- `OpenAIImageReconstructionService`: se usa solo como modo explicito (`Reconstruir IA`), no como sustituto silencioso de `PRO`
- decision de producto actual:
  - `Real-ESRGAN` queda recomendado para imagen pequena no facial
  - `Reconstruir IA` queda reservado para miniaturas extremas, compresion severa o retratos muy degradados
  - la UI puede sugerir uno u otro, pero ninguno se autoactiva todavia
- `FaceRestoreEngine`: pendiente
- `ProductIsolationEngine`: implementado para `Ecommerce` con foreground masking y recomposicion centrada sobre blanco
- `ExportPipeline`: pendiente como modulo dedicado; hoy sigue integrado en `ImageEnhancer`

Responsabilidades:

- `ImageAnalyzer`: Vision + OpenAI
- `EnhancementPlanner`: crea `EnhancementRecipe`
- `LocalPhotoPipeline`: Core Image base
- `ProductIsolationEngine`: recorte de producto y recomposicion sobre fondo blanco en `Ecommerce`
- `ProductIsolationEngine`: sigue siendo una etapa local; una reconstruccion mas limpia de bordes complejos requeriria una fase generativa opcional
- `UpscaleEngine`: SR opcional
- `FaceRestoreEngine`: modulo facial opcional
- `ExportPipeline`: render final y guardado

Orden real de implementacion recomendado:

1. `PortraitPipeline`
2. `AutoSceneResolver`
3. `ImageAnalyzer`
4. `EnhancementPlanner`
5. `LocalPhotoPipeline`
6. `UpscaleEngine`
7. `FaceRestoreEngine`

Motivo:

- el mayor riesgo actual no es la arquitectura teorica
- es la calidad visual de `Retrato`
- por eso el primer modulo serio debe ser el pipeline de retrato y luego hacer que `AUTO` herede ese resultado

## Estrategia de QA durante desarrollo

Referencia fija:

- entrada: `APPS/JUST4PICT/images/PHOTO-2026-03-18-22-18-19 5.jpg`
- entradas adicionales:
  - `APPS/JUST4PICT/images/5E57193E-1028-4B98-B674-77C71F64A195_1_105_c.jpeg`
  - `APPS/JUST4PICT/images/AE018C52-E452-4101-B77F-F5D7A4868D0B_1_105_c.jpeg`
  - `APPS/JUST4PICT/images/D92852D4-89B0-4918-9269-9AC8A49F11F0_1_105_c.jpeg`
  - `APPS/JUST4PICT/images/images_document_orig.jpeg`
  - `APPS/JUST4PICT/images/image_commerce_orig.jpeg`
  - `APPS/JUST4PICT/images/image_paisaje_orig.jpeg`
  - `APPS/JUST4PICT/images/image_upscale_lowres.jpeg`

Salidas QA:

- `APPS/JUST4PICT/images/test/*-pro-sample.png`

Uso actual:

- retrato para cerrar `PRO`
- paisaje para validar `AUTO` fuera de retrato
- nocturna para contener mejor sombras, color y brillo global
- documento para fijar `AUTO -> Documento` con muestra real
- ecommerce para fijar `AUTO -> Ecommerce` con muestra real
- salida de referencia retrato: `APPS/JUST4PICT/images/test/PHOTO-2026-03-18-22-18-19 5-pro-sample.png`

Objetivo:

- iterar `PRO` sin depender de una prueba manual en cada cambio
- mantener una comparativa estable entre versiones del pipeline

Herramientas:

- test de diagnostico en `Tests/JUST4PICTTests/ImageEnhancerDiagnosticsTests.swift`
- script `scripts/qa_portrait_sample.sh`

Regla:

- cualquier ajuste de `Retrato/PRO` debe regenerar la muestra de `images/test`
- si una iteracion vuelve a cerrar la imagen o rompe tono/color, se revierte de inmediato

## Estrategia de exportacion

La calidad de guardado debe ser un objetivo explicito, no una consecuencia.

Reglas:

- `JPG`: calidad minima 0.95 en modo IA
- `PNG`: usar cuando haya necesidad de maxima fidelidad local o graficos
- `HEIC`: opcional, no como formato principal si el usuario espera maxima compatibilidad
- upscale antes de exportar, no despues
- evitar dobles compresiones

## Fases

### Fase 0. Baseline estable

- congelar `PRO` usable
- mantener preview manual con `Enhance`
- versionar builds y nombres de salida para evitar confusion

### Fase 1. Retrato

- cerrar `PortraitPipeline`
- proteger piel
- mejorar detalle en pelo/ropa
- mantener blancos y rango dinamico

### Fase 2. AUTO

- si detecta cara, debe reutilizar el pipeline final de `Retrato`
- si detecta texto, documento
- si detecta baja luminancia, perfil oscuro
- resto: generico/paisaje

### Fase 3. IA

- una vez `PRO` y `AUTO` sean fiables
- IA analiza imagen real
- IA decide receta, no render final por defecto

### Fase 1

- estabilizar `PRO` con pipeline local simple
- mantener `IA` como analizador real de imagen
- `IA` devuelve `EnhancementRecipe` estructurada

### Fase 2

- introducir `UpscaleEngine`
- umbral por resolucion y recomendacion IA
- comparar calidad contra base local

### Fase 3

- introducir `FaceRestoreEngine`
- activacion solo si Vision + IA lo justifican

## Decisiones de producto

- no usar restauracion facial por defecto
- no usar generacion de imagen como salida final por defecto
- no vender "IA" si el render final es identico a `PRO`
- siempre mostrar al usuario que receta decidio IA

## Veredicto

Stack recomendado para JUST4PICT:

- base actual: `Core Image`
- decision inteligente: `OpenAI vision`
- evolucion seria macOS: `Core ML`
- experimento de calidad/upscale: `Real-ESRGAN`
- rostro degradado: `CodeFormer` opcional

La siguiente implementacion correcta no es seguir afinando sliders. Es formalizar `EnhancementRecipe` y convertir `IA` en un planificador real del pipeline local.
