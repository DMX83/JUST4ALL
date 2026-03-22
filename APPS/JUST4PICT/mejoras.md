# Mejoras PRO — JUST4PICT

Documento de referencia para la siguiente fase de mejora de calidad visual del pipeline `PRO`.

Última revisión: 2026-03-22 — post-cierre MVP, evaluación completa del estado del producto.

---

## Contexto

El MVP está cerrado de verdad. Hay QA con fotos reales, benchmarks documentados, DMG validado y tests que bloquean regresiones visuales cuantitativas. La arquitectura modular funciona. El trabajo que sigue es post-MVP y tiene un orden claro.

Los tres cambios del pipeline descritos aquí son incrementales e independientes. Cada uno se verifica antes de pasar al siguiente. Después de ellos viene la evaluación de Real-ESRGAN como motor de upscale real.

---

## Restricción importante antes de empezar

El test `testPortraitProBaselineStaysWithinCurrentReferenceWindow` fija ventanas numéricas de referencia para los canales RGB del retrato de muestra. Cualquier cambio debe mantenerse dentro de estas ventanas o actualizarlas conscientemente con justificación visual.

Ventanas actuales:

- Canal R global: 0.57 – 0.64
- Canal G global: 0.54 – 0.60
- Canal B global: 0.51 – 0.57
- Región facial R: 0.56 – 0.70
- Región facial G: 0.46 – 0.62
- Región facial B: 0.38 – 0.56

Implicaciones por paso:

- **Paso 1 (balance de blancos):** una corrección de dominante suave va a mover R y B en sentidos opuestos. Si la foto de referencia no tiene dominante fuerte, el método no toca nada y el test sigue verde automáticamente.
- **Paso 2 (curva de tono):** la ventana global es amplia. Una S-curve suave empuja los valores hacia el centro de la ventana, que es exactamente lo que se busca. El riesgo real es el test de región facial — si la curva quema altas luces en la cara, R facial puede superar 0.70.
- **Paso 3 (sharpen por máscara):** no mueve los valores medios de canal. El test de baseline debería seguir verde sin ajustes.

---

## Paso 1 — Corrección de balance de blancos adaptativa

**Archivo:** `LocalPhotoPipeline.swift`

**Qué hay que hacer:**

Añadir un método privado que use `CITemperatureAndTint`. El método recibe la imagen y el `PhotoAnalysis` que ya existe en el pipeline. Analiza el desequilibrio entre el canal rojo y el azul del análisis para detectar si la imagen tiene dominante cálida o fría. Si la detecta, aplica una corrección inversa suave — nunca más de ±400K de temperatura ni ±4 de tint. Si los canales están equilibrados, el método no toca la imagen.

Este método se llama dentro de `applyPortraitGuidedEnhancement` justo antes del sharpen, y también dentro de `applyAppleLikePhotoEnhancement` para el resto de escenas.

**Por qué importa:**

El pipeline actual no corrige balance de blancos de forma adaptativa. Una foto con dominante fría de interior o cálida de atardecer sale sin corregir. Es el cambio de mayor impacto perceptible con el menor riesgo de artefactos.

**Verificación:**

Correr `testWritesRepoSampleOutputsForQuickQA` y comparar visualmente las salidas en `images/test`. El delta en `testDetectsPortraitAndProducesMeasurableChangeForUserSample` debe subir respecto al baseline actual. Verificar que los canales del retrato de referencia siguen dentro de las ventanas del test de baseline.

---

## Paso 2 — Sustituir el contraste lineal por curva de tono

**Archivo:** `LocalPhotoPipeline.swift`

**Qué hay que hacer:**

Crear un método privado que use `CIToneCurve` con cinco puntos de control. Los puntos varían por escena:

- **Retrato:** curva casi plana con micro-punch solo en medios tonos. Protege piel y altas luces.
- **Paisaje:** S-curve más pronunciada. Da contraste local real sin quemar cielo.
- **Resto:** intermedio entre los dos anteriores.

Este método reemplaza el uso actual de `CIColorControls.contrast` en `applyPortraitGuidedEnhancement` y en `applyAppleLikePhotoEnhancement`. El parámetro `contrast` del `CoreTuning` y del `AIEnhancementTuning` se puede mantener como está — pasa a modular la intensidad de la curva en lugar de aplicarse directamente como contraste lineal.

**Por qué importa:**

El contraste lineal con `CIColorControls` comprime todo el rango tonal de forma uniforme. La curva de tono permite dar presencia en medios tonos sin quemar altas luces ni cerrar sombras. La diferencia visual en retratos es notable — la imagen gana presencia sin parecer procesada.

**Verificación:**

Correr `testWritesRepoSampleOutputsForQuickQA`. Comparar que el retrato de muestra gana presencia sin que las altas luces se quemen. Verificar que R facial no supera 0.70 en el test de baseline. Si el delta baja o aparecen altas luces quemadas, revertir.

---

## Paso 3 — Sharpen selectivo por máscara de bordes

**Archivo:** `LocalPhotoPipeline.swift`

**Qué hay que hacer:**

Crear un método privado que sustituya las llamadas actuales a `applySharpen` en los pipelines de retrato y fotografía general. El nuevo método sigue tres pasos:

1. Genera un mapa de bordes con `CIEdges`.
2. Suaviza ese mapa con `CIGaussianBlur` para que el blending sea gradual, sin cortes duros.
3. Aplica el sharpen solo donde la máscara de bordes tiene valor alto, usando `CIBlendWithMask`.

El radio del blur de la máscara es mayor en retrato que en paisaje o genérico — esto protege más la piel en retratos y permite más nitidez en texturas de paisaje.

El método `applySharpen` original se mantiene como fallback interno por si falla la generación del mapa de bordes.

**Por qué importa:**

El sharpen global actual aplicado a retrato genera textura artificial en zonas de piel plana. Con la máscara de bordes, la piel queda suave, el pelo queda nítido y los ojos ganan definición. Es el cambio que más diferencia hace en la calidad percibida de un retrato.

**Verificación:**

Correr `testFaceRestoreAddsContainedChangeOnPortraitSample` — el delta en la región facial no debe crecer de forma anómala. Inspeccionar visualmente que no aparecen halos en piel ni bordes duros alrededor de la cara. El test de baseline debería seguir verde sin ajustes ya que el sharpen no mueve medias de canal.

---

## Orden de ejecución

```
Paso 1 → verificar QA → Paso 2 → verificar QA → Paso 3 → verificar QA → pregunta de producto
```

No pasar al siguiente paso sin verificar el anterior. Si cualquier paso produce regresión visual en las muestras del repo, revertir ese paso antes de continuar.

---

## Pregunta de producto después de los tres pasos

Después de implementar y validar los tres pasos, hacer esta pregunta con fotos reales: ¿el resultado convence a alguien que no sabe de procesado de imágenes?

- Si la respuesta es **sí** → el pipeline PRO está cerrado. Siguiente frente: cerrar el gap de `EnhancementRecipe` como contrato efectivo.
- Si la respuesta es **no del todo** → el límite real es el upscale. Siguiente frente: Real-ESRGAN.

---

## Siguiente frente A — Cerrar el gap de EnhancementRecipe

**Cuándo:** después de los tres pasos de mejora visual, si el resultado PRO es satisfactorio.

**Archivo:** `ImageEnhancer.swift`

**Qué hay que hacer:**

En `makeEnhancedImage`, la escena se re-detecta localmente ignorando lo que dijo la IA. Si la receta IA dice que la imagen es retrato pero el detector local dice genérico, gana el detector local. Hay que permitir que la escena de la receta pueda sobrescribir la detección local cuando existe una receta válida. Es un cambio pequeño con alto impacto en coherencia del modo IA.

**Por qué importa:**

Sin este cambio, el modo IA no es realmente diferente del modo PRO en comportamiento de pipeline. La receta existe estructuralmente pero no gobierna el pipeline de forma completa. Es el gap más importante que queda entre la arquitectura documentada y su implementación efectiva.

---

## Siguiente frente B — Real-ESRGAN como motor de upscale

**Cuándo:** después de los tres pasos de mejora visual, si el resultado PRO tiene un techo perceptible en fotos pequeñas o con compresión agresiva.

**Qué hay que hacer:**

Real-ESRGAN tiene binario para macOS. Se puede llamar desde Swift con `Process()` sin tocar Core ML todavía. Se activa solo cuando la imagen está por debajo de un umbral de resolución o cuando el analizador detecta degradación severa — no por defecto en todas las fotos. El Lanczos actual se queda como fallback rápido cuando la imagen ya tiene resolución suficiente.

**Por qué importa:**

El Lanczos actual upscala resolución pero no recupera detalle destruido por compresión o resolución insuficiente. Real-ESRGAN inventa detalle de alta frecuencia real. Es el paso que convierte "mejora fotos" en "restaura fotos" para imágenes degradadas. Es también el mayor salto de calidad perceptible que queda disponible después de cerrar el pipeline tonal.

---

## Lo que no se abre ahora

Estos frentes son correctos arquitectónicamente pero sin impacto visible para el usuario en esta fase:

- `ExportPipeline` como módulo dedicado
- `UpscaleEngine` como módulo separado
- `CIContext` compartido en todos los flujos
- `autoreleasepool` en lote grande
- Firma y notarización

Los tres primeros son refactors que no cambian nada visible. Los dos de rendimiento tienen medición de referencia documentada en `QA_BATCH_LOCAL.md` — mientras no haya regresión observable en esas métricas, es optimización prematura. Firma y notarización espera a que el pipeline visual esté cerrado.

---

## Tests relevantes a mantener verdes

- `OutputFormatTests` — contratos de formato y calidad
- `PictHistoryStoreTests` — historial y privacidad
- `ImageEnhancerDiagnosticsTests` — QA visual con fotos reales del repo
- `testPortraitProBaselineStaysWithinCurrentReferenceWindow` — ventana numérica de baseline de retrato
- `ImageAnalyzerTests` — clasificación de escena
- `EnhancementPlannerTests` — resolución de receta y fallback

---

## Archivos afectados

| Archivo | Cambio |
|---|---|
| `LocalPhotoPipeline.swift` | Pasos 1, 2 y 3: añadir métodos nuevos y conectarlos al pipeline existente |
| `ImageEnhancer.swift` | Frente A: permitir que la receta IA sobrescriba la escena detectada localmente |
| `ENHANCE_ARCHITECTURE.md` | Actualizar estado de Fase 1 cuando los pasos estén cerrados |
| `TODO.md` | Marcar los ítems correspondientes de la sección `3B) Calidad visual avanzada` |
