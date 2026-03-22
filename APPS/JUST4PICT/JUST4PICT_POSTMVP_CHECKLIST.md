# JUST4PICT — Checklist post-MVP

Fecha de referencia: 2026-03-22

Prioridades: `alta` · `media` · `baja`

---

## Calidad visual

- [x] **Baseline numérica de Paisaje** `alta`
  Ya existe `testLandscapeProBaselineStaysWithinCurrentReferenceWindow` con ventanas RGB para cielo, suelo y bruma sobre la muestra real `image_paisaje_orig.jpeg`.

- [x] **Calentamiento del cielo en Paisaje** `alta`
  Umbral de cobertura bajado a 0.05 para nubes; mezcla vertical via `blendLandscapeWhiteBalance`. Validación numérica pendiente solo si se detecta regresión.

- [x] **Curva tonal de Paisaje en bruma** `alta`
  Punto (0.25, 0.235) suavizado respecto a la versión anterior (era 0.225). Validación visual realizada sobre muestra real, sin pérdida de detalle relevante.

- [ ] **Doble protección facial — validar ojos y cejas** `media`
  Ya existe una guardia automática para ojos/cejas, pero falta validación visual manual al 100% en más de un retrato antes de darlo por completamente cerrado.

- [x] **Desaturar input de `CIEdges` en `applySelectiveSharpen`** `media`
  Ya aplicado: la máscara de sharpen selectivo se genera desde luminancia desaturada y no desde color completo.

- [x] **Eliminar `applyPortraitAISafetyFinish` del path fotográfico** `baja`
  Ya limpiado del path fotográfico general.

- [x] **Unificar radios de blur de máscara entre pipelines** `baja`
  Ambos pipelines usan 5.5 / 3.2. Documentado y unificado salvo casos especiales justificados.

---

## Tests

- [ ] **Test de sharpen selectivo por escena** `alta`
  El test existente en `LocalPhotoPipelineTests` solo verifica que `applySelectiveSharpen` produce un delta medible frente al legacy. No valida que el resultado sea correcto por escena (cipreses, bruma, texto denso). Añadir al menos un caso por escena crítica.

- [x] **Validar 2 retratos adicionales para cerrar Retrato/PRO** `media`
  Ya queda cubierto con validación automática sobre dos retratos adicionales del repo usando detección facial y una guardia de detalle en la banda de ojos/cejas; uno de esos casos es una miniatura degradada para no cerrar el preset solo sobre retratos cómodos.

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

- [x] **Persistir decisión efectiva de AUTO en historial** `baja`
  Ya resuelto: el historial conserva la escena realmente aplicada cuando el lote se ejecuta desde `Auto`.

- [x] **Definir posición final de `Reconstruir IA`** `media`
  Ya queda fijado como herramienta manual de rescate extremo. Se recomienda para miniaturas extremas, compresión severa o retratos muy degradados, pero no se autoactiva.

- [x] **Comparar `Reconstruir IA` vs `Real-ESRGAN` en miniaturas extremas** `media`
  La regla actual queda fijada así: `Real-ESRGAN` para imágenes pequeñas no faciales; `Reconstruir IA` para miniaturas extremas o retratos degradados donde hace falta reconstrucción semántica. La UI ya lo sugiere sin autoactivar ninguno.

- [x] **`Ecommerce + IA` como rescate opcional** `media`
  Ya queda resuelto como variante manual de `Reconstruir IA`: cuando el preset o la escena efectiva son `Ecommerce`, la reconstrucción usa un prompt específico para limpiar bordes complejos y recomponer sobre blanco sin activarse sola.

- [x] **Unificar la política de export entre `PRO` y `Reconstruir IA`** `media`
  Ya resuelto con `ImageExportWriter`: resize por destino, `Web <300KB>` y compresión iterativa viven en un camino común y evitan duplicar lógica de exportación.

---

## Orden de ataque recomendado

```
1. Calentamiento del cielo + curva tonal de Paisaje  → correcciones en LocalPhotoPipeline / ImageAnalyzer
2. Sharpen selectivo desaturado + test por escena    → calidad + cobertura
3. Doble protección facial                           → validación visual, posible ajuste
4. Limpieza de puntos ya resueltos                   → deuda técnica
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
