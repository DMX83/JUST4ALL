# QA Batch Local — JUST4PICT

Fecha de referencia:

- 2026-03-22

Objetivo:

- validar una pasada local de lote real de 100 imagenes antes de cerrar el MVP
- ampliar despues la misma validacion a 1000 imagenes y dejar una referencia simple de tiempos por preset/tamaño

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
- se puede usar como referencia rapida para comparar regresiones futuras

Validacion de empaquetado de la baseline:

- el 2026-03-22 se genero y valido `dist/JUST4PICT-0.1.0+20260322114546-6fe34bc.dmg`
- el volumen monto correctamente como `/Volumes/JUST4PICT`
- se verifico `JUST4PICT.app` dentro del DMG
- `Info.plist` del bundle montado reporto `J4ABuildStamp = 20260322114546-6fe34bc`

## Bench post-MVP

Comandos ejecutados:

```bash
JUST4PICT_RUN_LONG_BENCHMARKS=1 swift test --filter ImageEnhancerDiagnosticsTests/testMeasuresPresetLatencyAcrossRealRepoSamples
/usr/bin/time -l env JUST4PICT_RUN_LONG_BENCHMARKS=1 swift test --filter ImageEnhancerDiagnosticsTests/testProcessesThousandImageLocalBatchUsingRealRepoSamples
```

Resultado 1000 imagenes:

- 1000/1000 salidas generadas correctamente
- duracion interna del test: `193.02s`
- tiempo real del comando: `194.66s`
- `maximum resident set size`: `1081966592` bytes
- `peak memory footprint`: `16777888` bytes

Tiempos por preset sobre 5 muestras reales del repo:

- `Auto`: total `1.07s`, media `0.215s` por imagen
- `Retrato`: total `0.88s`, media `0.177s` por imagen
- `Paisaje`: total `0.91s`, media `0.182s` por imagen
- `Documento`: total `0.77s`, media `0.154s` por imagen
- `Ecommerce`: total `0.88s`, media `0.177s` por imagen

Tiempos por tamaño con preset `Auto`:

- `small` (4 muestras): total `0.56s`, media `0.139s` por imagen
- `medium` (1 muestra): total `0.22s`, media `0.215s` por imagen

Lectura practica:

- el batch de 1000 sigue estable funcionalmente en la baseline actual
- `Auto` es el preset mas caro, pero sigue en un rango razonable para el set real del repo
- `Documento` es el preset mas barato de los medidos
- la memoria residente maxima observada ronda `1.01 GB` en la pasada larga; conviene mantener esto como referencia de regresion
