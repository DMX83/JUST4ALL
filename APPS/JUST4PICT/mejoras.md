# Mejoras PRO — JUST4PICT

Documento de referencia para la siguiente fase de mejora de calidad visual del pipeline `PRO`.

Última revisión: 2026-03-22 — revisión completa del código post-implementación. Diagnóstico visual realizado. Varios puntos de atención identificados.

---

## Estado actual

Los tres pasos de mejora están implementados. El frente A (sceneOverride) está cerrado. Se hizo validación visual comparando original, PRO e IA sobre una foto de retrato doble con flores de cerezo. El diagnóstico identificó el problema principal del balance de blancos y reveló varios puntos secundarios en el código que conviene revisar.

---

## Lo que está implementado

### `applyAdaptiveWhiteBalance` — `LocalPhotoPipeline.swift`

Usa `CITemperatureAndTint`. Analiza `analysis.averageRed` y `analysis.averageBlue` para detectar dominante. Umbral de activación: 0.025 en temperatura o 0.015 en tint. Máximo ±400K y ±4 tint. `PhotoAnalysis` ahora expone `averageRed`, `averageGreen`, `averageBlue` calculados en `analyzePhotograph`.

### `applyAdaptiveToneCurve` — `LocalPhotoPipeline.swift`

Usa `CIToneCurve` con cinco puntos. El parámetro `contrast` modula la curva vía `modulation = 1.0 + ((contrast - 1.0) * 6.0)`, clampeado entre 0.75 y 1.25. El `CIColorControls.contrast` está ahora hardcodeado a 1.0 en `applyCoreTuning` y `applyAppleLikePhotoEnhancement` — el contraste viaja solo por la curva.

### `applySelectiveSharpen` — `LocalPhotoPipeline.swift`

Usa `CIEdges` → `CIGaussianBlur` → `CIColorControls` (desaturar) → `CIBlendWithMask`. Edge intensity = `amount * 9.0`. Radio del blur: 5.5 con faceMask, 3.2 sin ella en `applyCoreTuning`. En `applyAppleLikePhotoEnhancement`: 5.0 para portrait, 3.0 para el resto.

### `sceneOverride` — `ImageEnhancer.swift`, `ContentView.swift`, `EnhancementRecipe.swift`

`mappedScene` en `EnhancementRecipe` mapea el campo `scene` de la receta IA a `SceneType`. `enhance()` y `enhancedPreviewImage()` aceptan `sceneOverride` opcional. `ContentView` pasa `recipe?.mappedScene` en batch, retry y preview IA.

---

## Problema principal — balance de blancos con análisis global

### Diagnóstico visual

En la foto de cerezo (retrato doble, flores blancas de fondo, luz difusa), PRO no corrige la dominante cálida visible en las flores. La versión IA sí mejora notablemente el detalle y el microcontraste. La diferencia PRO vs IA es mayor de lo que debería ser para un mismo motor local.

### Causa raíz en el código

`applyAdaptiveWhiteBalance` usa `analysis.averageRed - analysis.averageBlue` sobre el promedio global de toda la imagen. En esta foto, el pelo pelirrojo, las chaquetas marrones y la piel cálida elevan `averageRed` globalmente. El desequilibrio real de las flores blancas queda diluido. El umbral 0.025 puede activarse, pero la corrección resultante enfría toda la imagen incluyendo la piel — que no debería enfriarse porque su calidez es natural, no una dominante de iluminación.

Adicionalmente, `neutral` está hardcodeado a 6500K (luz de día). Si la escena tiene temperatura diferente, la corrección es incorrecta. Aceptable como limitación, pero conviene documentarlo.

### Corrección pendiente

**Archivos:** `ImageAnalyzer.swift`, `LocalPhotoPipeline.swift`

Añadir en `ImageAnalyzer` un método que calcule el promedio RGB solo de píxeles con luminancia > 0.72. Las altas luces son la referencia natural de blancos — si hay dominante cálida, las flores/zonas blancas la delatan sin que el pelo pelirrojo contamine el análisis.

Añadir a `PhotoAnalysis` los campos `highlightRed`, `highlightGreen`, `highlightBlue` con default 0.5. Calcular la proporción de píxeles en altas luces sobre el total. Si esa proporción es < 8%, no hay referencia de blancos fiable — caer al análisis global actual. Si hay suficientes altas luces, usar esos promedios para el balance de blancos.

El umbral de activación puede bajarse a 0.018 cuando se usan altas luces porque la señal es más limpia.

**Verificación:** la foto de cerezo debería mostrar flores más neutras sin que la piel se enfríe. El canal R global no debe caer por debajo de 0.57 ni B subir por encima de 0.57 en `testPortraitProBaselineStaysWithinCurrentReferenceWindow`.

**Test nuevo necesario:** verificar que la corrección se activa en una imagen con dominante en altas luces pero NO en una imagen donde el calor viene de los sujetos (piel, pelo, ropa) y las altas luces son neutrales.

---

## Puntos secundarios encontrados en la revisión del código

### 1. `CIEdges` opera sobre imagen en color — posibles artefactos cromáticos

`applySelectiveSharpen` aplica `CIEdges` directamente sobre la imagen en color. Subjects con colores saturados (pelo pelirrojo, ropa de colores vivos) pueden producir bordes más intensos en el mapa de aristas que los bordes reales de luminancia. El `maskContrast.saturation = 0.0` desatura el resultado pero no evita que el detector haya privilegiado bordes de color.

Una alternativa más robusta es desaturar la imagen antes de pasarla a `CIEdges` — así el detector solo responde a bordes de luminancia, no de color. El sharpen selectivo resultante sería más preciso, especialmente en cabello oscuro sobre piel clara.

**Prioridad:** media. No es urgente pero puede mejorar la calidad en retratos con mucho contraste de color.

### 2. `applyPortraitAISafetyFinish` en `applyAppleLikePhotoEnhancement` es código muerto en la práctica

En `applyAppleLikePhotoEnhancement` hay:
```swift
if scene == .portrait {
    output = applyPortraitAISafetyFinish(image: output)
}
```
Este bloque solo se alcanza cuando el perfil de recuperación es `.standard` con escena portrait. Pero `resolveRecoveryProfile` siempre devuelve `.conservativePortrait` para preset portrait o AUTO+portrait. Eso significa que los retratos van por `makePortraitImage` → `applyPortraitGuidedEnhancement`, nunca por `applyAppleLikePhotoEnhancement`. El safety finish de portrait en `applyAppleLikePhotoEnhancement` nunca se ejecuta en la práctica. Se puede eliminar sin consecuencias.

**Prioridad:** baja. No daña, pero es deuda de código.

### 3. El balance de blancos no tiene tests

Los tests existentes de `ImageAnalyzerTests` usan el inicializador de `PhotoAnalysis` sin pasar los canales RGB — quedan en 0.5 por defecto. Con `redBlueDelta = 0` y `greenBias = 0`, `applyAdaptiveWhiteBalance` nunca se activa en ningún test existente. El comportamiento del balance de blancos está completamente sin cobertura de test.

**Prioridad:** alta. Hay que añadir al menos un test que verifique la activación y uno que verifique el no-disparo.

### 4. Inconsistencia en el radio del blur de la máscara de sharpen entre los dos pipelines

En `applyCoreTuning` (vía portrait guided):
- Con faceMask: `edgeBlurRadius = 5.5`
- Sin faceMask: `edgeBlurRadius = 3.2`

En `applyAppleLikePhotoEnhancement`:
- Portrait: `edgeBlurRadius = 5.0`
- Resto: `edgeBlurRadius = 3.0`

Un retrato sin cara detectada usaría 3.2 en el primer pipeline y 5.0 en el segundo. No es un bug funcional pero sí una inconsistencia que puede dar resultados diferentes según qué ruta tome la imagen. Vale la pena unificar los valores o documentar la razón de la diferencia.

### 5. La curva de tono para paisaje es agresiva — pendiente de validación

Los puntos de la S-curve para paisaje son:
```
(0.00, 0.00), (0.25, 0.20), (0.50, 0.54), (0.75, 0.82), (1.00, 1.00)
```
Sombras aplastadas (0.25 → 0.20) y altas luces elevadas (0.75 → 0.82). En un paisaje con cielo brillante esto puede quemar detalles en nubes o cielos sobrexpuestos. Necesita validarse con al menos una foto de paisaje real con cielo en las muestras del repo.

**Prioridad:** media. Hay que verificar antes de congelar como baseline.

### 6. El multiplicador de modulación de la curva (6.0) es un número mágico no documentado

```swift
let modulation = max(min(1.0 + ((contrast - 1.0) * 6.0), 1.25), 0.75)
```
Con los valores de contrast actuales (portrait: 1.004, landscape: 1.005), el efecto de la modulación es muy pequeño: modulation = 1.024 y 1.03 respectivamente. El contraste real viene casi completamente de los puntos base de la curva. Si en el futuro la IA devuelve valores de contrast más extremos (por ejemplo 1.04), el multiplicador 6 haría modulation = 1.24 — que sí tiene efecto notable. Conviene documentarlo y establecer si el rango esperado del parámetro `contrast` cubre esos casos.

### 7. Doble protección facial en portrait — potencialmente excesiva

En `applyCoreTuning`, el sharpen selectivo ya usa un radio de blur mayor (5.5) cuando hay faceMask, lo que suaviza la máscara en la región facial. Encima de eso, se aplica el blend con faceMask:
```swift
let protectFaces = CIFilter.blendWithMask()
protectFaces.inputImage = output  // sin sharpen
protectFaces.backgroundImage = sharpened  // con sharpen
protectFaces.maskImage = faceMask
```
El resultado es: el sharpen en la cara ya está atenuado por el blur de la máscara de bordes, y luego se atenúa más por la faceMask. Esto puede producir que ojos y cejas — que sí deberían tener nitidez — queden también suavizados. Conviene validar con la foto de retrato ampliada al 100% si los ojos tienen suficiente definición.

**Prioridad:** media. Afecta directamente a la calidad percibida del retrato.

### 8. Edge intensity = `amount * 9.0` produce rangos muy distintos por escena

Con portrait sharpen = 0.036, intensity = 0.324. Con landscape sharpen = 0.22, intensity = 1.98. Con document sharpen = 0.30, intensity = 2.70. El detector de bordes tiene sensibilidad muy diferente según el preset. Un documento con mucho texto va a generar un mapa de bordes muy denso, lo que puede hacer que el sharpen selectivo sea prácticamente global en ese caso. No es necesariamente malo para documento — el texto necesita sharpen en casi toda la imagen — pero vale la pena verificarlo.

---

## Orden de trabajo recomendado

```
1. Añadir análisis de altas luces en ImageAnalyzer (highlightRed/Green/Blue)
2. Actualizar applyAdaptiveWhiteBalance para usar altas luces con fallback global
3. Añadir tests de balance de blancos (activación y no-disparo)
4. Validar con foto de cerezo: flores más neutras, piel sin enfriar
5. Correr testPortraitProBaselineStaysWithinCurrentReferenceWindow
6. Validar ojos/cejas al 100% en el retrato de referencia del repo
7. Validar curva de paisaje con foto de cielo brillante
8. Evaluar desaturar input de CIEdges para aristas más limpias en color
9. Eliminar applyPortraitAISafetyFinish del path de applyAppleLikePhotoEnhancement (código muerto)
10. Unificar radios de blur de máscara de sharpen entre pipelines
```

Los pasos 1-7 son validación y corrección de calidad. Los pasos 8-10 son limpieza y refinamiento.

---

## Pregunta de producto después de los pasos 1-7

Con la corrección del balance de blancos de altas luces aplicada, volver a comparar PRO vs IA en la foto de cerezo. Si PRO se acerca visualmente a IA sin llamada a red, el pipeline local está en el nivel correcto. Si IA sigue siendo claramente mejor, el gap es de criterio por imagen — ahí es donde IA tiene ventaja estructural y el siguiente paso es Real-ESRGAN, no seguir afinando filtros.

---

## Siguiente frente después de cerrar la validación — Real-ESRGAN

Real-ESRGAN tiene binario para macOS. Se puede llamar desde Swift con `Process()` sin Core ML. Se activa solo cuando la imagen está por debajo de un umbral de resolución o cuando el analizador detecta degradación severa. El Lanczos actual se queda como fallback. Es el paso que convierte "mejora fotos" en "restaura fotos" para imágenes pequeñas o con compresión agresiva.

---

## Lo que no se abre ahora

- `ExportPipeline` como módulo dedicado
- `UpscaleEngine` como módulo separado
- `CIContext` compartido en todos los flujos
- `autoreleasepool` en lote grande
- Firma y notarización

Sin regresión observable en `QA_BATCH_LOCAL.md`, los de rendimiento son optimización prematura.

---

## Tests relevantes a mantener verdes

- `OutputFormatTests`
- `PictHistoryStoreTests`
- `ImageEnhancerDiagnosticsTests`
- `testPortraitProBaselineStaysWithinCurrentReferenceWindow`
- `ImageAnalyzerTests`
- `EnhancementPlannerTests`

**Tests nuevos necesarios:**

- Test de activación de balance de blancos en imagen con altas luces con dominante
- Test de no-activación cuando la calidez viene de sujetos (pelo, piel) sin dominante en altas luces
- Test de que `applySelectiveSharpen` produce delta measurable respecto a `applySharpen` en una imagen con bordes definidos

---

## Archivos afectados por las correcciones pendientes

| Archivo | Cambio |
|---|---|
| `ImageAnalyzer.swift` | Añadir análisis de promedio RGB en píxeles con luminancia > 0.72 |
| `ImageAnalyzer.swift` | `PhotoAnalysis` añade `highlightRed`, `highlightGreen`, `highlightBlue` con default 0.5 y proporción de altas luces |
| `LocalPhotoPipeline.swift` | `applyAdaptiveWhiteBalance` usa altas luces con fallback al análisis global |
| `LocalPhotoPipeline.swift` | Evaluar desaturar input de `CIEdges` en `applySelectiveSharpen` |
| `LocalPhotoPipeline.swift` | Eliminar `applyPortraitAISafetyFinish` del branch portrait de `applyAppleLikePhotoEnhancement` |
| `LocalPhotoPipeline.swift` | Unificar radios de blur de máscara de sharpen entre `applyCoreTuning` y `applyAppleLikePhotoEnhancement` |
| `ImageEnhancerDiagnosticsTests.swift` | Tests de balance de blancos y sharpen selectivo |
