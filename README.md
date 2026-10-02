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
- APPS/JUST4FOLDERS: App nativa macOS (AppKit-first): commander de 2 paneles con indice instantaneo e IA, Panel Hub (DESK/PICT), monitor del sistema y copias instantaneas por clon APFS.
- APPS/JUST4PICT: App nativa macOS en SwiftUI para mejoramiento automatico de imagenes.
- APPS/JUST4DESK: App nativa macOS en SwiftUI para busqueda instantanea y organizacion automatica de documentos.
- APPS/LIFEOS: Cliente nativo macOS para LifeOS (captura, tu dia y bandeja) sobre la API de LifeOS; la primera subapp que necesita servidor.
- App principal (este repo): JUST4ALL en Swift (Sources/ y Resources/).

## Documentacion rapida

- Hub (este modulo): `README.md` y `TODO.md`
- JUST4PDF: `APPS/JUST4PDF/README.md` y `APPS/JUST4PDF/TODO.md`
- JUST4CONVERT: `APPS/JUST4CONVERT/README.md`
- JUST4FOLDERS: `APPS/JUST4FOLDERS/README.md` y `APPS/JUST4FOLDERS/TODO.md`
- JUST4PICT: `APPS/JUST4PICT/README.md`, `APPS/JUST4PICT/TODO.md`, `APPS/JUST4PICT/ENHANCE_ARCHITECTURE.md`, `APPS/JUST4PICT/QA_BATCH_LOCAL.md`
- JUST4DESK: `APPS/JUST4DESK/README.md`, `APPS/JUST4DESK/TODO.md`, `APPS/JUST4DESK/MEMORY.md` (memoria maestra)
- LIFEOS: `APPS/LIFEOS/README.md` y `APPS/LIFEOS/TODO.md` (plan en `PLAN_LIFEOS_MACOS_API.md`)
- Estado y pendientes del conjunto (por app, con prioridades): `PENDIENTES.md`

## Submodulos

- JUST4PDF: App macOS para leer PDFs, convertir PDF↔imagenes y herramientas basicas de PDF.
- JUST4CONVERT: App nativa macOS para conversion de audio, video e imagenes con cola de trabajos.
- JUST4FOLDERS: Commander de archivos con indice instantaneo, busqueda global/semantica y organizacion asistida por IA. Incluye Panel Hub (DESK/PICT), monitor del sistema (CPU/RAM/disco/IO/bateria) y motor de copia con clon APFS (v2.3.11).
- JUST4PICT: App nativa macOS para mejorar imagenes por lotes con presets automaticos.
- JUST4DESK: App nativa macOS para buscar al instante y archivar automaticamente documentos en una taxonomia ordenada.
- LIFEOS: App nativa macOS que se conecta por API a LifeOS (lifeos.perlatec.net o tu servidor) para capturar, confirmar y cerrar el dia.
- JUST4ALL: Hub macOS para lanzar subapps con vista de detalles.

## Principios del proyecto

- Independencia: cada submodulo debe funcionar solo.
- Modularidad: compartir utilidades solo cuando tenga sentido.
- Distribucion flexible: cada app puede publicarse por separado.

## Estado actual

El repositorio contiene al menos los siguientes submodulos:

- JUST4PDF (Python + PySide6)
- JUST4CONVERT (SwiftUI)
- JUST4FOLDERS (SwiftUI)
- JUST4PICT (SwiftUI)
- JUST4DESK (SwiftUI)
- LIFEOS (SwiftUI; cliente nativo de la API de LifeOS, requiere servidor)

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
- JUST4FOLDERS:
  - Commander de 2 paneles (modo unico/dual) con pestanas, arbol por panel, galeria, vista previa y paleta de comandos (⌘K).
  - Busqueda instantanea con el indice FTS5 compartido (J4IIndex): subarbol + global (⌘F) + semantica IA opcional (⌥⌘B).
  - Vista aplanada, filtro rapido, rename en lote, duplicados, etiquetas Finder, tamanos de carpeta y portapapeles completo.
  - «Ordenar esta carpeta» con reglas+taxonomia compartidas de JUST4DESK e IA opcional (diario + deshacer).
- JUST4PICT:
  - Seleccion por archivos o carpeta para lote de imagenes.
  - Presets automaticos (Auto, Retrato, Paisaje, Documento, Ecommerce).
  - Pipeline de mejora con Core Image (auto-ajuste, color, denoise, sharpen).
  - Export en JPG/PNG/HEIC/WEBP/TIFF con colisiones resueltas.
  - Baseline MVP cerrada: QA local 100/1000, DMG validado y release unsigned publicada.
- JUST4DESK:
  - Buscador instantaneo con indice local (SQLite FTS5 + FSEvents); bench 100k: crawl ~7 s, queries tipicas <40 ms.
  - Organizador automatico: watcher de carpeta de entrada con estabilidad de fichero, extraccion local
    (PDFKit/Vision OCR), clasificacion con reglas + DeepSeek opcional y taxonomia con undo/cuarentena.
- LIFEOS:
  - Cliente nativo macOS sobre la API de LifeOS: acceso con Google (como la web) o usuario/contrasena con TOTP;
    token en el llavero y `Authorization: Bearer`.
  - Ciclo diario: captura con propuesta revisable (nada se guarda sin confirmar), «Hoy» con el cierre del dia
    y los avisos, bandeja y ajustes. Agenda completa, diario y voz quedan para la siguiente ronda.
  - Atajo global ⌥Espacio con panel de captura, menu de barra y avisos del sistema; cola sin conexion con
    clave de idempotencia (reintentar no duplica).
  - **Necesita servidor**: el parche del flujo nativo esta aplicado en el repo de LifeOS y pendiente de desplegar.

## Build y ejecucion (alto nivel)

### JUST4PDF

- Dev/ejecucion: instalar el paquete local y ejecutar el entrypoint `just4pdf`.
- Build macOS: ver `APPS/JUST4PDF/packaging/build.sh` (usa PyInstaller).

### JUST4CONVERT

- App nativa macOS en SwiftUI (audio, video, imagenes).
- Incluye cola, historial, presets por item y procesamiento paralelo.
- Ver detalles en `APPS/JUST4CONVERT/README.md`.

### JUST4FOLDERS

- App nativa macOS (SPM, AppKit-first): commander de 2 paneles con indice FTS5 compartido.
- Ejecutar: `swift run` en `APPS/JUST4FOLDERS`; DMG con `./scripts/build_dmg.sh`.
- Ver detalles en `APPS/JUST4FOLDERS/README.md`.

### JUST4PICT

- App nativa macOS en SwiftUI para mejoramiento automatico de imagenes.
- Incluye procesamiento por lotes, presets, export multi-formato y QA local reproducible.
- Ver detalles en `APPS/JUST4PICT/README.md`.

### JUST4DESK

- App nativa macOS en SwiftUI: buscador instantaneo (FTS5 + FSEvents) y organizador automatico de documentos.
- Ejecutar: `swift run` en `APPS/JUST4DESK`; build DMG con `./scripts/build_dmg.sh`.

### LIFEOS

- App nativa macOS en SwiftUI que consume la API de LifeOS. Requiere cuenta y servidor (no funciona sola).
- Ejecutar: `swift run LIFEOS` en `APPS/LIFEOS` (para Google hace falta la app empaquetada); tests: `swift test`.
- Build DMG: `./scripts/build_dmg.sh`. Ver `APPS/LIFEOS/README.md`.
- Configuracion IA opcional: `DEEPSEEK_API_KEY` (entorno o `.env.secrets`); sin clave funciona solo con reglas locales.
- Ver detalles en `APPS/JUST4DESK/README.md`.

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
  - Sources/JUST4ALL/Resources/Assets/JUST4FOLDERS/
  - Sources/JUST4ALL/Resources/Assets/JUST4PICT/
- Nombres esperados:
  - logo.png
  - screen-1.png
  - screen-2.png

### UI actual

- Rejilla de tarjetas (una por subapp) que se adapta al ancho de la ventana, más panel de detalle con
  descripción, novedades, requisitos, capturas, enlaces e historial.
- Cada tarjeta y el panel enseñan el **estado real**: instalada en `/Applications`, copia local (el repo o
  un DMG montado) o sin instalar, con la versión que declara el bundle y la publicada en GitHub.
- Atajos ⌘1–⌘6 para elegir app y ⌘↩ para abrir; claro y oscuro adaptativos.
- Icono en la barra de menús y menú del clic derecho del Dock (ver «Instalar el hub en tu Mac»).

### Build DMG

```bash
./scripts/build_dmg.sh
```

### Instalar el hub en tu Mac

```bash
./scripts/build_dmg.sh                                  # compila Release y deja dist/JUST4ALL.dmg
cp -R build/Build/Products/Release/JUST4ALL.app /Applications/
open /Applications/JUST4ALL.app
```

- Aparece en Launchpad y en Spotlight (⌘Espacio → «JUST4ALL»). Para tenerlo siempre a mano abajo: clic
  derecho en su icono del Dock → *Opciones* → **Mantener en el Dock**.
- **Barra de menús** (arriba, junto al reloj): el hub deja un icono; al pulsarlo (clic izquierdo o
  derecho) se despliega la lista de las seis subapps, «Abrir JUST4ALL» y «Salir de JUST4ALL».
- **Dock**: con el **clic derecho** sobre el icono de JUST4ALL sale esa misma lista («Levantar una app»),
  que es la forma rápida de levantar una subapp sin abrir la ventana. Si la elegida todavía no está
  instalada, el hub se abre solo y ofrece su descarga.
- El hub busca las subapps instaladas por identificador (LaunchServices) y en `/Applications` y
  `~/Applications`; si no las encuentra y tiene el repo a mano, las lanza en modo desarrollo.

Pruebas del hub: `swift test` (7 pruebas: catálogo, menú del Dock y localización de subapps).

### Sincronizar DMGs locales

```bash
./scripts/sync_local_dmgs.sh
```

### Limpiar artefactos

```bash
./scripts/clean_artifacts.sh
```

Los DMG de las subapps se distribuyen via **GitHub Releases** como assets versionados
(por ejemplo `JUST4FOLDERS-2.3.15.dmg`). El ultimo release es **`v0.1.4`** (2-oct-2026): las seis apps
mas `SHA256SUMS.txt` en el mismo release. JUST4ALL descarga esos DMG a `~/Downloads` y los abre; para
elegir que version mostrar recorre **todos** los releases y se queda con la mayor por prefijo, asi que
no hay tag fijo que actualizar.

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
