## Plan: Potenciar el preset "pro" en JUST4PICT

El objetivo es que el preset "pro" logre una mejora de imagen perceptiblemente superior, manteniendo naturalidad y evitando artefactos, pero con mayor impacto visual y control profesional.

**Fases y pasos**

### 1. Ajustes de pipeline y parámetros

1. Integrar filtro de calidez (`CITemperatureAndTint`) en el pipeline "pro" (retratos), permitiendo corrección de dominantes y ajuste fino de tono de piel.
2. Añadir paso de dehaze sutil (`CIHazeRemovalFilter` o equivalente) al final del pipeline para mejorar contraste local y claridad.
3. Revisar y ampliar los rangos permitidos para exposición, saturación, nitidez y contraste en el perfil "pro", permitiendo mayor realce cuando la imagen lo requiera.
4. Hacer que los parámetros de ajuste sean adaptativos según el análisis de la imagen (luminancia, histograma, presencia de ruido, etc.).

### 2. Protección facial avanzada

1. Mejorar la generación de la máscara facial usando segmentación semántica (si es viable) o heurísticas más precisas para proteger ojos, boca y piel sin sobreproteger el resto.
2. Permitir un blending progresivo entre zonas protegidas y no protegidas para evitar bordes duros.

### 3. Validación perceptual y feedback

1. Implementar un paso de validación perceptual simple (por ejemplo, análisis de histograma, contraste local, detección de sobreprocesado) tras aplicar el pipeline.
2. Si el resultado es demasiado plano o poco natural, ajustar automáticamente los parámetros y volver a procesar (máximo 1-2 iteraciones).

### 4. Opcional: Integración IA avanzada

1. Investigar la integración de modelos Core ML o APIs externas para superresolución, mejora de detalle o ajuste perceptual.
2. Permitir que el usuario active/desactive el modo IA avanzada desde la UI.

**Archivos relevantes**

- APPS/JUST4PICT/Sources/JUST4PICT/ImageEnhancer.swift — Pipeline principal, presets, tuning, protección facial.
- APPS/JUST4PICT/propuesta.md — Documentación de arquitectura y mejoras propuestas.
- APPS/JUST4PICT/ENHANCE_ARCHITECTURE.md — Referencia de principios y objetivos.

**Verificación**

1. Procesar un set de retratos y comparar visualmente el resultado "pro" antes y después de los cambios.
2. Validar que la mejora es perceptible, natural y sin artefactos en la piel o fondo.
3. QA manual con la muestra fija del repo y las salidas visibles en `images/test`.
4. Revisar logs para asegurar que los nuevos pasos del pipeline se ejecutan correctamente.

**Decisiones**

- Se prioriza el impacto visual y la naturalidad, sin sacrificar la protección de rostros.
- Se mantiene la modularidad y la posibilidad de desactivar pasos avanzados si afectan el rendimiento.

**Consideraciones adicionales**

1. Si la segmentación facial avanzada no es viable, mantener la máscara elíptica pero ajustar el blur y blending.
2. Documentar todos los cambios en `propuesta.md` y actualizar la arquitectura en `ENHANCE_ARCHITECTURE.md`.
