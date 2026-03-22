# agent.md

## Resumen general

**JUST4ALL** es una plataforma modular para macOS que actúa como hub y lanzador de subaplicaciones especializadas (subapps), cada una instalable y ejecutable de forma independiente. El objetivo es ofrecer utilidades avanzadas para usuarios de escritorio, manteniendo independencia, modularidad y distribución flexible.

### Estructura del repositorio

- **APPS/**: Contiene subapps independientes:
  - **JUST4PDF**: Herramientas PDF (Python, PySide6)
  - **JUST4CONVERT**: Conversión multimedia (SwiftUI)
  - **JUST4FOLDERS**: Organización de archivos/carpetas (SwiftUI)
  - **JUST4PICT**: Mejoramiento de imágenes por lotes (SwiftUI)
- **Sources/JUST4ALL/**: Código fuente del hub principal (Swift)
- **scripts/**: Scripts de build, empaquetado, release y utilidades.
- **build/**: Artefactos de compilación.
- **MODULOS_A_CREAR.MD**: Ideas y lista de apps a implementar.
- **README.md, TODO.md**: Documentación central y tareas globales.

---

## Subaplicaciones y tecnologías

### 1. JUST4ALL (Hub principal)
- **Lenguaje**: Swift (SwiftUI)
- **Función**: Detecta, lanza y gestiona subapps. Descarga DMGs desde GitHub Releases, muestra changelogs, historial de instalación y uso.
- **Build**: `swift build` o Xcode. Empaquetado DMG vía script.
- **Recursos**: Logos, iconos y screenshots en `Sources/JUST4ALL/Resources/Assets/`.
- **Convenciones**: Modularidad estricta, cada subapp es autónoma.

### 2. JUST4PDF
- **Lenguaje**: Python 3.11+, PySide6, PyMuPDF, Pillow, img2pdf.
- **Función**: Lector PDF, conversión PDF↔imágenes, merge y compresión de PDFs, integración con Quick Actions de macOS.
- **Build**: PyInstaller (no incluido explícitamente), empaquetado DMG vía script.
- **Distribución**: DMG versionado en GitHub Releases.
- **Licencia**: MIT.

### 3. JUST4CONVERT
- **Lenguaje**: Swift (SwiftUI)
- **Función**: Conversión de audio, video e imágenes. Soporte batch, presets, procesamiento paralelo (80% núcleos), integración ffmpeg local.
- **Build**: Xcode/SPM, requiere binario ffmpeg en `Sources/JUST4CONVERT/ffmpeg/`.
- **Empaquetado**: Script DMG dedicado.
- **Notas**: FLAC pendiente, control de bitrate limitado en AVFoundation.

### 4. JUST4FOLDERS
- **Lenguaje**: Swift (SwiftUI, AppKit-first)
- **Función**: Análisis y organización de archivos por categorías, UI 2 paneles tipo commander, sandboxing, bookmarks, operaciones batch.
- **Arquitectura**: Modular SPM (J4FCore, J4FFileSystem, J4FOps, J4FUI).
- **Build**: Xcode/SPM, script DMG.
- **QA**: Scripts de performance, checklist manual, smoke tests.
- **Notas**: Motor adaptativo, cache LRU, manejo de volúmenes RO/NTFS.

### 5. JUST4PICT
- **Lenguaje**: Swift (SwiftUI)
- **Función**: Mejoramiento automático de imágenes por lotes, presets inteligentes, pipeline Core Image, sugerencia IA (OpenAI) para presets/calidad.
- **Build**: Xcode/SPM, script DMG.
- **Notas**: Exporta a JPG, PNG, HEIC, WEBP, TIFF. Upscale automático, logging QA, integración IA opcional. Baseline MVP cerrada con QA local 100/1000 y release unsigned.

---

## Flujos de build, testing y release

### Build y empaquetado

- Cada subapp tiene su propio script `build_dmg.sh` para generar el binario y empaquetar en DMG.
- Los binarios se colocan en carpetas `build/` y los DMGs en `dist/`.
- Los assets (iconos, screenshots) se ubican en `Sources/JUST4ALL/Resources/Assets/<SUBAPP>/`.
- Para JUST4CONVERT, el binario ffmpeg debe estar presente y con permisos de ejecución.
- Los Info.plist se generan dinámicamente en los scripts de build.

### Testing y QA

- **JUST4FOLDERS**: Incluye scripts de performance, smoke tests y checklist manual de UI.
- **JUST4PDF**: Testing manual, sin integración CI explícita.
- **JUST4PICT**: Incluye suite automatizada (`swift test`), muestras QA visibles y benchmarks locales opt-in.
- **JUST4ALL y otras subapps**: Testing principalmente manual; la cobertura automatizada sigue siendo desigual fuera de `JUST4PICT`.
- **CI/CD**: No se detecta pipeline CI/CD automatizado, pero se recomienda para builds y releases reproducibles.

### Release

- Los DMGs de cada subapp se publican como assets versionados en GitHub Releases.
- Ejemplo de nombres: `JUST4PDF-0.1.0.dmg`, `JUST4CONVERT-0.1.0.dmg`.
- El hub descarga y abre los DMGs desde GitHub.

---

## Integración IA

- **JUST4PICT**: Integra sugerencia IA (OpenAI) para recomendar y aplicar presets/calidad óptima. El prompt es interno, no editable por el usuario, y se guarda solo el resumen por privacidad.
- No se detectan otros módulos de IA o prompts en el resto de subapps.
- Recomendación: Centralizar prompts y lógica IA en archivos dedicados para trazabilidad y evolución.

---

## Convenciones y buenas prácticas

- **Independencia**: Cada subapp debe funcionar y distribuirse por separado.
- **Modularidad**: Compartir utilidades solo cuando sea necesario.
- **Versionado**: SemVer recomendado, reflejado en nombres de DMG y releases.
- **Recursos**: Todos los assets visuales deben estar en la carpeta correspondiente de cada subapp.
- **Empaquetado**: Scripts de build y empaquetado deben ser reproducibles y documentados.
- **Sandboxing**: Uso de App Sandbox y bookmarks para acceso seguro a archivos (JUST4FOLDERS).
- **Licencia**: MIT (al menos para JUST4PDF).

---

## Decisiones clave y lecciones aprendidas

- **No forzar dependencias**: El hub y las subapps son independientes, permitiendo instalación y actualización modular.
- **Procesamiento paralelo**: Uso intensivo de procesamiento batch y paralelo para eficiencia (80% núcleos por defecto).
- **Manejo de errores y UX**: Diagnóstico visible por item, reintentos rápidos, feedback de progreso para evitar bloqueos de UI.
- **QA manual**: Checklists y smoke tests documentados, especialmente en JUST4FOLDERS.
- **QA automatizada localizada**: `JUST4PICT` ya actúa como referencia interna de tests y benchmarks del ecosistema.
- **Distribución**: DMGs versionados y publicados en GitHub Releases, descargados automáticamente por el hub.
- **Integración IA**: Sugerencias automáticas, privacidad de prompts, integración opcional y no intrusiva.

---

## Trampas y advertencias

- **ffmpeg**: Debe estar presente y ejecutable en JUST4CONVERT, no se distribuye por defecto.
- **Build reproducible**: Asegurar que los scripts de build generen artefactos consistentes y firmados.
- **Testing**: Falta de tests automatizados en buena parte del ecosistema; `JUST4PICT` es hoy el módulo más avanzado en esa parte.
- **Sandboxing**: Manejar correctamente los bookmarks y permisos en macOS para evitar errores de acceso.
- **Integración IA**: Documentar y versionar prompts y lógica IA para trazabilidad.

---

## Expansión futura

- **MODULOS_A_CREAR.MD**: Lista de ideas y apps a implementar, mantener actualizada para roadmap.
- **Quick Actions**: Integración con Finder y CLI para automatización.
- **Notarización y firma**: Recomendado para releases públicos y distribución fuera de App Store.

---

## Referencias rápidas

- **Build subapp**: `cd APPS/<SUBAPP>; ./scripts/build_dmg.sh`
- **Ejecutar hub**: `swift run` en raíz o abrir en Xcode.
- **Descargar DMGs**: https://github.com/DMX83/JUST4ALL/releases
- **Assets**: `Sources/JUST4ALL/Resources/Assets/<SUBAPP>/`
- **Documentación**: README.md y TODO.md en raíz y en cada subapp.

---

Este archivo debe mantenerse actualizado y servir como referencia central para cualquier agente IA o humano que opere, mantenga o evolucione el ecosistema JUST4ALL.
