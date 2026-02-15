# JUST4ALL

JUST4ALL es una app para macOS que agrupa varios submodulos con objetivos diferentes. Cada submodulo es una aplicacion independiente que puede instalarse y usarse sin necesidad de instalar la app maestra.

## Objetivo

- Construir una plataforma principal para macOS que sirva como contenedor y punto de entrada.
- Desarrollar submodulos separados, cada uno con su propio objetivo y ciclo de vida.
- Permitir instalar cada submodulo por separado, sin dependencias forzadas con la app maestra.
- JUST4ALL actua como hub: detecta, abre y ofrece descarga/instalacion de subapps.

## Estructura del repositorio

- APPS/JUST4PDF: App enfocada en herramientas para PDF.
- APPS/JUST4CONVERT: MVP nativo macOS en Swift.
- App principal (este repo): JUST4ALL en Swift (Sources/ y Resources/).

## Submodulos

- JUST4PDF: App macOS para leer PDFs, convertir PDF↔imagenes y herramientas basicas de PDF.
- JUST4CONVERT: MVP nativo macOS para conversion de audio, video e imagenes.
- JUST4ALL: Hub macOS para lanzar subapps con vista de detalles.

## Principios del proyecto

- Independencia: cada submodulo debe funcionar solo.
- Modularidad: compartir utilidades solo cuando tenga sentido.
- Distribucion flexible: cada app puede publicarse por separado.

## Estado actual

El repositorio contiene al menos los siguientes submodulos:

- JUST4PDF (Python)
- JUST4CONVERT (Swift MVP)

## Build y ejecucion (alto nivel)

### JUST4PDF

- Dev/ejecucion: instalar el paquete local y ejecutar el entrypoint `just4pdf`.
- Build macOS: ver `APPS/JUST4PDF/packaging/build.sh` (usa PyInstaller).

### JUST4CONVERT

- MVP nativo macOS en Swift (audio, video, imagenes).
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

El DMG de JUST4ALL incluye las subapps como instaladores locales en
Sources/JUST4ALL/Resources/Downloads, para poder abrirlas sin depender de URLs.

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
