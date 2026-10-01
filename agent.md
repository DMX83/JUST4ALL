# agent.md

## Resumen general

**JUST4ALL** es una plataforma modular para macOS que actúa como hub y lanzador de subaplicaciones especializadas (subapps), cada una instalable y ejecutable de forma independiente. El objetivo es ofrecer utilidades avanzadas para usuarios de escritorio, manteniendo independencia, modularidad y distribución flexible.

### Estructura del repositorio

- **APPS/**: Contiene subapps independientes:
  - **JUST4PDF**: Herramientas PDF (Python, PySide6)
  - **JUST4CONVERT**: Conversión multimedia (SwiftUI)
  - **JUST4FOLDERS**: Organización de archivos/carpetas (AppKit-first, hosting mínimo de SwiftUI)
  - **JUST4PICT**: Mejoramiento de imágenes por lotes (SwiftUI)
  - **JUST4DESK**: Buscador instantáneo + organizador de documentos (SwiftUI)
  - **LIFEOS**: Cliente nativo de la API de LifeOS — captura, «Hoy» y bandeja (SwiftUI)
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
- **Lenguaje**: Swift (AppKit-first; el hosting de SwiftUI es mínimo).
- **Función**: Commander de 2 paneles con índice FTS5 propio (búsqueda global ⌘F y semántica con IA), vista aplanada, rename en lote, duplicados, etiquetas, «Ordenar esta carpeta» con taxonomía compartida de DESK, **Panel Hub** (Vista previa | DESK | PICT), **monitor del sistema** en el toolbar y organización asistida por IA.
- **Arquitectura**: Modular SPM (J4FCore, J4FFileSystem, J4FOps, J4FUI) + motores compartidos en `PACKAGES/J4SHARED` (J4ICore/J4IIndex).
- **Build**: Xcode/SPM (`swift build`), script DMG dedicado.
- **QA**: 61 tests en `J4FOpsTests`, scripts de performance (`perf_100k_listing.sh`), smoke test y checklist manual (`QA_LOCAL.md`).
- **Notas**: motor adaptativo (lanes big/small, telemetría y auto-tuning), **copias con clon APFS** (`clonefile`/`copyfile`, medido 12,6x en ficheros pequeños) y **caché persistente de tamaños** (`folder-sizes.json`). Última versión: **v2.3.11**.

### 5. JUST4PICT
- **Lenguaje**: Swift (SwiftUI)
- **Función**: Mejoramiento automático de imágenes por lotes, presets inteligentes, pipeline Core Image, sugerencia IA (OpenAI) para presets/calidad.
- **Build**: Xcode/SPM, script DMG.
- **Notas**: Exporta a JPG, PNG, HEIC, WEBP, TIFF. Upscale automático, logging QA, integración IA opcional. Baseline MVP cerrada con QA local 100/1000 y release unsigned.

### 6. JUST4DESK
- **Lenguaje**: Swift (SwiftUI, SPM modular: J4ICore, J4IIndex, J4IDocs, J4IAI, J4IFiling).
- **Función**: Buscador instantáneo tipo Everything (índice SQLite FTS5 + FSEvents) y organizador automático de documentos (watcher de carpeta de entrada, extracción local PDFKit/Vision OCR, clasificación con reglas + DeepSeek JSON opcional, taxonomía en `~/JUST4DESK`, undo/sin clasificar).
- **Build**: Xcode/SPM, script DMG dedicado; macOS 14+ (depende de módulos de JUST4FOLDERS vía library products).
- **Distribución**: DMG `JUST4DESK-<version>.dmg` + SHA256SUMS en GitHub Releases.
- **Notas**: Privacidad local-first (a DeepSeek solo texto truncado); nunca borra archivos (journal + undo); memoria maestra en `APPS/JUST4DESK/MEMORY.md`; skill de agente en `.github/skills/just4desk/`.

### 7. LIFEOS
- **Lenguaje**: Swift (SwiftUI, SPM modular: LifeOSAPI, LifeOSCore, LifeOSUI + ejecutable LIFEOS).
- **Función**: Cliente nativo de la API de LifeOS. Cubre el ciclo diario: captura con propuesta revisable, «Hoy» (cierre del día y avisos), bandeja y ajustes. Atajo global ⌥Espacio, menú de barra, avisos del sistema y cola sin conexión idempotente.
- **Auth**: Google con `ASWebAuthenticationSession` (el servidor devuelve `lifeos://auth?code=…`), o usuario/contraseña con TOTP. El token vive en el llavero y viaja como `Authorization: Bearer`. Hay respaldo automático por el endpoint clásico si el servidor no tiene el flujo nativo.
- **Build**: `swift build` / `swift test` / `./scripts/build_dmg.sh`; macOS 14+ (bundle `com.dmx83.lifeos`).
- **Distribución**: DMG `LIFEOS-<version>.dmg` + SHA256SUMS en GitHub Releases.
- **Notas**: **es la única subapp que necesita servidor** (no funciona sola). El parche del servidor (2 endpoints + `?native=true` en el authorize) está aplicado en `../0_server_dorticos/LifeOS` y **pendiente de desplegar**. Alcance acotado a propósito: objetivos, métricas, conocimiento, documentos y conectores siguen en la web.
- **Referencias**: `APPS/LIFEOS/README.md`, `APPS/LIFEOS/TODO.md`, `PLAN_LIFEOS_MACOS_API.md`, skill `.github/skills/lifeos/`.

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
