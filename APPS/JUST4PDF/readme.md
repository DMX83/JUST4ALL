# JUST4PDF (macOS) — Plan de desarrollo (Senior)

## Objetivo

Crear **JUST4PDF**, una app **desktop macOS** open source que:

1) Sea **PDF Reader** (visor) para abrir y leer PDFs.
2) Convierta **PDF → imágenes** (por página).
3) Convierta **imágenes → PDF** (multipágina).
4) **Unir PDFs** (merge) y **comprimir PDFs** en 3 niveles.
5) Se integre en macOS para que el usuario pueda **elegir JUST4PDF como lector por defecto** de PDFs, y también **quitarlo** (volver a otra app).

> Nota crítica: macOS no permite que una app “se imponga” como default sin acción del usuario. Lo correcto es:

- JUST4PDF declara soporte para PDF en su bundle.
- El usuario lo elige como default vía Finder (“Change All…”) o desde JUST4PDF guiándolo al panel correcto.

---

## Alcance por versiones

### v0.1 (MVP)

- GUI (PySide6) con 4 áreas:
  - **Reader** (visualización + navegación)
  - **PDF → Imágenes**
  - **Imágenes → PDF**
  - **PDF Tools** (merge + compress)
- Abrir PDF desde:
  - Selector de archivo
  - Doble click (si JUST4PDF es default o “Open With…”)
  - Drag & drop
- Render y exportaciones básicas + log.
- Merge de PDFs + compresión (3 niveles).

### v0.2 (Integración default PDF + UX)

- JUST4PDF declara oficialmente `com.adobe.pdf` en `Info.plist`.
- Manejo robusto de `argv`/open events para abrir PDFs.
- Pantalla “Preferencias” con:
  - Botón **“Cómo poner JUST4PDF como lector por defecto”**
  - Botón **“Cómo quitar JUST4PDF como lector por defecto”**
  - (No prometer automatización total; guiar y abrir el lugar adecuado)

### v0.3 (Finder Quick Action recomendado)

- Quick Action para:
  - “Exportar páginas a imágenes con JUST4PDF”
  - “Unir imágenes en PDF con JUST4PDF”
- Implementado con CLI interno para que funcione sin abrir UI.
  - `packaging/quick_actions/just4pdf-cli` (wrapper para `open -a JUST4PDF`)

---

## Stack (open source, práctico)

- Python 3.11+
- GUI: **PySide6 (Qt)**
- PDF render/text: **PyMuPDF (fitz)**
- Imágenes→PDF: **img2pdf**
- Imágenes: **Pillow** (EXIF + recomprimir)
- Packaging: **PyInstaller** (rápido para iterar)
- PDF Tools (merge/compresión): **PyMuPDF (fitz)**

Licencia: **MIT** (recomendado).

---

## Funcionalidades — PDF Reader (nuevo)

### Reader MVP

- Cargar PDF y mostrar páginas (render):
  - Zoom in/out, “fit width”, “fit page”
  - Navegación: página siguiente/anterior + caja “ir a página”
  - Scroll vertical (modo continuo) o página a página (elige uno en v0.1, continuo recomendado)
- Sidebar (v0.2):
  - miniaturas (thumbnails)
- Búsqueda en texto (v0.3):
  - si el PDF tiene texto digital: buscar y resaltar
  - si es escaneado: no (sin OCR)

> En v0.1 no prometas “edición”, solo lectura/visualización.

---

## Requisitos: “ser lector por defecto” y “elegir o quitar”

### Realidad macOS (sin humo)

- **No** existe un API estándar para “set default PDF viewer” que funcione universalmente sin interacción del usuario.
- La vía confiable:
  - Finder → seleccionar PDF → Get Info → “Open with” → JUST4PDF → “Change All…”
- Para “quitarlo”:
  - repetir el mismo flujo y escoger Preview (Vista Previa) u otra app.

### Lo que JUST4PDF sí debe hacer

1) **Declararse como app que abre PDFs** (Info.plist):
   - `CFBundleDocumentTypes` incluye `com.adobe.pdf`
2) **Abrir correctamente PDFs al recibirlos desde el sistema**:
   - via argv / open events
3) **Dar una UX clara**:
   - Preferencias → “Establecer como predeterminado”:
     - abre una guía paso a paso (1 pantalla)
     - opcional: botón “Abrir Finder y mostrar un PDF de ejemplo”
   - Preferencias → “Quitar como predeterminado”:
     - misma guía, pero eligiendo Vista Previa (Preview)

> Si más adelante quieres automatizar al máximo, se puede explorar LaunchServices (LSSetDefaultRoleHandlerForContentType) vía bridge Objective-C/Swift. Pero no lo pongo como requisito del MVP porque complica packaging y mantenimiento.

---

## Estructura de proyecto

```text
just4pdf/
├─ README.md
├─ LICENSE
├─ pyproject.toml
├─ src/
│  └─ just4pdf/
│     ├─ __init__.py
│     ├─ app.py                 # arranque + manejo open/argv
│     ├─ ui_main.py             # ventana principal (tabs/stack)
│     ├─ ui_reader.py           # widgets del lector
│     ├─ ui_convert.py          # widgets conversión
│     ├─ preferences.py         # guía default app + settings
│     ├─ workers.py             # threads, señales progreso
│     ├─ services/
│     │  ├─ reader_render.py     # render páginas + cache
│     │  ├─ pdf_to_images.py     # export páginas
│     │  ├─ images_to_pdf.py     # crear pdf
│     │  ├─ pdf_tools.py         # merge + compresión
│     │  └─ utils.py
│     └─ resources/
│        ├─ icons/
│        └─ docs/               # guía "default PDF"
├─ tests/
└─ packaging/
  ├─ pyinstaller.spec
  └─ macos/
    ├─ Info.plist             # document types + identifiers
    └─ quick_actions/         # v0.3
```

---

## Diseño técnico — Reader

### Render y performance

- PyMuPDF renderiza rápido, pero PDFs grandes pueden ser pesados:
  - Cache LRU de pixmaps por página y nivel de zoom
  - Render “lazy” (solo páginas visibles)
- UI no debe congelarse:
  - render en background (QThread) + placeholder

### Controles mínimos

- Toolbar:
  - Open, Prev, Next
  - Page: [input] / total
  - Zoom - / +, Fit Width
- Area central: vista de páginas (QScrollArea + layout vertical)

---

## Integración macOS (default PDF)

### 1) Declarar soporte PDF en bundle

- En `Info.plist`:
  - `CFBundleDocumentTypes`:
    - `LSItemContentTypes`: `com.adobe.pdf`
    - `CFBundleTypeRole`: `Viewer`
  - Opcional: imágenes si quieres “Open With” directo para imágenes.

### 2) Abrir archivos desde sistema

- Leer `sys.argv` (PyInstaller) para rutas al abrir
- En macOS, también pueden llegar open events; validar que argv funciona en tu packaging.
- Comportamiento:
  - Si recibe `.pdf`: abrir en Reader y seleccionar tab Reader.
  - Si recibe imágenes: ir a “Imágenes → PDF” y precargar lista.

### 3) UI para “poner/quitar por defecto”

- Menú: JUST4PDF → Preferences
- Sección “PDF por defecto”:
  - Botón “Ver guía para establecer JUST4PDF”
  - Botón “Ver guía para quitar JUST4PDF”
- La guía muestra:
  1. En Finder, selecciona un PDF
  2. ⌘I (Get Info)
  3. Open with: JUST4PDF (o Preview)
  4. Change All…

> Esto cumple el requisito “se pueda elegir o quitar” con un flujo realista y soportado.

---

## Criterios de aceptación

### Reader

- [ ] Abre un PDF y muestra páginas correctamente.
- [ ] Navegación por páginas funciona.
- [ ] Zoom y fit width funcionan.
- [ ] No se congela con PDFs medianos (50–200 páginas) al hacer scroll (render lazy).

### Default app

- [ ] JUST4PDF aparece en “Open With…” para PDFs.
- [ ] Si el usuario lo pone como default, doble click abre JUST4PDF.
- [ ] La guía para “quitarlo” es clara y funciona.

### Conversión

- [ ] PDF→imágenes exporta con naming estable.
- [ ] imágenes→PDF respeta orden y corrige EXIF.
- [ ] Unir PDFs mantiene el orden elegido.
- [ ] Compresión con 3 niveles genera PDF válido.
- [ ] Compresión en modo seguro (no guardar si crece) + preview.

---

## Roadmap (prioridad real)

- v0.1: Reader + conversiones + threading + build `.app`
- v0.2: Integración default (Info.plist) + abrir vía sistema + Preferencias/guía
- v0.3: Quick Actions + CLI interno
- v0.4: thumbnails + búsqueda texto + mejoras cache/render

---

## Tareas (para ChatGPT Agent en VS Code)

### Sprint 1 — Reader MVP

1. Crear estructura `src/just4pdf`.
2. Implementar `ui_reader.py` (toolbar + scroll view).
3. Implementar `services/reader_render.py` (render page -> QImage/QPixmap).
4. Cache LRU básica.
5. Abrir PDF desde file dialog.
6. Threading para render.

### Sprint 2 — Conversiones

1. `services/pdf_to_images.py`
2. `services/images_to_pdf.py`
3. `services/pdf_tools.py` (merge + compresión)
4. UI convert (tab) + workers + progreso/logs.

### Sprint 3 — macOS default + open with

1. Manejo `sys.argv` en `app.py` para abrir archivo al arrancar.
2. Preparar `packaging/macos/Info.plist` con `com.adobe.pdf`.
3. PyInstaller spec + generar `.app`.
4. Añadir Preferences con guía “poner/quitar por defecto”.

### Sprint 4 — Quick Actions (opcional)

1. Crear `just4pdf-cli`
2. Assets Automator/Shortcuts
3. Documentación en README

---

## Build (PyInstaller) — base

- `pip install pyinstaller`
- `pyinstaller --windowed --name "JUST4PDF" --osx-bundle-identifier "com.tuempresa.just4pdf" src/just4pdf/app.py`
- `./packaging/build.sh` (usa `packaging/pyinstaller.spec` + `Info.plist`)

## Releases

- v0.1.0 (DMG): `https://github.com/DMX83/JUST4PDF/releases/tag/v0.1.0`

## Pruebas manuales (macOS)

1) Build `.app`: `./packaging/build.sh`
2) Abre un PDF desde Finder (doble click / Open With… JUST4PDF).
3) Verifica: Reader carga el archivo y “Open With” respeta la preferencia.

> Recomendado: usar `pyinstaller.spec` + `Info.plist` custom para document types.  
> JUST4PDF debe salir como `.app` y aparecer en “Open With…”.

---
