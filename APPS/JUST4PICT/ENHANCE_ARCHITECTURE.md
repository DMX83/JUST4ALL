# Enhance Architecture — JUST4PICT

## Estado actual

Baseline activa validada manualmente:

- build de referencia visual con `PRO` ya estable en retrato
- preview manual con boton `Enhance`
- doble click en previews abre visor ampliado con navegacion solo entre imagenes disponibles
- `PRO` ya no rompe el retrato y sirve como base conservadora usable
- `PRO` ya tiene un remate pequeno de detalle local con proteccion facial
- `AUTO` ya hereda `Retrato` cuando detecta cara
- `AUTO` ya detecta mejor paisaje vertical por contenido y contiene mejor la nocturna
- muestra fija de QA en `APPS/JUST4PICT/images/PHOTO-2026-03-18-22-18-19 2.jpg`
- QA multiprueba con salidas visibles en `APPS/JUST4PICT/images/test/*-pro-sample.png`

Situacion del producto ahora:

- la UI y el versionado ya son fiables
- `PRO` es usable y ya funciona bien como baseline visual para retrato
- la validacion ya no depende solo de prueba manual: existe un set pequeno dentro del repo
- `IA` existe, pero todavia no debe marcar la direccion del producto hasta que `PRO` y `AUTO` queden solidos

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

Responsabilidades:

- `ImageAnalyzer`: Vision + OpenAI
- `EnhancementPlanner`: crea `EnhancementRecipe`
- `LocalPhotoPipeline`: Core Image base
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

- entrada: `APPS/JUST4PICT/images/PHOTO-2026-03-18-22-18-19 2.jpg`
- entradas adicionales:
  - `APPS/JUST4PICT/images/32474560-ED95-47FF-96E9-2ACD793D0A30_1_105_c.jpeg`
  - `APPS/JUST4PICT/images/58706BD4-3915-4068-80EF-B7B11F7D2EC6_1_105_c.jpeg`

Salidas QA:

- `APPS/JUST4PICT/images/test/*-pro-sample.png`

Uso actual:

- retrato para cerrar `PRO`
- paisaje para validar `AUTO` fuera de retrato
- nocturna para contener mejor sombras, color y brillo global
- salida: `APPS/JUST4PICT/images/test/portrait-pro-sample.png`

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
