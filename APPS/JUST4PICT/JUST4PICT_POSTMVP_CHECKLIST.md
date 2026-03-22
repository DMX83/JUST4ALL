# JUST4PICT — Checklist post-MVP

Fecha de referencia: 2026-03-22

Prioridades: `alta` · `media` · `baja`

---

## Calidad visual

- [ ] **Baseline numérica de Paisaje** `alta`
  Crear test equivalente a `testPortraitProBaselineStaysWithinCurrentReferenceWindow` con ventanas RGB para la muestra de paisaje del repo. Sin esto, cualquier cambio futuro puede degradar Paisaje sin que nadie lo detecte.

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

- [ ] **`CIContext` compartido entre todos los módulos** `media`
  `ImageEnhancer` tiene `sharedContext` pero `LocalPhotoPipeline`, `ProductIsolationEngine` y `FaceRestoreEngine` crean contextos propios en cada instancia. El RSS de `529 MB` en el batch de 100 imágenes apunta aquí. Pasar el contexto compartido por inyección de dependencia.

- [ ] **`autoreleasepool` en el bucle del batch** `media`
  Sin pool explícito en el bucle de `processBatch`, los objetos `CIImage` y `CGImage` se acumulan hasta que el pool del hilo los libera. El RSS de `1 GB` en el batch de 1000 imágenes lo confirma. Wrappear cada iteración en `autoreleasepool {}`.

- [x] **`UpscaleEngine` como módulo dedicado** `baja`
  Ya extraído como módulo propio y además ampliado con backend local + `Real-ESRGAN`.

---

## UX y producto

- [ ] **Comparar PRO vs IA en Paisaje tras corregir balance de blancos** `alta`
  Decisión de producto todavía útil: si después de la corrección del balance de blancos IA sigue siendo claramente mejor con el mismo motor local, el gap es de criterio por imagen y el siguiente paso es planificación/criterio, no más afinado ciego de filtros.

- [ ] **Before/after con slider** `media`
  En roadmap desde v0.2. Las tres cards de preview son funcionales pero para detectar halos o pérdida de detalle puntual el slider es mucho más efectivo. Especialmente útil para validar mejoras de sharpen y curva tonal.

- [ ] **Fallback IA visible en UI** `media`
  Cuando la API no está disponible, el modo IA ejecuta exactamente el mismo pipeline que PRO sin que el usuario lo sepa. Hay un log en el panel de actividad pero no hay ninguna indicación visual en la sección de preview. El usuario ve "IA" activo pero recibe PRO.

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
2. Baseline numérica de Paisaje                      → nuevo test en ImageEnhancerDiagnosticsTests
3. Comparativa PRO vs IA en Paisaje                  → decisión de producto
4. Sharpen selectivo desaturado + test por escena    → calidad + cobertura
5. CIContext compartido + autoreleasepool             → memoria y rendimiento en batch
6. Doble protección facial                           → validación visual, posible ajuste
7. Before/after con slider                           → UX
8. Fallback IA visible                               → UX
9. Definir posición final de `Reconstruir IA`        → producto
10. Limpieza de puntos ya resueltos                  → deuda técnica
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
