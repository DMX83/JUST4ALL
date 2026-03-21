# Propuesta de Mejoras para JUST4PICT

Este documento detalla una serie de propuestas para refinar la arquitectura, optimizar el rendimiento y mejorar la experiencia de usuario (UI/UX) de la aplicación JUST4PICT.

## 1. Arquitectura y Refactorización del Código

El objetivo es reducir la duplicación de código, aumentar la legibilidad y facilitar el mantenimiento futuro.

### 1.1. Centralizar la Lógica de Aplicación de Filtros

*   **Problema:** La lógica para aplicar filtros de Core Image (`exposure`, `contrast`, `saturation`, etc.) está duplicada en varios lugares, como en `applyPortraitGuidedEnhancement` y `applyAppleLikePhotoEnhancement`.
*   **Propuesta:** Crear una única función privada que reciba una `CIImage` y una estructura de `tuning` (como `AIEnhancementTuning`) y devuelva la imagen con los filtros base aplicados.

    ```swift
    // En ImageEnhancer.swift
    private func applyCoreTuning(image: CIImage, tuning: AIEnhancementTuning) -> CIImage {
        var output = image
        // Aplicar exposición, contraste, saturación, etc., usando los valores de `tuning`.
        // ...
        return output
    }
    ```

### 1.2. Unificar la Detección de Pipeline

*   **Problema:** La decisión de qué pipeline de mejora utilizar está dispersa entre `resolvedOptions` y `resolveRecoveryProfile`.
*   **Propuesta:** Unificar esta lógica en una sola función que analice el `preset` y la `scene` y devuelva un objeto de configuración de pipeline (`PipelineConfig`) más completo.

    ```swift
    // En ImageEnhancer.swift
    private struct PipelineConfig {
        let recoveryProfile: RecoveryProfile
        let options: EnhancementOptions
        // ... otros parámetros de configuración
    }

    private func resolvePipelineConfig(for preset: EnhancementPreset, detectedScene: SceneType?) -> PipelineConfig {
        // ... lógica unificada aquí
    }
    ```

### 1.3. Abstraer Filtros en Funciones Puras

*   **Problema:** El método `makeEnhancedImage` es largo y contiene la configuración de muchos `CIFilter`.
*   **Propuesta:** Extraer cada bloque de configuración de filtro a su propia función `private static`. Esto hará que el pipeline principal sea mucho más legible, pareciendo una secuencia de pasos claros.

    ```swift
    // En ImageEnhancer.swift
    private static func applySharpen(image: CIImage, amount: Double, radius: Double) -> CIImage {
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = image
        filter.sharpness = Float(amount)
        filter.radius = Float(radius)
        return filter.outputImage ?? image
    }

    // El pipeline principal se vería así:
    // output = Self.applySharpen(image: output, amount: 0.1, radius: 0.25)
    ```

## 2. Optimizaciones de Rendimiento

El objetivo es hacer la aplicación más rápida y responsiva, especialmente durante la previsualización.

### 2.1. Cachear Resultados de Análisis de Imagen

*   **Problema:** La aplicación re-analiza las propiedades de la imagen (dimensiones, tipo de escena) en varias ocasiones.
*   **Propuesta:** Al seleccionar una imagen para la `preview`, analizarla una vez y guardar los resultados (dimensiones, `SceneType`, `PhotoAnalysis`) en una propiedad de estado (`@State`). Estos datos cacheados se pueden reutilizar para la IA y otros pipelines.

### 2.2. Pipeline de Preview Simplificado

*   **Problema:** La generación de `previews` utiliza el mismo pipeline de alta calidad que el procesamiento final, lo que puede ser lento.
*   **Propuesta:** Crear un pipeline de `preview` alternativo que:
    1.  Reescale la imagen a una resolución menor *al principio* del pipeline.
    2.  Omita los filtros más costosos computacionalmente, como la reducción de ruido (`CINoiseReduction`).
    Esto ofrecerá una previsualización casi instantánea, sacrificando un poco de fidelidad que no es crítica para la `preview`.

## 3. Mejoras al Pipeline "Pro"

El objetivo es refinar la calidad de imagen del pipeline de retratos.

### 3.1. Añadir Control de Calidez (Warmth)

*   **Propuesta:** Añadir las propiedades `temperature` y `tint` a la estructura `AIEnhancementTuning` y usar el filtro `CITemperatureAndTint` en el pipeline. Esto es fundamental para corregir dominantes de color y dar un aspecto más profesional a los retratos.

### 3.2. Reducción de Ruido Adaptativa

*   **Propuesta:** En lugar de aplicar una reducción de ruido global, crear una máscara basada en las áreas de baja frecuencia (zonas desenfocadas, piel) y aplicar una reducción de ruido más intensa en esas zonas, protegiendo el detalle en ojos, pelo y texturas. Se puede usar una combinación de `CIEdges` y `CIGaussianBlur` para crear dicha máscara.

### 3.3. Introducir "Dehaze" Sutil

*   **Propuesta:** Añadir un paso final con `CIHazeRemovalFilter` y una intensidad muy baja (ej: `0.1` - `0.2`). Este filtro puede mejorar el contraste local y la "presencia" de la imagen de una forma muy natural.

## 4. Mejoras de UI/UX

El objetivo es hacer la aplicación más intuitiva y potente para el usuario.

### 4.1. Cachear la Última Receta de la IA

*   **Problema:** Si el usuario activa el modo IA, obtiene una receta, y luego cambia temporalmente al modo "Pro", la receta de la IA se pierde.
*   **Propuesta:** Guardar en una propiedad `@State` la última `EnhancementRecipe` generada para la imagen de `preview` actual. Si el usuario vuelve al modo IA, se reutiliza esta receta cacheada en lugar de hacer una nueva llamada a la API, ahorrando tiempo y costes.

### 4.2. Feedback Visual Inmediato de la Receta IA

*   **Problema:** La receta de la IA se muestra como texto, pero los controles de la UI (sliders, pickers) no reflejan sus sugerencias.
*   **Propuesta:** Al recibir una receta de la IA, actualizar los controles de la UI correspondientes:
    *   El `Slider` de calidad se movería a la posición sugerida.
    *   El `Picker` de `preset` se seleccionaría.
    *   **Propuesta Avanzada:** Añadir sliders para los parámetros clave del `tuning` (sombras, luces, nitidez) y hacer que estos también se actualicen. Esto no solo daría un feedback excelente, sino que permitiría al usuario *ajustar* la recomendación de la IA antes de procesar el lote.

### 4.3. Botón para "Re-analizar con IA"

*   **Problema:** Una vez que la IA ha dado una recomendación, no hay una forma fácil de pedir una nueva si se han cambiado parámetros.
*   **Propuesta:** Añadir un botón de "refrescar" o "re-analizar" junto al estado de la IA. Esto permitiría al usuario forzar un nuevo análisis si, por ejemplo, ha cambiado el `preset` y quiere una nueva recomendación de `tuning` basada en ese cambio.

## 5. Mejoras Adicionales

### 5.1. Refactorizar `OpenAIImageEditClient`

*   **Problema:** El cliente para la API de edición de imágenes de OpenAI (`OpenAIImageEditClient`) construye el cuerpo de la petición `multipart/form-data` manualmente, lo cual es propenso a errores y difícil de leer.
*   **Propuesta:** Crear una clase o struct `MultipartFormDataBuilder` que abstraiga la creación del cuerpo de la petición. Esto haría el código más limpio y reutilizable.

    ```swift
    // Ejemplo de cómo se podría usar
    let body = MultipartFormDataBuilder(boundary: boundary)
        .add(name: "image", filename: "input.png", contentType: "image/png", data: imageData)
        .add(name: "prompt", value: prompt)
        .add(name: "model", value: model)
        .build()
    ```

### 5.2. Unificar el Manejo de la API Key de OpenAI

*   **Problema:** La lógica para resolver la API key de OpenAI (`resolveAPIKey` y `findEnvSecretsFile`) está duplicada o referenciada en `OpenAIImageAdvisor` y `OpenAIImageEditClient`.
*   **Propuesta:** Crear un singleton o un servicio inyectable (ej. `OpenAIServiceLocator`) que se encargue de encontrar y proveer la API key. Ambas clases (`OpenAIImageAdvisor` y `OpenAIImageEditClient`) obtendrían la key de esta fuente única.

### 5.3. Mejorar la Gestión del Historial (`PictHistoryStore`)

*   **Problema:** El historial se guarda en `UserDefaults`, lo cual es adecuado para pequeñas cantidades de datos, pero puede no ser ideal si el historial crece o si las entradas contienen más información (como prompts completos).
*   **Propuesta a corto plazo:** La implementación actual con un límite de `maxEntries` es razonable.
*   **Propuesta a largo plazo:** Si se espera que el historial sea una característica más importante, considerar migrarlo a un archivo dedicado en el directorio de soporte de la aplicación (usando `JSON` o `CoreData`). Esto permitiría un historial más grande y robusto.

### 5.4. Gestión de Foco y Ventana en `Just4PictApp`

*   **Problema:** El código en `onAppear` para activar la aplicación y la ventana es un poco verboso y usa `DispatchQueue.main.async`.
*   **Propuesta:** SwiftUI ha mejorado el manejo de ventanas. Se podría investigar el uso de los modificadores de escena más modernos para simplificar este código, aunque la solución actual es funcional y robusta para AppKit. No es un cambio crítico.
