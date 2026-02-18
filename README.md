# JUST4ALL

JUST4ALL es una app para macOS que agrupa varios submodulos con objetivos diferentes. Cada submodulo es una aplicacion independiente que puede instalarse y usarse sin necesidad de instalar la app maestra.

## Objetivo

- Construir una plataforma principal para macOS que sirva como contenedor y punto de entrada.
- Desarrollar submodulos separados, cada uno con su propio objetivo y ciclo de vida.
- Permitir instalar cada submodulo por separado, sin dependencias forzadas con la app maestra.
- JUST4ALL actua como hub: detecta, abre y ofrece descarga/instalacion de subapps.

## Estructura del repositorio

- APPS/JUST4PDF: App enfocada en herramientas para PDF.
- APPS/JUST4CONVERT: App nativa macOS en SwiftUI para conversion multimedia.
- App principal (este repo): JUST4ALL en Swift (Sources/ y Resources/).

## Documentacion rapida

- Hub (este modulo): `README.md` y `TODO.md`
- JUST4PDF: `APPS/JUST4PDF/README.md` y `APPS/JUST4PDF/TODO.md`
- JUST4CONVERT: `APPS/JUST4CONVERT/README.md`

## Submodulos

- JUST4PDF: App macOS para leer PDFs, convertir PDF↔imagenes y herramientas basicas de PDF.
- JUST4CONVERT: App nativa macOS para conversion de audio, video e imagenes con cola de trabajos.
- JUST4ALL: Hub macOS para lanzar subapps con vista de detalles.

## Principios del proyecto

- Independencia: cada submodulo debe funcionar solo.
- Modularidad: compartir utilidades solo cuando tenga sentido.
- Distribucion flexible: cada app puede publicarse por separado.

## Estado actual

El repositorio contiene al menos los siguientes submodulos:

- JUST4PDF (Python + PySide6)
- JUST4CONVERT (SwiftUI)

### Estado funcional resumido

- JUST4ALL:
  - UI hub con tarjetas y panel de detalle por subapp.
  - Detecta instalacion local, muestra version/changelog, permite descargar DMG desde GitHub Releases y abrir instalador.
  - Guarda historial de instalacion y ultimo uso por subapp.
- JUST4CONVERT:
  - Cola multiarchivo con procesamiento en paralelo configurable (por defecto 80% de nucleos).
  - Progreso por item + progreso global + ETA.
  - Presets globales y override por item.
  - Historial local de conversiones con acciones "Abrir" y "Revelar".
  - Soporte de formatos:
    - Audio: m4a, mp3 (flac visible pero pendiente).
    - Video: mov, mp4, mkv (mkv via ffmpeg incluido en app).
    - Imagen: jpg, png, heic, heif, webp, tiff, bmp, gif.
- JUST4PDF:
  - Reader PDF con navegacion, zoom, thumbnails y busqueda basica.
  - Conversion PDF -> imagenes e imagenes -> PDF.
  - Merge y compresion de PDF en tres niveles.
  - Packaging para .app/.dmg y soporte de apertura de PDFs via integracion de macOS.

## Build y ejecucion (alto nivel)

### JUST4PDF

- Dev/ejecucion: instalar el paquete local y ejecutar el entrypoint `just4pdf`.
- Build macOS: ver `APPS/JUST4PDF/packaging/build.sh` (usa PyInstaller).

### JUST4CONVERT

- App nativa macOS en SwiftUI (audio, video, imagenes).
- Incluye cola, historial, presets por item y procesamiento paralelo.
- Ver detalles en `APPS/JUST4CONVERT/README.md`.

### JUST4ALL

- App nativa macOS en Swift.
- Proyecto Swift en la raiz del repo (Package.swift, Sources/).
- Generar proyecto Xcode:

```bash
./scripts/generate_xcodeproj.sh
```

### Workspace (opcional)

Para trabajar JUST4ALL y JUST4CONVERT en Xcode al mismo tiempo, se recomienda un .xcworkspace.

### Recursos y vistas

- Logos y screenshots:
  - Sources/JUST4ALL/Resources/Assets/JUST4PDF/
  - Sources/JUST4ALL/Resources/Assets/JUST4CONVERT/
- Nombres esperados:
  - logo.png
  - screen-1.png
  - screen-2.png

### UI actual

- Vista con tarjetas de subapps y panel de detalles.
- Incluye descripcion, requisitos, links y screenshots por subapp.

### Build DMG

```bash
./scripts/build_dmg.sh
```

### Sincronizar DMGs locales

```bash
./scripts/sync_local_dmgs.sh
```

### Limpiar artefactos

```bash
./scripts/clean_artifacts.sh
```

Los DMG de las subapps se distribuyen via **GitHub Releases** como assets versionados
(por ejemplo `JUST4PDF-0.1.0.dmg`). JUST4ALL descarga esos DMG a `~/Downloads` y los abre.

## App maestra

- Nombre: JUST4ALL.
- Proposito: ofrecer un hub macOS para descubrir, instalar y actualizar subapps independientes.
- Flujo recomendado: cada subapp se distribuye como DMG independiente y JUST4ALL solo las abre o inicia la descarga.

## Como contribuir

1. Entra al submodulo que quieras trabajar.
2. Sigue el README de ese submodulo para instalar dependencias y ejecutar.
3. Abre un PR con cambios claros y enfocados.

## Roadmap (alto nivel)

- Definir una interfaz comun para la app maestra.
- Estandarizar el empaquetado y la distribucion por submodulo.
- Crear un sistema de actualizaciones por app.

## Licencia

Ver los archivos de licencia dentro de cada submodulo.
