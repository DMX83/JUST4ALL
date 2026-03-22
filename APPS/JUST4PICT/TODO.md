# TODO — JUST4PICT (MVP)

## Direccion actual

Objetivo inmediato:

- congelar una baseline visual buena de `PRO` que ya es usable, natural y consistente
- hacer que `AUTO` herede correctamente ese pipeline cuando detecte cara y mejore su criterio en paisaje/nocturna
- mantener la UI estable y la preview manual con `Enhance`

Objetivo de producto:

- evolucionar desde un MVP funcional a un modulo `Enhance` serio, por componentes
- conseguir una mejora visible y limpia, sin artefactos, con exportacion alta calidad
- dejar la puerta abierta a upscale serio y modulos avanzados sin romper la base local

## Guardrails antes de insertar mas IA

- no romper `PNG` como formato por defecto ni su posicion como primera opcion del selector
- no reintroducir `JPG` con compresion por defecto
- no degradar `PRO`, que sigue siendo la baseline visual de referencia
- no cambiar la preview manual por refresco automatico agresivo
- no perder compatibilidad con historial local, naming con colisiones y export multi-formato
- no persistir el prompt completo de IA por defecto
- cualquier ampliacion de `IA` debe pasar por tests y mantener verdes:
  - `OutputFormatTests`
  - `PictHistoryStoreTests`
  - `ImageEnhancerDiagnosticsTests`

## 0) Base del modulo

- [x] Crear modulo nativo `APPS/JUST4PICT` en SwiftUI.
- [x] Configurar `Package.swift` y entrypoint de app.
- [x] Crear script de build DMG.
- [x] Crear README y roadmap inicial.

## 1) Pipeline de mejoramiento automatico

- [x] Presets base (Auto, Retrato, Paisaje, Documento, Ecommerce).
- [x] Auto-ajuste inicial con Core Image.
- [x] Ajustes base de color y nitidez.
- [x] Reduccion de ruido suave.
- [x] Export JPG/PNG/HEIC/WEBP/TIFF.
- [x] Manejo de colisiones en nombres de salida.
- [x] Upscale automatico a HD (Lanzcos, lado mayor >= 1920 cuando aplica).
- [x] Paso adaptativo post-upscale para recuperar detalle sin halos.
- [x] Deteccion automatica discreta de tipo de imagen (retrato/documento/paisaje) en preset Auto.
- [x] Modo conservador interno para retratos (evitar sobreprocesado sin perder mejora).
- [x] Logging interno QA cuando se activa conservativePortrait y upscale.
- [x] Ajuste fino "Retrato Pro" para recuperar microdetalle sin halos.
- [x] Preview manual con boton `Enhance` (sin auto-refresh agresivo).
- [x] Visor ampliado de preview por doble click, con navegacion solo entre imagenes disponibles.
- [x] Versionado visible en UI y nombres de salida versionados para evitar mezclas de builds.
- [x] Baseline usable de `PRO` para retrato, ya sin oscuridad ni dominante rota.
- [x] QA visible dentro del repo para multiples muestras en `images/test/*-pro-sample.png`.
- [x] `AUTO` hereda explicitamente `Retrato`, `Documento` y `Paisaje` segun escena detectada.
- [x] Deteccion adicional de paisaje vertical por contenido para evitar depender solo del ratio.
- [x] Ajuste fino inicial de `PRO` para retrato, paisaje y nocturna sobre muestras reales del repo.
- [x] Ajuste fino final de `Retrato/PRO` para la baseline actual del MVP.
- [x] Limpiar residuos del pipeline antiguo de retrato y mantener una sola baseline `PRO`.
- [x] Afinar `AUTO` en nocturna y generico oscuro con una receta base mas inteligente.
- [x] Mejorar deteccion `AUTO` para documento mas alla de cara/texto/ratio.
- [x] Mejorar deteccion `AUTO` para producto/ecommerce mas alla de cara/texto/ratio.
- [x] Extender `AUTO -> Ecommerce` para cubrir muestra real de catalogo movil, no solo producto sobre fondo blanco puro.
- [x] Detectar producto principal en `Ecommerce`, quitar fondo y recomponerlo centrado sobre blanco.
- [x] Corregir `Documento` para que mantenga fondo blanco visible y no derive a grises oscuros en la muestra real.

## 1A) Fase Retrato Pro

Meta:

- que `Retrato/PRO` sea el preset de referencia del producto

Trabajo:

- [ ] mantener tono y exposicion neutros como base estable
- [ ] añadir detalle local moderado en pelo, ropa y bordes
- [ ] proteger piel y cara durante el sharpen
- [ ] introducir micro-punch muy leve sin cerrar negros ni quemar blancos
- [ ] evaluar `temperature/tint` muy sutil para corregir dominantes de piel
- [ ] definir limites de seguridad para no volver a resultados oscuros/calentados
- [ ] validar con la foto fija del repo y al menos 2 retratos adicionales

Verificacion:

- [x] QA automatizada sobre `APPS/JUST4PICT/images/PHOTO-2026-03-18-22-18-19 2.jpg`
- [x] Generar salidas visibles en `APPS/JUST4PICT/images/test/*-pro-sample.png`
- [x] QA visual A/B contra salida anterior
- [x] confirmar que el resultado mejora detalle sin perder naturalidad
- [ ] validar con 2 retratos adicionales para cerrar `Retrato/PRO`

## 1B) Fase AUTO

Meta:

- que `AUTO` sea fiable y use el mejor pipeline disponible por tipo de imagen

Trabajo:

- [x] si detecta cara, usar exactamente el pipeline final de `Retrato`
- [ ] si detecta texto denso, usar `Documento`
- [x] si detecta baja luminancia, activar perfil de recuperacion de fotos oscuras
- [x] mejorar clasificacion de paisaje/generico con analisis de luminancia y textura
- [x] documentar decision efectiva de `AUTO` en logs y UI
- [x] congelar el perfil de export al iniciar lote/reintento para evitar mezclas dentro del mismo batch
- [x] validar `AUTO` con muestras reales del repo para `document` y `ecommerce`
- [x] hacer menos ambiguo el log de `AUTO` al cargar lotes; debe reflejar que se trata de la preview actual

Verificacion:

- [x] prueba con retrato
- [x] prueba con paisaje
- [x] prueba unitaria de clasificacion para documento
- [x] prueba con foto oscura
- [x] prueba diagnostica con `APPS/JUST4PICT/images/images_document_orig.jpeg`
- [x] prueba diagnostica con `APPS/JUST4PICT/images/image_commerce_orig.jpeg`
- [x] generar salidas QA visibles `images_document_orig-auto-sample.png` y `image_commerce_orig-auto-sample.png`
- [x] verificar por test que las esquinas del export `Ecommerce` quedan blancas en la muestra real

## 2) UX batch

- [x] Seleccion de imagenes por archivo.
- [x] Agregar carpeta (escaneo recursivo).
- [x] Progreso global del lote.
- [x] Log por item (ok/error).
- [x] Cancelacion de lote en ejecucion.
- [x] Reintento rapido para errores.
- [x] Fijar `PNG` como formato por defecto y primera opcion del selector para priorizar maxima calidad.

## 3) Calidad y producto

- [x] Vista comparativa de preview en tiempo real.
- [x] Sugerencia IA (OpenAI) para preset/calidad HD + prompt HD copiable.
- [x] Guardar sugerencia IA aplicada en historial (preset/calidad/prompt).
- [x] Privacidad: guardar por defecto resumen de prompt IA en historial (no texto completo).
- [x] Preview paralela `Original` / `PRO` / `IA`.
- [x] IA devuelve receta local inicial (sombras, luces, vibrance, nitidez, contraste, saturacion, exposicion).
- [x] Hacer que IA analice la imagen real por vision, no solo metadatos.
- [x] Formalizar `EnhancementRecipe` como modelo central del pipeline.
- [x] Separar `ImageAnalyzer`, `EnhancementPlanner` y `LocalPhotoPipeline`.
- [x] Mostrar en UI la receta IA completa aplicada.
- [x] Resize inteligente por preset/destino (`social`, `web`, `ecommerce`).
- [ ] Correccion de horizonte y recorte de documento (Vision).
- [ ] Perfil "Recuperar fotos oscuras".
- [ ] Perfil "Optimizar para web < 300KB".
- [ ] Introducir `UpscaleEngine` dedicado para fotos pequenas.
- [ ] Evaluar `Core ML` como motor serio de enhancement/upscale.
- [ ] Evaluar `Real-ESRGAN` como benchmark de calidad para upscale.
- [~] Añadir modulo opcional de restauracion facial, apagado por defecto.
  Ya existe una primera version local, selectiva y conservadora; falta evaluar si se queda asi o pasa a motor dedicado.

## 3A) Refactor de arquitectura

Meta:

- dejar de depender de un `ImageEnhancer` monolitico

Trabajo:

- [x] separar `ImageAnalyzer`
- [x] separar `EnhancementPlanner`
- [x] separar `LocalPhotoPipeline`
- [x] reducir duplicacion obvia de orquestacion en `ContentView` sin cambiar el flujo funcional
- [~] convertir `EnhancementRecipe` en contrato central efectivo, no solo estructural
  Ya gobierna `scene`, `preset`, `format`, `quality`, `upscale` y `faceRestore`; aun falta cerrar mejor el resto del planner y futuras etapas opcionales.
- [x] propagar `faceRestore` como contrato estable de receta en batch, preview y export
- [ ] reutilizar `CIContext` compartido en todos los flujos
- [ ] introducir `autoreleasepool` en lote grande
- [x] evitar lectura de dimensiones con `NSImage` en el flujo IA; usar metadata/pixel size

Verificacion:

- [ ] medir que no se degrada la velocidad de preview
- [ ] medir que el batch no crece en memoria de forma anomala

## 3B) Calidad visual avanzada

Meta:

- llevar `Enhance` a un nivel claramente superior al MVP inicial

Trabajo:

- [~] sustituir contraste global por `CIToneCurve` donde aporte valor real
- [~] introducir sharpen selectivo por mascara de bordes
- [~] introducir correccion adaptativa de balance de blancos en `PRO` y fotografia general
- [x] mover el criterio de balance de blancos hacia altas luces fiables con fallback al promedio global
- [x] desaturar la entrada de `CIEdges` para que el sharpen selectivo responda a luminancia y no a bordes cromaticos
- [x] unificar radios de blur de la mascara de sharpen entre rutas de retrato/fotografia general
- [x] eliminar rama muerta de `applyPortraitAISafetyFinish` en el path fotografico general
- [ ] refinar la mascara facial para proteger piel y mantener ojos/cabello
- [ ] evaluar microcontraste moderado por escena
- [ ] añadir validacion perceptual simple para detectar sobreprocesado
- [ ] bloquear automaticamente recetas que cierren demasiado la imagen

Nota:

- existe una primera pasada aplicada desde `mejoras.md` con curva tonal, sharpen selectivo y balance de blancos adaptativo
- esta pasada ya incorpora referencia de altas luces para blancos y sharpen por luminancia; sigue pendiente validacion visual fina antes de consolidarla como baseline nueva

Verificacion:

- [ ] comparar antes/despues en set de retratos
- [ ] comparar antes/despues en set de paisajes
- [ ] confirmar que no aparecen halos ni plastificado
- [x] añadir tests unitarios para activacion/no-disparo del balance de blancos
- [x] añadir test unitario para diferencia medible del sharpen selectivo frente al sharpen legacy
- [x] añadir muestra degradada controlada para validar `upscale` local (`image_upscale_lowres.jpeg`)

## 3C) Calidad de exportacion

Meta:

- que la mejora no se pierda al guardar

Trabajo:

- [x] alinear preview y export para que el render final sea coherente
- [x] respetar formato/calidad sugeridos por receta IA
- [x] asegurar `PNG` como salida por defecto de maxima calidad en la UI
- [ ] asegurar exportacion maxima en `PNG` y `JPG` segun caso
- [x] introducir resize inteligente por destino (`social`, `web`, `ecommerce`)
- [ ] evitar dobles compresiones y reescalados innecesarios
- [ ] evaluar si el recorte de producto necesita controles manuales o margen configurable para catalogo estricto
- [ ] evaluar una variante opcional `Ecommerce + IA` para reconstruccion/limpieza de bordes complejos cuando Vision no recorte bien el producto

Verificacion:

- [x] comparar preview vs archivo exportado
  Cobertura añadida para coherencia general y resize real de export.
- [ ] medir tamaño final y fidelidad visual

## 3D) IA de producto

Meta:

- que `IA` aporte criterio real y no solo otra variante de `PRO`

Trabajo:

- [ ] hacer que la IA describa intencion visual y no solo sliders
- [ ] usar esa intencion para guiar el planner local
- [x] cachear la ultima receta IA por imagen para no repetir analisis
- [ ] decidir si conviene upscale o face restore solo cuando haya evidencia
- [x] dejar `faceRestore` integrado como etapa local conservadora sin romper la baseline `PRO`
- [ ] mostrar en UI una explicacion corta de la decision IA

Verificacion:

- [ ] comparar `PRO` vs `IA` en retrato
- [ ] comparar `PRO` vs `IA` en paisaje
- [ ] confirmar que `IA` aporta algo real o reducir su alcance

## 4) Integracion con JUST4ALL

- [x] Agregar JUST4PICT al catalogo del hub.
- [x] Crear metadata de descarga por asset prefix (`JUST4PICT`).
- [x] Historial local de lotes con acciones abrir/revelar en Finder.
- [x] Publicar primer DMG versionado en GitHub Releases.
- [ ] Agregar recursos visuales en `Sources/JUST4ALL/Resources/Assets/JUST4PICT`.

## 5) Release

- [x] Congelar baseline visual de `PRO` antes de reabrir trabajo fuerte en `IA`.
- [x] QA local en lotes de 100/1000 imagenes.
  Ya existen pasadas validadas de 100 y 1000 imagenes en `QA_BATCH_LOCAL.md`.
- [x] Medir tiempos por preset y tamaño promedio.
  Referencia local documentada en `QA_BATCH_LOCAL.md`.
- [ ] Firma/notarizacion.
- [x] Publicacion v0.1.0.
  Publicada como baseline unsigned dentro de la release del repo `v0.1.3`; queda pendiente solo una release firmada/notarizada cuando exista cuenta Apple Developer.
- [x] Generar y validar DMG funcional de la baseline MVP actual.
  Validado el 2026-03-22 montando `dist/JUST4PICT-0.1.0+20260322114546-6fe34bc.dmg` y comprobando `JUST4PICT.app` + build stamp.

## 6) Camino a algo muy bueno

Definicion de "muy bueno":

- `PRO` mejora de forma visible sin parecer filtro
- `AUTO` acierta la mayor parte de las veces sin intervencion del usuario
- `IA` aporta criterio real donde el pipeline local no basta
- el resultado exportado mantiene calidad alta y consistencia
- el lote funciona bien con memoria y tiempos controlados

Hitos:

- [x] `Retrato/PRO` usable como baseline visual
- [x] `AUTO` fiable para retrato, paisaje y nocturna base
- [ ] `Documento` y `Paisaje` refinados
- [ ] arquitectura modular estable
- [ ] upscale dedicado evaluado
- [ ] QA de volumen completada
- [ ] release candidata lista para firma

## 7) Cierre de MVP

Objetivo:

- definir un punto claro de "MVP terminado" para dejar de abrir frentes y pasar a afinado

Condicion de salida:

- cuando estos puntos esten completos, `JUST4PICT` puede darse por cerrado como MVP funcional

Checklist de cierre:

- [x] `Retrato/PRO` queda congelado como baseline visual estable
  Queda congelado para la baseline actual del MVP, con test de referencia sobre la muestra fija del repo.
- [x] `AUTO` funciona de forma fiable en:
  - retrato
  - documento
  - foto oscura
  - ecommerce
- [x] `Documento` mantiene fondo claro y legibilidad en la muestra real del repo
- [x] `Ecommerce` deja el producto centrado sobre blanco de forma suficientemente limpia en la muestra real del repo
- [x] preview manual `Original / PRO / IA` se mantiene estable y coherente con export
- [x] export por defecto queda fijado en `PNG` + calidad `1.0`
- [x] perfiles de export `Original / Social / Web / Ecommerce` funcionan sin regressions
- [x] historial local, naming versionado y manejo de colisiones siguen estables
- [x] `swift test` del modulo queda verde de forma consistente
- [x] existe QA visible actualizada en `APPS/JUST4PICT/images/test`
- [x] se hace una pasada de QA local de lote real al menos con 100 imagenes
- [x] se miden tiempos basicos de lote y no hay señal funcional de crecimiento anomalo de memoria en la pasada local de 100 imagenes
- [x] DMG funcional generado y validado para esta baseline

Estado actual:

- [x] `JUST4PICT` queda cerrado como MVP funcional

Pendiente ya fuera del cierre del MVP:

- [x] ampliar QA de lote a 1000 imagenes si se quiere endurecer la baseline
- [x] medir tiempos por preset y por tamaño promedio
- [ ] firma/notarizacion
- [x] publicacion formal v0.1.0

Fuera del MVP:

- notarizacion/firma
- `Ecommerce + IA`
- upscale dedicado
- Core ML / Real-ESRGAN
- afinado visual fino por escena
- optimizacion web `< 300KB`
- correccion avanzada de documento con recorte/horizonte

## 8) Afinado Post-MVP

Meta:

- mejorar calidad, velocidad y casos limite sin volver a discutir el alcance del MVP

Prioridad alta:

- [ ] cerrar ajuste fino final de `Retrato/PRO`
- [x] QA de volumen con 100/1000 imagenes
- [~] medir tiempos/memoria y aplicar correcciones de batch
  Medicion base ya documentada; quedan solo correcciones si aparece regresion real.
- [ ] evaluar `Ecommerce + IA` como opcion puntual para recortes complejos

Prioridad media:

- [ ] persistir en historial la decision efectiva de `AUTO`
- [ ] evitar dobles compresiones y reescalados innecesarios
- [ ] añadir controles o margen configurable al aislamiento de producto
- [ ] convertir `EnhancementRecipe` en contrato central efectivo

Prioridad baja:

- [ ] before/after con slider
- [ ] perfil web `< 300KB`
- [ ] evaluar motores dedicados de upscale/restauracion
