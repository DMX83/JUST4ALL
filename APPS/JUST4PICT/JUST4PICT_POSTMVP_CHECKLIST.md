# JUST4PICT — Checklist post-MVP

Fecha de referencia: 2026-03-22

Prioridades: `alta` · `media` · `baja`

---

## Calidad visual

- [ ] **Baseline numérica de Paisaje** `alta`
  Crear test equivalente a `testPortraitProBaselineStaysWithinCurrentReferenceWindow` con ventanas RGB para la muestra de paisaje del repo. Sin esto, cualquier cambio futuro puede degradar Paisaje sin que nadie lo detecte.

- [ ] **Calentamiento del cielo en Paisaje** `alta`
  Verificar que el umbral de luminancia `0.72` en `highlightReferenceRGB` captura bien nubes gris-claro. Si `highlightCoverage` no alcanza `0.08` en escenas nubladas, el balance de blancos cae al promedio global y calienta el cielo. Ajustar el umbral o la cobertura mínima.

- [ ] **Curva tonal de Paisaje en bruma** `alta`
  El punto `(0.25, 0.225)` aplasta sombras medias donde vive la bruma de las montañas. Validar con al menos una foto de cielo brillante del repo y ajustar si hay pérdida de detalle en nubes o transiciones de niebla.

- [ ] **Doble protección facial — validar ojos y cejas** `media`
  El blur de la máscara de bordes (`edgeBlurRadius 5.5`) más el blend con `faceMask` en `applyCoreTuning` pueden estar suavizando en exceso ojos y cejas. Verificar al 100% en el retrato de referencia del repo que los ojos tienen definición suficiente.

- [ ] **Desaturar input de `CIEdges` en `applySelectiveSharpen`** `media`
  `CIEdges` opera actualmente sobre la imagen en color. Sujetos con colores saturados (pelo pelirrojo, ropa viva) producen bordes cromáticos falsos en la máscara. Desaturar la imagen antes de pasarla a `CIEdges` para que el detector responda solo a bordes de luminancia.

- [ ] **Eliminar `applyPortraitAISafetyFinish` del path fotográfico** `baja`
  Código muerto en `applyAppleLikePhotoEnhancement`: el branch `if scene == .portrait` nunca se ejecuta porque `resolveRecoveryProfile` siempre devuelve `.conservativePortrait` para retratos, que va por `makePortraitImage`. Eliminar sin consecuencias funcionales.

- [ ] **Unificar radios de blur de máscara entre pipelines** `baja`
  `applyCoreTuning` usa `5.5` / `3.2`; `applyAppleLikePhotoEnhancement` usa `5.0` / `3.0`. Un retrato sin cara detectada toma rutas distintas con resultados diferentes. Unificar los valores o documentar la razón de la diferencia.

---

## Tests

- [ ] **Test de sharpen selectivo por escena** `alta`
  El test existente en `LocalPhotoPipelineTests` solo verifica que `applySelectiveSharpen` produce un delta medible frente al legacy. No valida que el resultado sea correcto por escena (cipreses, bruma, texto denso). Añadir al menos un caso por escena crítica.

- [ ] **Validar 2 retratos adicionales para cerrar Retrato/PRO** `media`
  El TODO lo marca como pendiente. La baseline actual solo tiene una muestra fija en el repo. Necesita al menos 2 casos más antes de declarar Retrato/PRO cerrado definitivamente.

---

## Arquitectura

- [ ] **`CIContext` compartido entre todos los módulos** `media`
  `ImageEnhancer` tiene `sharedContext` pero `LocalPhotoPipeline`, `ProductIsolationEngine` y `FaceRestoreEngine` crean contextos propios en cada instancia. El RSS de `529 MB` en el batch de 100 imágenes apunta aquí. Pasar el contexto compartido por inyección de dependencia.

- [ ] **`autoreleasepool` en el bucle del batch** `media`
  Sin pool explícito en el bucle de `processBatch`, los objetos `CIImage` y `CGImage` se acumulan hasta que el pool del hilo los libera. El RSS de `1 GB` en el batch de 1000 imágenes lo confirma. Wrappear cada iteración en `autoreleasepool {}`.

- [ ] **`UpscaleEngine` como módulo dedicado** `baja`
  El upscale vive actualmente dentro de `LocalPhotoPipeline`. Cuando llegue Real-ESRGAN no habrá dónde encajarlo limpiamente sin un refactor mayor. Extraer a módulo propio antes de que crezca la dependencia.

---

## UX y producto

- [ ] **Comparar PRO vs IA en Paisaje tras corregir balance de blancos** `alta`
  Decisión de producto bloqueante: si después de la corrección del balance de blancos IA sigue siendo claramente mejor con el mismo motor local, el gap es de criterio por imagen y el siguiente paso es Real-ESRGAN o Core ML, no más afinado de filtros.

- [ ] **Before/after con slider** `media`
  En roadmap desde v0.2. Las tres cards de preview son funcionales pero para detectar halos o pérdida de detalle puntual el slider es mucho más efectivo. Especialmente útil para validar mejoras de sharpen y curva tonal.

- [ ] **Fallback IA visible en UI** `media`
  Cuando la API no está disponible, el modo IA ejecuta exactamente el mismo pipeline que PRO sin que el usuario lo sepa. Hay un log en el panel de actividad pero no hay ninguna indicación visual en la sección de preview. El usuario ve "IA" activo pero recibe PRO.

- [ ] **Persistir decisión efectiva de AUTO en historial** `baja`
  El historial guarda el preset seleccionado por el usuario (`Auto`) pero no la escena realmente detectada y aplicada (`Paisaje`, `Documento`, etc.). Útil para debugar decisiones incorrectas de `AUTO` en lotes reales.

---

## Orden de ataque recomendado

```
1. Calentamiento del cielo + curva tonal de Paisaje  → correcciones en LocalPhotoPipeline / ImageAnalyzer
2. Baseline numérica de Paisaje                      → nuevo test en ImageEnhancerDiagnosticsTests
3. Comparativa PRO vs IA en Paisaje                  → decisión de producto
4. Sharpen selectivo desaturado + test por escena    → calidad + cobertura
5. CIContext compartido + autoreleasepool             → memoria y rendimiento en batch
6. Doble protección facial                           → validación visual, posible ajuste
7. Before/after con slider                           → UX
8. Fallback IA visible                               → UX
9. Limpieza de código muerto                         → deuda técnica
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
