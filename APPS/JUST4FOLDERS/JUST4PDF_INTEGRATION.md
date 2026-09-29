# Integración de JUST4PDF en JUST4FOLDERS — evaluación y diseño

> Evaluación (29-sep) de las capacidades reales de `APPS/JUST4PDF` (verificadas en código, no en
> docs) y de cómo llevarlas al clic derecho (y más allá) de JUST4FOLDERS, siguiendo el mismo
> patrón ya probado con JUST4PICT (`Convertir a PNG/JPEG/50 %` vía submenú contextual + módulo).

## 1. Capacidades verificadas en código (hoy)

| Capacidad | Servicio (Python, cabe en CLI sin Qt) | Firma clave | Estado |
|---|---|---|---|
| **Unir PDFs** | `services/pdf_tools.py` → `merge_pdfs` | `merge_pdfs(pdf_paths, output_path, progress_cb?, should_cancel?) -> bool` | ✅ implementado |
| **Comprimir PDF** (3 niveles) | `services/pdf_tools.py` → `compress_pdf` | `compress_pdf(pdf, out, level="medium", strategy="fitz|pikepdf|auto", safe=True) -> (bool, antes, después)` | ✅ (pikepdf opcional; `auto` elige el menor) |
| **PDF → imágenes** (por página) | `services/pdf_to_images.py` → `export_pdf_to_images` | `(pdf, out_dir, zoom=2.0, progress?, cancel?) -> [rutas]`; naming `page-0001.png` | ✅ |
| **Imágenes → PDF** (multipágina, EXIF) | `services/images_to_pdf.py` → `images_to_pdf` | `(image_paths, output_path, mode="png")` | ✅ |
| **Reader** (zoom, miniaturas, búsqueda) | `services/reader_render.py` (usa Qt) | — | ✅ app GUI |
| **Abrir con / argv / FileOpen** | `app.py` (`_open_from_argv`, `QFileOpenEvent`, toggle `macos_open_with_enabled`) | — | ✅ de facto (v0.2 hecha) |
| **CLI real** | `packaging/quick_actions/just4pdf-cli` | `open -a "JUST4PDF" "$@"` | ⚠️ **STUB** — su v0.3 (roadmap) es el wrapper real |

**Conclusión clave**: el motor PDF ya está entero y desacoplado de la UI (los servicios no
importan PySide6), y el venv del repo ya tiene el entry point (`/Users/dmx83/Repos/JUST4ALL/.venv/bin/just4pdf`).
Lo único que falta para integrarlo es el **CLI de verdad** (pequeño: 4 subcomandos que llaman a
esos servicios).

## 2. Diseño de integración en JUST4FOLDERS

### 2.1 Submenú contextual «JUST4PDF ▸» (patrón PICT ya montado)

En el menú contextual de los paneles (`FilePanelViewController`, `ContextTag` + `updateContextMenuState`):

| Ítem | Habilitado cuando | Acción |
|---|---|---|
| **Unir PDFs en uno…** | ≥2 ficheros, todos `.pdf` | `merge` → `unido.pdf` (nombre único) junto al primero |
| **Comprimir ▸** Bajo / Medio / Alto | ≥1 `.pdf` | `compress --level` → sufijo `-comprimido.pdf` (único) |
| **Exportar páginas a imágenes…** | 1 `.pdf` | `pdf2img --zoom 2` → carpeta `«nombre» Paginas/` junto al PDF |
| **Crear PDF con estas imágenes…** | ≥2 ficheros, todos imágenes | `img2pdf` → `«carpeta».pdf` (único) junto a la primera |
| **Abrir con JUST4PDF** | ≥1 `.pdf` y app localizada | `open -a` (o `NSWorkspace.open` con la app) |

Reglas de estilo (igual que en PICT): nunca sobrescribir (sufijo numérico « 2», « 3»…), no tocar
los originales, estado en la barra inferior («PDF: comprimiendo…»), refresco del panel al terminar.

### 2.2 El CLI que falta en JUST4PDF (F1, esfuerzo bajo)

Nuevo `src/just4pdf/cli.py` + entry en `pyproject.toml` (`[project.scripts] just4pdf-cli = "just4pdf.cli:main"`),
llamando a los servicios existentes (sin Qt):

```
just4pdf-cli merge   -o salida.pdf a.pdf b.pdf …
just4pdf-cli compress --level low|medium|high [--strategy auto] [-o salida.pdf] entrada.pdf
just4pdf-cli pdf2img [--zoom 2.0] [--out-dir D] entrada.pdf
just4pdf-cli img2pdf -o salida.pdf img1 img2 …
```

- Códigos de salida: `0` OK · `2` uso · `3` error de operación (con mensaje en stderr).
- Opcional F3: `--progress` (líneas `PROGRESS n/total` en stderr) para barra en FOLDERS.
- El CLI es también la base de sus **Quick Actions v0.3** (comparten wrapper).

### 2.3 Cómo invoca FOLDERS el motor (detección en cascada)

1. `just4pdf-cli` en `PATH` (instalación de usuario).
2. Venv del repo: `/Users/dmx83/Repos/JUST4ALL/.venv/bin/just4pdf-cli` (dev; ya hay venv).
3. Si no aparece → ítems deshabilitados con tooltip «Instala JUST4PDF (o el venv del repo)».

Ejecución con `Process` (array de args; rutas con espacios/unicode OK) en **background**:
la UI no se bloquea; barra de estado con spinner y refresco de paneles al terminar. F3 puede
engancharlo a la **cola de trabajos** existente para progreso real.

### 2.4 «Abrir con JUST4PDF» (reader)

Ya viable: `app.py` maneja `argv` y `QFileOpenEvent` (toggle en Preferencias). FOLDERS lo ofrece
con `NSWorkspace.open([pdf], withApplicationAt:)` usando el bundle detectado
(`urlForApplication(withBundleIdentifier: "com.dmx83.just4pdf")` o la ruta del venv/app dev).

## 3. Alternativa evaluada (NO recomendada como principal)

Reimplementar merge/compresión/export en Swift con **PDFKit/CoreGraphics** dentro de FOLDERS:
- Pro: cero dependencia de Python.
- Contra: duplica motor y diverge de JUST4PDF; la compresión sería claramente peor que
  `pikepdf`/`fitz` (que ya eligen la mejor estrategia con `auto`); más código a mantener.
- Solo tendría sentido como *fallback* si algún día se quiere distribuir FOLDERS sin el venv.

## 4. Fases y esfuerzo

| Fase | Qué | Dónde | Esfuerzo |
|---|---|---|---|
| **F1** | CLI real (`cli.py`, 4 subcomandos + tests) | JUST4PDF | ✅ **hecho (29-sep)**: commit `6b5cf14`; 7 tests en verde; compress real 1936→1326 B |
| **F2** | Submenú «JUST4PDF ▸» + runner + detección + validación e2e | FOLDERS | ✅ **hecho (29-sep)**: submenú con reglas de visibilidad, merge validado e2e desde el menú (`~/unido.pdf`, 4 págs) |
| **F3** | Progreso en cola de trabajos + Quick Actions Finder (v0.3) sobre el mismo CLI | Ambos | Medio |
| **F4** | Módulo del Panel Hub (opcional): mini acciones PDF sobre la selección (como PICT). **Patrón ya probado con PICT**: `just4pict-cli` + «Mejorar con JUST4PICT ▸» (v2.3.7) | FOLDERS | Bajo si F2 está hecho |

### Estado de validación (29-sep)

- CLI: `merge`/`compress`/`pdf2img`/`img2pdf` con tests + smoke manual; instalado como
  `just4pdf-cli` en el venv del repo (y entry en pyproject para instalaciones de usuario).
- FOLDERS: «JUST4PDF ▸» visible con PDFs y oculto con selecciones no usables; «Unir PDFs en
  uno…» habilitado con ≥2 PDFs; «Crear PDF con estas imágenes…» deshabilitado con PDFs;
  merge E2E desde el menú con refresco del panel al terminar.
- **Pendiente de clic manual**: Comprimir (3 niveles), Exportar páginas, Crear PDF con
  imágenes y Abrir con JUST4PDF (la plomería es la misma del merge ya validado).

## 5. Decisiones abiertas (propuestas por defecto)

- **Salida**: nombre único automático junto al origen (sin diálogos) — v1. ¿Quieres un
  `NSSavePanel` opcional con «recordar»?
- **Al terminar**: ¿revelar/abrir el resultado o solo refrescar + estado? (propuesta: refrescar +
  seleccionar el resultado en el panel).
- **Progreso**: v1 simple (spinner); v2 en la cola de trabajos.
- **pikepdf**: opcional; `--strategy auto` ya degrada a `fitz` si falta.

## 6. Riesgos

- Rutas raras: mitigado con `Process` + args en array (ya validado en PICT con sips).
- PDFs corruptos/protegidos: el servicio lanza error → mensaje en la barra (código ≠ 0).
- Distribución: para usuarios finales habrá que empaquetar el CLI (PyInstaller one-file) o
  instalar el paquete; en dev basta el venv del repo (ya existente).
- El stub actual `just4pdf-cli` (Quick Action) debe sustituirse por el CLI real para no divergir.
