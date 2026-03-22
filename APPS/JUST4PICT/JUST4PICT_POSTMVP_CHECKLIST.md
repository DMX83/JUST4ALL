# JUST4PICT — Checklist post-MVP

Fecha de referencia: 2026-03-22

Prioridades: `alta` · `media` · `baja`

---

## Calidad visual

- [x] **Baseline numérica de Paisaje** `alta`
  Ya existe `testLandscapeProBaselineStaysWithinCurrentReferenceWindow` con ventanas RGB para cielo, suelo y bruma sobre la muestra real `image_paisaje_orig.jpeg`.

- [ ] **Calentamiento del cielo en Paisaje** `alta`
  Verificar que la lógica actual de altas luces para cielo nublado sigue siendo suficientemente neutra en escenas con nubes gris-claro. El umbral ya fue bajado y el blend suavizado, pero falta fijar una validación numérica que detecte recalentamiento del cielo antes de futuras regresiones.

- [ ] **Curva tonal de Paisaje en bruma** `alta`
  La curva de paisaje ya fue suavizada, pero falta una validación estable con al menos una foto de cielo brillante del repo para detectar pérdida de detalle en nubes o transiciones de niebla.

- [ ] **Doble protección facial — validar ojos y cejas** `media`
  Ya existe una guardia automática para ojos/cejas, pero falta validación visual manual al 100% en más de un retrato antes de darlo por completamente cerrado.

- [x] **Desaturar input de `CIEdges` en `applySelectiveSharpen`** `media`
  Ya aplicado: la máscara de sharpen selectivo se genera desde luminancia desaturada y no desde color completo.

- [x] **Eliminar `applyPortraitAISafetyFinish` del path fotográfico** `baja`
  Ya limpiado del path fotográfico general.

- [ ] **Unificar radios de blur de máscara entre pipelines** `baja`
  Revisar si la diferencia residual entre radios de blur sigue teniendo sentido visual o si conviene documentarla/mejor unificarla.

---

## Tests

- [ ] **Test de sharpen selectivo por escena** `alta`
  El test existente en `LocalPhotoPipelineTests` solo verifica que `applySelectiveSharpen` produce un delta medible frente al legacy. No valida que el resultado sea correcto por escena (cipreses, bruma, texto denso). Añadir al menos un caso por escena crítica.

- [ ] **Validar 2 retratos adicionales para cerrar Retrato/PRO** `media`
  El TODO lo marca como pendiente. La baseline actual solo tiene una muestra fija en el repo. Necesita al menos 2 casos más antes de declarar Retrato/PRO cerrado definitivamente.

---

## Arquitectura

- [x] **`CIContext` compartido entre todos los módulos** `media`
  Ya resuelto: `ImageEnhancer` centraliza `sharedContext` y lo inyecta en `ImageAnalyzer`, `LocalPhotoPipeline`, `UpscaleEngine` y `ProductIsolationEngine`. `FaceRestoreEngine` no crea contexto propio.

- [x] **`autoreleasepool` en el bucle del batch** `media`
  Ya aplicado en export, preview y worker detached del batch. La repetición de 100 imágenes con `/usr/bin/time -l` bajó la RSS máxima observada de ~`529 MB` a ~`143 MB`.

- [x] **`UpscaleEngine` como módulo dedicado** `baja`
  Ya extraído como módulo propio y además ampliado con backend local + `Real-ESRGAN`.

---

## UX y producto

- [x] **Comparar PRO vs IA en Paisaje tras corregir balance de blancos** `alta`
  Ya existe `testAIDiagnosticComparesProAgainstAIOnLandscapeSample`. En la muestra real actual, IA eligió `Paisaje`, `PNG` y `q=1.0` sin mostrar una ventaja fuerte frente a `PRO`, así que el siguiente salto ya no parece estar en más ajuste fino ciego de IA para paisaje.

- [x] **Before/after con slider** `media`
  Ya resuelto en preview como comparador adicional de inspección rápida, sin sustituir las tres cards existentes.

- [x] **Fallback IA visible en UI** `media`
  Ya resuelto: la barra de estado y la tarjeta de preview muestran explícitamente `IA→PRO` cuando la recomendación IA cae a fallback local.

- [ ] **Persistir decisión efectiva de AUTO en historial** `baja`
  El historial guarda el preset seleccionado por el usuario (`Auto`) pero no la escena realmente detectada y aplicada (`Paisaje`, `Documento`, etc.). Útil para debugar decisiones incorrectas de `AUTO` en lotes reales.

- [ ] **Definir posición final de `Reconstruir IA`** `media`
  Ya existe como modo opcional de preview y batch con salida separada. Falta decidir si se queda como herramienta manual para rescate extremo o si merece heurística automática para imágenes muy degradadas.

- [ ] **Comparar `Reconstruir IA` vs `Real-ESRGAN` en miniaturas extremas** `media`
  Ahora ambos caminos existen. Falta decidir con muestras reales cuándo conviene cada uno y si alguno debe quedar preferido por escena o por nivel de degradación.

---

## Orden de ataque recomendado

```
1. Calentamiento del cielo + curva tonal de Paisaje  → correcciones en LocalPhotoPipeline / ImageAnalyzer
2. Sharpen selectivo desaturado + test por escena    → calidad + cobertura
3. Doble protección facial                           → validación visual, posible ajuste
4. Definir posición final de `Reconstruir IA`        → producto
5. Limpieza de puntos ya resueltos                   → deuda técnica
```

---

## Tests a mantener verdes en todo momento

- `OutputFormatTests`
- `PictHistoryStoreTests`
- `ImageEnhancerDiagnosticsTests`
- `testPortraitProBaselineStaysWithinCurrentReferenceWindow`
- `ImageAnalyzerTests`
- `EnhancementPlannerTests`
- `LocalPhotoPipelineTests`
- `ExportProfileTests`
