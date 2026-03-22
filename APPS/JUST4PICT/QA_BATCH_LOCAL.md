# QA Batch Local — JUST4PICT

Fecha de referencia:

- 2026-03-22

Objetivo:

- validar una pasada local de lote real de 100 imagenes antes de cerrar el MVP

Comando ejecutado:

```bash
swift test --filter ImageEnhancerDiagnosticsTests/testProcessesHundredImageLocalBatchUsingRealRepoSamples
```

Medicion complementaria:

```bash
/usr/bin/time -l swift test --filter ImageEnhancerDiagnosticsTests/testProcessesHundredImageLocalBatchUsingRealRepoSamples
```

Dataset usado:

- 5 muestras reales del repo:
  - `APPS/JUST4PICT/images/PHOTO-2026-03-18-22-18-19 2.jpg`
  - `APPS/JUST4PICT/images/32474560-ED95-47FF-96E9-2ACD793D0A30_1_105_c.jpeg`
  - `APPS/JUST4PICT/images/58706BD4-3915-4068-80EF-B7B11F7D2EC6_1_105_c.jpeg`
  - `APPS/JUST4PICT/images/image_doc_orig.jpeg`
  - `APPS/JUST4PICT/images/image_product_orig.jpeg`
- repetidas ciclicamente hasta completar 100 inputs

Resultado:

- 100/100 salidas generadas correctamente
- test verde
- duracion observada del lote: `16.83s`
- segunda pasada con medicion del sistema:
  - duracion interna del test: `16.36s`
  - tiempo real del comando: `18.32s`
  - `maximum resident set size`: `529334272` bytes
  - `peak memory footprint`: `16925368` bytes

Lectura practica:

- la baseline actual procesa 100 imagenes reales del set del repo sin fallo funcional
- este paso cierra la QA minima de lote para el MVP
- ya existe una medicion explicita de tiempo y memoria para el batch de 100
- sigue pendiente ampliar la prueba a 1000 imagenes si se quiere endurecer post-MVP

Validacion de empaquetado de la baseline:

- el 2026-03-22 se genero y valido `dist/JUST4PICT-0.1.0+20260322101203-72d60f7.dmg`
- el volumen monto correctamente como `/Volumes/JUST4PICT`
- se verifico `JUST4PICT.app` dentro del DMG
- `Info.plist` del bundle montado reporto `J4ABuildStamp = 20260322101203-72d60f7`
