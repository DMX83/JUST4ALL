# Mejoras PRO — JUST4PICT

Documento de referencia para la siguiente fase de mejora de calidad visual del pipeline `PRO`.

---

## Contexto

El pipeline PRO actual funciona y es usable como baseline. Es conservador por diseño para no romper retratos. El objetivo de esta fase es subir el nivel de calidad perceptible sin introducir artefactos, manteniendo todos los contratos actuales del producto.

Los tres cambios descritos aquí son incrementales e independientes. Cada uno se verifica antes de pasar al siguiente.

---

## Paso 1 — Corrección de balance de blancos adaptativa

**Archivo:** `LocalPhotoPipeline.swift`

**Qué hay que hacer:**

Añadir un método privado que use `CITemperatureAndTint`. El método recibe la imagen y el `PhotoAnalysis` que ya existe en el pipeline. Analiza el desequilibrio entre el canal rojo y el azul del análisis para detectar si la imagen tiene dominante cálida o fría. Si la detecta, aplica una corrección inversa suave — nunca más de ±400K de temperatura ni ±4 de tint. Si los canales están equilibrados, el método no toca la imagen.

Este método se llama dentro de `applyPortraitGuidedEnhancement` justo antes del sharpen, y también dentro de `applyAppleLikePhotoEnhancement` para el resto de escenas.

**Por qué importa:**

El pipeline actual no corrige balance de blancos de forma adaptativa. Una foto con dominante fría de interior o cálida de atardecer sale sin corregir. Este es el cambio de mayor impacto perceptible con el menor riesgo de artefactos.

**Verificación:**

Correr `testWritesRepoSampleOutputsForQuickQA` y comparar visualmente las salidas en `images/test`. El delta en `testDetectsPortraitAndProducesMeasurableChangeForUserSample` debe subir respecto al baseline actual.

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

Correr `testWritesRepoSampleOutputsForQuickQA`. Comparar que el retrato de muestra gana presencia sin que las altas luces se quemen. Si el delta baja o aparecen altas luces quemadas, revertir.

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

Correr `testFaceRestoreAddsContainedChangeOnPortraitSample` — el delta en la región facial no debe crecer de forma anómala. Inspeccionar visualmente que no aparecen halos en piel ni bordes duros alrededor de la cara.

---

## Orden de ejecución

```
Paso 1 → verificar QA → Paso 2 → verificar QA → Paso 3 → verificar QA
```

No pasar al siguiente paso sin verificar el anterior. Si cualquier paso produce regresión visual en las muestras del repo, revertir ese paso antes de continuar.

---

## Lo que estos cambios no resuelven

Fotos muy pequeñas o con compresión JPEG severa tienen un techo con Core Image. Los tres pasos anteriores mejoran la calidad tonal y de detalle, pero no pueden recuperar información destruida por compresión agresiva o resolución insuficiente.

El siguiente paso correcto después de cerrar estos tres es evaluar **Real-ESRGAN** como motor de upscale alternativo al Lanczos actual, activado solo cuando la imagen está por debajo de un umbral de resolución o cuando el analizador detecta degradación severa.

---

## Tests relevantes a mantener verdes

- `OutputFormatTests` — contratos de formato y calidad
- `PictHistoryStoreTests` — historial y privacidad
- `ImageEnhancerDiagnosticsTests` — QA visual con fotos reales del repo
- `ImageAnalyzerTests` — clasificación de escena
- `EnhancementPlannerTests` — resolución de receta y fallback

---

## Archivos afectados

| Archivo | Cambio |
|---|---|
| `LocalPhotoPipeline.swift` | Añadir los tres métodos nuevos y conectarlos al pipeline existente |
| `ENHANCE_ARCHITECTURE.md` | Actualizar estado de Fase 1 cuando los pasos estén cerrados |
| `TODO.md` | Marcar los ítems correspondientes de la sección `3B) Calidad visual avanzada` |
