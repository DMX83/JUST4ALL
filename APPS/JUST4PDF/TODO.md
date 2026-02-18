# TODO — JUST4PDF (MVP)

## Documentacion relacionada

- Plan del modulo: `README.md`
- Hub principal: `../../README.md`
- Roadmap general: `../../TODO.md`

## 0) Base del proyecto

- [x] Crear estructura `src/just4pdf/`
- [x] Crear `pyproject.toml`
- [x] Crear `README.md`
- [x] Crear `LICENSE` (MIT)
- [x] Crear `.gitignore`

## 1) App y ventana principal

- [x] Crear `src/just4pdf/app.py` (entrypoint)
- [x] Crear `src/just4pdf/ui_main.py` (ventana principal con tabs)
- [x] Definir tabs: Reader / PDF → Imágenes / Imágenes → PDF
- [x] Wiring básico (abrir, logs simples)
- [x] Preferencias + config (toggle “Open With”)

## 2) Reader MVP (visor)

- [x] Crear `src/just4pdf/ui_reader.py` (toolbar + scroll)
- [x] Crear `src/just4pdf/services/reader_render.py` (render páginas)
- [x] Abrir PDF desde diálogo
- [x] Render de páginas visibles (lazy)
- [x] Navegación: siguiente/anterior + ir a página
- [x] Zoom + fit width
- [x] Thumbnails + búsqueda básica

## 3) Conversión PDF → Imágenes

- [x] Crear `src/just4pdf/services/pdf_to_images.py`
- [x] UI simple en tab PDF → Imágenes
- [x] Exportar páginas con naming estable
- [x] Progreso/logs básicos
- [x] Cancelar + presets de calidad

## 3.1) PDF → PDF (nuevas herramientas)

- [x] Unir PDFs (merge)
- [x] Comprimir PDF (3 niveles)
- [x] Compresión con preview, modo seguro y estrategia auto

## 4) Conversión Imágenes → PDF

- [x] Crear `src/just4pdf/services/images_to_pdf.py`
- [x] UI simple en tab Imágenes → PDF
- [x] Orden de imágenes + corrección EXIF
- [x] Progreso/logs básicos
- [x] Drag & drop + preview + presets

## 5) Hilos/Workers

- [x] Crear `src/just4pdf/workers.py` (QThread + señales)
- [x] Integrar en render/convert para no congelar UI

## 6) Packaging básico

- [x] Crear `packaging/pyinstaller.spec`
- [x] Comando build `.app` (`packaging/build.sh`)
- [x] Icono base (logo → .ico)
- [x] Icono .icns para app macOS

## 7) Quick Actions / CLI (v0.3)

- [x] Stub `just4pdf-cli` (wrapper `open -a JUST4PDF`)

---

### Notas

- Empezar por estructura + ventana principal.
- Mantener el MVP simple (sin thumbnails ni búsqueda).
